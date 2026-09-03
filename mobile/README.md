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

### Run on a physical iPhone

1. Connect the unlocked iPhone to the Mac, tap **Trust** on the iPhone, and
   enter the device passcode.
2. Open `ios/Runner.xcworkspace` in Xcode. Do not open `Runner.xcodeproj`.
3. In **Xcode → Settings → Accounts**, sign in with the Apple Account that owns
   the developer membership.
4. Select **Runner → TARGETS: Runner → Signing & Capabilities → All**. Enable
   **Automatically manage signing** and select the developer **Team**. Keep the
   bundle identifier as `site.krzene.krzeneMobile` unless the same identifier is
   also changed in Apple Developer and Supabase.
5. Select the connected iPhone as the run destination and press **Run** once.
   Xcode will register the phone and create/download a development provisioning
   profile when automatic signing is enabled.
6. If prompted, enable **Settings → Privacy & Security → Developer Mode** on the
   iPhone, restart it, confirm Developer Mode, and run again.
7. After Xcode has provisioned the app, it can also be launched from this folder:

   ```bash
   flutter devices
   flutter run -d <iphone-device-id>
   ```

   `flutter run` installs a Debug build. On a physical iPhone running iOS 14 or
   later, that build requires Flutter or Xcode to remain attached and cannot be
   relaunched normally from the Home Screen. To install a standalone test copy
   that keeps working after the phone is unplugged, use an AOT Release build:

   ```bash
   flutter run --release -d <iphone-device-id>
   ```

   Use Debug for hot reload while developing and Release for untethered testing.

The iPhone and Mac only need to share a network when testing against a local
Krzene API. The default `https://krzene.site` API and Supabase project work over
the phone's normal internet connection.

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
   `site.krzene.app://login-callback` and
   `site.krzene.app://reset-password` to **Redirect URLs**. They must match
   exactly; otherwise Supabase falls back to the website Site URL.
2. In **Supabase Dashboard → Authentication → Providers → Google**, keep the
   Google Web client ID and secret configured.
3. In Google Auth Platform, keep the Supabase callback URL shown on that
   provider page registered as an authorized redirect URI for the Web client.

## Email and password authentication

The mobile sign-in screen also supports creating an account with a name, email,
and password and signing in with those credentials. The name is stored in
Supabase Auth user metadata as `full_name`. Apply
`supabase/migrations/20260903000000_email_auth_initial_profile.sql` and
`supabase/migrations/20260903010000_all_auth_initial_profiles.sql` so every new
Supabase account receives an initial viewer profile. The trigger supports
email/password, Google, and Apple accounts.

In **Supabase Dashboard → Authentication → Sign In / Providers → Email**:

1. Enable the Email provider.
2. Keep **Confirm email** enabled for production.
3. In **URL Configuration**, keep `site.krzene.app://login-callback` in the
   Redirect URLs list so confirmation links return to the mobile app. Also add
   `site.krzene.app://reset-password` for password recovery links.
4. Customize the confirmation email under **Authentication → Email Templates**
   if desired.
5. Under **Authentication → Email Templates → Security notifications**, enable
   **Password changed**. Supabase then emails the user after either the mobile
   or web client successfully updates their password.

The web reset flow returns through `/auth/recovery` and then opens the password
form. Add `https://krzene.site/auth/recovery` and `https://krzene.site/**` to
the Supabase Redirect URLs list, along with any local or preview origins used
for testing.

Run every migration in chronological order in the Supabase SQL Editor before
testing a newly registered account. The app never stores a plaintext password;
password verification and storage are handled by Supabase Auth.

The app deliberately requests account selection once. It does not retry the
picker after a failure, so a single tap cannot produce duplicate Google account
dialogs.

No `GoogleService-Info.plist` is required for this implementation. The iOS app
uses the same Supabase browser OAuth flow and Google Web client as Android; iOS
only needs the registered custom URL scheme already present in `Info.plist`.

## Sign in with Apple

The iOS app uses Apple's native Authentication Services dialog and exchanges
the Apple identity token with Supabase using a hashed nonce. It stores the
person's name in Supabase user metadata immediately because Apple only returns
the name on the first authorization.

The code, iOS entitlement, and Xcode capability are already included. Complete
these account settings once:

### Apple Developer

1. Open **Certificates, Identifiers & Profiles → Identifiers** in Apple
   Developer. Create or select an explicit **App ID** whose bundle ID is exactly
   `site.krzene.krzeneMobile`.
2. Edit that App ID, enable **Sign in with Apple**, click **Configure**, and use
   **Enable as a primary App ID** unless this app must share users with an
   existing Apple app group. Leave the server-to-server notification URL blank.
3. Save the App ID. If Apple invalidates an older provisioning profile after the
   capability change, let Xcode automatic signing regenerate it.
4. In Xcode, confirm **Runner → Signing & Capabilities** shows **Sign in with
   Apple**. The checked-in `Runner.entitlements` file already declares it.

### Supabase

1. Open **Authentication → Sign In / Providers → Apple** for the project.
2. Enable Apple and add `site.krzene.krzeneMobile` to **Client IDs**. The value
   is case-sensitive and must match Xcode and the Apple App ID exactly.
3. Save. For this native iOS-only flow, a Services ID, `.p8` signing key, and
   OAuth secret are not required. Those are only needed if Apple sign-in is also
   offered through the web or a browser OAuth flow.

Test with the **Continue with Apple** button on a real iPhone. Try both **Share
My Email** and **Hide My Email**. A hidden address ending in
`privaterelay.appleid.com` is expected. Confirm the new user appears in
**Supabase → Authentication → Users**, with `apple` as the provider.

To repeat Apple's first-authorization experience, remove Krzene under the Apple
Account's **Sign in with Apple** app settings and delete the corresponding test
user from Supabase before testing again.

## Verify and build

```bash
flutter analyze
flutter test
flutter build apk --release
```

Configure a private Android release signing key before publishing; the generated
project currently uses the debug signing configuration for local release builds.
