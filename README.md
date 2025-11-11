# Traczi Billing Middleware

Node.js/Express middleware for handling Stripe subscriptions and Traccar user provisioning for the Traczi platform.

## Features

- Stripe Checkout integration for subscription plans
- Webhook handling for subscription lifecycle events
- Traccar API integration for user provisioning and device limit management
- Rate limiting and security middleware
- Comprehensive logging

## Prerequisites

- Node.js 18+
- Stripe account with test/live API keys
- Traccar server with admin credentials
- Stripe CLI (for webhook testing)

## Installation

```bash
cd server
npm install
```

## Configuration

1. Copy the example environment file:
```bash
cp .env.example .env
```

2. Update `.env` with your configuration:

Required variables:
- `STRIPE_SECRET_KEY` - Your Stripe secret key
- `STRIPE_PUBLISHABLE_KEY` - Your Stripe publishable key
- `STRIPE_WEBHOOK_SECRET` - Webhook signing secret (get after registering webhook)
- `STRIPE_PRICE_*` - Price IDs for each plan tier
- `TRACCAR_ADMIN_EMAIL` - Traccar admin email
- `TRACCAR_ADMIN_PASSWORD` - Traccar admin password

## Subscription Plans

The middleware supports three subscription tiers:

| Plan | Price | Device Limit |
|------|-------|--------------|
| Basic | $20/month | 30 devices |
| Moderate | $40/month | 80 devices |
| Advance | $100/month | 150 devices |

Plans are configured in `config/plans.js`.

## API Endpoints

### Billing Endpoints

**GET /billing/plans**
- List all available subscription plans
- Returns: Array of plan objects with details

**GET /billing/plans/:planId**
- Get specific plan details
- Params: `planId` (basic, moderate, advance)

**POST /billing/checkout**
- Create Stripe checkout session
- Body: `{ planId, email, metadata }`
- Returns: Checkout session URL and ID

**POST /billing/portal**
- Create customer portal session for subscription management
- Body: `{ customerId }`
- Returns: Portal URL

**GET /billing/session/:sessionId**
- Retrieve checkout session details
- Params: `sessionId`

**GET /billing/subscription/:subscriptionId**
- Get subscription details
- Params: `subscriptionId`

**GET /billing/config**
- Get public billing configuration
- Returns: Publishable key and plans

### Webhook Endpoint

**POST /webhooks/stripe**
- Stripe webhook handler
- Handles events: checkout.session.completed, customer.subscription.*, invoice.payment_*

## Development

Start the development server with auto-reload:

```bash
npm run dev
```

The server will start on port 4000 (configurable via PORT env variable).

## Setting Up Stripe Webhooks

### Local Development (using Stripe CLI)

1. Install Stripe CLI: https://stripe.com/docs/stripe-cli

2. Login to Stripe:
```bash
stripe login
```

3. Forward webhooks to local server:
```bash
stripe listen --forward-to localhost:4000/webhooks/stripe
```

4. Copy the webhook signing secret (whsec_...) to your `.env` file as `STRIPE_WEBHOOK_SECRET`

### Production

1. Register webhook endpoint in Stripe Dashboard:
   - URL: `https://your-domain.com/webhooks/stripe`
   - Events to listen to:
     - `checkout.session.completed`
     - `customer.subscription.created`
     - `customer.subscription.updated`
     - `customer.subscription.deleted`
     - `invoice.payment_failed`
     - `invoice.payment_succeeded`

2. Copy the webhook signing secret to your production environment

## Traccar Integration

The middleware communicates with Traccar to:
- Create/update user accounts
- Set device limits based on subscription tier
- Enable/disable accounts based on subscription status
- Store subscription metadata in user attributes

### User Attributes Stored

- `stripeCustomerId` - Stripe customer ID
- `stripeSubscriptionId` - Stripe subscription ID
- `subscriptionPlan` - Plan tier (basic, moderate, advance)
- `subscriptionStatus` - Current status (active, canceled, etc.)
- `subscriptionStartDate` - When subscription started

## Security

- Rate limiting on all API endpoints
- Helmet.js for security headers
- CORS configuration for allowed origins
- Webhook signature verification
- Request validation with express-validator

## Logging

Logs are stored in the `logs/` directory:
- `combined.log` - All logs
- `error.log` - Error logs only

Log levels:
- Development: `debug`
- Production: `info`

## Testing Subscription Flow

1. Start the middleware server:
```bash
npm run dev
```

2. Start Stripe webhook forwarding:
```bash
stripe listen --forward-to localhost:4000/webhooks/stripe
```

3. Create a checkout session via API or frontend

4. Use Stripe test cards:
   - Success: `4242 4242 4242 4242`
   - Decline: `4000 0000 0000 0002`

5. Monitor logs and Traccar for user provisioning

## Error Handling

The middleware includes comprehensive error handling:
- Stripe errors are caught and returned with appropriate status codes
- Traccar API errors are logged and propagated
- All errors are logged with context

## Production Deployment

1. Set `NODE_ENV=production` in your environment

2. Use a process manager like PM2:
```bash
npm install -g pm2
pm2 start index.js --name traczi-billing
```

3. Enable PM2 startup:
```bash
pm2 startup
pm2 save
```

4. Monitor logs:
```bash
pm2 logs traczi-billing
```

## Troubleshooting

**Webhook signature verification fails:**
- Ensure `STRIPE_WEBHOOK_SECRET` matches your Stripe webhook endpoint
- Check that the raw body is being passed to the webhook handler

**Traccar authentication fails:**
- Verify admin credentials in `.env`
- Check Traccar server is accessible
- Review logs for detailed error messages

**User device limit not updating:**
- Verify webhook events are being received
- Check Traccar API permissions
- Review middleware logs for API errors

## Support

For issues or questions:
- Check logs in `logs/` directory
- Review Stripe Dashboard for webhook delivery status
- Verify Traccar API is responding
