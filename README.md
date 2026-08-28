# Krzene

Krzene is a cinematic streaming interface built with Next.js. It combines a TMDB-powered catalog, VidSrc playback, Google authentication, multiple viewer profiles, and separate cloud-synced libraries for every profile.

## Features

- Responsive streaming catalog for desktop and mobile
- Trending, movie, series, anime, and Top 10 carousels
- TMDB metadata, artwork, search, genres, and recommendations
- VidSrc movie and episode playback
- CineSrc and MultiEmbed fallback playback servers
- Google sign-in through Supabase Auth
- Multiple viewer profiles per account
- Separate Supabase-backed library for every profile
- Signed-in-only libraries, hidden from guests
- Row Level Security protecting profile and library data
- Privacy-aware manual AdSense placements (disabled for Kids profiles)
- Vercel-ready OAuth callback and session middleware

## Technology

- Next.js 15 and React 19
- TypeScript
- Tailwind CSS 4
- Supabase Auth, PostgreSQL, and Row Level Security
- TMDB API
- Watchmode availability API
- VidSrc embeds

## Requirements

- Node.js 20 or newer
- A [TMDB API key](https://www.themoviedb.org/settings/api)
- A [Watchmode API key](https://api.watchmode.com/requestApiKey/) for legal availability links (optional)
- A [Supabase](https://supabase.com/) project
- A Google Cloud project for OAuth
- A Vercel account for deployment (optional)
- A Google AdSense account for ads (optional)

## Local installation

Clone the repository, install dependencies, and create a local environment file:

```bash
npm install
```

Copy `.env.example` to `.env.local` and provide real values:

```dotenv
TMDB_API_KEY=your_tmdb_key
WATCHMODE_API_KEY=your_watchmode_api_key
WATCHMODE_REGION=PH
NEXT_PUBLIC_SUPABASE_URL=https://your-project-ref.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=your_publishable_key
```

Use a Supabase publishable key (`sb_publishable_...`) in the public variable. Never put a service-role key or another secret key in a `NEXT_PUBLIC_` variable.

`WATCHMODE_API_KEY` is server-only. The watch page maps each TMDB ID to Watchmode and displays legal subscription, free, rental, and purchase links for `WATCHMODE_REGION`. Watchmode is an availability provider, not an embedded playback server.

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
```

The migration creates:

- `viewer_profiles` for the profiles belonging to each authenticated account
- `library_items` for saved titles belonging to a specific viewer profile
- `watch_progress` for the signed-in profile's Continue Watching rail
- Foreign keys and indexes
- Row Level Security policies for selecting, creating, editing, and deleting data

Keep Row Level Security enabled. Browser requests use the signed-in session, and all profile-owned data remains protected by its policies.

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

## AdSense setup

The app only creates manual ad units on the homepage catalog. It does not add ads to `/watch/*`, `/auth/*`, `/offline`, or Kids profiles.

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
6. Configure a consent message/CMP in AdSense for every region where consent is required.

Ad inventory can be empty in test or newly approved accounts. Ad blockers can also hide units; neither case should affect catalog layout or playback.

### Optional timed sponsor promotion

The catalog can show a direct-sponsor promotion after a random delay of five to eight minutes. Its close control unlocks after five seconds, and the next promotion is scheduled at least five minutes later. It is disabled on Watch pages and Kids profiles.

Do not place AdSense code in this modal. Google prohibits AdSense ads in popups. To use the modal for a direct sponsor, configure these optional public variables. Without a sponsor URL, the modal remains disabled:

```dotenv
NEXT_PUBLIC_CATALOG_SPONSOR_URL=https://sponsor.example/offer
NEXT_PUBLIC_CATALOG_SPONSOR_TITLE=Sponsor offer title
NEXT_PUBLIC_CATALOG_SPONSOR_DESCRIPTION=A short and accurate description of the offer.
NEXT_PUBLIC_CATALOG_SPONSOR_CTA=View offer
NEXT_PUBLIC_CATALOG_SPONSOR_IMAGE_URL=https://sponsor.example/creative.jpg
```

## Vercel deployment

Import the repository into Vercel, then open **Project → Settings → Environment Variables**.

Add these variables to Production, Preview, and Development:

```text
TMDB_API_KEY
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
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
