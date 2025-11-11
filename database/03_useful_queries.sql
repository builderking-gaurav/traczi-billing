-- ============================================================================
-- Traczi Subscription System - Useful Queries
-- Common queries for managing and monitoring subscriptions
-- ============================================================================

-- ============================================================================
-- USER SUBSCRIPTION QUERIES
-- ============================================================================

-- Get complete subscription status for a user
SELECT *
FROM v_user_subscription_status
WHERE userid = 1;

-- Find user by email
SELECT *
FROM v_user_subscription_status
WHERE email LIKE '%test%';

-- List all active subscribers
SELECT
  userid,
  name,
  email,
  plan_name,
  owned_devices,
  subscription_device_limit,
  remaining_devices
FROM v_user_subscription_status
WHERE subscription_status = 'active'
ORDER BY name;

-- Find users at or over device limit
SELECT
  userid,
  name,
  email,
  plan_name,
  owned_devices,
  subscription_device_limit
FROM v_user_subscription_status
WHERE owned_devices >= subscription_device_limit
ORDER BY owned_devices DESC;

-- ============================================================================
-- DEVICE QUERIES
-- ============================================================================

-- List all devices with ownership info
SELECT *
FROM v_device_ownership_details
ORDER BY owner_name, device_name;

-- Find devices owned by specific user
SELECT
  device_name,
  uniqueid,
  device_status,
  users_with_access,
  shared_with
FROM v_device_ownership_details
WHERE ownerid = 1;

-- Find shared devices (multiple users have access)
SELECT
  deviceid,
  device_name,
  owner_name,
  users_with_access,
  shared_with
FROM v_device_ownership_details
WHERE users_with_access > 1
ORDER BY users_with_access DESC;

-- Find orphaned devices (in tc_devices but not in tc_device_ownership)
SELECT
  d.id,
  d.name,
  d.uniqueid,
  d.status
FROM tc_devices d
LEFT JOIN tc_device_ownership do ON d.id = do.deviceid
WHERE do.deviceid IS NULL;

-- ============================================================================
-- REVENUE & ANALYTICS QUERIES
-- ============================================================================

-- Revenue summary by plan
SELECT *
FROM v_subscription_analytics
ORDER BY monthly_revenue DESC;

-- Total revenue
SELECT
  SUM(monthly_revenue) as total_monthly_revenue,
  SUM(active_subscriptions) as total_active_subscriptions,
  AVG(price) as average_subscription_price
FROM v_subscription_analytics;

-- Revenue trend (last 6 months)
SELECT
  DATE_FORMAT(created_at, '%Y-%m') as month,
  COUNT(*) as new_subscriptions,
  SUM(CASE WHEN event_type = 'subscription_canceled' THEN 1 ELSE 0 END) as cancellations,
  COUNT(*) - SUM(CASE WHEN event_type = 'subscription_canceled' THEN 1 ELSE 0 END) as net_change
FROM tc_subscription_history
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 6 MONTH)
GROUP BY DATE_FORMAT(created_at, '%Y-%m')
ORDER BY month DESC;

-- Churn rate (cancellations vs active)
SELECT
  (SELECT COUNT(*) FROM tc_user_subscriptions WHERE cancel_at_period_end = TRUE) as pending_cancellations,
  (SELECT COUNT(*) FROM tc_user_subscriptions WHERE status = 'active') as active_subscriptions,
  ROUND(
    (SELECT COUNT(*) FROM tc_user_subscriptions WHERE cancel_at_period_end = TRUE) /
    (SELECT COUNT(*) FROM tc_user_subscriptions WHERE status = 'active') * 100,
    2
  ) as churn_rate_percent;

-- ============================================================================
-- SUBSCRIPTION STATUS QUERIES
-- ============================================================================

-- Subscriptions expiring soon (next 7 days)
SELECT
  userid,
  name,
  email,
  plan_name,
  current_period_end,
  days_until_renewal
FROM v_user_subscription_status
WHERE days_until_renewal BETWEEN 0 AND 7
  AND subscription_status = 'active'
ORDER BY days_until_renewal;

-- Expired subscriptions
SELECT
  userid,
  name,
  email,
  plan_name,
  current_period_end,
  days_until_renewal
FROM v_user_subscription_status
WHERE effective_status = 'expired'
ORDER BY current_period_end DESC;

