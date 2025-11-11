-- ============================================================================
-- Traczi Subscription System - Data Migration Script
-- Migrates existing subscription data from tc_users.attributes to new tables
-- ============================================================================

-- IMPORTANT: Run this AFTER running 01_create_subscription_tables.sql

-- ============================================================================
-- STEP 1: Migrate existing subscriptions from user attributes
-- ============================================================================

INSERT INTO tc_user_subscriptions (
  userid,
  plan_id,
  stripe_customer_id,
  stripe_subscription_id,
  stripe_payment_method_id,
  status,
  device_limit,
  start_date,
  current_period_end,
  cancel_at_period_end
)
SELECT
  u.id as userid,

  -- Extract plan_id from attributes
  COALESCE(
    JSON_UNQUOTE(JSON_EXTRACT(u.attributes, '$.subscriptionPlan')),
    'basic'
  ) as plan_id,

  -- Extract Stripe IDs
  JSON_UNQUOTE(JSON_EXTRACT(u.attributes, '$.stripeCustomerId')) as stripe_customer_id,
  JSON_UNQUOTE(JSON_EXTRACT(u.attributes, '$.stripeSubscriptionId')) as stripe_subscription_id,
  JSON_UNQUOTE(JSON_EXTRACT(u.attributes, '$.stripePaymentMethodId')) as stripe_payment_method_id,

  -- Extract status
  COALESCE(
    JSON_UNQUOTE(JSON_EXTRACT(u.attributes, '$.subscriptionStatus')),
    'active'
  ) as status,

  -- Map device limit based on plan
  CASE
    WHEN JSON_UNQUOTE(JSON_EXTRACT(u.attributes, '$.subscriptionPlan')) = 'test' THEN 5
    WHEN JSON_UNQUOTE(JSON_EXTRACT(u.attributes, '$.subscriptionPlan')) = 'basic' THEN 30
    WHEN JSON_UNQUOTE(JSON_EXTRACT(u.attributes, '$.subscriptionPlan')) = 'moderate' THEN 80
    WHEN JSON_UNQUOTE(JSON_EXTRACT(u.attributes, '$.subscriptionPlan')) = 'advance' THEN 350
    WHEN u.devicelimit > 0 THEN u.devicelimit
    ELSE 30
  END as device_limit,

  -- Extract dates
  STR_TO_DATE(
    JSON_UNQUOTE(JSON_EXTRACT(u.attributes, '$.subscriptionStartDate')),
    '%Y-%m-%d %H:%i:%s'
  ) as start_date,

  u.expirationtime as current_period_end,

  -- Extract cancel flag
  COALESCE(
    CAST(JSON_UNQUOTE(JSON_EXTRACT(u.attributes, '$.cancelAtPeriodEnd')) AS UNSIGNED),
    0
  ) as cancel_at_period_end

FROM tc_users u
WHERE
  -- Only migrate users with Stripe subscription ID
  JSON_EXTRACT(u.attributes, '$.stripeSubscriptionId') IS NOT NULL
  AND JSON_UNQUOTE(JSON_EXTRACT(u.attributes, '$.stripeSubscriptionId')) != ''

  -- Avoid duplicates if script is run multiple times
  AND NOT EXISTS (
    SELECT 1 FROM tc_user_subscriptions s
    WHERE s.userid = u.id
  );

-- ============================================================================
-- STEP 2: Set device ownership based on tc_user_device
-- ============================================================================

-- Strategy: First user in tc_user_device becomes the owner
-- If you have a different logic, modify this query

INSERT INTO tc_device_ownership (deviceid, ownerid)
SELECT
  ud.deviceid,
  MIN(ud.userid) as ownerid
FROM tc_user_device ud
WHERE NOT EXISTS (
  SELECT 1 FROM tc_device_ownership do
  WHERE do.deviceid = ud.deviceid
)
GROUP BY ud.deviceid;

-- ============================================================================
-- STEP 3: Create initial history entries for migrated subscriptions
-- ============================================================================

