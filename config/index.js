import dotenv from 'dotenv';

dotenv.config();

const config = {
  port: process.env.PORT || 4000,
  nodeEnv: process.env.NODE_ENV || 'development',

  stripe: {
    secretKey: process.env.STRIPE_SECRET_KEY,
    publishableKey: process.env.STRIPE_PUBLISHABLE_KEY,
    webhookSecret: process.env.STRIPE_WEBHOOK_SECRET,
    prices: {
      basic: process.env.STRIPE_PRICE_BASIC,
      moderate: process.env.STRIPE_PRICE_MODERATE,
      advance: process.env.STRIPE_PRICE_ADVANCE,
    },
  },

  traccar: {
    baseUrl: process.env.TRACCAR_BASE_URL || 'http://35.192.15.228:8082',
    adminEmail: process.env.TRACCAR_ADMIN_EMAIL,
    adminPassword: process.env.TRACCAR_ADMIN_PASSWORD,
  },

  frontend: {
    url: process.env.FRONTEND_URL || 'http://localhost:3000',
    successUrl: process.env.SUCCESS_URL || 'http://localhost:3000/registration-success',
    cancelUrl: process.env.CANCEL_URL || 'http://localhost:3000/register',
  },

  security: {
    allowedOrigins: (process.env.ALLOWED_ORIGINS || 'http://localhost:3000').split(','),
  },
};

// Validation
const validateConfig = () => {
  const required = [
    'stripe.secretKey',
    'stripe.webhookSecret',
    'traccar.adminEmail',
    'traccar.adminPassword',
  ];

  const missing = required.filter(key => {
    const value = key.split('.').reduce((obj, k) => obj?.[k], config);
    return !value;
  });

  if (missing.length > 0) {
    throw new Error(`Missing required configuration: ${missing.join(', ')}`);
  }
};

export { config, validateConfig };
