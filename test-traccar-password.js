import dotenv from 'dotenv';

dotenv.config();

// Use built-in fetch (Node 18+)
const fetch = globalThis.fetch;

const TRACCAR_BASE_URL = process.env.TRACCAR_BASE_URL || 'http://35.192.15.228:8082';
const ADMIN_EMAIL = process.env.TRACCAR_ADMIN_EMAIL;
const ADMIN_PASSWORD = process.env.TRACCAR_ADMIN_PASSWORD;

async function authenticate() {
  console.log('🔐 Authenticating with Traccar...');
  const response = await fetch(`${TRACCAR_BASE_URL}/api/session`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      email: ADMIN_EMAIL,
      password: ADMIN_PASSWORD,
    }),
  });

  if (!response.ok) {
    throw new Error(`Auth failed: ${response.status}`);
  }

  const cookies = response.headers.get('set-cookie');
  const sessionCookie = cookies?.split(';')[0];
  console.log('✅ Authentication successful\n');
  return sessionCookie;
}

async function testPasswordLength(sessionCookie, testPassword) {
  const testEmail = `test-${Date.now()}@example.com`;

  console.log(`📝 Testing password: "${testPassword}" (length: ${testPassword.length})`);

  try {
    // Create user with test password
    const createResponse = await fetch(`${TRACCAR_BASE_URL}/api/users`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Cookie': sessionCookie,
      },
      body: JSON.stringify({
        name: 'Test User',
        email: testEmail,
        password: testPassword,
        deviceLimit: 1,
        disabled: false,
      }),
    });

    if (!createResponse.ok) {
      const error = await createResponse.text();
      console.log(`❌ User creation failed: ${error}\n`);
      return false;
    }

    const user = await createResponse.json();
    console.log(`✅ User created (ID: ${user.id})`);

    // Test login with FULL password
    console.log(`🔑 Testing login with FULL password: "${testPassword}"`);
    const loginResponse = await fetch(`${TRACCAR_BASE_URL}/api/session`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        email: testEmail,
        password: testPassword,
      }),
    });

    const loginSuccess = loginResponse.ok;
    console.log(loginSuccess ? '✅ Login successful with FULL password' : '❌ Login failed with FULL password');

    // If full password failed, try truncated versions
    if (!loginSuccess) {
      for (let len = testPassword.length - 1; len >= 1; len--) {
        const truncated = testPassword.substring(0, len);
        console.log(`🔑 Testing login with truncated password (${len} chars): "${truncated}"`);

        const truncatedLoginResponse = await fetch(`${TRACCAR_BASE_URL}/api/session`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: new URLSearchParams({
            email: testEmail,
            password: truncated,
          }),
        });

        if (truncatedLoginResponse.ok) {
          console.log(`⚠️  LOGIN WORKS WITH ${len} CHARACTERS: "${truncated}"`);
          console.log(`🔴 PASSWORD WAS TRUNCATED FROM ${testPassword.length} TO ${len} CHARACTERS!\n`);
          break;
        }
      }
    }

    // Delete test user
    await fetch(`${TRACCAR_BASE_URL}/api/users/${user.id}`, {
      method: 'DELETE',
      headers: {
        'Cookie': sessionCookie,
      },
    });
    console.log(`🗑️  Test user deleted\n`);

    return loginSuccess;
  } catch (error) {
    console.error(`❌ Error testing password:`, error.message);
    return false;
  }
}

async function main() {
  console.log('='.repeat(60));
  console.log('🧪 TRACCAR PASSWORD LENGTH TESTER');
  console.log('='.repeat(60));
  console.log(`Server: ${TRACCAR_BASE_URL}\n`);

  try {
    const sessionCookie = await authenticate();

    // Test various password lengths
    const testPasswords = [
      'short',           // 5 chars
      'medium1',         // 7 chars
      'qwerty@1',        // 8 chars (what worked)
      'qwerty@12',       // 9 chars (what you entered)
      'longpassword',    // 12 chars
      'verylongpassword123', // 20 chars
    ];

    console.log('Testing different password lengths:\n');
    console.log('='.repeat(60));

    for (const testPassword of testPasswords) {
      await testPasswordLength(sessionCookie, testPassword);
    }

    console.log('='.repeat(60));
    console.log('✅ Testing complete!');
    console.log('='.repeat(60));
  } catch (error) {
    console.error('❌ Fatal error:', error.message);
  }
}

main();
