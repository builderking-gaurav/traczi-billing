import express from 'express';
import Stripe from 'stripe';
import { config } from '../config/index.js';
import { PLANS, getPlanById, getAllPlans } from '../config/plans.js';
import { validateCheckoutSession, validatePortalSession } from '../middleware/validation.js';
import { asyncHandler } from '../middleware/errorHandler.js';
import { checkoutLimiter } from '../middleware/rateLimiter.js';
import logger from '../utils/logger.js';

const router = express.Router();
const stripe = new Stripe(config.stripe.secretKey);

/**
 * GET /billing/plans
 * List all available subscription plans
 */
router.get('/plans', asyncHandler(async (req, res) => {
  const plans = getAllPlans().map(plan => ({
    ...plan,
    stripePriceId: config.stripe.prices[plan.id],
  }));

  res.json({
    success: true,
    plans,
  });
}));

/**
 * GET /billing/plans/:planId
 * Get specific plan details
 */
router.get('/plans/:planId', asyncHandler(async (req, res) => {
  const { planId } = req.params;
  const plan = getPlanById(planId);

  if (!plan) {
    return res.status(404).json({
      success: false,
      error: 'Plan not found',
    });
  }

  res.json({
    success: true,
    plan: {
      ...plan,
      stripePriceId: config.stripe.prices[plan.id],
    },
  });
}));

/**
 * POST /billing/checkout
 * Create Stripe checkout session for plan subscription
 */
router.post(
  '/checkout',
  checkoutLimiter,
  validateCheckoutSession,
  asyncHandler(async (req, res) => {
    const { planId, email, metadata = {} } = req.body;

    const plan = getPlanById(planId);
    if (!plan) {
      return res.status(400).json({
        success: false,
        error: 'Invalid plan ID',
      });
    }

    const stripePriceId = config.stripe.prices[plan.id];
    if (!stripePriceId) {
      logger.error(`Stripe price ID not configured for plan: ${plan.id}`);
      return res.status(500).json({
        success: false,
        error: 'Plan configuration error',
      });
    }

    logger.info(`Creating checkout session for ${email} - Plan: ${plan.name}`);

    // Create Stripe checkout session
    const session = await stripe.checkout.sessions.create({
      mode: 'subscription',
      payment_method_types: ['card'],
      customer_email: email,
      line_items: [
        {
          price: stripePriceId,
          quantity: 1,
        },
      ],
      success_url: `${config.frontend.successUrl}?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: config.frontend.cancelUrl,
      metadata: {
        planId: plan.id,
        deviceLimit: plan.deviceLimit.toString(),
        userEmail: email,
        ...metadata,
      },
      subscription_data: {
        metadata: {
          planId: plan.id,
          deviceLimit: plan.deviceLimit.toString(),
          userEmail: email,
        },
      },
    });

    logger.info(`Checkout session created: ${session.id}`);

    res.json({
      success: true,
      sessionId: session.id,
      sessionUrl: session.url,
      publishableKey: config.stripe.publishableKey,
    });
  })
);

/**
 * POST /billing/portal
 * Create Stripe customer portal session for subscription management
 */
router.post(
  '/portal',
  validatePortalSession,
  asyncHandler(async (req, res) => {
    const { customerId } = req.body;

    logger.info(`Creating portal session for customer: ${customerId}`);

    // Validate return URL
    const returnUrl = config.frontend.url;
    if (!returnUrl || returnUrl === 'undefined' || returnUrl === 'null') {
      logger.error('FRONTEND_URL not configured');
      return res.status(500).json({
        success: false,
        error: 'Payment processing error',
        message: 'Frontend URL not configured. Please contact support.',
      });
    }

    // Validate URL format
    try {
      new URL(returnUrl);
    } catch (err) {
      logger.error(`Invalid FRONTEND_URL: ${returnUrl}`);
      return res.status(500).json({
        success: false,
        error: 'Payment processing error',
        message: 'Not a valid URL',
      });
    }

    const session = await stripe.billingPortal.sessions.create({
      customer: customerId,
      return_url: returnUrl,
    });

    res.json({
      success: true,
      url: session.url,
    });
  })
);

/**
 * GET /billing/session/:sessionId
 * Retrieve checkout session details
 */
router.get('/session/:sessionId', asyncHandler(async (req, res) => {
  const { sessionId } = req.params;

  const session = await stripe.checkout.sessions.retrieve(sessionId);

  res.json({
    success: true,
    session: {
      id: session.id,
      status: session.status,
      customerEmail: session.customer_email,
      customerId: session.customer,
      subscriptionId: session.subscription,
      metadata: session.metadata,
    },
  });
}));

/**
 * GET /billing/subscription/:subscriptionId
 * Get subscription details
 */
router.get('/subscription/:subscriptionId', asyncHandler(async (req, res) => {
  const { subscriptionId } = req.params;

  const subscription = await stripe.subscriptions.retrieve(subscriptionId);

  res.json({
    success: true,
    subscription: {
      id: subscription.id,
      status: subscription.status,
      currentPeriodEnd: subscription.current_period_end,
      cancelAtPeriodEnd: subscription.cancel_at_period_end,
      metadata: subscription.metadata,
    },
  });
}));

/**
 * GET /billing/config
 * Get public billing configuration
 */
router.get('/config', asyncHandler(async (req, res) => {
  res.json({
    success: true,
    publishableKey: config.stripe.publishableKey,
    plans: getAllPlans(),
  });
}));

export default router;
