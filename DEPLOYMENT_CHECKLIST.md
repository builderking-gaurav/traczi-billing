# 🚀 Traczi Billing Server - Deployment Checklist

## ✅ Pre-Deployment Verification

### 1. Code Status
- [x] All changes committed to Git
- [x] Latest code pushed to GitHub (main branch)
- [x] Database integration complete
- [x] mysql2 dependency installed (v3.15.3)

### 2. Key Files Verified
- [x] `lib/database.js` - Database connection pool
- [x] `lib/subscriptionService.js` - Subscription management service
- [x] `lib/traccarClient.js` - Traccar API client
- [x] `routes/webhooks.js` - Updated with database integration
- [x] `index.js` - Database initialization on startup
- [x] `config/index.js` - Database configuration
- [x] `package.json` - mysql2 dependency added

### 3. Database Setup
- [x] Schema created (01_create_subscription_tables.sql)
- [x] Migration completed (9 subscriptions created)
- [x] Views working (v_user_subscription_status)
- [x] Stored procedures working (sp_can_add_device)
- [x] Triggers recreated
- [x] Device ownership assigned (15 devices)

---

## 🔧 Render Deployment Steps

### Step 1: Add Environment Variables

Go to: https://dashboard.render.com → Your Service → Environment

**Required Variables:**

```env
# Server
PORT=4000
NODE_ENV=production

# Stripe (Use values from .env file - DO NOT COMMIT ACTUAL KEYS)
STRIPE_SECRET_KEY=your_stripe_secret_key_here
STRIPE_PUBLISHABLE_KEY=your_stripe_publishable_key_here
STRIPE_WEBHOOK_SECRET=your_stripe_webhook_secret_here

# Stripe Price IDs
STRIPE_PRICE_TEST=price_1SSEtvQdFmHlqkLVLcforalC
STRIPE_PRICE_BASIC=price_1SRv6DQdFmHlqkLVsvSNdI03
STRIPE_PRICE_MODERATE=price_1SRv7LQdFmHlqkLVqGzYmitb
STRIPE_PRICE_ADVANCE=price_1SRv90QdFmHlqkLVxImJEMZ9

# Traccar
TRACCAR_BASE_URL=https://api.traczi.com
TRACCAR_ADMIN_EMAIL=your_admin_email
TRACCAR_ADMIN_PASSWORD=your_admin_password

# Frontend
FRONTEND_URL=https://your-frontend-domain.com
SUCCESS_URL=https://your-frontend-domain.com/registration-success
CANCEL_URL=https://your-frontend-domain.com/register

# Security
ALLOWED_ORIGINS=https://your-frontend-domain.com,https://traczi-billing.onrender.com

# Database (NEW - REQUIRED)
DB_HOST=35.192.15.228
DB_PORT=3306
DB_NAME=traccar
DB_USER=root
DB_PASSWORD=your_database_password
DB_CONNECTION_LIMIT=10
```

### Step 2: Deploy

1. Click **"Manual Deploy"** → **"Deploy latest commit"**
2. Wait for build to complete
3. Check logs for successful startup

### Step 3: Verify Deployment

**Expected Log Messages:**
```
✓ Configuration validated successfully
✓ Database connection pool initialized
✓ Database: 35.192.15.228/traccar
✓ Traczi Billing Middleware started on port 4000
✓ Environment: production
✓ Traccar API: https://api.traczi.com
✓ Frontend URL: https://your-frontend-domain.com
```

---

## 🧪 Post-Deployment Testing

### Test 1: Health Check
```bash
curl https://traczi-billing.onrender.com/health
```

**Expected Response:**
```json
{
  "status": "healthy",
  "timestamp": "2025-11-11T...",
  "environment": "production"
}
```

### Test 2: Get Plans
```bash
curl https://traczi-billing.onrender.com/billing/plans
```

**Expected Response:**
```json
{
  "success": true,
  "plans": [
    {
      "id": "test",
      "name": "Test Plan",
      "price": 5,
      "deviceLimit": 5,
      ...
    },
    ...
  ]
}
```

