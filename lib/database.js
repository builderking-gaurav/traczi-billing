import mysql from 'mysql2/promise';
import { config } from '../config/index.js';
import logger from '../utils/logger.js';

/**
 * Database connection pool for Traccar MySQL database
 */
class Database {
  constructor() {
    this.pool = null;
  }

  /**
   * Initialize the connection pool
   */
  async initialize() {
    try {
      this.pool = mysql.createPool({
        host: config.database.host,
        port: config.database.port,
        database: config.database.database,
        user: config.database.user,
        password: config.database.password,
        connectionLimit: config.database.connectionLimit,
        waitForConnections: config.database.waitForConnections,
        queueLimit: config.database.queueLimit,
        enableKeepAlive: true,
        keepAliveInitialDelay: 0,
      });

      // Test the connection
      const connection = await this.pool.getConnection();
      logger.info('Database connection pool established', {
        host: config.database.host,
        database: config.database.database,
      });
      connection.release();

      return this.pool;
    } catch (error) {
      logger.error('Failed to initialize database connection pool', error);
      throw new Error(`Database connection failed: ${error.message}`);
    }
  }

  /**
   * Get a connection from the pool
   */
  async getConnection() {
    if (!this.pool) {
      await this.initialize();
    }
    return this.pool.getConnection();
  }

  /**
   * Execute a query
   */
  async query(sql, params = []) {
    if (!this.pool) {
      await this.initialize();
    }

    try {
      const [rows] = await this.pool.execute(sql, params);
      return rows;
    } catch (error) {
      logger.error('Database query error', { sql, error: error.message });
      throw error;
    }
  }

  /**
   * Execute a query and return first row
   */
  async queryOne(sql, params = []) {
    const rows = await this.query(sql, params);
    return rows.length > 0 ? rows[0] : null;
  }

  /**
   * Begin a transaction
   */
  async beginTransaction() {
    const connection = await this.getConnection();
    await connection.beginTransaction();
    return connection;
  }

  /**
   * Close the connection pool
   */
  async close() {
    if (this.pool) {
      await this.pool.end();
      logger.info('Database connection pool closed');
      this.pool = null;
    }
  }
}

// Export singleton instance
export default new Database();
