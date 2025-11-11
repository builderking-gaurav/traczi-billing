import { body, param, validationResult } from 'express-validator';

/**
 * Validate request and return errors if any
 */
export const validate = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({
      error: 'Validation error',
      details: errors.array(),
    });
  }
  next();
};

/**
 * Validation rules for checkout session creation
 */
export const validateCheckoutSession = [
  body('planId')
    .isString()
    .isIn(['basic', 'moderate', 'advance'])
    .withMessage('Invalid plan ID. Must be one of: basic, moderate, advance'),
  body('email')
    .isEmail()
    .normalizeEmail()
    .withMessage('Valid email is required'),
  body('metadata')
    .optional()
    .isObject()
    .withMessage('Metadata must be an object'),
  validate,
];

/**
 * Validation rules for portal session creation
 */
export const validatePortalSession = [
  body('customerId')
    .isString()
    .notEmpty()
    .withMessage('Customer ID is required'),
  validate,
];

/**
 * Validation rules for plan ID parameter
 */
export const validatePlanId = [
  param('planId')
    .isString()
    .isIn(['basic', 'moderate', 'advance'])
    .withMessage('Invalid plan ID'),
  validate,
];