### Test 3: Check Database Connection

Look in Render logs for:
```
Database connection pool initialized
Database: 35.192.15.228/traccar
```

If you see errors like "Can't connect to MySQL server", check:
- DB_HOST is accessible from Render
- DB_PORT is correct (3306)
- DB_USER and DB_PASSWORD are correct
- MySQL allows connections from Render's IP

---

## 🔍 Monitoring & Debugging

### Check Subscription Status (from database)
```sql
SELECT * FROM v_user_subscription_status ORDER BY userid;
```

### Check Recent Stripe Events
```sql
SELECT * FROM tc_stripe_events
ORDER BY created_at DESC LIMIT 10;
```

### Check Subscription History
```sql
SELECT * FROM tc_subscription_history
ORDER BY created_at DESC LIMIT 10;
```

### Render Logs
Monitor for:
- Database connection errors
- Stripe webhook events
- Subscription updates
- API errors

---

## ⚠️ Troubleshooting

### Database Connection Fails
**Error:** `Failed to initialize database connection pool`

**Solutions:**
1. Verify DB_HOST is reachable from Render
2. Check if MySQL allows remote connections
3. Verify DB_USER and DB_PASSWORD are correct
4. Check if firewall allows Render's IPs

### Stripe Webhooks Not Processing
**Error:** Events logged but not processed

**Solutions:**
1. Check STRIPE_WEBHOOK_SECRET is correct
2. Verify webhook endpoint is accessible
3. Check tc_stripe_events table for error_message
4. Review Render logs for webhook errors

### Subscriptions Not Syncing to tc_users
**Error:** devicelimit not updating

**Solutions:**
1. Check triggers are enabled: `SHOW TRIGGERS;`
2. Verify sp_sync_subscription_to_user exists
3. Check tc_subscription_history for errors
4. Manually run sync: `CALL sp_sync_subscription_to_user(userid);`

---

## 📊 Current System Status

### Database
- **Tables:** 5 subscription tables + device ownership
- **Views:** 3 (status, ownership, analytics)
- **Procedures:** 3 (can_add_device, sync_to_user, add_history)
- **Triggers:** 4 (sync and history tracking)
- **Subscriptions:** 9 active
- **Device Ownership:** 15 devices tracked

### Revenue Breakdown
- Test Plan (1 user × $5): $5.00/month
- Basic Plan (3 users × $20): $60.00/month
- Moderate Plan (5 users × $40): $200.00/month
- **Total:** $265.00/month

### Users Status
- **With subscriptions:** 9 users
- **Without subscriptions:** 3 users (devicelimit = -1)
- **At device limit:** 1 user (test@gmail.com: 5/5)

---

## ✅ Deployment Complete Checklist

- [ ] All environment variables added to Render
- [ ] Deployment triggered
- [ ] Build succeeded (check logs)
- [ ] Server started successfully
- [ ] Database connection confirmed
- [ ] Health check returns 200 OK
- [ ] Plans endpoint returns data
- [ ] Test Stripe checkout flow
- [ ] Verify webhook events are logged
- [ ] Check subscriptions appear in database
- [ ] Confirm device limits are enforced

---

## 🎯 Next Steps After Deployment

1. **Update Frontend URLs**
   - Replace localhost URLs with production URLs
   - Update FRONTEND_URL in Render environment

2. **Test Full Flow**
   - User registration
   - Stripe checkout
   - Subscription activation
   - Device limit enforcement
   - Plan upgrades

3. **Setup Monitoring**
   - Track Stripe webhook success rate
   - Monitor database connection health
   - Alert on subscription failures

4. **Documentation**
   - Update API documentation
   - Document webhook endpoints
   - Create runbook for common issues

---

## 📞 Support

If issues occur during deployment:
1. Check Render logs first
2. Verify all environment variables are set
3. Test database connection separately
4. Review tc_stripe_events for webhook errors
5. Check tc_subscription_history for sync issues

---

**Latest Commit:** b756ee0 - Fix migration by temporarily disabling triggers
**Branch:** main
**Status:** ✅ Ready for deployment
