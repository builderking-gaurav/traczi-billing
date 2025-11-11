# Traczi Subscription Database Schema

Complete database schema for subscription-based GPS tracking system built on Traccar.

## 📋 Files

1. **`01_create_subscription_tables.sql`** - Creates all subscription tables, views, procedures, and triggers
2. **`02_migrate_existing_data.sql`** - Migrates existing subscription data from user attributes
3. **`03_useful_queries.sql`** - Common queries for managing subscriptions
4. **`04_backup_restore.sql`** - Backup and restore procedures

## 🚀 Installation

### Step 1: Backup Your Database

```bash
mysqldump -u root -p traccar > traccar_backup_$(date +%Y%m%d_%H%M%S).sql
```

### Step 2: Run Schema Creation

```bash
mysql -u root -p traccar < 01_create_subscription_tables.sql
```

### Step 3: Migrate Existing Data

```bash
mysql -u root -p traccar < 02_migrate_existing_data.sql
```

### Step 4: Verify Migration

```sql
-- Check migration status
SELECT * FROM v_user_subscription_status;

-- Check for any issues
SELECT * FROM v_user_subscription_status
WHERE effective_status IN ('expired', 'payment_required', 'limit_reached');
```

## 📊 Database Structure

### Core Tables

#### 1. `tc_subscription_plans`
Stores available subscription plans (Test, Basic, Moderate, Advance).

```sql
+------------------+---------------+
| Field            | Type          |
+------------------+---------------+
| id               | INT           |
| plan_id          | VARCHAR(50)   |
| name             | VARCHAR(100)  |
| price            | DECIMAL(10,2) |
| device_limit     | INT           |
| stripe_price_id  | VARCHAR(100)  |
| features         | JSON          |
+------------------+---------------+
```

#### 2. `tc_user_subscriptions`
Tracks active subscription per user.

```sql
+---------------------------+---------------+
| Field                     | Type          |
+---------------------------+---------------+
| id                        | INT           |
| userid                    | INT           |
| plan_id                   | VARCHAR(50)   |
| stripe_customer_id        | VARCHAR(100)  |
| stripe_subscription_id    | VARCHAR(100)  |
| status                    | VARCHAR(50)   |
| device_limit              | INT           |
| current_period_end        | TIMESTAMP     |
| cancel_at_period_end      | BOOLEAN       |
+---------------------------+---------------+
```

#### 3. `tc_device_ownership`
Tracks which user **owns** each device for billing.

```sql
+-------------------+---------------+
| Field             | Type          |
+-------------------+---------------+
| deviceid          | INT (PK)      |
| ownerid           | INT           |
| created_at        | TIMESTAMP     |
| transferred_from  | INT           |
+-------------------+---------------+
```

**Important Distinction:**
- `tc_user_device` → Who can **ACCESS** the device (many-to-many)
- `tc_device_ownership` → Who **OWNS** the device for billing (one-to-one)

#### 4. `tc_subscription_history`
Full audit trail of all subscription changes.

#### 5. `tc_stripe_events`
Logs all Stripe webhook events for debugging.

### Views

#### `v_user_subscription_status`
Complete subscription status for each user including device counts.

```sql
SELECT * FROM v_user_subscription_status WHERE userid = 1;
```

#### `v_device_ownership_details`
Shows device ownership and sharing information.

```sql
SELECT * FROM v_device_ownership_details;
```

#### `v_subscription_analytics`
Revenue and usage analytics per plan.

```sql
SELECT * FROM v_subscription_analytics;
```

## 🔧 Stored Procedures

### `sp_can_add_device(userid, OUT can_add, OUT message, OUT remaining)`

Checks if user can add another device.

```sql
CALL sp_can_add_device(1, @can_add, @message, @remaining);
SELECT @can_add, @message, @remaining;
```

### `sp_sync_subscription_to_user(userid)`

Syncs subscription data to Traccar's user fields.

```sql
CALL sp_sync_subscription_to_user(1);
```

### `sp_add_subscription_history(userid, subscription_id, event_type, description, metadata)`

Adds entry to subscription history.

```sql
CALL sp_add_subscription_history(
  1,
  1,
  'plan_upgraded',
  'User upgraded from basic to moderate',
  '{"old_plan": "basic", "new_plan": "moderate"}'
);
```

## 🔄 Automatic Features

### Triggers

1. **Subscription Sync** - Automatically updates `tc_users.devicelimit` when subscription changes
2. **History Tracking** - Automatically logs all subscription changes
3. **Status Updates** - Tracks plan changes and status transitions

### Integrations

- ✅ Syncs with Traccar's built-in `devicelimit` field
- ✅ Compatible with Traccar's device sharing via `tc_user_device`
- ✅ Preserves Traccar's existing authentication and permissions
- ✅ Works with Traccar's `expirationtime` for subscription expiry

## 💡 Common Use Cases

### Check User's Subscription Status

