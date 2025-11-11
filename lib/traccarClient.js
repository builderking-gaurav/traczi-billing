import { config } from '../config/index.js';
import logger from '../utils/logger.js';

/**
 * Traccar API Client
 * Manages communication with Traccar backend for user provisioning and device limits
 */
class TraccarClient {
  constructor() {
    this.baseUrl = config.traccar.baseUrl;
    this.adminEmail = config.traccar.adminEmail;
    this.adminPassword = config.traccar.adminPassword;
    this.sessionCookie = null;
    this.sessionExpiry = null;
  }

  /**
   * Authenticate with Traccar as admin
   */
  async authenticate() {
    // Check if existing session is still valid
    if (this.sessionCookie && this.sessionExpiry && Date.now() < this.sessionExpiry) {
      return this.sessionCookie;
    }

    try {
      logger.info('Authenticating with Traccar API');
      logger.debug(`Traccar URL: ${this.baseUrl}`);
      logger.debug(`Admin Email: ${this.adminEmail}`);
      logger.debug(`Password length: ${this.adminPassword?.length || 0}`);

      const response = await fetch(`${this.baseUrl}/api/session`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
          email: this.adminEmail,
          password: this.adminPassword,
        }),
      });

      if (!response.ok) {
        const error = await response.text();
        logger.error(`Traccar auth failed with status ${response.status}: ${error}`);
        throw new Error(`Traccar authentication failed: ${error}`);
      }

      // Extract session cookie
      const cookies = response.headers.get('set-cookie');
      if (cookies) {
        this.sessionCookie = cookies.split(';')[0];
        // Set expiry to 23 hours from now (sessions typically last 24 hours)
        this.sessionExpiry = Date.now() + (23 * 60 * 60 * 1000);
      }

      const user = await response.json();
      logger.info('Successfully authenticated with Traccar', { userId: user.id });

      return this.sessionCookie;
    } catch (error) {
      logger.error('Traccar authentication error:', error);
      throw new Error(`Failed to authenticate with Traccar: ${error.message}`);
    }
  }

  /**
   * Make authenticated request to Traccar API
   */
  async request(endpoint, options = {}) {
    await this.authenticate();

    const url = `${this.baseUrl}${endpoint}`;
    const headers = {
      'Content-Type': 'application/json',
      'Cookie': this.sessionCookie,
      ...options.headers,
    };

    try {
      const response = await fetch(url, {
        ...options,
        headers,
      });

      if (!response.ok) {
        const error = await response.text();
        const traccarError = new Error(`Traccar API error: ${error}`);
        traccarError.traccarError = true;
        traccarError.statusCode = response.status;
        throw traccarError;
      }

      // Handle empty responses
      const contentType = response.headers.get('content-type');
      if (contentType?.includes('application/json')) {
        return await response.json();
      }

      return null;
    } catch (error) {
      logger.error(`Traccar API request failed: ${endpoint}`, error);
      throw error;
    }
  }

  /**
   * Get user by email
   */
  async getUserByEmail(email) {
    try {
      const users = await this.request('/api/users');
      return users.find(user => user.email === email);
    } catch (error) {
      logger.error(`Failed to get user by email: ${email}`, error);
      throw error;
    }
  }

  /**
   * Get user by ID
   */
  async getUserById(userId) {
    try {
      return await this.request(`/api/users/${userId}`);
    } catch (error) {
      logger.error(`Failed to get user by ID: ${userId}`, error);
      throw error;
    }
  }

  /**
   * Update user device limit and attributes
   */
  async updateUserLimits(userId, deviceLimit, attributes = {}) {
    try {
      logger.info(`Updating device limit for user ${userId} to ${deviceLimit}`);

      // First, get the current user data
      const user = await this.getUserById(userId);

      // Update user with new device limit and attributes
      const updatedUser = {
        ...user,
        deviceLimit,
        attributes: {
          ...user.attributes,
          ...attributes,
        },
      };

      await this.request(`/api/users/${userId}`, {
        method: 'PUT',
        body: JSON.stringify(updatedUser),
      });

      logger.info(`Successfully updated user ${userId} limits`);
      return updatedUser;
    } catch (error) {
      logger.error(`Failed to update user limits: ${userId}`, error);
      throw error;
    }
  }

  /**
   * Enable or disable user account
   */
  async setUserStatus(userId, disabled = false) {
    try {
      logger.info(`${disabled ? 'Disabling' : 'Enabling'} user ${userId}`);

      const user = await this.getUserById(userId);
      const updatedUser = {
        ...user,
        disabled,
      };

      await this.request(`/api/users/${userId}`, {
        method: 'PUT',
        body: JSON.stringify(updatedUser),
      });

      logger.info(`Successfully ${disabled ? 'disabled' : 'enabled'} user ${userId}`);
      return updatedUser;
    } catch (error) {
      logger.error(`Failed to set user status: ${userId}`, error);
      throw error;
    }
  }

  /**
   * Create new user (for registration)
   */
  async createUser(userData) {
    try {
      logger.info(`Creating new user: ${userData.email}`);

      // Ensure user is not disabled by default
      const userPayload = {
        name: userData.name,
        email: userData.email,
        password: userData.password,
        deviceLimit: userData.deviceLimit || -1,
        disabled: false, // Explicitly set to false
        administrator: false,
        readonly: false,
        deviceReadonly: false,
        limitCommands: false,
      };

      logger.debug(`User payload (password hidden): ${JSON.stringify({ ...userPayload, password: '***' })}`);

      const newUser = await this.request('/api/users', {
        method: 'POST',
        body: JSON.stringify(userPayload),
      });

      logger.info(`Successfully created user ${newUser.id}`);
      return newUser;
    } catch (error) {
      logger.error('Failed to create user', error);
      throw error;
    }
  }

  /**
   * Update user password
   */
  async updateUserPassword(userId, newPassword) {
    try {
      logger.info(`Updating password for user ${userId}`);

      const user = await this.getUserById(userId);

      const updatedUser = {
        ...user,
        password: newPassword,
      };

      await this.request(`/api/users/${userId}`, {
        method: 'PUT',
        body: JSON.stringify(updatedUser),
      });

      logger.info(`Successfully updated password for user ${userId}`);
      return true;
    } catch (error) {
      logger.error(`Failed to update password for user ${userId}`, error);
      throw error;
    }
  }

  /**
   * Verify user credentials (test login)
   */
  async verifyUserCredentials(email, password) {
    try {
      logger.info(`Testing login for user: ${email}`);

      const response = await fetch(`${this.baseUrl}/api/session`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
          email,
          password,
        }),
      });

      if (response.ok) {
        logger.info(`✓ Login test successful for ${email}`);
        return true;
      } else {
        const error = await response.text();
        logger.error(`✗ Login test failed for ${email}: ${error}`);
        return false;
      }
    } catch (error) {
      logger.error(`Error testing login for ${email}:`, error);
      return false;
    }
  }

  /**
   * Get user's device count
   */
  async getUserDeviceCount(userId) {
    try {
      const devices = await this.request('/api/devices');
      const userDevices = devices.filter(device => {
        // Check if user has access to this device
        return device.userId === userId;
      });

      return userDevices.length;
    } catch (error) {
      logger.error(`Failed to get device count for user ${userId}`, error);
      throw error;
    }
  }

  /**
   * Update user subscription metadata
   */
  async updateSubscriptionMetadata(userId, subscriptionData) {
    try {
      const user = await this.getUserById(userId);

      const updatedUser = {
        ...user,
        attributes: {
          ...user.attributes,
          stripeCustomerId: subscriptionData.customerId,
          stripeSubscriptionId: subscriptionData.subscriptionId,
          subscriptionPlan: subscriptionData.plan,
          subscriptionStatus: subscriptionData.status,
          subscriptionStartDate: subscriptionData.startDate,
        },
      };

      await this.request(`/api/users/${userId}`, {
        method: 'PUT',
        body: JSON.stringify(updatedUser),
      });

      logger.info(`Updated subscription metadata for user ${userId}`);
      return updatedUser;
    } catch (error) {
      logger.error(`Failed to update subscription metadata: ${userId}`, error);
      throw error;
    }
  }
}

// Export singleton instance
export default new TraccarClient();
