-- ============================================================================
-- Verify Current Database State
-- ============================================================================

-- 1. Check what data exists in user attributes
SELECT '=== USER ATTRIBUTES DATA ===' as section;
SELECT
  id,
  email,
  name,
  devicelimit,
  JSON_UNQUOTE(JSON_EXTRACT(attributes, '$.stripeSubscriptionId')) as has_stripe,
  JSON_UNQUOTE(JSON_EXTRACT(attributes, '$.subscriptionPlan')) as plan
FROM tc_users
WHERE attributes IS NOT NULL
ORDER BY id;

-- 2. Check device ownership
SELECT '=== DEVICE OWNERSHIP ===' as section;
SELECT
  ownerid,
  u.email,
  u.name,
  COUNT(*) as devices_owned
FROM tc_device_ownership do
INNER JOIN tc_users u ON do.ownerid = u.id
GROUP BY ownerid, u.email, u.name
ORDER BY devices_owned DESC;

-- 3. Check current subscriptions
SELECT '=== CURRENT SUBSCRIPTIONS ===' as section;
SELECT COUNT(*) as total_subscriptions FROM tc_user_subscriptions;

-- 4. Check subscription plans
SELECT '=== AVAILABLE PLANS ===' as section;
SELECT plan_id, name, price, device_limit FROM tc_subscription_plans ORDER BY price;

-- 5. Summary
SELECT '=== SUMMARY ===' as section;
SELECT
  'Total Users' as item,
  COUNT(*) as value
FROM tc_users
WHERE administrator = 0
UNION ALL
SELECT
  'Users with device limits',
  COUNT(*)
FROM tc_users
WHERE devicelimit > 0 AND administrator = 0
UNION ALL
SELECT
  'Users with Stripe data',
  COUNT(*)
FROM tc_users
WHERE JSON_EXTRACT(attributes, '$.stripeSubscriptionId') IS NOT NULL
  AND administrator = 0
UNION ALL
SELECT
  'Total Devices',
  COUNT(*)
FROM tc_devices
UNION ALL
SELECT
  'Devices with Ownership',
  COUNT(*)
FROM tc_device_ownership;
