import dotenv from 'dotenv';
dotenv.config();

const TRACCAR_BASE_URL = process.env.TRACCAR_BASE_URL || 'http://35.192.15.228:8082';

async function testLogin(email, password) {
  console.log(`\n🔐 Testing login for: ${email}`);
  console.log(`📝 Password: "${password}" (length: ${password.length})`);

  try {
    const response = await fetch(`${TRACCAR_BASE_URL}/api/session`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        email,
        password,
      }),
    });

    if (response.ok) {
      const user = await response.json();
      console.log(`✅ LOGIN SUCCESSFUL!`);
      console.log(`   User ID: ${user.id}`);
      console.log(`   Name: ${user.name}`);
      console.log(`   Email: ${user.email}`);
      return true;
    } else {
      const error = await response.text();
      console.log(`❌ LOGIN FAILED!`);
      console.log(`   Status: ${response.status}`);
      console.log(`   Error: ${error}`);
      return false;
    }
  } catch (error) {
    console.log(`❌ ERROR: ${error.message}`);
    return false;
  }
}

// Test rohit@gmail.com
testLogin('rohit@gmail.com', 'Pass@1234');