```sql
SELECT
  userid,
  name,
  email,
  plan_name,
  subscription_status,
  owned_devices,
  remaining_devices,
  days_until_renewal
FROM v_user_subscription_status
WHERE userid = 1;
```

### List Devices User Owns

```sql
SELECT
  device_name,
  uniqueid,
  device_status,
  users_with_access,
  shared_with
FROM v_device_ownership_details
WHERE ownerid = 1;
```

### Find Users Over Limit

```sql
SELECT *
FROM v_user_subscription_status
WHERE owned_devices > subscription_device_limit;
```

### Revenue Report

```sql
SELECT
  plan_name,
  active_subscriptions,
  monthly_revenue,
  avg_devices_per_user,
  users_at_limit
FROM v_subscription_analytics
ORDER BY monthly_revenue DESC;
```

### Subscription Expiring Soon

```sql
SELECT
  userid,
  name,
  email,
  plan_name,
  days_until_renewal,
  current_period_end
FROM v_user_subscription_status
WHERE days_until_renewal BETWEEN 0 AND 7
  AND subscription_status = 'active'
ORDER BY days_until_renewal;
```

## 🔐 Security Considerations

1. **Grant Minimal Permissions**
   ```sql
   GRANT SELECT, INSERT, UPDATE ON traccar.tc_subscription_* TO 'app_user'@'localhost';
   GRANT SELECT ON traccar.v_* TO 'app_user'@'localhost';
   ```

2. **Protect Stripe Data**
   - Never expose Stripe IDs in public APIs
   - Log webhook events for audit trail
   - Store sensitive data in `tc_stripe_events`

3. **Device Limits**
   - Always check `sp_can_add_device()` before adding devices
   - Enforce limits in application code
   - Alert users when approaching limit

## 📈 Monitoring Queries

### Subscription Health Check

```sql
SELECT
  'Active Subscriptions' as metric,
  COUNT(*) as value
FROM tc_user_subscriptions
WHERE status = 'active'

UNION ALL

SELECT
  'Expired This Week',
  COUNT(*)
FROM tc_user_subscriptions
WHERE current_period_end BETWEEN DATE_SUB(NOW(), INTERVAL 7 DAY) AND NOW()

UNION ALL

SELECT
  'Pending Cancellations',
  COUNT(*)
FROM tc_user_subscriptions
WHERE cancel_at_period_end = TRUE AND status = 'active';
```

### Failed Payments

```sql
SELECT
  u.email,
  s.plan_id,
  s.status,
  s.current_period_end,
  DATEDIFF(NOW(), s.current_period_end) as days_overdue
FROM tc_user_subscriptions s
INNER JOIN tc_users u ON s.userid = u.id
WHERE s.status = 'past_due'
ORDER BY days_overdue DESC;
```

## 🔄 Maintenance

### Monthly Cleanup

```sql
-- Archive old Stripe events (keep last 90 days)
DELETE FROM tc_stripe_events
WHERE created_at < DATE_SUB(NOW(), INTERVAL 90 DAY)
  AND processed = TRUE;

-- Archive old subscription history (keep last 2 years)
-- Create archive table first, then delete from main table
```

### Subscription Expiry Cleanup

```sql
-- Mark subscriptions as ended if past due for 30+ days
UPDATE tc_user_subscriptions
SET
  status = 'canceled',
  ended_at = NOW()
WHERE status = 'past_due'
  AND current_period_end < DATE_SUB(NOW(), INTERVAL 30 DAY);
```

## 🐛 Troubleshooting

### Subscription Not Showing

```sql
-- Check user attributes
SELECT id, email, attributes
FROM tc_users
WHERE id = 1;

-- Check subscription record
SELECT * FROM tc_user_subscriptions WHERE userid = 1;

-- Force sync
CALL sp_sync_subscription_to_user(1);
```

### Device Count Mismatch

```sql
-- Check ownership vs access
SELECT
  u.id,
  u.email,
  (SELECT COUNT(*) FROM tc_device_ownership WHERE ownerid = u.id) as owned,
  (SELECT COUNT(*) FROM tc_user_device WHERE userid = u.id) as accessible
FROM tc_users u
WHERE id = 1;
```

### Migration Issues

```sql
-- Check for users without subscriptions
SELECT u.id, u.email, u.name
FROM tc_users u
LEFT JOIN tc_user_subscriptions s ON u.id = s.userid
WHERE s.id IS NULL
  AND JSON_EXTRACT(u.attributes, '$.stripeSubscriptionId') IS NOT NULL;
```

## 📚 Additional Resources

- [Traccar Documentation](https://www.traccar.org/documentation/)
- [Stripe API Reference](https://stripe.com/docs/api)
- [MariaDB JSON Functions](https://mariadb.com/kb/en/json-functions/)

## 🤝 Support

For issues or questions:
1. Check the troubleshooting section above
2. Review the useful queries in `03_useful_queries.sql`
3. Check subscription history: `SELECT * FROM tc_subscription_history WHERE userid = ?`
