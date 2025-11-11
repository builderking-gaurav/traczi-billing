import logger from '../utils/logger.js';

/**
 * Global error handler middleware
 */
export const errorHandler = (err, req, res, next) => {
  logger.error(`Error: ${err.message}`, {
    stack: err.stack,
    path: req.path,
    method: req.method,
  });

  // Stripe errors
  if (err.type?.startsWith('Stripe')) {
    return res.status(400).json({
      error: 'Payment processing error',
      message: err.message,
    });
  }

  // Validation errors
  if (err.name === 'ValidationError') {
    return res.status(400).json({
      error: 'Validation error',
      details: err.details || err.message,
    });
  }

  // Traccar API errors
  if (err.traccarError) {
    return res.status(err.statusCode || 500).json({
      error: 'Traccar API error',
      message: err.message,
    });
  }

  // Default error response
  const statusCode = err.statusCode || 500;
  res.status(statusCode).json({
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'production'
      ? 'An unexpected error occurred'
      : err.message,
  });
};

/**
 * 404 handler
 */
export const notFoundHandler = (req, res) => {
  res.status(404).json({
    error: 'Not found',
    message: `Route ${req.method} ${req.path} not found`,
  });
};

/**
 * Async handler wrapper to catch async errors
 */
export const asyncHandler = (fn) => (req, res, next) => {
  Promise.resolve(fn(req, res, next)).catch(next);
};
