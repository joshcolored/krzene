import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';
import 'models.dart';

class CatalogApi {
  const CatalogApi();

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${AppConfig.apiBaseUrl}$path').replace(queryParameters: query);

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final response = await http.get(uri).timeout(const Duration(seconds: 25));
    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().contains('application/json')) {
      if (response.statusCode == 404 && uri.path == '/api/catalog') {
        throw Exception(
          'The catalog API is not available on ${uri.host}. '
          'Run the Next.js app locally or deploy the new /api/catalog route.',
        );
      }
      throw Exception(
        'The Krzene API returned an unexpected response '
        '(${response.statusCode}).',
      );
    }
    Object? payload;
    try {
      payload = jsonDecode(response.body);
    } on FormatException {
      throw Exception('The Krzene API returned invalid data.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        payload is Map
            ? payload['error'] ?? 'Request failed.'
            : 'Request failed.',
      );
    }
    if (payload is! Map) {
      throw Exception('The Krzene API returned invalid data.');
    }
    return Map<String, dynamic>.from(payload);
  }

  Future<HomeCatalog> home(String language) async {
    try {
      return HomeCatalog.fromJson(
        await _get(_uri('/api/catalog', {'lang': language})),
      );
    } catch (_) {
      try {
        return await _fallbackHome(language);
      } catch (_) {
        rethrow;
      }
    }
  }

  Future<HomeCatalog> _fallbackHome(String language) async {
    const seeds = ['Dune', 'Spider-Man', 'One Piece'];
    final groups = await Future.wait(
      seeds.map((query) => search(query, language)),
    );
    final seen = <String>{};
    final recommendations = <Media>[];
    for (final item in groups.expand((items) => items)) {
      if (item.key.isNotEmpty && seen.add(item.key)) recommendations.add(item);
    }
    if (recommendations.isEmpty) {
      throw Exception('No recommendations are available right now.');
    }

    final heroMedia = recommendations.firstWhere(
      (item) => item.backdrop != null,
      orElse: () => recommendations.first,
    );
    final hero = _asDetail(
      heroMedia,
      recommendations: recommendations
          .where((item) => item.key != heroMedia.key)
          .take(12)
          .toList(),
    );
    final movies = recommendations.where((item) => !item.isSeries).toList();
    final shows = recommendations.where((item) => item.isSeries).toList();
    return HomeCatalog(hero, [
      MediaRail(
        'recommended',
        'PICKS FOR YOU',
        'Recommended to watch',
        recommendations.take(20).toList(),
      ),
      if (movies.isNotEmpty)
        MediaRail('recommended-movies', 'MOVIES', 'Movies to discover', movies),
      if (shows.isNotEmpty)
        MediaRail('recommended-shows', 'SERIES', 'Shows to start', shows),
    ], language);
  }

  Future<List<Media>> search(
    String query,
    String language, {
    bool kidsOnly = false,
  }) async {
    final payload = await _get(
      _uri('/api/search', {
        'q': query,
        'lang': language,
        if (kidsOnly) 'kids': '1',
      }),
    );
    final results = (payload['results'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Media.fromJson)
        .toList();
    return kidsOnly
        ? results.where((media) => media.isKidsSafe).toList()
        : results;
  }

  Future<MediaDetail> detail(Media media, String language) async {
    try {
      final payload = await _get(
        _uri('/api/title/${media.kind}/${media.tmdbId}', {'lang': language}),
      );
      return MediaDetail.fromJson(payload['detail'] as Map<String, dynamic>);
    } catch (_) {
      final recommendations = await search(media.title, language);
      return _asDetail(
        media,
        recommendations: recommendations
            .where((item) => item.key != media.key)
            .take(12)
            .toList(),
      );
    }
  }

  Future<List<EpisodeInfo>> seasonEpisodes(
    int tmdbId,
    int season,
    String language,
  ) async {
    final payload = await _get(
      _uri('/api/title/tv/$tmdbId/season/$season', {'lang': language}),
    );
    return (payload['episodes'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(EpisodeInfo.fromJson)
        .toList();
  }

  MediaDetail _asDetail(
    Media media, {
    List<Media> recommendations = const [],
  }) => MediaDetail(
    key: media.key,
    kind: media.kind,
    tmdbId: media.tmdbId,
    title: media.title,
    overview: media.overview,
    poster: media.poster,
    backdrop: media.backdrop,
    score: media.score,
    genres: media.genres,
    year: media.year,
    runtime: '',
    tagline: '',
    seasons: const [],
    recommendations: recommendations,
  );
}

class EmailSignUpResult {
  const EmailSignUpResult({
    required this.email,
    required this.confirmationRequired,
  });

  final String email;
  final bool confirmationRequired;
}

class AccountRepository {
  static const _staySignedInKey = 'stay_signed_in_v1';

  SupabaseClient? get _client =>
      AppConfig.supabaseReady ? Supabase.instance.client : null;
  User? get user => _client?.auth.currentUser;

  bool get usesEmailPassword =>
      user?.appMetadata['provider'] == 'email' ||
      (user?.identities ?? const <UserIdentity>[]).any(
        (identity) => identity.provider == 'email',
      );

  Stream<AuthState> get authChanges =>
      _client?.auth.onAuthStateChange ?? const Stream<AuthState>.empty();

  Future<bool> staySignedIn() async =>
      (await SharedPreferences.getInstance()).getBool(_staySignedInKey) ?? true;

  Future<void> setStaySignedIn(bool value) async {
    await (await SharedPreferences.getInstance()).setBool(
      _staySignedInKey,
      value,
    );
  }

  Future<void> prepareSession({bool passwordRecovery = false}) async {
    final client = _client;
    if (client == null || passwordRecovery || await staySignedIn()) return;
    if (client.auth.currentSession != null) {
      await client.auth.signOut(scope: SignOutScope.local);
    }
  }

  Future<EmailSignUpResult> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    final client = _client;
    if (client == null) throw Exception('Supabase is not configured.');
    final normalizedName = name.trim();
    final normalizedEmail = email.trim().toLowerCase();
    final response = await client.auth.signUp(
      email: normalizedEmail,
      password: password,
      emailRedirectTo: 'site.krzene.app://login-callback',
      data: {'full_name': normalizedName, 'name': normalizedName},
    );
    return EmailSignUpResult(
      email: normalizedEmail,
      confirmationRequired: response.session == null,
    );
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final client = _client;
    if (client == null) throw Exception('Supabase is not configured.');
    await client.auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
  }

  Future<void> requestPasswordReset(String email) async {
    final client = _client;
    if (client == null) throw Exception('Supabase is not configured.');
    await client.auth.resetPasswordForEmail(
      email.trim().toLowerCase(),
      redirectTo: 'site.krzene.app://reset-password',
    );
  }

  Future<void> changePassword({
    required String newPassword,
    String? currentPassword,
  }) async {
    final client = _client;
    if (client == null) throw Exception('Supabase is not configured.');
    await client.auth.updateUser(
      UserAttributes(
        password: newPassword,
        currentPassword: currentPassword?.isEmpty == true
            ? null
            : currentPassword,
      ),
    );
  }

  Future<void> signInWithGoogle() async {
    final client = _client;
    if (client == null) throw Exception('Supabase is not configured.');

    final response = await client.auth.getOAuthSignInUrl(
      provider: OAuthProvider.google,
      redirectTo: 'site.krzene.app://login-callback',
      queryParams: const {'prompt': 'select_account'},
    );
    final launched = await launchUrl(
      Uri.parse(response.url),
      mode: LaunchMode.inAppBrowserView,
    );
    if (!launched) {
      throw Exception('Krzene could not open Google sign-in.');
    }
  }

  Future<bool> signInWithApple() async {
    final client = _client;
    if (client == null) throw Exception('Supabase is not configured.');

    final rawNonce = client.auth.generateRawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    late final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
    } on SignInWithAppleAuthorizationException catch (exception) {
      if (exception.code == AuthorizationErrorCode.canceled) return false;
      rethrow;
    }

    final identityToken = credential.identityToken;
    if (identityToken == null) {
      throw const AuthException(
        'Apple did not return an identity token. Please try again.',
      );
    }

    await client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: identityToken,
      nonce: rawNonce,
    );

    // Apple only returns the person's name on the first authorization. Save it
    // immediately so it remains available on later launches and sign-ins.
    final givenName = credential.givenName?.trim();
    final familyName = credential.familyName?.trim();
    final fullName = [
      if (givenName != null && givenName.isNotEmpty) givenName,
      if (familyName != null && familyName.isNotEmpty) familyName,
    ].join(' ');
    if (fullName.isNotEmpty) {
      await client.auth.updateUser(
        UserAttributes(
          data: {
            'full_name': fullName,
            if (givenName != null && givenName.isNotEmpty)
              'given_name': givenName,
            if (familyName != null && familyName.isNotEmpty)
              'family_name': familyName,
          },
        ),
      );
    }

    return true;
  }

  Future<void> signOut() async => _client?.auth.signOut();

  String get _parentalPinKey {
    final userId = user?.id;
    if (userId == null) throw Exception('Sign in to manage the parental PIN.');
    return 'parental_pin_v1_$userId';
  }

  Future<bool> hasParentalPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_parentalPinKey) != null;
  }

  Future<void> setParentalPin(String pin) async {
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw Exception('Use exactly four numbers for the parental PIN.');
    }
    final digest = sha256.convert(utf8.encode('${user!.id}:$pin')).toString();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_parentalPinKey, digest);
  }

  Future<bool> verifyParentalPin(String pin) async {
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) return false;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_parentalPinKey);
    if (stored == null) return false;
    final digest = sha256.convert(utf8.encode('${user!.id}:$pin')).toString();
    return stored == digest;
  }

  Future<void> deleteAccount() async {
    final client = _client;
    if (client == null) throw Exception('Supabase is not configured.');

    final deleted = await client.rpc<bool>('delete_own_account');
    if (!deleted) {
      throw Exception(
        'Krzene could not delete your account. Please try again.',
      );
    }

    await _clearLocalWatchProgress();

    // The account no longer exists on the server. Clear the cached device
    // session without making a second request with the now-invalid token.
    await client.auth.signOut(scope: SignOutScope.local);
  }

  Future<List<ViewerProfile>> profiles() async {
    var rows = await _client!
        .from('viewer_profiles')
        .select()
        .order('created_at');
    if ((rows as List).isEmpty && user != null) {
      final metadata = user!.userMetadata ?? const <String, dynamic>{};
      final suggestedName =
          [
                metadata['full_name'],
                metadata['name'],
                metadata['user_name'],
                user!.email?.split('@').first,
                'Viewer',
              ]
              .whereType<String>()
              .map((value) => value.trim())
              .firstWhere((value) => value.isNotEmpty, orElse: () => 'Viewer');
      final avatar = metadata['avatar_url'] ?? metadata['picture'];
      await _client!.from('viewer_profiles').insert({
        'owner_id': user!.id,
        'name': suggestedName.substring(0, suggestedName.length.clamp(0, 32)),
        if (avatar is String && avatar.trim().isNotEmpty)
          'avatar_url': avatar.trim(),
      });
      rows = await _client!
          .from('viewer_profiles')
          .select()
          .order('created_at');
    }
    return (rows as List)
        .map((row) => ViewerProfile.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<ViewerProfile> createProfile(String name, {bool kids = false}) async {
    final row = await _client!
        .from('viewer_profiles')
        .insert({'owner_id': user!.id, 'name': name, 'is_kids': kids})
        .select()
        .single();
    return ViewerProfile.fromJson(Map<String, dynamic>.from(row));
  }

  Future<ViewerProfile> updateProfileName(
    ViewerProfile profile,
    String name,
  ) async {
    final row = await _client!
        .from('viewer_profiles')
        .update({
          'name': name,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', profile.id)
        .eq('owner_id', user!.id)
        .select()
        .single();
    return ViewerProfile.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> deleteProfile(String profileId) async {
    await _client!
        .from('viewer_profiles')
        .delete()
        .eq('id', profileId)
        .eq('owner_id', user!.id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_watchProgressCacheKey(profileId));
  }

  Future<List<Media>> library(String profileId) async {
    final rows = await _client!
        .from('library_items')
        .select('media')
        .eq('profile_id', profileId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map(
          (row) =>
              Media.fromJson(Map<String, dynamic>.from(row['media'] as Map)),
        )
        .toList();
  }

  Future<List<ContinueItem>> continueWatching(String profileId) async {
    final localItems = await _readLocalWatchProgress(profileId);
    try {
      final rows = await _client!
          .from('watch_progress')
          .select('media,position,duration,season,episode,updated_at')
          .eq('profile_id', profileId)
          .order('updated_at', ascending: false)
          .limit(20);
      final remoteItems = (rows as List)
          .map((row) => ContinueItem.fromJson(Map<String, dynamic>.from(row)))
          .toList();
      final merged = _mergeWatchProgress(localItems, remoteItems);
      await _writeLocalWatchProgress(profileId, merged);
      return merged;
    } catch (_) {
      return localItems;
    }
  }

  Future<void> setLibrary({
    required ViewerProfile profile,
    required Media media,
    required bool saved,
  }) async {
    if (saved) {
      await _client!
          .from('library_items')
          .delete()
          .eq('profile_id', profile.id)
          .eq('media_key', media.key);
    } else {
      await _client!.from('library_items').upsert({
        'owner_id': user!.id,
        'profile_id': profile.id,
        'media_key': media.key,
        'media': media.toJson(),
      }, onConflict: 'profile_id,media_key');
    }
  }

  Future<void> saveWatchProgress({
    required ViewerProfile profile,
    required Media media,
    required double position,
    required double duration,
    required bool completed,
    int? season,
    int? episode,
  }) async {
    final client = _client;
    final currentUser = user;
    if (client == null || currentUser == null) return;

    final updatedAt = DateTime.now().toUtc();
    await _saveLocalWatchProgress(
      profile.id,
      ContinueItem(
        media: media,
        position: position,
        duration: duration,
        season: season,
        episode: episode,
        updatedAt: updatedAt,
      ),
      completed: completed,
    );

    if (completed) {
      await client
          .from('watch_progress')
          .delete()
          .eq('profile_id', profile.id)
          .eq('media_key', media.key);
      return;
    }

    await client.from('watch_progress').upsert({
      'owner_id': currentUser.id,
      'profile_id': profile.id,
      'media_key': media.key,
      'media': media.toJson(),
      'position': position,
      'duration': duration,
      'season': season,
      'episode': episode,
      'updated_at': updatedAt.toIso8601String(),
    }, onConflict: 'profile_id,media_key');
  }

  String _watchProgressCacheKey(String profileId) {
    final userId = user?.id;
    if (userId == null) throw Exception('Sign in to access watch progress.');
    return 'watch_progress_v2_${userId}_$profileId';
  }

  Future<List<ContinueItem>> _readLocalWatchProgress(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getStringList(_watchProgressCacheKey(profileId));
    if (encoded == null) return [];
    final items = <ContinueItem>[];
    for (final value in encoded) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          items.add(ContinueItem.fromJson(Map<String, dynamic>.from(decoded)));
        }
      } catch (_) {
        // Ignore a damaged cache entry; the remote copy can replace it.
      }
    }
    return items;
  }

  Future<void> _writeLocalWatchProgress(
    String profileId,
    List<ContinueItem> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _watchProgressCacheKey(profileId),
      items.take(20).map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  Future<void> _saveLocalWatchProgress(
    String profileId,
    ContinueItem item, {
    required bool completed,
  }) async {
    final current = await _readLocalWatchProgress(profileId);
    final remaining = current
        .where((entry) => entry.media.key != item.media.key)
        .toList();
    await _writeLocalWatchProgress(
      profileId,
      completed ? remaining : [item, ...remaining],
    );
  }

  List<ContinueItem> _mergeWatchProgress(
    List<ContinueItem> local,
    List<ContinueItem> remote,
  ) {
    final byMedia = <String, ContinueItem>{};
    for (final item in [...remote, ...local]) {
      final previous = byMedia[item.media.key];
      final previousDate = previous?.updatedAt;
      final itemDate = item.updatedAt;
      if (previous == null ||
          (itemDate != null &&
              (previousDate == null || itemDate.isAfter(previousDate)))) {
        byMedia[item.media.key] = item;
      }
    }
    final merged = byMedia.values.toList()
      ..sort(
        (a, b) => (b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );
    return merged.take(20).toList();
  }

  Future<void> _clearLocalWatchProgress() async {
    final userId = user?.id;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'watch_progress_v2_${userId}_';
    for (final key in prefs.getKeys().where((key) => key.startsWith(prefix))) {
      await prefs.remove(key);
    }
  }
}
