import Stripe from 'stripe';
import dotenv from 'dotenv';
import readline from 'readline';

dotenv.config();

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});

const question = (query) => new Promise((resolve) => rl.question(query, resolve));

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

const plans = [
  {
    id: 'test',
    name: 'Test Plan',
    price: 5,
    deviceLimit: 5,
    description: 'Up to 5 devices with real-time tracking and basic reports',
  },
  {
    id: 'basic',
    name: 'Basic Plan',
    price: 20,
    deviceLimit: 30,
    description: 'Up to 30 devices with real-time tracking and basic reports',
  },
  {
    id: 'moderate',
    name: 'Moderate Plan',
    price: 40,
    deviceLimit: 80,
    description: 'Up to 80 devices with advanced reports and geofencing',
  },
  {
    id: 'advance',
    name: 'Advance Plan',
    price: 100,
    deviceLimit: 150,
    description: 'Up to 150 devices with all features and 24/7 support',
  },
];

console.log('\n🚀 Traczi Stripe Setup Wizard\n');
console.log('This script will create subscription products in your Stripe account.\n');

async function createProducts() {
  console.log('Creating products in Stripe...\n');

  const priceIds = {};

  for (const plan of plans) {
    try {
      console.log(`Creating ${plan.name}...`);

      // Create product
      const product = await stripe.products.create({
        name: plan.name,
        description: plan.description,
        metadata: {
          planId: plan.id,
          deviceLimit: plan.deviceLimit.toString(),
        },
      });

      console.log(`  ✓ Product created: ${product.id}`);

      // Create price
      const price = await stripe.prices.create({
        product: product.id,
        unit_amount: plan.price * 100, // Convert to cents
        currency: 'usd',
        recurring: {
          interval: 'month',
        },
        metadata: {
          planId: plan.id,
          deviceLimit: plan.deviceLimit.toString(),
        },
      });

      console.log(`  ✓ Price created: ${price.id}`);
      console.log(`  ✓ $${plan.price}/month\n`);

      priceIds[plan.id] = price.id;
    } catch (error) {
      console.error(`  ✗ Error creating ${plan.name}:`, error.message);
    }
  }

  return priceIds;
}

async function main() {
  try {
    // Check if Stripe key is configured
    if (!process.env.STRIPE_SECRET_KEY || process.env.STRIPE_SECRET_KEY === 'sk_test_YOUR_KEY_HERE') {
      console.error('❌ Error: STRIPE_SECRET_KEY not configured in .env file');
      console.log('\nPlease:');
      console.log('1. Go to https://dashboard.stripe.com/test/apikeys');
      console.log('2. Copy your Secret key (sk_test_...)');
      console.log('3. Add it to server/.env as STRIPE_SECRET_KEY');
      console.log('4. Run this script again\n');
      process.exit(1);
    }

    console.log('✓ Stripe key found\n');

    // Ask for confirmation
    const confirm = await question('Create products in Stripe? (yes/no): ');

    if (confirm.toLowerCase() !== 'yes' && confirm.toLowerCase() !== 'y') {
      console.log('\nSetup cancelled.');
      process.exit(0);
    }

    const priceIds = await createProducts();

    console.log('\n✅ Setup Complete!\n');
    console.log('Update your server/.env file with these Price IDs:\n');
    console.log(`STRIPE_PRICE_TEST=${priceIds.test}`);
    console.log(`STRIPE_PRICE_BASIC=${priceIds.basic}`);
    console.log(`STRIPE_PRICE_MODERATE=${priceIds.moderate}`);
    console.log(`STRIPE_PRICE_ADVANCE=${priceIds.advance}`);
    console.log('\nAfter updating .env, restart your server.\n');

  } catch (error) {
    console.error('\n❌ Error:', error.message);
    process.exit(1);
  } finally {
    rl.close();
  }
}

main();
