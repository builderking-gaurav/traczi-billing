import database from './database.js';
import logger from '../utils/logger.js';

/**
 * Subscription Service
 * Manages subscription operations using the new database schema
 */
class SubscriptionService {
  /**
   * Get user subscription status
   */
  async getUserSubscription(userId) {
    try {
      const sql = `
        SELECT * FROM v_user_subscription_status
        WHERE userid = ?
        LIMIT 1
      `;
      return await database.queryOne(sql, [userId]);
    } catch (error) {
      logger.error(`Failed to get subscription for user ${userId}`, error);
      throw error;
    }
  }

  /**
   * Create or update user subscription
   */
  async upsertSubscription(userId, subscriptionData) {
    const connection = await database.getConnection();

    try {
      await connection.beginTransaction();

      // Check if subscription exists
      const [existing] = await connection.execute(
        'SELECT id FROM tc_user_subscriptions WHERE userid = ? LIMIT 1',
        [userId]
      );

      let subscriptionId;

      if (existing.length > 0) {
        // Update existing subscription
        subscriptionId = existing[0].id;
        const sql = `
          UPDATE tc_user_subscriptions
          SET
            plan_id = ?,
            stripe_customer_id = ?,
            stripe_subscription_id = ?,
            stripe_payment_method_id = ?,
            status = ?,
            device_limit = ?,
            current_period_start = ?,
            current_period_end = ?,
            trial_start = ?,
            trial_end = ?,
            canceled_at = ?,
            cancel_at_period_end = ?,
            updated_at = CURRENT_TIMESTAMP
          WHERE id = ?
        `;

        await connection.execute(sql, [
          subscriptionData.plan_id,
          subscriptionData.stripe_customer_id,
          subscriptionData.stripe_subscription_id,
          subscriptionData.stripe_payment_method_id || null,
          subscriptionData.status,
          subscriptionData.device_limit,
          subscriptionData.current_period_start || null,
          subscriptionData.current_period_end || null,
          subscriptionData.trial_start || null,
          subscriptionData.trial_end || null,
          subscriptionData.canceled_at || null,
          subscriptionData.cancel_at_period_end || false,
          subscriptionId,
        ]);

        logger.info(`Updated subscription ${subscriptionId} for user ${userId}`);
      } else {
        // Insert new subscription
        const sql = `
          INSERT INTO tc_user_subscriptions (
            userid, plan_id, stripe_customer_id, stripe_subscription_id,
            stripe_payment_method_id, status, device_limit,
            current_period_start, current_period_end,
            trial_start, trial_end, cancel_at_period_end
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `;

        const [result] = await connection.execute(sql, [
          userId,
          subscriptionData.plan_id,
          subscriptionData.stripe_customer_id,
          subscriptionData.stripe_subscription_id,
          subscriptionData.stripe_payment_method_id || null,
          subscriptionData.status,
          subscriptionData.device_limit,
          subscriptionData.current_period_start || null,
          subscriptionData.current_period_end || null,
          subscriptionData.trial_start || null,
          subscriptionData.trial_end || null,
          subscriptionData.cancel_at_period_end || false,
        ]);

        subscriptionId = result.insertId;
        logger.info(`Created subscription ${subscriptionId} for user ${userId}`);
      }

      // Sync to tc_users table using stored procedure
      await connection.execute('CALL sp_sync_subscription_to_user(?)', [userId]);

      await connection.commit();
      return subscriptionId;
    } catch (error) {
      await connection.rollback();
      logger.error(`Failed to upsert subscription for user ${userId}`, error);
      throw error;
    } finally {
      connection.release();
    }
  }

  /**
   * Cancel subscription at period end
   */
  async cancelSubscription(userId, cancelAtPeriodEnd = true) {
    try {
      const sql = `
        UPDATE tc_user_subscriptions
        SET
          cancel_at_period_end = ?,
          canceled_at = CASE WHEN ? = TRUE THEN NOW() ELSE canceled_at END,
          updated_at = CURRENT_TIMESTAMP
        WHERE userid = ?
          AND status IN ('active', 'trialing')
      `;

      await database.query(sql, [cancelAtPeriodEnd, cancelAtPeriodEnd, userId]);
      logger.info(`Set cancel_at_period_end=${cancelAtPeriodEnd} for user ${userId}`);

      // Add history entry
      await this.addSubscriptionHistory(userId, 'subscription_canceled',
        cancelAtPeriodEnd ? 'Subscription will cancel at period end' : 'Subscription cancellation undone'
      );
    } catch (error) {
      logger.error(`Failed to cancel subscription for user ${userId}`, error);
      throw error;
    }
  }

