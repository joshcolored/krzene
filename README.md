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
NEXT_PUBLIC_SITE_URL=http://localhost:3000
```

Use a Supabase publishable key (`sb_publishable_...`) in the public variable. Never put a service-role key or another secret key in a `NEXT_PUBLIC_` variable.

Start the development server:

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

## Database setup

Open the Supabase SQL Editor and run the complete migration:

```text
supabase/migrations/20260826000000_profiles_and_libraries.sql
```

The migration creates:

- `viewer_profiles` for the profiles belonging to each authenticated account
- `library_items` for saved titles belonging to a specific viewer profile
- Foreign keys and indexes
- Row Level Security policies for selecting, creating, editing, and deleting data

Keep Row Level Security enabled. The application is designed to access Supabase using the signed-in user session, not a service-role key.

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

## Vercel deployment

Import the repository into Vercel, then open **Project → Settings → Environment Variables**.

Add these variables to Production, Preview, and Development:

```text
TMDB_API_KEY
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
```

Add the following to Production with the final application URL:

```text
NEXT_PUBLIC_SITE_URL=https://your-project.vercel.app
```

For Preview deployments, `NEXT_PUBLIC_SITE_URL` can be omitted so the current preview origin is used.

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
  PlayerChrome.tsx     Custom playback interface
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

Run the SQL migration in the Supabase SQL Editor and confirm that `viewer_profiles` and `library_items` exist.

### Authentication works locally but fails on Vercel

Check that the production domain is configured in Google, Supabase URL Configuration, and `NEXT_PUBLIC_SITE_URL`. Redeploy after changing Vercel environment variables.

### A saved title is missing

Confirm that the correct viewer profile is selected. Libraries are intentionally isolated per profile.

## Data providers

Catalog metadata and artwork are provided by TMDB. Playback is embedded through VidSrc.

This product uses the TMDB API but is not endorsed or certified by TMDB.
