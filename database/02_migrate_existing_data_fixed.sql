-- ============================================================================
-- Traczi Subscription System - Data Migration Script (FIXED)
-- Migrates existing subscription data from tc_users.attributes to new tables
-- ============================================================================

-- IMPORTANT: Run this AFTER running 01_create_subscription_tables.sql

-- ============================================================================
-- STEP 1: Migrate existing subscriptions from user attributes (FIXED)
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

  -- Extract dates - FIXED: Handle ISO 8601 format (2025-11-11T03:51:01.198Z)
  -- Convert ISO 8601 to MySQL TIMESTAMP by replacing 'T' with space and removing 'Z'
  CASE
    WHEN JSON_EXTRACT(u.attributes, '$.subscriptionStartDate') IS NOT NULL THEN
      CONVERT_TZ(
        STR_TO_DATE(
          REPLACE(REPLACE(JSON_UNQUOTE(JSON_EXTRACT(u.attributes, '$.subscriptionStartDate')), 'T', ' '), 'Z', ''),
          '%Y-%m-%d %H:%i:%s'
        ),
        '+00:00', @@session.time_zone
      )
    ELSE NOW()
  END as start_date,

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
-- STEP 2: Migrate users without Stripe data but with devicelimit set
-- ============================================================================

-- Create subscriptions for users who have devicelimit set but no Stripe data
-- This handles users who may have been set up manually
INSERT INTO tc_user_subscriptions (
  userid,
  plan_id,
  status,
  device_limit,
  start_date,
  current_period_end
)
SELECT
  u.id as userid,

  -- Determine plan based on device limit
  CASE
    WHEN u.devicelimit <= 5 THEN 'test'
    WHEN u.devicelimit <= 30 THEN 'basic'
    WHEN u.devicelimit <= 80 THEN 'moderate'
    WHEN u.devicelimit > 80 THEN 'advance'
    ELSE 'basic'
  END as plan_id,

  'active' as status,
  u.devicelimit as device_limit,
  NOW() as start_date,
  u.expirationtime as current_period_end

FROM tc_users u
WHERE
  -- Users with devicelimit set
  u.devicelimit > 0

  -- But no Stripe subscription ID
  AND (
    JSON_EXTRACT(u.attributes, '$.stripeSubscriptionId') IS NULL
    OR JSON_UNQUOTE(JSON_EXTRACT(u.attributes, '$.stripeSubscriptionId')) = ''
  )

  -- Avoid duplicates
  AND NOT EXISTS (
    SELECT 1 FROM tc_user_subscriptions s
    WHERE s.userid = u.id
  )

  -- Not administrator
  AND u.administrator = 0;

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

-- Show users with subscriptions
SELECT
  u.id,
  u.email,
  u.name,
  s.plan_id,
  s.status,
  s.device_limit,
  (SELECT COUNT(*) FROM tc_device_ownership do WHERE do.ownerid = u.id) as owned_devices,
  s.current_period_end,
  s.stripe_subscription_id
FROM tc_users u
INNER JOIN tc_user_subscriptions s ON u.id = s.userid
ORDER BY u.id;

-- Show users without subscriptions (potential issues)
SELECT
  u.id,
  u.email,
  u.name,
  u.devicelimit,
  u.administrator,
  (SELECT COUNT(*) FROM tc_device_ownership do WHERE do.ownerid = u.id) as owned_devices
FROM tc_users u
LEFT JOIN tc_user_subscriptions s ON u.id = s.userid
WHERE s.id IS NULL
  AND u.administrator = 0
ORDER BY u.id;
