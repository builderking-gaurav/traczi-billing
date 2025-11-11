import express from 'express';
import Stripe from 'stripe';
import { config } from '../config/index.js';
import { getPlanByPriceId } from '../config/plans.js';
import traccarClient from '../lib/traccarClient.js';
import { webhookLimiter } from '../middleware/rateLimiter.js';
import logger from '../utils/logger.js';

const router = express.Router();
const stripe = new Stripe(config.stripe.secretKey);

/**
 * POST /webhooks/stripe
 * Handle Stripe webhook events
 */
router.post(
  '/stripe',
  webhookLimiter,
  express.raw({ type: 'application/json' }),
  async (req, res) => {
    const sig = req.headers['stripe-signature'];
    let event;

    try {
      // Verify webhook signature
      event = stripe.webhooks.constructEvent(
        req.body,
        sig,
        config.stripe.webhookSecret
      );
    } catch (err) {
      logger.error(`Webhook signature verification failed: ${err.message}`);
      return res.status(400).send(`Webhook Error: ${err.message}`);
    }

    logger.info(`Received Stripe webhook: ${event.type}`);

    try {
      // Handle different event types
      switch (event.type) {
        case 'checkout.session.completed':
          await handleCheckoutCompleted(event.data.object);
          break;

        case 'customer.subscription.created':
          await handleSubscriptionCreated(event.data.object);
          break;

        case 'customer.subscription.updated':
          await handleSubscriptionUpdated(event.data.object);
          break;

        case 'customer.subscription.deleted':
          await handleSubscriptionDeleted(event.data.object);
          break;

        case 'invoice.payment_failed':
          await handlePaymentFailed(event.data.object);
          break;

        case 'invoice.payment_succeeded':
          await handlePaymentSucceeded(event.data.object);
          break;

        default:
          logger.info(`Unhandled event type: ${event.type}`);
      }

      res.json({ received: true });
    } catch (error) {
      logger.error(`Error processing webhook: ${error.message}`, error);
      res.status(500).json({ error: 'Webhook processing failed' });
    }
  }
);

/**
 * Handle checkout.session.completed event
 */
async function handleCheckoutCompleted(session) {
  logger.info(`Processing checkout completion: ${session.id}`);

  const { customer_email: email, customer, subscription, metadata } = session;

  logger.debug(`Metadata received: ${JSON.stringify(metadata)}`);
  logger.debug(`Has temporaryPassword: ${!!metadata.temporaryPassword}`);
  logger.debug(`Password length: ${metadata.temporaryPassword?.length || 0}`);

  if (!subscription) {
    logger.warn('No subscription in checkout session');
    return;
  }

  // Get or create user in Traccar
  let user = await traccarClient.getUserByEmail(email);

  if (!user) {
    logger.info(`User not found, creating new user: ${email}`);
    const password = metadata.temporaryPassword || generateRandomPassword();

    logger.info(`Creating user with password length: ${password.length}`);

    user = await traccarClient.createUser({
      name: metadata.userName || email.split('@')[0],
      email,
      password,
      deviceLimit: parseInt(metadata.deviceLimit, 10),
    });

    logger.info(`User ${user.id} created. Testing login...`);

    // Verify the credentials work immediately
    let loginWorks = await traccarClient.verifyUserCredentials(email, password);
    if (!loginWorks) {
      logger.warn(`⚠️  Login test failed for user ${user.id}. Attempting password reset...`);

      // Try to fix by updating the password
      try {
        await traccarClient.updateUserPassword(user.id, password);
        logger.info(`Password updated via PUT request. Testing login again...`);

        loginWorks = await traccarClient.verifyUserCredentials(email, password);
        if (loginWorks) {
          logger.info(`✓ Login working after password reset!`);
        } else {
          logger.error(`✗ Login still failing after password reset`);
        }
      } catch (error) {
        logger.error(`Failed to reset password: ${error.message}`);
      }
    } else {
      logger.info(`✓ Login verified for user ${user.id}`);
    }
  }

  // Update user with subscription metadata
  await traccarClient.updateSubscriptionMetadata(user.id, {
    customerId: customer,
    subscriptionId: subscription,
    plan: metadata.planId,
    status: 'active',
    startDate: new Date().toISOString(),
  });

  logger.info(`Checkout completed for user ${user.id}`);
}

/**
 * Handle customer.subscription.created event
 */
