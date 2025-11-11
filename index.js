import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { config, validateConfig } from './config/index.js';
import { errorHandler, notFoundHandler } from './middleware/errorHandler.js';
import { apiLimiter } from './middleware/rateLimiter.js';
import billingRoutes from './routes/billing.js';
import webhookRoutes from './routes/webhooks.js';
import logger from './utils/logger.js';

// Validate configuration on startup
try {
  validateConfig();
  logger.info('Configuration validated successfully');
} catch (error) {
  logger.error('Configuration validation failed:', error);
  process.exit(1);
}

const app = express();

// Security middleware
app.use(helmet({
  contentSecurityPolicy: false, // Disable for API server
}));

// CORS configuration
app.use(cors({
  origin: (origin, callback) => {
    // Allow requests with no origin (mobile apps, Postman, etc.)
    if (!origin) return callback(null, true);

    if (config.security.allowedOrigins.includes(origin)) {
      callback(null, true);
    } else {
      callback(new Error('Not allowed by CORS'));
    }
  },
  credentials: true,
}));

// Apply rate limiting to all routes except webhooks
app.use('/api', apiLimiter);

// Body parsing middleware
// Note: Webhook route needs raw body, so it's handled separately in webhooks.js
app.use((req, res, next) => {
  if (req.path === '/webhooks/stripe') {
    next();
  } else {
    express.json()(req, res, next);
  }
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    environment: config.nodeEnv,
  });
});

// API routes
app.use('/billing', billingRoutes);
app.use('/webhooks', webhookRoutes);

// 404 handler
app.use(notFoundHandler);

// Error handler
app.use(errorHandler);

// Start server
const PORT = config.port;
app.listen(PORT, () => {
  logger.info(`Traczi Billing Middleware started on port ${PORT}`);
  logger.info(`Environment: ${config.nodeEnv}`);
  logger.info(`Traccar API: ${config.traccar.baseUrl}`);
  logger.info(`Frontend URL: ${config.frontend.url}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  logger.info('SIGTERM received, shutting down gracefully');
  process.exit(0);
});

process.on('SIGINT', () => {
  logger.info('SIGINT received, shutting down gracefully');
  process.exit(0);
});

export default app;
