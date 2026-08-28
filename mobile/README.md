# Krzene mobile

Flutter client for Android and iOS. It uses the Krzene Next.js API for catalog
and title metadata, embeds the same playback providers as the web app, and can
sync profiles, libraries, and VidSrc watch progress through Supabase.

## Run locally

From this directory:

```bash
flutter pub get
flutter run
```

All builds use `https://krzene.site` by default, including debug builds on a
physical phone. To test against a local Next.js server, override the API URL
explicitly:

```bash
# Android emulator
flutter run --dart-define=KRZENE_API_BASE_URL=http://10.0.2.2:3000

# Physical Android or iOS device (replace with the computer's LAN address)
flutter run --dart-define=KRZENE_API_BASE_URL=http://192.168.1.20:3000
```

For a physical device, keep the phone and computer on the same network and run
the Next.js development server on `0.0.0.0`. The Supabase URL and publishable
client key are included in the app configuration; `--dart-define` can still
override them per build.

Google sign-in uses one Supabase OAuth session in a secure browser panel. After
Google signs the user in, the browser returns to the native app through:

```text
site.krzene.app://login-callback
```

This avoids Android Credential Manager's ambiguous account-reauthentication
errors and works the same way on Android and iOS. The callback scheme is
already declared in `android/app/src/main/AndroidManifest.xml` and
`ios/Runner/Info.plist`.

Complete these dashboard settings once:

1. In **Supabase Dashboard → Authentication → URL Configuration**, add
   `site.krzene.app://login-callback` to **Redirect URLs**. It must match
   exactly; otherwise Supabase falls back to the website Site URL.
2. In **Supabase Dashboard → Authentication → Providers → Google**, keep the
   Google Web client ID and secret configured.
3. In Google Auth Platform, keep the Supabase callback URL shown on that
   provider page registered as an authorized redirect URI for the Web client.

The app deliberately requests account selection once. It does not retry the
picker after a failure, so a single tap cannot produce duplicate Google account
dialogs.

## Verify and build

```bash
flutter analyze
flutter test
flutter build apk --release
```

Configure a private Android release signing key before publishing; the generated
project currently uses the debug signing configuration for local release builds.
