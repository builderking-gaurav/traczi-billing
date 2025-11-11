import traccarClient from './lib/traccarClient.js';
import readline from 'readline';

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});

const question = (query) => new Promise((resolve) => rl.question(query, resolve));

async function resetPassword() {
  try {
    console.log('\n🔐 Reset Traccar User Password\n');

    const email = await question('Enter user email: ');
    const newPassword = await question('Enter new password: ');

    console.log('\nFetching user...');
    const user = await traccarClient.getUserByEmail(email);

    if (!user) {
      console.error(`❌ User not found: ${email}`);
      process.exit(1);
    }

    console.log(`✓ Found user: ${user.name} (ID: ${user.id})`);

    // Update user with new password
    const updatedUser = {
      ...user,
      password: newPassword, // Traccar will hash this
    };

    await traccarClient.request(`/api/users/${user.id}`, {
      method: 'PUT',
      body: JSON.stringify(updatedUser),
    });

    console.log(`\n✅ Password updated successfully!`);
    console.log(`\nYou can now log in with:`);
    console.log(`Email: ${email}`);
    console.log(`Password: ${newPassword}\n`);

  } catch (error) {
    console.error('\n❌ Error:', error.message);
  } finally {
    rl.close();
  }
}

resetPassword();
