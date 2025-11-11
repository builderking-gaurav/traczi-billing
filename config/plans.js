/**
 * Subscription Plans Configuration
 * Maps plan tiers to device limits and pricing
 */

export const PLANS = {
  TEST: {
    id: 'test',
    name: 'Test Plan',
    price: 5,
    currency: 'USD',
    deviceLimit: 5,
    features: [
      'Up to 5 devices',
      'Real-time tracking',
      'Basic reports',
      'Email support',
    ],
  },
  BASIC: {
    id: 'basic',
    name: 'Basic Plan',
    price: 20,
    currency: 'USD',
    deviceLimit: 30,
    features: [
      'Up to 30 devices',
      'Real-time tracking',
      'Basic reports',
      'Email support',
    ],
  },
  MODERATE: {
    id: 'moderate',
    name: 'Moderate Plan',
    price: 40,
    currency: 'USD',
    deviceLimit: 80,
    features: [
      'Up to 80 devices',
      'Real-time tracking',
      'Advanced reports',
      'Geofencing',
      'Priority email support',
    ],
  },
  ADVANCE: {
    id: 'advance',
    name: 'Advance Plan',
    price: 100,
    currency: 'USD',
    deviceLimit: 350,
    features: [
      'Up to 350 devices',
      'Real-time tracking',
      'All reports',
      'Advanced geofencing',
      'API access',
      '24/7 priority support',
    ],
  },
};

/**
 * Get plan by ID
 */
export const getPlanById = (planId) => {
  const normalizedId = planId.toUpperCase();
  return PLANS[normalizedId] || null;
};

/**
 * Get plan by Stripe Price ID
 */
export const getPlanByPriceId = (priceId, stripePrices) => {
  if (priceId === stripePrices.test) return PLANS.TEST;
  if (priceId === stripePrices.basic) return PLANS.BASIC;
  if (priceId === stripePrices.moderate) return PLANS.MODERATE;
  if (priceId === stripePrices.advance) return PLANS.ADVANCE;
  return null;
};

/**
 * Get all plans as array
 */
export const getAllPlans = () => Object.values(PLANS);

/**
 * Validate if a plan exists
 */
export const isValidPlan = (planId) => {
  const normalizedId = planId?.toUpperCase();
  return Object.keys(PLANS).includes(normalizedId);
};
