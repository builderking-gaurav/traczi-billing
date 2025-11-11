-- Check what subscription data exists in user attributes
SELECT
  id,
  email,
  name,
  devicelimit,
  expirationtime,
  JSON_EXTRACT(attributes, '$.stripeCustomerId') as stripe_customer,
  JSON_EXTRACT(attributes, '$.stripeSubscriptionId') as stripe_subscription,
  JSON_EXTRACT(attributes, '$.subscriptionPlan') as plan,
  JSON_EXTRACT(attributes, '$.subscriptionStatus') as status,
  JSON_EXTRACT(attributes, '$.subscriptionStartDate') as start_date,
  JSON_EXTRACT(attributes, '$.cancelAtPeriodEnd') as cancel_flag
FROM tc_users
WHERE attributes IS NOT NULL
ORDER BY id;
