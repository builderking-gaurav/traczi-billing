import rateLimit from 'express-rate-limit';

/**
 * General API rate limiter
 */
export const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // Limit each IP to 100 requests per windowMs
  message: 'Too many requests from this IP, please try again later.',
  standardHeaders: true,
  legacyHeaders: false,
});

/**
 * Strict rate limiter for checkout endpoints
 */
export const checkoutLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 10, // Limit each IP to 10 checkout attempts per hour
  message: 'Too many checkout attempts, please try again later.',
  standardHeaders: true,
  legacyHeaders: false,
});

/**
 * Webhook rate limiter
 */
export const webhookLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 100, // Allow up to 100 webhook calls per minute
  message: 'Too many webhook requests.',
  standardHeaders: true,
  legacyHeaders: false,
  skipSuccessfulRequests: true,
});
