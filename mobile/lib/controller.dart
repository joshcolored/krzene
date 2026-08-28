import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'models.dart';
import 'services.dart';

class KrzeneController extends ChangeNotifier {
  KrzeneController({
    this.catalogApi = const CatalogApi(),
    AccountRepository? account,
  }) : account = account ?? AccountRepository();

  final CatalogApi catalogApi;
  final AccountRepository account;
  StreamSubscription? _authSubscription;

  HomeCatalog? catalog;
  String language = 'en-US';
  bool initialized = false;
  bool loading = true;
  String? error;
  List<ViewerProfile> profiles = [];
  ViewerProfile? activeProfile;
  List<Media> library = [];
  List<ContinueItem> continueWatching = [];

  bool get signedIn => account.user != null;
  Set<String> get libraryKeys => library.map((item) => item.key).toSet();

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    language = prefs.getString('language') ?? 'en-US';
    _authSubscription = account.authChanges.listen((_) => refreshAccount());
    await Future.wait([loadCatalog(), refreshAccount()]);
    initialized = true;
    notifyListeners();
  }

  Future<void> loadCatalog() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      catalog = await catalogApi.home(language);
    } catch (exception) {
      error = exception.toString().replaceFirst('Exception: ', '');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> changeLanguage(String value) async {
    if (language == value) return;
    language = value;
    (await SharedPreferences.getInstance()).setString('language', value);
    await loadCatalog();
  }

  Future<void> refreshAccount() async {
    if (!AppConfig.hasSupabase || !signedIn) {
      profiles = [];
      activeProfile = null;
      library = [];
      continueWatching = [];
      notifyListeners();
      return;
    }
    try {
      profiles = await account.profiles();
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString('active_profile');
      activeProfile =
          profiles.where((profile) => profile.id == savedId).firstOrNull ??
          profiles.firstOrNull;
      if (activeProfile != null) {
        await _loadProfileData(activeProfile!);
      }
    } catch (exception) {
      error = exception.toString().replaceFirst('Exception: ', '');
    }
    notifyListeners();
  }

  Future<void> selectProfile(ViewerProfile profile) async {
    activeProfile = profile;
    (await SharedPreferences.getInstance()).setString(
      'active_profile',
      profile.id,
    );
    await _loadProfileData(profile);
    notifyListeners();
  }

  Future<void> _loadProfileData(ViewerProfile profile) async {
    final values = await Future.wait([
      account.library(profile.id),
      account.continueWatching(profile.id),
    ]);
    library = values[0] as List<Media>;
    continueWatching = values[1] as List<ContinueItem>;
  }

  Future<void> toggleLibrary(Media media) async {
    final profile = activeProfile;
    if (profile == null) return;
    final saved = library.any((item) => item.key == media.key);
    await account.setLibrary(profile: profile, media: media, saved: saved);
    library = saved
        ? library.where((item) => item.key != media.key).toList()
        : [media, ...library];
    notifyListeners();
  }

  Future<void> createProfile(String name, {bool kids = false}) async {
    final profile = await account.createProfile(name, kids: kids);
    profiles = [...profiles, profile];
    await selectProfile(profile);
  }

  Future<void> renameProfile(ViewerProfile profile, String name) async {
    final updated = await account.updateProfileName(profile, name);
    profiles = [
      for (final item in profiles)
        if (item.id == updated.id) updated else item,
    ];
    if (activeProfile?.id == updated.id) activeProfile = updated;
    notifyListeners();
  }

  Future<void> deleteProfile(ViewerProfile profile) async {
    await account.deleteProfile(profile.id);
    profiles = profiles.where((item) => item.id != profile.id).toList();
    if (activeProfile?.id == profile.id) {
      activeProfile = profiles.firstOrNull;
      final prefs = await SharedPreferences.getInstance();
      if (activeProfile == null) {
        await prefs.remove('active_profile');
        library = [];
        continueWatching = [];
      } else {
        await prefs.setString('active_profile', activeProfile!.id);
        await _loadProfileData(activeProfile!);
      }
    }
    notifyListeners();
  }

  Future<void> saveWatchProgress(
    Media media,
    double position,
    double duration, {
    int? season,
    int? episode,
  }) async {
    final profile = activeProfile;
    if (profile == null || position < 5) return;

    final completed = duration > 0 && position / duration >= .95;
    if (completed) {
      continueWatching = continueWatching
          .where((item) => item.media.key != media.key)
          .toList();
    } else {
      final next = ContinueItem(
        media: media,
        position: position,
        duration: duration,
        season: season,
        episode: episode,
      );
      continueWatching = [
        next,
        ...continueWatching.where((item) => item.media.key != media.key),
      ].take(20).toList();
    }
    notifyListeners();

    try {
      await account.saveWatchProgress(
        profile: profile,
        media: media,
        position: position,
        duration: duration,
        season: season,
        episode: episode,
        completed: completed,
      );
    } catch (exception) {
      error = exception.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

extension FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
