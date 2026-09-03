// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krzene_mobile/app.dart';
import 'package:krzene_mobile/config.dart';
import 'package:krzene_mobile/controller.dart';
import 'package:krzene_mobile/design.dart';
import 'package:krzene_mobile/models.dart';
import 'package:krzene_mobile/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _SignedInAccount extends AccountRepository {
  @override
  User? get user => const User(
    id: 'test-user',
    appMetadata: {'provider': 'google'},
    userMetadata: {'full_name': 'Krzene Viewer'},
    aud: 'authenticated',
    email: 'viewer@krzene.site',
    createdAt: '2026-08-28T00:00:00.000Z',
  );
}

class _EditableAccount extends _SignedInAccount {
  var nextId = 1;
  final deletedProfileIds = <String>[];
  var accountDeleted = false;
  String? parentalPin;
  String? changedPassword;
  String? suppliedCurrentPassword;

  @override
  Future<ViewerProfile> createProfile(String name, {bool kids = false}) async =>
      ViewerProfile(id: '${nextId++}', name: name, isKids: kids);

  @override
  Future<ViewerProfile> updateProfileName(
    ViewerProfile profile,
    String name,
  ) async => ViewerProfile(
    id: profile.id,
    name: name,
    isKids: profile.isKids,
    avatarUrl: profile.avatarUrl,
    avatarColor: profile.avatarColor,
  );

  @override
  Future<void> deleteProfile(String profileId) async {
    deletedProfileIds.add(profileId);
  }

  @override
  Future<void> deleteAccount() async {
    accountDeleted = true;
  }

  @override
  Future<bool> hasParentalPin() async => parentalPin != null;

  @override
  Future<void> setParentalPin(String pin) async {
    parentalPin = pin;
  }

  @override
  Future<bool> verifyParentalPin(String pin) async => parentalPin == pin;

  @override
  Future<void> changePassword({
    required String newPassword,
    String? currentPassword,
  }) async {
    changedPassword = newPassword;
    suppliedCurrentPassword = currentPassword;
  }

  @override
  Future<List<Media>> library(String profileId) async => [];

  @override
  Future<List<ContinueItem>> continueWatching(String profileId) async => [];
}

class _EmailAccount extends _EditableAccount {
  String? registeredName;
  String? registeredEmail;
  String? registeredPassword;
  String? signedInEmail;
  String? signedInPassword;
  String? resetEmail;
  bool? rememberedSession;

  @override
  Future<bool> staySignedIn() async => true;

  @override
  Future<void> setStaySignedIn(bool value) async {
    rememberedSession = value;
  }

  @override
  Future<EmailSignUpResult> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    registeredName = name;
    registeredEmail = email;
    registeredPassword = password;
    return EmailSignUpResult(email: email, confirmationRequired: true);
  }

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    signedInEmail = email;
    signedInPassword = password;
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    resetEmail = email;
  }
}

class _ProgressAccount extends _SignedInAccount {
  final saves = <ContinueItem>[];

  @override
  Future<void> saveWatchProgress({
    required ViewerProfile profile,
    required Media media,
    required double position,
    required double duration,
    required bool completed,
    int? season,
    int? episode,
  }) async {
    if (!completed) {
      saves.add(
        ContinueItem(
          media: media,
          position: position,
          duration: duration,
          season: season,
          episode: episode,
        ),
      );
    }
  }
}