  /**
   * End subscription immediately
   */
  async endSubscription(userId) {
    try {
      const sql = `
        UPDATE tc_user_subscriptions
        SET
          status = 'canceled',
          ended_at = NOW(),
          updated_at = CURRENT_TIMESTAMP
        WHERE userid = ?
          AND status != 'canceled'
      `;

      await database.query(sql, [userId]);
      logger.info(`Ended subscription for user ${userId}`);

      // Sync to tc_users (will set devicelimit to -1 or 0)
      await database.query('CALL sp_sync_subscription_to_user(?)', [userId]);

      // Add history entry
      await this.addSubscriptionHistory(userId, 'subscription_ended', 'Subscription ended');
    } catch (error) {
      logger.error(`Failed to end subscription for user ${userId}`, error);
      throw error;
    }
  }

  /**
   * Add subscription history entry
   */
  async addSubscriptionHistory(userId, eventType, description, metadata = null) {
    try {
      const sql = `
        INSERT INTO tc_subscription_history (
          userid, subscription_id, plan_id, status, event_type, description, metadata
        )
        SELECT
          ?,
          s.id,
          s.plan_id,
          s.status,
          ?,
          ?,
          ?
        FROM tc_user_subscriptions s
        WHERE s.userid = ?
        LIMIT 1
      `;

      const metadataJson = metadata ? JSON.stringify(metadata) : null;
      await database.query(sql, [userId, eventType, description, metadataJson, userId]);

      logger.debug(`Added subscription history for user ${userId}: ${eventType}`);
    } catch (error) {
      logger.error(`Failed to add subscription history for user ${userId}`, error);
      // Don't throw - history is non-critical
    }
  }

  /**
   * Log Stripe webhook event
   */
  async logStripeEvent(eventData) {
    try {
      const sql = `
        INSERT INTO tc_stripe_events (
          stripe_event_id, event_type, stripe_customer_id, stripe_subscription_id,
          userid, payload, processed, error_message
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
          processed = VALUES(processed),
          error_message = VALUES(error_message),
          processed_at = CASE WHEN VALUES(processed) = TRUE THEN NOW() ELSE processed_at END
      `;

      await database.query(sql, [
        eventData.stripe_event_id,
        eventData.event_type,
        eventData.stripe_customer_id || null,
        eventData.stripe_subscription_id || null,
        eventData.userid || null,
        JSON.stringify(eventData.payload || {}),
        eventData.processed || false,
        eventData.error_message || null,
      ]);

      logger.debug(`Logged Stripe event: ${eventData.stripe_event_id}`);
    } catch (error) {
      logger.error('Failed to log Stripe event', error);
      // Don't throw - event logging is non-critical
    }
  }

  /**
   * Mark Stripe event as processed
   */
  async markEventProcessed(stripeEventId, success = true, errorMessage = null) {
    try {
      const sql = `
        UPDATE tc_stripe_events
        SET
          processed = ?,
          error_message = ?,
          processed_at = NOW()
        WHERE stripe_event_id = ?
      `;

      await database.query(sql, [success, errorMessage, stripeEventId]);
    } catch (error) {
      logger.error('Failed to mark event as processed', error);
    }
  }

  /**
   * Check if user can add device
   */
  async canAddDevice(userId) {
    try {
      const sql = 'CALL sp_can_add_device(?, @can_add, @message, @remaining)';
      await database.query(sql, [userId]);

      const result = await database.queryOne('SELECT @can_add as can_add, @message as message, @remaining as remaining');

      return {
        canAdd: result.can_add === 1,
        message: result.message,
        remaining: result.remaining,
      };
    } catch (error) {
      logger.error(`Failed to check device limit for user ${userId}`, error);
      throw error;
    }
  }

  /**
   * Get device ownership details for a user
   */
  async getDeviceOwnership(userId) {
    try {
      const sql = `
        SELECT * FROM v_device_ownership_details
        WHERE ownerid = ?
        ORDER BY device_name
      `;
      return await database.query(sql, [userId]);
    } catch (error) {
      logger.error(`Failed to get device ownership for user ${userId}`, error);
      throw error;
    }
  }

  /**
   * Set device ownership
   */
  async setDeviceOwner(deviceId, ownerId) {
    try {
      const sql = `
        INSERT INTO tc_device_ownership (deviceid, ownerid)
        VALUES (?, ?)
        ON DUPLICATE KEY UPDATE
          transferred_from = ownerid,
          ownerid = VALUES(ownerid),
          transferred_at = NOW()
      `;

      await database.query(sql, [deviceId, ownerId]);
      logger.info(`Set device ${deviceId} owner to user ${ownerId}`);
    } catch (error) {
      logger.error(`Failed to set device ownership`, error);
      throw error;
    }
  }

  /**
   * Get subscription analytics
   */
  async getSubscriptionAnalytics() {
    try {
      const sql = 'SELECT * FROM v_subscription_analytics ORDER BY monthly_revenue DESC';
      return await database.query(sql);
    } catch (error) {
      logger.error('Failed to get subscription analytics', error);
      throw error;
    }
  }
}

// Export singleton instance
export default new SubscriptionService();
