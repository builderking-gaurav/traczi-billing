-- ============================================================================
-- Migration with Triggers Disabled
-- This avoids the circular reference issue
-- ============================================================================

-- Step 1: Disable triggers temporarily
SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='';
DROP TRIGGER IF EXISTS tr_subscription_sync_after_insert;
DROP TRIGGER IF EXISTS tr_subscription_sync_after_update;
DROP TRIGGER IF EXISTS tr_subscription_history_after_insert;
DROP TRIGGER IF EXISTS tr_subscription_history_after_update;
SET SQL_MODE=@OLD_SQL_MODE;

SELECT '✓ Triggers temporarily disabled' as step_0;

-- Step 1: Create subscriptions for all users with devicelimit > 0
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

  -- Assign plan based on devicelimit
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
  DATE_ADD(NOW(), INTERVAL 1 YEAR) as current_period_end

FROM tc_users u
WHERE u.devicelimit > 0
  AND u.administrator = 0
  AND NOT EXISTS (
    SELECT 1 FROM tc_user_subscriptions s WHERE s.userid = u.id
  );

SELECT CONCAT('✓ Created ', ROW_COUNT(), ' subscriptions') as step_1;

-- Step 2: Manually sync to tc_users (since triggers are disabled)
UPDATE tc_users u
INNER JOIN tc_user_subscriptions s ON u.id = s.userid
SET
  u.expirationtime = s.current_period_end
WHERE s.status IN ('active', 'trialing');

SELECT CONCAT('✓ Synced ', ROW_COUNT(), ' users') as step_2;

-- Step 3: Create history entries manually
INSERT INTO tc_subscription_history (
  userid, subscription_id, plan_id, status, event_type, description, metadata
)
SELECT
  s.userid, s.id, s.plan_id, s.status,
  'migrated',
  'Subscription created from existing devicelimit',
  JSON_OBJECT(
    'plan_id', s.plan_id,
    'device_limit', s.device_limit,
    'migration_date', NOW()
  )
FROM tc_user_subscriptions s
WHERE NOT EXISTS (
  SELECT 1 FROM tc_subscription_history h
  WHERE h.subscription_id = s.id AND h.event_type = 'migrated'
);

SELECT CONCAT('✓ Created ', ROW_COUNT(), ' history entries') as step_3;

-- Step 4: Re-enable triggers
DELIMITER //

CREATE TRIGGER tr_subscription_sync_after_insert
AFTER INSERT ON tc_user_subscriptions
FOR EACH ROW
BEGIN
  IF NEW.status IN ('active', 'trialing') THEN
    CALL sp_sync_subscription_to_user(NEW.userid);
  END IF;
END//

CREATE TRIGGER tr_subscription_sync_after_update
AFTER UPDATE ON tc_user_subscriptions
FOR EACH ROW
BEGIN
  IF NEW.status IN ('active', 'trialing') OR OLD.status IN ('active', 'trialing') THEN
    CALL sp_sync_subscription_to_user(NEW.userid);
  END IF;
END//

CREATE TRIGGER tr_subscription_history_after_insert
AFTER INSERT ON tc_user_subscriptions
FOR EACH ROW
BEGIN
  CALL sp_add_subscription_history(
    NEW.userid,
    NEW.id,
    'subscription_created',
    CONCAT('Subscription created: ', NEW.plan_id),
    JSON_OBJECT(
      'plan_id', NEW.plan_id,
      'status', NEW.status,
      'device_limit', NEW.device_limit
    )
  );
END//

CREATE TRIGGER tr_subscription_history_after_update
AFTER UPDATE ON tc_user_subscriptions
FOR EACH ROW
BEGIN
  IF OLD.status != NEW.status THEN
    CALL sp_add_subscription_history(
      NEW.userid,
      NEW.id,
      'status_changed',
      CONCAT('Status changed from ', OLD.status, ' to ', NEW.status),
      JSON_OBJECT(
        'old_status', OLD.status,
        'new_status', NEW.status
      )
    );
  END IF;

  IF OLD.plan_id != NEW.plan_id THEN
    CALL sp_add_subscription_history(
      NEW.userid,
      NEW.id,
      'plan_changed',
      CONCAT('Plan changed from ', OLD.plan_id, ' to ', NEW.plan_id),
      JSON_OBJECT(
        'old_plan', OLD.plan_id,
        'new_plan', NEW.plan_id
      )
    );
  END IF;
END//

DELIMITER ;

SELECT '✓ Triggers re-enabled' as step_4;

-- Verification
SELECT '========================================' as divider;
SELECT '         MIGRATION SUMMARY              ' as title;
SELECT '========================================' as divider;

SELECT
  'Total Users (non-admin)' as metric,
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
  'Devices with Ownership',
  COUNT(*)
FROM tc_device_ownership
UNION ALL
SELECT
  'History Entries',
  COUNT(*)
FROM tc_subscription_history;

-- Show subscriptions by plan
SELECT '========================================' as divider;
SELECT '       SUBSCRIPTIONS BY PLAN            ' as title;
SELECT '========================================' as divider;

SELECT
  sp.name as plan_name,
  sp.device_limit,
  sp.price as monthly_price,
  COUNT(s.id) as subscribers,
  SUM(sp.price) as total_revenue
FROM tc_subscription_plans sp
LEFT JOIN tc_user_subscriptions s ON sp.plan_id = s.plan_id AND s.status IN ('active', 'trialing')
GROUP BY sp.plan_id, sp.name, sp.device_limit, sp.price
ORDER BY sp.price;

-- Show all users with their subscription details
SELECT '========================================' as divider;
SELECT '       USER SUBSCRIPTION STATUS         ' as title;
SELECT '========================================' as divider;

SELECT
  u.id,
  u.email,
  LEFT(u.name, 15) as name,
  s.plan_id,
  s.device_limit,
  s.status,
  (SELECT COUNT(*) FROM tc_device_ownership do WHERE do.ownerid = u.id) as owned,
  CASE
    WHEN s.device_limit IS NULL THEN 'No subscription'
    WHEN (SELECT COUNT(*) FROM tc_device_ownership do WHERE do.ownerid = u.id) >= s.device_limit THEN '⚠️ At limit'
    ELSE '✓ OK'
  END as status_check
FROM tc_users u
LEFT JOIN tc_user_subscriptions s ON u.id = s.userid
WHERE u.administrator = 0
ORDER BY u.id;

-- Test the view
SELECT '========================================' as divider;
SELECT '     TESTING SUBSCRIPTION VIEW          ' as title;
SELECT '========================================' as divider;

SELECT
  userid,
  LEFT(name, 15) as name,
  plan_name,
  subscription_status,
  owned_devices,
  subscription_device_limit as limit_val,
  remaining_devices
FROM v_user_subscription_status
WHERE userid IN (5, 6, 9, 17, 19)
ORDER BY userid;

SELECT '========================================' as divider;
SELECT '✓✓✓ MIGRATION COMPLETE! ✓✓✓            ' as status;
SELECT '========================================' as divider;
