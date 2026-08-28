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
  Future<List<Media>> library(String profileId) async => [];

  @override
  Future<List<ContinueItem>> continueWatching(String profileId) async => [];
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
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('Terms'), findsOneWidget);
  });

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
}