-- Subscriptions with payment issues
SELECT
  u.id,
  u.email,
  u.name,
  s.plan_id,
  s.status,
  s.current_period_end,
  DATEDIFF(NOW(), s.current_period_end) as days_overdue
FROM tc_user_subscriptions s
INNER JOIN tc_users u ON s.userid = u.id
WHERE s.status IN ('past_due', 'unpaid')
ORDER BY days_overdue DESC;

-- Trial subscriptions
SELECT
  u.id,
  u.email,
  s.plan_id,
  s.trial_end,
  DATEDIFF(s.trial_end, NOW()) as days_remaining
FROM tc_user_subscriptions s
INNER JOIN tc_users u ON s.userid = u.id
WHERE s.status = 'trialing'
ORDER BY s.trial_end;

-- ============================================================================
-- SUBSCRIPTION HISTORY QUERIES
-- ============================================================================

-- Complete history for a user
SELECT
  created_at,
  event_type,
  plan_id,
  status,
  description
FROM tc_subscription_history
WHERE userid = 1
ORDER BY created_at DESC;

-- Recent subscription changes (last 24 hours)
SELECT
  u.email,
  h.event_type,
  h.plan_id,
  h.status,
  h.description,
  h.created_at
FROM tc_subscription_history h
INNER JOIN tc_users u ON h.userid = u.id
WHERE h.created_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
ORDER BY h.created_at DESC;

-- Plan change events
SELECT
  u.email,
  JSON_UNQUOTE(JSON_EXTRACT(h.metadata, '$.old_plan')) as from_plan,
  JSON_UNQUOTE(JSON_EXTRACT(h.metadata, '$.new_plan')) as to_plan,
  h.created_at
FROM tc_subscription_history h
INNER JOIN tc_users u ON h.userid = u.id
WHERE h.event_type = 'plan_changed'
ORDER BY h.created_at DESC;

-- ============================================================================
-- STRIPE EVENTS QUERIES
-- ============================================================================

-- Recent Stripe events
SELECT
  stripe_event_id,
  event_type,
  userid,
  processed,
  created_at,
  processed_at
FROM tc_stripe_events
ORDER BY created_at DESC
LIMIT 50;

-- Failed Stripe events (need attention)
SELECT
  id,
  stripe_event_id,
  event_type,
  error_message,
  created_at,
  payload
FROM tc_stripe_events
WHERE processed = FALSE
  OR error_message IS NOT NULL
ORDER BY created_at DESC;

-- Stripe events for specific customer
SELECT
  stripe_event_id,
  event_type,
  processed,
  error_message,
  created_at
FROM tc_stripe_events
WHERE stripe_customer_id = 'cus_...'
ORDER BY created_at DESC;

-- ============================================================================
-- USER MANAGEMENT QUERIES
-- ============================================================================

-- Create new subscription for user
INSERT INTO tc_user_subscriptions (
  userid, plan_id, device_limit, status, start_date
) VALUES (
  ?, 'basic', 30, 'active', NOW()
);

-- Update subscription plan
UPDATE tc_user_subscriptions
SET
  plan_id = 'moderate',
  device_limit = 80
WHERE userid = ?
  AND status = 'active';

-- Cancel subscription (end of period)
UPDATE tc_user_subscriptions
SET
  cancel_at_period_end = TRUE,
  canceled_at = NOW()
WHERE userid = ?
  AND status = 'active';

-- Reactivate canceled subscription
UPDATE tc_user_subscriptions
SET
  cancel_at_period_end = FALSE,
  canceled_at = NULL
WHERE userid = ?
  AND status = 'active'
  AND cancel_at_period_end = TRUE;

-- ============================================================================
-- DEVICE MANAGEMENT QUERIES
-- ============================================================================

-- Transfer device ownership
UPDATE tc_device_ownership
SET
  ownerid = ?,
  transferred_from = ownerid,
  transferred_at = NOW()
WHERE deviceid = ?;

-- Add device ownership (when creating new device)
INSERT INTO tc_device_ownership (deviceid, ownerid)
VALUES (?, ?);

-- Remove device ownership (when deleting device)
DELETE FROM tc_device_ownership
WHERE deviceid = ?;

