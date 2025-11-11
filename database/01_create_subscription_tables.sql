-- ============================================================================
-- Traczi Subscription System - Database Schema
-- Compatible with Traccar's existing structure
-- ============================================================================

-- 1. Subscription Plans Table
-- Stores available subscription plans
CREATE TABLE IF NOT EXISTS tc_subscription_plans (
  id INT AUTO_INCREMENT PRIMARY KEY,
  plan_id VARCHAR(50) UNIQUE NOT NULL,
  name VARCHAR(100) NOT NULL,
  description VARCHAR(500),
  price DECIMAL(10,2) NOT NULL,
  currency VARCHAR(3) DEFAULT 'USD',
  device_limit INT NOT NULL,
  user_limit INT DEFAULT 0,
  features JSON,
  stripe_price_id VARCHAR(100),
  active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  INDEX idx_plan_id (plan_id),
  INDEX idx_active (active),
  INDEX idx_stripe_price (stripe_price_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Subscription plan definitions';

-- 2. User Subscriptions Table
-- Tracks active subscription per user
CREATE TABLE IF NOT EXISTS tc_user_subscriptions (
  id INT AUTO_INCREMENT PRIMARY KEY,
  userid INT NOT NULL,
  plan_id VARCHAR(50) NOT NULL,
  stripe_customer_id VARCHAR(100),
  stripe_subscription_id VARCHAR(100),
  stripe_payment_method_id VARCHAR(100),
  status VARCHAR(50) NOT NULL DEFAULT 'active',
  device_limit INT NOT NULL,
  user_limit INT DEFAULT 0,

  -- Dates
  start_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  current_period_start TIMESTAMP,
  current_period_end TIMESTAMP,
  trial_start TIMESTAMP NULL,
  trial_end TIMESTAMP NULL,
  canceled_at TIMESTAMP NULL,
  ended_at TIMESTAMP NULL,

  -- Flags
  cancel_at_period_end BOOLEAN DEFAULT FALSE,

  -- Timestamps
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  FOREIGN KEY (userid) REFERENCES tc_users(id) ON DELETE CASCADE,
  FOREIGN KEY (plan_id) REFERENCES tc_subscription_plans(plan_id),
  UNIQUE KEY unique_stripe_sub (stripe_subscription_id),
  INDEX idx_user_status (userid, status),
  INDEX idx_stripe_customer (stripe_customer_id),
  INDEX idx_period_end (current_period_end),
  INDEX idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Active user subscriptions';

-- 3. Subscription History Table
-- Keeps full history of all subscription changes
CREATE TABLE IF NOT EXISTS tc_subscription_history (
  id INT AUTO_INCREMENT PRIMARY KEY,
  userid INT NOT NULL,
  subscription_id INT,
  plan_id VARCHAR(50),
  status VARCHAR(50),
  event_type VARCHAR(50) NOT NULL,
  description TEXT,
  metadata JSON,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

  FOREIGN KEY (userid) REFERENCES tc_users(id) ON DELETE CASCADE,
  FOREIGN KEY (subscription_id) REFERENCES tc_user_subscriptions(id) ON DELETE SET NULL,
  INDEX idx_user_date (userid, created_at),
  INDEX idx_event_type (event_type),
  INDEX idx_subscription (subscription_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Subscription change history';

-- 4. Stripe Events Table
-- Stores Stripe webhook events for debugging and audit
CREATE TABLE IF NOT EXISTS tc_stripe_events (
  id INT AUTO_INCREMENT PRIMARY KEY,
  stripe_event_id VARCHAR(100) UNIQUE NOT NULL,
  event_type VARCHAR(100) NOT NULL,
  stripe_customer_id VARCHAR(100),
  stripe_subscription_id VARCHAR(100),
  userid INT,
  payload JSON,
  processed BOOLEAN DEFAULT FALSE,
  error_message TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  processed_at TIMESTAMP NULL,

  INDEX idx_stripe_event (stripe_event_id),
  INDEX idx_event_type (event_type),
  INDEX idx_customer (stripe_customer_id),
  INDEX idx_subscription (stripe_subscription_id),
  INDEX idx_processed (processed, created_at),
  FOREIGN KEY (userid) REFERENCES tc_users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Stripe webhook events log';

-- 5. Device Ownership Table
-- Tracks which user OWNS each device (for billing purposes)
-- Note: tc_user_device tracks ACCESS, this tracks OWNERSHIP
CREATE TABLE IF NOT EXISTS tc_device_ownership (
  deviceid INT PRIMARY KEY,
  ownerid INT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  transferred_from INT NULL,
  transferred_at TIMESTAMP NULL,

  FOREIGN KEY (deviceid) REFERENCES tc_devices(id) ON DELETE CASCADE,
  FOREIGN KEY (ownerid) REFERENCES tc_users(id) ON DELETE CASCADE,
  FOREIGN KEY (transferred_from) REFERENCES tc_users(id) ON DELETE SET NULL,
  INDEX idx_owner (ownerid),
  INDEX idx_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Device ownership for billing';

-- ============================================================================
-- VIEWS
-- ============================================================================

-- View: Active subscriptions with device counts
CREATE OR REPLACE VIEW v_user_subscription_status AS
SELECT
  u.id as userid,
  u.name,
  u.email,
  u.devicelimit as traccar_device_limit,
  s.plan_id,
  sp.name as plan_name,
  s.status as subscription_status,
  s.device_limit as subscription_device_limit,
  s.current_period_end,
  s.cancel_at_period_end,

  -- Count owned devices
  (SELECT COUNT(*)
   FROM tc_device_ownership do
   WHERE do.ownerid = u.id) as owned_devices,

  -- Count accessible devices (including shared)
  (SELECT COUNT(*)
   FROM tc_user_device ud
   WHERE ud.userid = u.id) as accessible_devices,

  -- Calculate remaining slots
  s.device_limit - (SELECT COUNT(*)
                    FROM tc_device_ownership do
                    WHERE do.ownerid = u.id) as remaining_devices,

  -- Subscription status flags
  CASE
    WHEN s.status = 'active' AND s.current_period_end < NOW() THEN 'expired'
    WHEN s.status = 'past_due' THEN 'payment_required'
    WHEN s.status = 'trialing' AND s.trial_end < NOW() THEN 'trial_expired'
    WHEN (SELECT COUNT(*) FROM tc_device_ownership do WHERE do.ownerid = u.id) >= s.device_limit THEN 'limit_reached'
    ELSE s.status
  END as effective_status,

  DATEDIFF(s.current_period_end, NOW()) as days_until_renewal,
  s.stripe_customer_id,
  s.stripe_subscription_id

FROM tc_users u
LEFT JOIN tc_user_subscriptions s
  ON u.id = s.userid
  AND s.status IN ('active', 'trialing', 'past_due')
LEFT JOIN tc_subscription_plans sp
  ON s.plan_id = sp.plan_id;

-- View: Device ownership details
CREATE OR REPLACE VIEW v_device_ownership_details AS
SELECT
  d.id as deviceid,
  d.name as device_name,
  d.uniqueid,
  d.status as device_status,
  d.disabled,
  do.ownerid,
  u.name as owner_name,
  u.email as owner_email,

  -- Count how many users have access
  (SELECT COUNT(*)
   FROM tc_user_device ud
   WHERE ud.deviceid = d.id) as users_with_access,

  -- List users with access (comma-separated)
  (SELECT GROUP_CONCAT(u2.name SEPARATOR ', ')
   FROM tc_user_device ud2
   INNER JOIN tc_users u2 ON ud2.userid = u2.id
   WHERE ud2.deviceid = d.id) as shared_with,

  do.created_at as owned_since,
  do.transferred_from

FROM tc_devices d
INNER JOIN tc_device_ownership do ON d.id = do.deviceid
INNER JOIN tc_users u ON do.ownerid = u.id;

-- View: Subscription revenue analytics
CREATE OR REPLACE VIEW v_subscription_analytics AS
SELECT
  sp.plan_id,
  sp.name as plan_name,
  sp.price,
  COUNT(s.id) as active_subscriptions,
  SUM(sp.price) as monthly_revenue,
  AVG(DATEDIFF(NOW(), s.start_date)) as avg_subscription_age_days,
  SUM(CASE WHEN s.cancel_at_period_end THEN 1 ELSE 0 END) as pending_cancellations,

  -- Device usage stats
  AVG((SELECT COUNT(*)
       FROM tc_device_ownership do
       WHERE do.ownerid = s.userid)) as avg_devices_per_user,

  SUM(CASE
    WHEN (SELECT COUNT(*)
          FROM tc_device_ownership do
          WHERE do.ownerid = s.userid) >= sp.device_limit
    THEN 1 ELSE 0
  END) as users_at_limit

FROM tc_subscription_plans sp
LEFT JOIN tc_user_subscriptions s
  ON sp.plan_id = s.plan_id
  AND s.status IN ('active', 'trialing')
GROUP BY sp.plan_id, sp.name, sp.price;

-- ============================================================================
-- STORED PROCEDURES
-- ============================================================================

DELIMITER //

-- Procedure: Check if user can add a device
CREATE PROCEDURE sp_can_add_device(
  IN p_userid INT,
  OUT p_can_add BOOLEAN,
  OUT p_message VARCHAR(255),
  OUT p_remaining INT
)
BEGIN
  DECLARE v_device_limit INT;
  DECLARE v_current_count INT;
  DECLARE v_status VARCHAR(50);

  -- Get user's subscription info
  SELECT
    device_limit,
    status,
    (SELECT COUNT(*) FROM tc_device_ownership WHERE ownerid = p_userid)
  INTO v_device_limit, v_status, v_current_count
  FROM tc_user_subscriptions
  WHERE userid = p_userid
    AND status IN ('active', 'trialing')
  LIMIT 1;

  -- Check if user has active subscription
  IF v_status IS NULL THEN
    SET p_can_add = FALSE;
    SET p_message = 'No active subscription found';
    SET p_remaining = 0;
  -- Check device limit
  ELSEIF v_current_count >= v_device_limit THEN
    SET p_can_add = FALSE;
    SET p_message = CONCAT('Device limit reached (', v_device_limit, ' devices)');
    SET p_remaining = 0;
  ELSE
    SET p_can_add = TRUE;
    SET p_remaining = v_device_limit - v_current_count;
    SET p_message = CONCAT('Can add ', p_remaining, ' more device(s)');
  END IF;
END//

-- Procedure: Sync subscription to Traccar user fields
CREATE PROCEDURE sp_sync_subscription_to_user(
  IN p_userid INT
)
BEGIN
  DECLARE v_device_limit INT;
  DECLARE v_expiration TIMESTAMP;

  -- Get subscription info
  SELECT
    device_limit,
    current_period_end
  INTO v_device_limit, v_expiration
  FROM tc_user_subscriptions
  WHERE userid = p_userid
    AND status IN ('active', 'trialing')
  LIMIT 1;

  -- Update tc_users fields to keep Traccar in sync
  UPDATE tc_users
  SET
    devicelimit = COALESCE(v_device_limit, -1),
    expirationtime = v_expiration
  WHERE id = p_userid;
END//

-- Procedure: Create subscription history entry
CREATE PROCEDURE sp_add_subscription_history(
  IN p_userid INT,
  IN p_subscription_id INT,
  IN p_event_type VARCHAR(50),
  IN p_description TEXT,
  IN p_metadata JSON
)
BEGIN
  DECLARE v_plan_id VARCHAR(50);
  DECLARE v_status VARCHAR(50);

  -- Get current subscription info
  SELECT plan_id, status
  INTO v_plan_id, v_status
  FROM tc_user_subscriptions
  WHERE id = p_subscription_id;

  -- Insert history record
  INSERT INTO tc_subscription_history (
    userid, subscription_id, plan_id, status,
    event_type, description, metadata
  ) VALUES (
    p_userid, p_subscription_id, v_plan_id, v_status,
    p_event_type, p_description, p_metadata
  );
END//

DELIMITER ;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

DELIMITER //

-- Trigger: Sync subscription changes to tc_users
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

-- Trigger: Add history entry on subscription changes
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

-- ============================================================================
-- INSERT DEFAULT PLANS
-- ============================================================================

INSERT INTO tc_subscription_plans (plan_id, name, description, price, device_limit, stripe_price_id, features) VALUES
('test', 'Test Plan', 'Perfect for testing with up to 5 devices', 5.00, 5, 'price_1SSEtvQdFmHlqkLVLcforalC',
 JSON_ARRAY('Up to 5 devices', 'Real-time tracking', 'Basic reports', 'Email support')),

('basic', 'Basic Plan', 'Ideal for small fleets with up to 30 devices', 20.00, 30, 'price_1SRv6DQdFmHlqkLVsvSNdI03',
 JSON_ARRAY('Up to 30 devices', 'Real-time tracking', 'Basic reports', 'Email support')),

('moderate', 'Moderate Plan', 'Great for growing businesses with up to 80 devices', 40.00, 80, 'price_1SRv7LQdFmHlqkLVqGzYmitb',
 JSON_ARRAY('Up to 80 devices', 'Real-time tracking', 'Advanced reports', 'Geofencing', 'Priority email support')),

('advance', 'Advance Plan', 'Enterprise solution with up to 350 devices', 100.00, 350, 'price_1SRv90QdFmHlqkLVxImJEMZ9',
 JSON_ARRAY('Up to 350 devices', 'Real-time tracking', 'All reports', 'Advanced geofencing', 'API access', '24/7 priority support'));

-- ============================================================================
-- GRANT PERMISSIONS (adjust username as needed)
-- ============================================================================

-- GRANT SELECT, INSERT, UPDATE ON traccar.tc_subscription_* TO 'traccar'@'localhost';
-- GRANT SELECT, INSERT, UPDATE ON traccar.tc_stripe_events TO 'traccar'@'localhost';
-- GRANT SELECT, INSERT, UPDATE, DELETE ON traccar.tc_device_ownership TO 'traccar'@'localhost';
-- GRANT EXECUTE ON PROCEDURE traccar.sp_can_add_device TO 'traccar'@'localhost';
-- GRANT EXECUTE ON PROCEDURE traccar.sp_sync_subscription_to_user TO 'traccar'@'localhost';
