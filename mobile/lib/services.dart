import 'dart:convert';

import 'package:http/http.dart' as http;
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

  Future<List<Media>> search(String query, String language) async {
    final payload = await _get(
      _uri('/api/search', {'q': query, 'lang': language}),
    );
    return (payload['results'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Media.fromJson)
        .toList();
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

class AccountRepository {
  SupabaseClient? get _client =>
      AppConfig.supabaseReady ? Supabase.instance.client : null;
  User? get user => _client?.auth.currentUser;

  Stream<AuthState> get authChanges =>
      _client?.auth.onAuthStateChange ?? const Stream<AuthState>.empty();

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

  Future<void> signOut() async => _client?.auth.signOut();

  Future<List<ViewerProfile>> profiles() async {
    final rows = await _client!
        .from('viewer_profiles')
        .select()
        .order('created_at');
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
    final rows = await _client!
        .from('watch_progress')
        .select('media,position,duration,season,episode')
        .eq('profile_id', profileId)
        .order('updated_at', ascending: false)
        .limit(20);
    return (rows as List)
        .map((row) => ContinueItem.fromJson(Map<String, dynamic>.from(row)))
        .toList();
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
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'profile_id,media_key');
  }
}