-- ============================================================================
-- ADMIN & MONITORING QUERIES
-- ============================================================================

-- System health check
SELECT
  'Total Users' as metric,
  COUNT(*) as count
FROM tc_users

UNION ALL

SELECT
  'Active Subscriptions',
  COUNT(*)
FROM tc_user_subscriptions
WHERE status = 'active'

UNION ALL

SELECT
  'Total Devices',
  COUNT(*)
FROM tc_devices

UNION ALL

SELECT
  'Devices with Ownership',
  COUNT(*)
FROM tc_device_ownership

UNION ALL

SELECT
  'Pending Cancellations',
  COUNT(*)
FROM tc_user_subscriptions
WHERE cancel_at_period_end = TRUE

UNION ALL

SELECT
  'Past Due Subscriptions',
  COUNT(*)
FROM tc_user_subscriptions
WHERE status = 'past_due';

-- Database size report
SELECT
  table_name,
  ROUND(((data_length + index_length) / 1024 / 1024), 2) AS size_mb
FROM information_schema.TABLES
WHERE table_schema = 'traccar'
  AND table_name LIKE 'tc_%'
ORDER BY (data_length + index_length) DESC;

-- Recent user registrations with subscriptions
SELECT
  u.id,
  u.email,
  u.name,
  s.plan_id,
  s.status,
  s.created_at as subscription_created
FROM tc_users u
INNER JOIN tc_user_subscriptions s ON u.id = s.userid
WHERE s.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
ORDER BY s.created_at DESC;

-- Users without subscriptions
SELECT
  u.id,
  u.email,
  u.name,
  u.devicelimit,
  (SELECT COUNT(*) FROM tc_device_ownership WHERE ownerid = u.id) as owned_devices
FROM tc_users u
LEFT JOIN tc_user_subscriptions s ON u.id = s.userid
WHERE s.id IS NULL
  AND u.administrator = 0;

-- ============================================================================
-- BULK OPERATIONS
-- ============================================================================

-- Expire all past due subscriptions (older than 30 days)
UPDATE tc_user_subscriptions
SET
  status = 'canceled',
  ended_at = NOW()
WHERE status = 'past_due'
  AND current_period_end < DATE_SUB(NOW(), INTERVAL 30 DAY);

-- Sync all subscriptions to tc_users
-- (Useful after bulk updates)
UPDATE tc_users u
INNER JOIN tc_user_subscriptions s ON u.id = s.userid
SET
  u.devicelimit = s.device_limit,
  u.expirationtime = s.current_period_end
WHERE s.status IN ('active', 'trialing');

-- Clean up old Stripe events (keep last 90 days)
DELETE FROM tc_stripe_events
WHERE created_at < DATE_SUB(NOW(), INTERVAL 90 DAY)
  AND processed = TRUE
  AND error_message IS NULL;

-- ============================================================================
-- TESTING & DEBUG QUERIES
-- ============================================================================

-- Check stored procedure: Can user add device?
CALL sp_can_add_device(1, @can_add, @message, @remaining);
SELECT @can_add as can_add, @message as message, @remaining as remaining;

-- Check user subscription sync status
SELECT
  u.id,
  u.email,
  u.devicelimit as traccar_limit,
  s.device_limit as subscription_limit,
  u.expirationtime as traccar_expiry,
  s.current_period_end as subscription_expiry,
  CASE
    WHEN u.devicelimit != s.device_limit THEN 'MISMATCH: device limit'
    WHEN u.expirationtime != s.current_period_end THEN 'MISMATCH: expiry date'
    ELSE 'SYNCED'
  END as sync_status
FROM tc_users u
INNER JOIN tc_user_subscriptions s ON u.id = s.userid
WHERE s.status IN ('active', 'trialing');

-- Verify device ownership counts match
SELECT
  u.id,
  u.email,
  (SELECT COUNT(*) FROM tc_device_ownership WHERE ownerid = u.id) as ownership_count,
  s.device_limit,
  CASE
    WHEN (SELECT COUNT(*) FROM tc_device_ownership WHERE ownerid = u.id) > s.device_limit
    THEN 'OVER LIMIT'
    ELSE 'OK'
  END as status
FROM tc_users u
INNER JOIN tc_user_subscriptions s ON u.id = s.userid
WHERE s.status IN ('active', 'trialing');