void main() {
  test('production API is the safe default for every device', () {
    expect(AppConfig.apiBaseUrl, 'https://krzene.site');
  });

  test('account access is safe before Supabase finishes initializing', () {
    expect(AccountRepository().user, isNull);
  });

  testWidgets('Krzene app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const KrzeneApp());
    expect(find.byType(KrzeneLaunchGate), findsOneWidget);
  });

  testWidgets('signed-out users see the login gate', (
    WidgetTester tester,
  ) async {
    final controller = KrzeneController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: krzeneTheme(),
        home: KrzeneLoginPage(controller: controller),
      ),
    );

    expect(find.text('Welcome to Krzene'), findsOneWidget);
    expect(find.text('Sign in with email'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('Terms'), findsOneWidget);
  });

  testWidgets('email registration submits name email and password', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final account = _EmailAccount();
    final controller = KrzeneController(account: account);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: krzeneTheme(),
        home: KrzeneLoginPage(controller: controller),
      ),
    );

    await tester.tap(find.text('Create account').first);
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Taylor Viewer');
    await tester.enterText(fields.at(1), 'Taylor@Example.com');
    await tester.enterText(fields.at(2), 'password123');
    await tester.enterText(fields.at(3), 'password123');
    await tester.tap(find.text('Create account').last);
    await tester.pumpAndSettle();

    expect(account.registeredName, 'Taylor Viewer');
    expect(account.registeredEmail, 'Taylor@Example.com');
    expect(account.registeredPassword, 'password123');
    expect(find.textContaining('confirm your email'), findsOneWidget);
  });

  testWidgets('email sign in submits credentials', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final account = _EmailAccount();
    final controller = KrzeneController(account: account);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: krzeneTheme(),
        home: KrzeneLoginPage(controller: controller),
      ),
    );

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'viewer@example.com');
    await tester.enterText(fields.at(1), 'password123');
    await tester.tap(find.text('Sign in with email'));
    await tester.pumpAndSettle();

    expect(account.signedInEmail, 'viewer@example.com');
    expect(account.signedInPassword, 'password123');
    expect(account.rememberedSession, isTrue);
  });

  testWidgets('forgot password sends a Supabase reset request', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final account = _EmailAccount();
    final controller = KrzeneController(account: account);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: krzeneTheme(),
        home: KrzeneLoginPage(controller: controller),
      ),
    );

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Email').last,
      'reset@example.com',
    );
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();

    expect(account.resetEmail, 'reset@example.com');
    expect(find.textContaining('a reset link has been sent'), findsOneWidget);
  });

  test(
    'watch progress immediately updates Continue Watching and persists',
    () async {
      final account = _ProgressAccount();
      const profile = ViewerProfile(
        id: 'profile-1',
        name: 'Viewer',
        isKids: false,
      );
      final media = _media('Progress Movie', ['Drama']);
      final controller = KrzeneController(account: account)
        ..profiles = const [profile]
        ..activeProfile = profile;
      addTearDown(controller.dispose);

      await controller.saveWatchProgress(media, 42, 120);

      expect(controller.continueWatching, hasLength(1));
      expect(controller.continueWatching.single.media.key, media.key);
      expect(controller.continueWatching.single.position, 42);
      expect(account.saves.single.position, 42);
    },
  );

  testWidgets('profile shows account data and settings', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = KrzeneController(account: _SignedInAccount());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: krzeneTheme(),
        home: Scaffold(body: KrzeneAccountPage(controller: controller)),
      ),
    );

    expect(find.text('Krzene Viewer'), findsOneWidget);
    expect(find.text('viewer@krzene.site'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Language & region'), findsOneWidget);
    expect(find.text('Manage profiles'), findsOneWidget);
    expect(find.text('Help & support'), findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Terms of use'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('create profile sheet closes without framework assertions', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = KrzeneController(account: _EditableAccount());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: krzeneTheme(),
        home: Scaffold(body: KrzeneAccountPage(controller: controller)),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -320));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add profile'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Family');
    await tester.pump();
    await tester.tap(find.text('Create profile'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(controller.profiles.single.name, 'Family');
  });

  testWidgets('manage profiles confirms permanent swipe deletion', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final account = _EditableAccount();
    final controller = KrzeneController(account: account)
      ..profiles = const [
        ViewerProfile(id: 'profile-1', name: 'Family', isKids: false),
      ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: krzeneTheme(),
        home: Scaffold(body: KrzeneAccountPage(controller: controller)),
      ),
    );

    await tester.ensureVisible(find.text('Manage profiles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage profiles'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Family').first, const Offset(-360, 0));
    await tester.pumpAndSettle();

    expect(find.text('Delete Family?'), findsOneWidget);
    expect(find.textContaining('This permanently deletes'), findsOneWidget);
    await tester.tap(find.text('Delete profile'));
    await tester.pumpAndSettle();

    expect(account.deletedProfileIds, ['profile-1']);
    expect(controller.profiles, isEmpty);
  });

  testWidgets('manage profiles opens and submits change password', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final account = _EditableAccount();
    final controller = KrzeneController(account: account);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: krzeneTheme(),
        home: Scaffold(body: KrzeneAccountPage(controller: controller)),
      ),
    );

    await tester.ensureVisible(find.text('Manage profiles'));
    await tester.tap(find.text('Manage profiles'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Change password'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'New password'),
      'new-password-123',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm new password'),
      'new-password-123',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Change password'));
    await tester.pumpAndSettle();

    expect(account.changedPassword, 'new-password-123');
    expect(
      find.textContaining('Password changed successfully'),
      findsOneWidget,
    );
  });

  testWidgets('help and support confirms account deletion', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final account = _EditableAccount();
    final controller = KrzeneController(account: account);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: krzeneTheme(),
        home: Scaffold(body: KrzeneAccountPage(controller: controller)),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Help & support'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Help & support'));
    await tester.pumpAndSettle();
    expect(find.text('Delete my account'), findsOneWidget);

    await tester.tap(find.text('Delete my account'));
    await tester.pumpAndSettle();
    expect(find.text('Delete your account?'), findsOneWidget);
    expect(find.textContaining('This permanently deletes'), findsOneWidget);
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();

    expect(account.accountDeleted, isTrue);
  });

  testWidgets('search is populated with catalog recommendations', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const recommended = Media(
      key: 'movie-1',
      kind: 'movie',
      tmdbId: 1,
      title: 'Recommended Movie',
      overview: 'A recommendation for the viewer.',
      poster: null,
      backdrop: null,
      score: 8.4,
      genres: ['Drama'],
      year: 2026,
    );
    final controller = KrzeneController()
      ..catalog = HomeCatalog(
        MediaDetail(
          key: 'hero-1',
          kind: 'movie',
          tmdbId: 2,
          title: 'Hero Movie',
          overview: '',
          poster: null,
          backdrop: null,
          score: 8,
          genres: const ['Action'],
          runtime: '',
          tagline: '',
          seasons: const [],
          recommendations: const [recommended],
        ),
        const [
          MediaRail('recommended', 'FOR YOU', 'Recommended to watch', [
            recommended,
          ]),
        ],
        'en-US',
      );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: krzeneTheme(),
        home: Scaffold(body: SearchPage(controller: controller)),
      ),
    );

    expect(find.text('Recommended to watch'), findsOneWidget);
    expect(find.text('Recommended Movie'), findsAtLeastNWidgets(1));
  });

  test('kids safety accepts only explicit Kids or Family genres', () {
    expect(_media('Family Movie', ['Family']).isKidsSafe, isTrue);
    expect(_media('Kids Show', ['Kids']).isKidsSafe, isTrue);
    expect(
      _media('Animated Crime', ['Animation', 'Crime']).isKidsSafe,
      isFalse,
    );
    expect(_media('Whisper Man', ['Crime', 'Drama']).isKidsSafe, isFalse);
  });

  testWidgets('kids profile replaces the unrestricted hero and filters rails', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = KrzeneController()
      ..activeProfile = const ViewerProfile(
        id: 'kid',
        name: 'Kid',
        isKids: true,
      )
      ..catalog = HomeCatalog(_detail('The Whisper Man', ['Crime', 'Drama']), [
        MediaRail('kids-trending', 'KIDS', 'Popular for kids', [
          _media('Family Adventure', ['Family']),
          _media('Adult Animation', ['Animation', 'Crime']),
        ]),
      ], 'en-US');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: krzeneTheme(),
        home: Scaffold(body: BrowsePage(controller: controller)),
      ),
    );

    expect(find.text('Family Adventure'), findsWidgets);
    expect(find.text('The Whisper Man'), findsNothing);
    expect(find.text('Adult Animation'), findsNothing);
  });

  testWidgets('kids search recommendations exclude unrestricted titles', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = KrzeneController()
      ..activeProfile = const ViewerProfile(
        id: 'kid',
        name: 'Kid',
        isKids: true,
      )
      ..catalog = HomeCatalog(_detail('Adult Hero', ['Drama']), [
        MediaRail('kids-trending', 'KIDS', 'Popular for kids', [
          _media('Family Search Pick', ['Family']),
          _media('Crime Search Pick', ['Crime']),
        ]),
      ], 'en-US');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: krzeneTheme(),
        home: Scaffold(body: SearchPage(controller: controller)),
      ),
    );

    expect(find.text('Family Search Pick'), findsWidgets);
    expect(find.text('Crime Search Pick'), findsNothing);
    expect(find.text('Adult Hero'), findsNothing);
  });

  testWidgets('library uses a two-column vertical grid', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const profile = ViewerProfile(
      id: 'profile-1',
      name: 'Viewer',
      isKids: false,
    );
    final controller = KrzeneController(account: _SignedInAccount())
      ..activeProfile = profile
      ..profiles = const [profile]
      ..library = [
        _media('Library One', ['Drama']),
        _media('Library Two', ['Comedy']),
        _media('Library Three', ['Action']),
      ];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: krzeneTheme(),
        home: Scaffold(body: LibraryPage(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    final first = tester.getTopLeft(find.text('Library One').last);
    final second = tester.getTopLeft(find.text('Library Two').last);
    final third = tester.getTopLeft(find.text('Library Three').last);
    expect((first.dy - second.dy).abs(), lessThan(2));
    expect(second.dx, greaterThan(first.dx));
    expect(third.dy, greaterThan(first.dy + 100));
  });

  testWidgets('leaving kids mode requires first-time parental PIN setup', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final account = _EditableAccount();
    const kids = ViewerProfile(id: 'kid', name: 'Kids', isKids: true);
    const adult = ViewerProfile(id: 'adult', name: 'Parents', isKids: false);
    final controller = KrzeneController(account: account)
      ..profiles = const [kids, adult]
      ..activeProfile = kids;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: krzeneTheme(),
        home: Scaffold(body: KrzeneAccountPage(controller: controller)),
      ),
    );

    await tester.tap(find.text('Parents'));
    await tester.pumpAndSettle();
    expect(find.text('Set a parental PIN'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '2468');
    await tester.enterText(find.byType(TextField).at(1), '2468');
    await tester.tap(find.text('Save PIN'));
    await tester.pumpAndSettle();

    expect(account.parentalPin, '2468');
    expect(controller.activeProfile?.id, adult.id);
  });
}

Media _media(String title, List<String> genres) => Media(
  key: title.toLowerCase().replaceAll(' ', '-'),
  kind: 'movie',
  tmdbId: title.hashCode.abs(),
  title: title,
  overview: '',
  poster: null,
  backdrop: null,
  score: 0,
  genres: genres,
  year: 2026,
);

MediaDetail _detail(String title, List<String> genres) {
  final media = _media(title, genres);
  return MediaDetail(
    key: media.key,
    kind: media.kind,
    tmdbId: media.tmdbId,
    title: media.title,
    overview: media.overview,
    poster: media.poster,
    backdrop: media.backdrop,
    score: media.score,
    genres: media.genres,
    runtime: '',
    tagline: '',
    seasons: const [],
    recommendations: const [],
    year: media.year,
  );
}