async function handleSubscriptionCreated(subscription) {
  logger.info(`Processing subscription created: ${subscription.id}`);

  const { customer, metadata, items } = subscription;
  const priceId = items.data[0].price.id;

  const plan = getPlanByPriceId(priceId, config.stripe.prices);
  if (!plan) {
    logger.error(`Unknown price ID: ${priceId}`);
    return;
  }

  const email = metadata.userEmail;
  if (!email) {
    logger.error('No email in subscription metadata');
    return;
  }

  const user = await traccarClient.getUserByEmail(email);
  if (!user) {
    logger.error(`User not found: ${email}`);
    return;
  }

  // Update device limit
  await traccarClient.updateUserLimits(user.id, plan.deviceLimit, {
    subscriptionPlan: plan.id,
  });

  // Enable user account
  await traccarClient.setUserStatus(user.id, false);

  logger.info(`Subscription activated for user ${user.id} - Plan: ${plan.name}`);
}

/**
 * Handle customer.subscription.updated event
 */
async function handleSubscriptionUpdated(subscription) {
  logger.info(`Processing subscription updated: ${subscription.id}`);

  const { metadata, status, items } = subscription;
  const priceId = items.data[0].price.id;

  const plan = getPlanByPriceId(priceId, config.stripe.prices);
  if (!plan) {
    logger.error(`Unknown price ID: ${priceId}`);
    return;
  }

  const email = metadata.userEmail;
  if (!email) {
    logger.error('No email in subscription metadata');
    return;
  }

  const user = await traccarClient.getUserByEmail(email);
  if (!user) {
    logger.error(`User not found: ${email}`);
    return;
  }

  // Update device limit based on new plan
  await traccarClient.updateUserLimits(user.id, plan.deviceLimit, {
    subscriptionPlan: plan.id,
    subscriptionStatus: status,
  });

  // Handle status changes
  if (status === 'unpaid' || status === 'past_due') {
    logger.warn(`Subscription payment issue for user ${user.id}`);
    // Optionally disable account after grace period
  } else if (status === 'active') {
    await traccarClient.setUserStatus(user.id, false);
  }

  logger.info(`Subscription updated for user ${user.id} - Status: ${status}`);
}

/**
 * Handle customer.subscription.deleted event
 */
async function handleSubscriptionDeleted(subscription) {
  logger.info(`Processing subscription deleted: ${subscription.id}`);

  const { metadata } = subscription;
  const email = metadata.userEmail;

  if (!email) {
    logger.error('No email in subscription metadata');
    return;
  }

  const user = await traccarClient.getUserByEmail(email);
  if (!user) {
    logger.error(`User not found: ${email}`);
    return;
  }

  // Disable user account
  await traccarClient.setUserStatus(user.id, true);

  // Optionally reduce device limit to 0 or minimal
  await traccarClient.updateUserLimits(user.id, 0, {
    subscriptionStatus: 'canceled',
  });

  logger.info(`Subscription canceled for user ${user.id}`);
}

/**
 * Handle invoice.payment_failed event
 */
async function handlePaymentFailed(invoice) {
  logger.warn(`Payment failed for subscription: ${invoice.subscription}`);

  const { customer_email: email } = invoice;

  if (!email) {
    logger.error('No email in invoice');
    return;
  }

  const user = await traccarClient.getUserByEmail(email);
  if (!user) {
    logger.error(`User not found: ${email}`);
    return;
  }

  // Update subscription status
  await traccarClient.updateUserLimits(user.id, user.deviceLimit, {
    subscriptionStatus: 'payment_failed',
    lastPaymentAttempt: new Date().toISOString(),
  });

  logger.info(`Payment failed notification for user ${user.id}`);
}

/**
 * Handle invoice.payment_succeeded event
 */
async function handlePaymentSucceeded(invoice) {
  logger.info(`Payment succeeded for subscription: ${invoice.subscription}`);

  const { customer_email: email } = invoice;

  if (!email) {
    return;
  }

  const user = await traccarClient.getUserByEmail(email);
  if (!user) {
    return;
  }

  // Update subscription status
  await traccarClient.updateUserLimits(user.id, user.deviceLimit, {
    subscriptionStatus: 'active',
    lastPaymentDate: new Date().toISOString(),
  });

  // Ensure account is enabled
  await traccarClient.setUserStatus(user.id, false);

  logger.info(`Payment confirmed for user ${user.id}`);
}

/**
 * Generate random password for new users
 */
function generateRandomPassword() {
  return Math.random().toString(36).slice(-12) + Math.random().toString(36).slice(-12);
}

export default router;
