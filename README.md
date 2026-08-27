# Krzene

Krzene is a cinematic streaming interface built with Next.js. It combines a TMDB-powered catalog, VidSrc playback, Google authentication, multiple viewer profiles, and separate cloud-synced libraries for every profile.

## Features

- Responsive streaming catalog for desktop and mobile
- Trending, movie, series, anime, and Top 10 carousels
- TMDB metadata, artwork, search, genres, and recommendations
- VidSrc movie and episode playback
- Google sign-in through Supabase Auth
- Multiple viewer profiles per account
- Separate Supabase-backed library for every profile
- Local-storage library fallback for signed-out visitors
- Row Level Security protecting profile and library data
- ₱50 Premium access with server-verified PayMongo checkout
- Privacy-aware manual AdSense placements (disabled for Kids and Premium)
- Vercel-ready OAuth callback and session middleware

## Technology

- Next.js 15 and React 19
- TypeScript
- Tailwind CSS 4
- Supabase Auth, PostgreSQL, and Row Level Security
- TMDB API
- VidSrc embeds

## Requirements

- Node.js 20 or newer
- A [TMDB API key](https://www.themoviedb.org/settings/api)
- A [Supabase](https://supabase.com/) project
- A Google Cloud project for OAuth
- A Vercel account for deployment (optional)
- A PayMongo account for Premium payments
- A Google AdSense account for ads (optional)

## Local installation

Clone the repository, install dependencies, and create a local environment file:

```bash
npm install
```

Copy `.env.example` to `.env.local` and provide real values:

```dotenv
TMDB_API_KEY=your_tmdb_key
NEXT_PUBLIC_SUPABASE_URL=https://your-project-ref.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=your_publishable_key
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
APP_URL=http://localhost:3000
PAYMONGO_SECRET_KEY=sk_test_your_secret_key
PAYMONGO_WEBHOOK_SECRET=whsk_your_test_webhook_secret
```

Use a Supabase publishable key (`sb_publishable_...`) in the public variable. Never put a service-role key or another secret key in a `NEXT_PUBLIC_` variable.

Start the development server:

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

## Database setup

Open the Supabase SQL Editor and run all migrations in order:

```text
supabase/migrations/20260826000000_profiles_and_libraries.sql
supabase/migrations/20260827000000_watch_progress.sql
supabase/migrations/20260828000000_premium_access.sql
```

The migration creates:

- `viewer_profiles` for the profiles belonging to each authenticated account
- `library_items` for saved titles belonging to a specific viewer profile
- `watch_progress` for the signed-in profile's Continue Watching rail
- `premium_subscriptions`, checkout records, and idempotent webhook records
- Foreign keys and indexes
- Row Level Security policies for selecting, creating, editing, and deleting data

Keep Row Level Security enabled. Browser requests use the signed-in session. The service-role key is used only by server routes to record PayMongo checkout sessions and activate Premium after a verified webhook; never expose it through a `NEXT_PUBLIC_` variable.

## Google authentication

### 1. Create the Google OAuth client

In the [Google Auth Platform](https://console.cloud.google.com/auth/overview):

1. Configure the OAuth consent screen and application branding.
2. Choose an External audience unless the application is limited to a Google Workspace organization.
3. Add your Google account as a test user while the OAuth application is in testing mode.
4. Create an OAuth client with the **Web application** type.

Add this local Authorized JavaScript origin:

```text
http://localhost:3000
```

After deploying, add the production origin as well:

```text
https://your-project.vercel.app
```

Add the Supabase callback as an Authorized redirect URI:

```text
https://your-project-ref.supabase.co/auth/v1/callback
```

Do not use the application `/auth/callback` URL in Google. Google returns to Supabase first; Supabase then redirects to the application callback.

### 2. Enable Google in Supabase

In **Supabase → Authentication → Sign In / Providers → Google**:

1. Enable Google.
2. Paste the Google OAuth Client ID.
3. Paste the Google OAuth Client secret.
4. Save the provider configuration.

The Google Client secret belongs in Supabase. It should not be stored in `.env.local` or exposed to the browser.

### 3. Configure Supabase URLs

In **Supabase → Authentication → URL Configuration**, use this Site URL during local development:

```text
http://localhost:3000
```

Add this Redirect URL:

```text
http://localhost:3000/**
```

For production, change the Site URL and add an exact production redirect entry:

```text
https://your-project.vercel.app
https://your-project.vercel.app/**
```

For Vercel previews, Supabase supports a wildcard such as:

```text
https://*-your-team-slug.vercel.app/**
```

## Authentication flow

```text
Krzene → Google → Supabase → /auth/callback → Krzene
```

After the callback exchanges the OAuth code for a secure session, Krzene loads or creates the account's initial profile. A selected profile determines which library is displayed and updated.

Signed-out visitors can still save titles locally. Signed-in profile libraries are stored in Supabase and protected by Row Level Security.

## Premium and PayMongo setup

Krzene currently sells **30 days of Premium for ₱50** as a one-time PayMongo Hosted Checkout. It does not silently auto-renew. A customer can renew early; every successful payment adds another 30 days after the account's current expiry.

### 1. Prepare PayMongo

1. Create or activate your merchant at [PayMongo](https://dashboard.paymongo.com/).
2. Complete the required business/KYC steps.
3. Open **Developers → API Keys** and copy the **test secret key** (`sk_test_...`).
4. Put it in `.env.local` as `PAYMONGO_SECRET_KEY`. Never prefix this variable with `NEXT_PUBLIC_`.
5. Set the methods enabled for your account. The default is:

```dotenv
PAYMONGO_PAYMENT_METHODS=qrph
```

If checkout reports that a method is unavailable, remove that method until PayMongo activates it for the account.

### 2. Create the webhook

Deploy once so the endpoint is public, then in **PayMongo Dashboard → Developers → Webhooks → Add endpoint** enter:

```text
https://krzene.site/api/paymongo/webhook
```

Subscribe only to:

```text
checkout_session.payment.paid
```

Copy the endpoint's signing secret (`whsk_...`) into Vercel as `PAYMONGO_WEBHOOK_SECRET`. This is different from the PayMongo API secret key. The route verifies `Paymongo-Signature` against the raw request body with HMAC-SHA256 before touching Supabase, and records each event ID once so retries cannot add duplicate access.

For local webhook testing, use a public HTTPS tunnel and create a separate **test-mode** webhook for that tunnel. PayMongo cannot deliver to `localhost` directly.

### 3. Configure the server secrets

In Vercel, add these as **server-only** variables for Production (and Preview only if you intend to test there):

```dotenv
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
APP_URL=https://krzene.site
PAYMONGO_SECRET_KEY=sk_test_...
PAYMONGO_WEBHOOK_SECRET=whsk_...
PAYMONGO_PAYMENT_METHODS=qrph
```

Get the service-role key from **Supabase → Project Settings → API Keys**. It bypasses RLS and must never be copied into browser code, committed, or given a `NEXT_PUBLIC_` name.

### 4. Test before going live

1. Apply `20260828000000_premium_access.sql`.
2. Deploy the environment variables.
3. Sign in, open **Go Premium**, and complete a PayMongo test checkout.
4. In PayMongo, confirm the webhook received a `2xx` response.
5. In Supabase, confirm the checkout is `paid` and `premium_subscriptions.current_period_end` is about 30 days ahead.
6. Refresh the catalog and confirm the Premium badge appears and both ad units disappear.
7. Repeat the same event from PayMongo's delivery tools and confirm the expiry is **not** extended twice.

When ready, replace `sk_test_...` with the live key and register a separate live webhook. Never test the payment code first with a live key.

### Optional true monthly auto-renewal

PayMongo has a Subscriptions API, but PayMongo must enable it for the merchant account. Scheduled subscriptions currently support cards and Maya and require a reusable Plan, Customer, and initial payment flow. Contact PayMongo support to enable Subscriptions before changing this implementation. Until then, the UI intentionally says **₱50 for 30 days** and **does not auto-renew**.

## AdSense setup

The app only creates manual ad units on the homepage catalog. It does not add ads to `/watch/*`, `/auth/*`, `/offline`, Premium accounts, or Kids profiles.

1. In AdSense, keep **Auto ads**, overlay, vignette, anchor, and popup-style formats disabled.
2. Create two responsive **Display ad** units.
3. Copy each numeric slot ID into Vercel:

```dotenv
NEXT_PUBLIC_ADSENSE_CLIENT_ID=ca-pub-5965941687701015
NEXT_PUBLIC_ADSENSE_SLOT_CATALOG=1234567890
NEXT_PUBLIC_ADSENSE_SLOT_FOOTER=0987654321
NEXT_PUBLIC_SUPPORT_EMAIL=support@krzene.site
```

4. Redeploy and verify [https://krzene.site/ads.txt](https://krzene.site/ads.txt) returns:

```text
google.com, pub-5965941687701015, DIRECT, f08c47fec0942fa0
```

5. Review `/privacy`, `/terms`, `/contact`, and `/copyright`. Replace the support email with a monitored address before launch.
6. Configure a consent message/CMP in AdSense for every region where consent is required. Premium removes display ads, but it does not replace your privacy and consent obligations.

Ad inventory can be empty in test or newly approved accounts. Ad blockers can also hide units; neither case should affect catalog layout or playback.

## Vercel deployment

Import the repository into Vercel, then open **Project → Settings → Environment Variables**.

Add these variables to Production, Preview, and Development:

```text
TMDB_API_KEY
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
```

Add the payment server secrets and final application URL to Production:

```text
SUPABASE_SERVICE_ROLE_KEY
APP_URL=https://krzene.site
PAYMONGO_SECRET_KEY
PAYMONGO_WEBHOOK_SECRET
PAYMONGO_PAYMENT_METHODS
```

OAuth callbacks automatically use the origin where sign-in begins. This keeps custom-domain sessions on `https://krzene.site` and preview sessions on their own Vercel URL.

Keep each production or preview origin you use in Supabase's redirect allowlist.

After Vercel provides the production domain, also update:

- Google Authorized JavaScript origins
- Supabase Site URL
- Supabase Redirect URLs

Environment variable changes only affect new deployments. Redeploy after modifying them.

## Available commands

```bash
npm run dev      # Start the local development server
npm run build    # Create and validate the production build
npm run start    # Run the production server
npm run lint     # Run the configured Next.js lint command
```

## Project structure

```text
app/
  api/search/          TMDB search endpoint
  auth/callback/       Supabase OAuth code exchange
  watch/               Movie and series playback routes
components/
  AuthProvider.tsx     Authentication, profiles, and library state
  ProfileChooser.tsx   Viewer selection and profile management
  StreamingHome.tsx    Catalog, navigation, rails, and footer
  WatchExperience.tsx  Watch page and library integration
  WatchExperience.tsx  Provider player, servers, subtitles, and episodes
lib/
  supabase/            Browser, server, and middleware clients
  home.ts              Home catalog assembly
  tmdb.ts              TMDB API client
  vidsrc.ts            VidSrc embed helpers
supabase/migrations/   Database schema and RLS policies
```

## Troubleshooting

### Google reports `redirect_uri_mismatch`

Verify that Google contains the exact Supabase callback:

```text
https://your-project-ref.supabase.co/auth/v1/callback
```

### Profiles are not ready

Run both SQL migrations in the Supabase SQL Editor and confirm that `viewer_profiles`, `library_items`, and `watch_progress` exist.

### Authentication works locally but fails on Vercel

Check that the production domain is configured in Google and Supabase URL Configuration, then redeploy.

### A saved title is missing

Confirm that the correct viewer profile is selected. Libraries are intentionally isolated per profile.

## Data providers

Catalog metadata and artwork are provided by TMDB. Playback is embedded through VidSrc.

This product uses the TMDB API but is not endorsed or certified by TMDB.
