import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  StreamSubscription<Uri>? _linkSubscription;

  HomeCatalog? catalog;
  String language = 'en-US';
  bool initialized = false;
  bool loading = true;
  String? error;
  List<ViewerProfile> profiles = [];
  ViewerProfile? activeProfile;
  List<Media> library = [];
  List<ContinueItem> continueWatching = [];
  final Set<String> _libraryMutations = <String>{};
  bool _adultProfilesUnlocked = false;
  bool passwordRecoveryMode = false;

  bool get signedIn => account.user != null;
  bool get kidsMode => activeProfile?.isKids == true;
  bool get hasKidsProfile => profiles.any((profile) => profile.isKids);
  Set<String> get libraryKeys => library.map((item) => item.key).toSet();
  bool isLibraryUpdating(String mediaKey) =>
      _libraryMutations.contains(mediaKey);

  bool requiresParentalUnlock(ViewerProfile profile) =>
      !profile.isKids && hasKidsProfile && !_adultProfilesUnlocked;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    language = prefs.getString('language') ?? 'en-US';
    final appLinks = AppLinks();
    final initialLink = await appLinks.getInitialLink();
    passwordRecoveryMode = _isPasswordRecoveryLink(initialLink);
    await account.prepareSession(passwordRecovery: passwordRecoveryMode);
    _authSubscription = account.authChanges.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) {
        passwordRecoveryMode = true;
      }
      unawaited(refreshAccount());
    });
    _linkSubscription = appLinks.uriLinkStream.listen((uri) {
      if (_isPasswordRecoveryLink(uri)) {
        passwordRecoveryMode = true;
        notifyListeners();
      }
    });
    await Future.wait([loadCatalog(), refreshAccount()]);
    initialized = true;
    notifyListeners();
  }

  bool _isPasswordRecoveryLink(Uri? uri) =>
      uri?.scheme == 'site.krzene.app' && uri?.host == 'reset-password';

  void finishPasswordRecovery() {
    passwordRecoveryMode = false;
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
      _adultProfilesUnlocked = false;
      notifyListeners();
      return;
    }
    try {
      profiles = await account.profiles();
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString('active_profile');
      final saved = profiles
          .where((profile) => profile.id == savedId)
          .firstOrNull;
      final kidsProfile = profiles
          .where((profile) => profile.isKids)
          .firstOrNull;
      // A cold launch never restores an unlocked standard profile when a Kids
      // profile exists. This prevents closing and reopening the app from
      // bypassing the parental gate.
      activeProfile = saved != null && (!hasKidsProfile || saved.isKids)
          ? saved
          : kidsProfile ?? saved ?? profiles.firstOrNull;
      if (activeProfile != null) {
        if (activeProfile!.isKids) {
          await prefs.setString('active_profile', activeProfile!.id);
        }
        await _loadProfileData(activeProfile!);
      }
    } catch (exception) {
      error = exception.toString().replaceFirst('Exception: ', '');
    }
    notifyListeners();
  }

  Future<void> selectProfile(
    ViewerProfile profile, {
    bool parentalUnlock = false,
  }) async {
    if (requiresParentalUnlock(profile) && !parentalUnlock) {
      throw Exception('Enter the parental PIN to open a standard profile.');
    }
    if (profile.isKids) {
      _adultProfilesUnlocked = false;
    } else if (parentalUnlock || !hasKidsProfile) {
      _adultProfilesUnlocked = true;
    }
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
    final nextLibrary = values[0] as List<Media>;
    final nextContinueWatching = values[1] as List<ContinueItem>;
    library = profile.isKids
        ? nextLibrary.where((item) => item.isKidsSafe).toList()
        : nextLibrary;
    continueWatching = profile.isKids
        ? nextContinueWatching.where((item) => item.media.isKidsSafe).toList()
        : nextContinueWatching;
  }

  Future<void> toggleLibrary(Media media) async {
    final profile = activeProfile;
    if (profile == null) return;
    if (_libraryMutations.contains(media.key)) return;
    if (profile.isKids && !media.isKidsSafe) {
      throw Exception('This title is not available in a Kids profile.');
    }
    final saved = library.any((item) => item.key == media.key);
    final previousLibrary = library;
    _libraryMutations.add(media.key);
    library = saved
        ? library.where((item) => item.key != media.key).toList()
        : [media, ...library];
    notifyListeners();
    try {
      await account.setLibrary(profile: profile, media: media, saved: saved);
    } catch (_) {
      library = previousLibrary;
      rethrow;
    } finally {
      _libraryMutations.remove(media.key);
      notifyListeners();
    }
  }

  Future<void> createProfile(String name, {bool kids = false}) async {
    final profile = await account.createProfile(name, kids: kids);
    profiles = [...profiles, profile];
    if (kids || !hasKidsProfile || activeProfile?.isKids != true) {
      await selectProfile(profile);
    } else {
      notifyListeners();
    }
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
      activeProfile =
          profiles.where((item) => item.isKids).firstOrNull ??
          profiles.firstOrNull;
      _adultProfilesUnlocked = activeProfile != null && !hasKidsProfile;
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
    bool force = false,
  }) async {
    final profile = activeProfile;
    if (profile == null || (!force && position < 5)) return;
    if (profile.isKids && !media.isKidsSafe) return;

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
        updatedAt: DateTime.now().toUtc(),
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
    _linkSubscription?.cancel();
    super.dispose();
  }
}

extension FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
