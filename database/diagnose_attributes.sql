-- Check what's in the attributes field for users
SELECT
  id,
  email,
  devicelimit,
  JSON_UNQUOTE(JSON_EXTRACT(attributes, '$.stripeSubscriptionId')) as stripe_sub_id,
  JSON_UNQUOTE(JSON_EXTRACT(attributes, '$.subscriptionPlan')) as plan,
  JSON_UNQUOTE(JSON_EXTRACT(attributes, '$.subscriptionStartDate')) as start_date_raw,
  LENGTH(JSON_UNQUOTE(JSON_EXTRACT(attributes, '$.subscriptionStartDate'))) as date_length
FROM tc_users
WHERE attributes IS NOT NULL
ORDER BY id;
