import Stripe from 'stripe';
import dotenv from 'dotenv';

dotenv.config();

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

const productIds = {
  test: 'prod_TP2zObZkt8i0wf',
  basic: 'prod_TOiXzoqvhPFULI',
  moderate: 'prod_TOiYODcalj8N1U',
  advance: 'prod_TOiaeL07yuHM7H',
};

async function getPriceIds() {
  console.log('\n🔍 Fetching Price IDs from Stripe...\n');

  const priceIds = {};

  for (const [planName, productId] of Object.entries(productIds)) {
    try {
      const prices = await stripe.prices.list({
        product: productId,
        active: true,
        limit: 1,
      });

      if (prices.data.length > 0) {
        const price = prices.data[0];
        priceIds[planName] = price.id;
        console.log(`✓ ${planName.toUpperCase()}: ${price.id} ($${price.unit_amount / 100}/${price.recurring.interval})`);
      } else {
        console.log(`✗ ${planName.toUpperCase()}: No prices found for product ${productId}`);
        console.log(`  Create a price at: https://dashboard.stripe.com/test/products/${productId}`);
      }
    } catch (error) {
      console.error(`✗ Error fetching ${planName}:`, error.message);
    }
  }

  if (Object.keys(priceIds).length === 4) {
    console.log('\n✅ All Price IDs found!\n');
    console.log('Update your server/.env with:\n');
    console.log(`STRIPE_PRICE_TEST=${priceIds.test}`);
    console.log(`STRIPE_PRICE_BASIC=${priceIds.basic}`);
    console.log(`STRIPE_PRICE_MODERATE=${priceIds.moderate}`);
    console.log(`STRIPE_PRICE_ADVANCE=${priceIds.advance}`);
    console.log('\n');
  } else {
    console.log('\n⚠️  Some prices are missing. You need to create prices for each product.');
    console.log('\nTo create prices:');
    console.log('1. Go to https://dashboard.stripe.com/test/products');
    console.log('2. Click on the product');
    console.log('3. Click "Add another price"');
    console.log('4. Set the amount and billing period');
    console.log('5. Save and run this script again\n');
  }
}

getPriceIds().catch(console.error);
