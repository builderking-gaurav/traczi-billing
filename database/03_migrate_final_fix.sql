-- ============================================================================
-- Traczi Subscription System - Final Migration Fix
-- Properly handles ISO 8601 timestamps with milliseconds
-- ============================================================================

-- IMPORTANT: This fixes the milliseconds issue in timestamps

-- ============================================================================
-- STEP 1: Migrate users WITH Stripe subscription data
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

  -- Extract dates - FINAL FIX: Handle ISO 8601 format with milliseconds
  -- Format: 2025-11-11T03:51:01.198Z
  -- Step 1: Extract the raw date string
  -- Step 2: Replace T with space, remove Z
  -- Step 3: Remove milliseconds by taking substring before the dot
  -- Step 4: Parse as datetime
  CASE
    WHEN JSON_EXTRACT(u.attributes, '$.subscriptionStartDate') IS NOT NULL THEN
      STR_TO_DATE(
        -- Remove milliseconds: take everything before the last dot if it exists
        SUBSTRING_INDEX(
          -- Replace T with space and remove Z
          REPLACE(REPLACE(
            JSON_UNQUOTE(JSON_EXTRACT(u.attributes, '$.subscriptionStartDate')),
            'T', ' '
          ), 'Z', ''),
          '.', 1  -- Take everything before the first dot (removes .198)
        ),
        '%Y-%m-%d %H:%i:%s'
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

-- Show result of first migration
SELECT
  CONCAT('Migrated ', COUNT(*), ' users with Stripe subscription data') as result
FROM tc_user_subscriptions;

-- ============================================================================
-- STEP 2: Migrate users WITHOUT Stripe data but WITH devicelimit set
-- ============================================================================

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

  -- If expirationtime is NULL, set to 1 year from now
  COALESCE(u.expirationtime, DATE_ADD(NOW(), INTERVAL 1 YEAR)) as current_period_end

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

-- Show result of second migration
SELECT
  CONCAT('Migrated ', COUNT(*), ' users without Stripe data') as result
FROM tc_user_subscriptions
WHERE stripe_subscription_id IS NULL;

-- ============================================================================
-- STEP 3: Create initial history entries
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
  CASE
    WHEN s.stripe_subscription_id IS NOT NULL THEN 'Subscription migrated from user attributes (Stripe data)'
    ELSE 'Subscription created from devicelimit (no Stripe data)'
  END as description,
  JSON_OBJECT(
    'plan_id', s.plan_id,
    'status', s.status,
    'device_limit', s.device_limit,
    'has_stripe_data', IF(s.stripe_subscription_id IS NOT NULL, true, false),
    'migration_date', NOW()
  )
FROM tc_user_subscriptions s
WHERE NOT EXISTS (
  SELECT 1 FROM tc_subscription_history h
  WHERE h.subscription_id = s.id
  AND h.event_type = 'migrated'
);

-- ============================================================================
-- STEP 4: Sync to tc_users
-- ============================================================================

UPDATE tc_users u
INNER JOIN tc_user_subscriptions s ON u.id = s.userid
SET
  u.devicelimit = s.device_limit,
  u.expirationtime = s.current_period_end
WHERE s.status IN ('active', 'trialing');

SELECT CONCAT('Synced ', ROW_COUNT(), ' users to tc_users table') as result;

-- ============================================================================
-- STEP 5: Detailed Verification
-- ============================================================================

SELECT '=== MIGRATION SUMMARY ===' as section;

SELECT
  'Total Users' as metric,
  COUNT(*) as count
FROM tc_users
WHERE administrator = 0
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
  'With Stripe Data',
  COUNT(*)
FROM tc_user_subscriptions
WHERE stripe_subscription_id IS NOT NULL
UNION ALL
SELECT
  'Without Stripe Data',
  COUNT(*)
FROM tc_user_subscriptions
WHERE stripe_subscription_id IS NULL
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
SELECT '=== SUBSCRIPTIONS BY PLAN ===' as section;

SELECT
  sp.name as plan_name,
  sp.price,
  COUNT(s.id) as subscribers,
  SUM(sp.price) as monthly_revenue
FROM tc_subscription_plans sp
LEFT JOIN tc_user_subscriptions s ON sp.plan_id = s.plan_id AND s.status IN ('active', 'trialing')
GROUP BY sp.plan_id, sp.name, sp.price
ORDER BY sp.price;

-- Show all users with their subscription status
SELECT '=== USER SUBSCRIPTION STATUS ===' as section;

SELECT
  u.id,
  u.email,
  u.name,
  u.devicelimit as traccar_limit,
  s.plan_id,
  s.device_limit as sub_limit,
  s.status,
  (SELECT COUNT(*) FROM tc_device_ownership do WHERE do.ownerid = u.id) as owned_devices,
  IF(s.stripe_subscription_id IS NOT NULL, 'Yes', 'No') as has_stripe,
  s.current_period_end
FROM tc_users u
LEFT JOIN tc_user_subscriptions s ON u.id = s.userid
WHERE u.administrator = 0
ORDER BY u.id;

-- Show any remaining issues
SELECT '=== USERS WITHOUT SUBSCRIPTIONS ===' as section;

SELECT
  u.id,
  u.email,
  u.name,
  u.devicelimit,
  (SELECT COUNT(*) FROM tc_device_ownership do WHERE do.ownerid = u.id) as owned_devices
FROM tc_users u
LEFT JOIN tc_user_subscriptions s ON u.id = s.userid
WHERE s.id IS NULL
  AND u.administrator = 0
ORDER BY u.id;