INSERT INTO tc_subscription_history (
  userid,
  subscription_id,
  plan_id,
  status,
  event_type,
  description,
  metadata
)
SELECT
  s.userid,
  s.id,
  s.plan_id,
  s.status,
  'migrated',
  'Subscription migrated from user attributes',
  JSON_OBJECT(
    'plan_id', s.plan_id,
    'status', s.status,
    'device_limit', s.device_limit,
    'migration_date', NOW()
  )
FROM tc_user_subscriptions s
WHERE NOT EXISTS (
  SELECT 1 FROM tc_subscription_history h
  WHERE h.subscription_id = s.id
  AND h.event_type = 'migrated'
);

-- ============================================================================
-- STEP 4: Sync subscription data back to tc_users
-- ============================================================================

-- Update tc_users.devicelimit and expirationtime to match subscriptions
UPDATE tc_users u
INNER JOIN tc_user_subscriptions s ON u.id = s.userid
SET
  u.devicelimit = s.device_limit,
  u.expirationtime = s.current_period_end
WHERE s.status IN ('active', 'trialing');

-- ============================================================================
-- STEP 5: Verify Migration
-- ============================================================================

-- Show migration summary
SELECT
  'Total Users' as metric,
  COUNT(*) as count
FROM tc_users
UNION ALL
SELECT
  'Users with Subscriptions',
  COUNT(*)
FROM tc_user_subscriptions
UNION ALL
SELECT
  'Active Subscriptions',
  COUNT(*)
FROM tc_user_subscriptions
WHERE status IN ('active', 'trialing')
UNION ALL
SELECT
  'Devices with Ownership',
  COUNT(*)
FROM tc_device_ownership
UNION ALL
SELECT
  'History Entries',
  COUNT(*)
FROM tc_subscription_history;

-- Show subscriptions by plan
SELECT
  sp.name as plan_name,
  COUNT(s.id) as subscribers,
  SUM(sp.price) as monthly_revenue
FROM tc_subscription_plans sp
LEFT JOIN tc_user_subscriptions s ON sp.plan_id = s.plan_id AND s.status IN ('active', 'trialing')
GROUP BY sp.plan_id, sp.name, sp.price
ORDER BY sp.price;

-- Show users with potential issues
SELECT
  u.id,
  u.email,
  u.name,
  u.devicelimit as traccar_limit,
  s.device_limit as subscription_limit,
  (SELECT COUNT(*) FROM tc_device_ownership do WHERE do.ownerid = u.id) as owned_devices,
  s.status,
  CASE
    WHEN s.id IS NULL THEN 'No subscription found'
    WHEN s.status NOT IN ('active', 'trialing') THEN CONCAT('Inactive: ', s.status)
    WHEN (SELECT COUNT(*) FROM tc_device_ownership do WHERE do.ownerid = u.id) > s.device_limit THEN 'Over limit'
    ELSE 'OK'
  END as issue
FROM tc_users u
LEFT JOIN tc_user_subscriptions s ON u.id = s.userid AND s.status IN ('active', 'trialing')
HAVING issue != 'OK';

-- ============================================================================
-- CLEANUP (Optional - Only run if you want to remove old data)
-- ============================================================================

/*
-- Remove subscription data from user attributes after successful migration
-- UNCOMMENT AND RUN ONLY AFTER VERIFYING MIGRATION WAS SUCCESSFUL

UPDATE tc_users
SET attributes = JSON_REMOVE(
  attributes,
  '$.subscriptionPlan',
  '$.subscriptionStatus',
  '$.subscriptionStartDate',
  '$.stripeCustomerId',
  '$.stripeSubscriptionId',
  '$.stripePaymentMethodId',
  '$.cancelAtPeriodEnd'
)
WHERE attributes IS NOT NULL
AND (
  JSON_EXTRACT(attributes, '$.stripeSubscriptionId') IS NOT NULL
  OR JSON_EXTRACT(attributes, '$.stripeCustomerId') IS NOT NULL
);
*/
