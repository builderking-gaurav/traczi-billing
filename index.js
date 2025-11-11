import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { config, validateConfig } from './config/index.js';
import { errorHandler, notFoundHandler } from './middleware/errorHandler.js';
import { apiLimiter } from './middleware/rateLimiter.js';
import billingRoutes from './routes/billing.js';
import webhookRoutes from './routes/webhooks.js';
import database from './lib/database.js';
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

// Initialize database and start server
const PORT = config.port;
let server;

async function startServer() {
  try {
    // Try to initialize database connection pool (optional)
    try {
      await database.initialize();
      logger.info('✓ Database connection pool initialized');
      logger.info(`Database: ${config.database.host}/${config.database.database}`);
    } catch (dbError) {
      logger.warn('⚠️  Database connection failed - server will run without database features');
      logger.warn(`Database error: ${dbError.message}`);
      logger.warn('Subscription management will use Traccar user attributes as fallback');
    }

    // Start Express server (even if database failed)
    server = app.listen(PORT, () => {
      logger.info(`Traczi Billing Middleware started on port ${PORT}`);
      logger.info(`Environment: ${config.nodeEnv}`);
      logger.info(`Traccar API: ${config.traccar.baseUrl}`);
      logger.info(`Frontend URL: ${config.frontend.url}`);
    });
  } catch (error) {
    logger.error('Failed to start server:', error);
    process.exit(1);
  }
}

// Graceful shutdown handler
async function gracefulShutdown(signal) {
  logger.info(`${signal} received, shutting down gracefully`);

  // Close server (stop accepting new connections)
  if (server) {
    server.close(() => {
      logger.info('HTTP server closed');
    });
  }

  // Close database connections
  try {
    await database.close();
    logger.info('Database connections closed');
  } catch (error) {
    logger.error('Error closing database:', error);
  }

  process.exit(0);
}

// Register shutdown handlers
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

// Start the server
startServer();

export default app;
