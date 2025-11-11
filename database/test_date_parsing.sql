-- Test date parsing logic before running migration
-- This helps verify the date conversion works correctly

SELECT '=== TEST DATE PARSING ===' as section;

-- Test with sample ISO 8601 date with milliseconds
SELECT
  '2025-11-11T03:51:01.198Z' as original_format,
  REPLACE(REPLACE('2025-11-11T03:51:01.198Z', 'T', ' '), 'Z', '') as step1_replace_TZ,
  SUBSTRING_INDEX(
    REPLACE(REPLACE('2025-11-11T03:51:01.198Z', 'T', ' '), 'Z', ''),
    '.', 1
  ) as step2_remove_milliseconds,
  STR_TO_DATE(
    SUBSTRING_INDEX(
      REPLACE(REPLACE('2025-11-11T03:51:01.198Z', 'T', ' '), 'Z', ''),
      '.', 1
    ),
    '%Y-%m-%d %H:%i:%s'
  ) as final_timestamp;

-- Test with actual data from your database
SELECT '=== TEST WITH ACTUAL USER DATA ===' as section;

SELECT
  u.id,
  u.email,
  JSON_UNQUOTE(JSON_EXTRACT(u.attributes, '$.subscriptionStartDate')) as raw_date,
  SUBSTRING_INDEX(
    REPLACE(REPLACE(
      JSON_UNQUOTE(JSON_EXTRACT(u.attributes, '$.subscriptionStartDate')),
      'T', ' '
    ), 'Z', ''),
    '.', 1
  ) as cleaned_date,
  STR_TO_DATE(
    SUBSTRING_INDEX(
      REPLACE(REPLACE(
        JSON_UNQUOTE(JSON_EXTRACT(u.attributes, '$.subscriptionStartDate')),
        'T', ' '
      ), 'Z', ''),
      '.', 1
    ),
    '%Y-%m-%d %H:%i:%s'
  ) as parsed_timestamp
FROM tc_users u
WHERE JSON_EXTRACT(u.attributes, '$.subscriptionStartDate') IS NOT NULL
LIMIT 5;

-- Show what will be migrated
SELECT '=== USERS READY FOR MIGRATION ===' as section;

SELECT
  COUNT(*) as users_with_stripe_data
FROM tc_users u
WHERE JSON_EXTRACT(u.attributes, '$.stripeSubscriptionId') IS NOT NULL
  AND JSON_UNQUOTE(JSON_EXTRACT(u.attributes, '$.stripeSubscriptionId')) != ''
  AND NOT EXISTS (
    SELECT 1 FROM tc_user_subscriptions s
    WHERE s.userid = u.id
  );

SELECT
  COUNT(*) as users_with_devicelimit_only
FROM tc_users u
WHERE u.devicelimit > 0
  AND (
    JSON_EXTRACT(u.attributes, '$.stripeSubscriptionId') IS NULL
    OR JSON_UNQUOTE(JSON_EXTRACT(u.attributes, '$.stripeSubscriptionId')) = ''
  )
  AND NOT EXISTS (
    SELECT 1 FROM tc_user_subscriptions s
    WHERE s.userid = u.id
  )
  AND u.administrator = 0;
