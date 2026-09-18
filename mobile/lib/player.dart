import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'controller.dart';
import 'design.dart';
import 'models.dart';
import 'playback.dart';
import 'player_scripts.dart';
import 'subtitles.dart';

class WatchScreen extends StatefulWidget {
  const WatchScreen({
    super.key,
    required this.media,
    required this.controller,
    this.resume,
    this.playerPreview,
  });
  final Media media;
  final KrzeneController controller;
  final ContinueItem? resume;
  final Widget? playerPreview;

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> with WidgetsBindingObserver {
  late final WebViewController web;
  late Future<MediaDetail> detailFuture;
  late Future<List<EpisodeInfo>> episodesFuture;
  static const source = PlaybackSource.cineSrc;
  int loadGeneration = 0;
  int subtitleLoadGeneration = 0;
  bool loadingSource = true;
  bool playerReady = false;
  bool controlsVisible = true;
  bool buffering = false;
  bool muted = false;
  bool scrubbing = false;
  double scrubPosition = 0;
  double? pendingSeekTarget;
  DateTime? pendingSeekStartedAt;
  double playbackRate = 1;
  double volumeBoost = 1;
  String? qualityPreference;
  SubtitleTrack? subtitleTrack;
  bool subtitleEnabled = true;
  bool findingSubtitle = false;
  double subtitleOffset = 0;
  double subtitleSpeed = 1;
  double subtitleFontSize = 20;
  double subtitleBackground = .68;
  Color subtitleBackgroundColor = Colors.black;
  Color subtitleColor = Colors.white;
  final subtitleService = const SubtitleService();
  int season = 1;
  int episode = 1;
  Timer? progressTimer;
  Timer? controlsTimer;
  Timer? seekTimeoutTimer;
  double position = 0;
  double duration = 0;
  int savedProgressBucket = 0;
  bool playerPageReady = false;
  bool appActive = true;
  bool? playerReportedPlaying;
  DateTime? lastProgressTick;
  DateTime? lastExactProgressAt;
  late bool immersive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    season = widget.resume?.season ?? 1;
    episode = widget.resume?.episode ?? 1;
    position = widget.resume?.position ?? 0;
    duration = widget.resume?.duration ?? 0;
    if (widget.playerPreview != null) {
      loadingSource = false;
      playerReady = true;
    }
    immersive =
        widget.playerPreview == null &&
        defaultTargetPlatform == TargetPlatform.android;
    savedProgressBucket = (position / 10).floor();
    lastProgressTick = DateTime.now();
    progressTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _tickProgress(),
    );
    detailFuture = widget.controller.catalogApi.detail(
      widget.media,
      widget.controller.language,
    );
    episodesFuture = widget.media.isSeries
        ? widget.controller.catalogApi.seasonEpisodes(
            widget.media.tmdbId,
            season,
            widget.controller.language,
          )
        : Future.value(const <EpisodeInfo>[]);
    if (widget.playerPreview == null) {
      late final PlatformWebViewControllerCreationParams params;
      if (WebViewPlatform.instance is WebKitWebViewPlatform) {
        params = WebKitWebViewControllerCreationParams(
          allowsInlineMediaPlayback: true,
          mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
        );
      } else {
        params = const PlatformWebViewControllerCreationParams();
      }
      web = WebViewController.fromPlatformCreationParams(params)
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.black)
        ..addJavaScriptChannel(
          'KrzeneBridge',
          onMessageReceived: (message) => _handleBridgeMessage(message.message),
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) {
              playerPageReady = false;
              playerReady = false;
              lastProgressTick = DateTime.now();
            },
            onPageFinished: (_) {
              playerPageReady = true;
              lastProgressTick = DateTime.now();
              _installPlaybackBridge();
            },
            onNavigationRequest: _handleNavigation,
          ),
        );
      if (web.platform is AndroidWebViewController) {
        final android = web.platform as AndroidWebViewController;
        unawaited(android.setMediaPlaybackRequiresUserGesture(false));
      }
      web.loadRequest(Uri.parse(_embedUrl()));
      unawaited(_restoreLocalSubtitle());
    }
    if (immersive) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _enterImmersive());
    }
  }

  Future<void> _installPlaybackBridge() async {
    try {
      await web.runJavaScript(krzenePlayerScript);
    } catch (_) {
      // The document can be between navigations; onPageFinished retries.
    }
  }

  NavigationDecision _handleNavigation(NavigationRequest request) {
    final target = Uri.tryParse(request.url);
    if (target == null || target.scheme == 'about') {
      return NavigationDecision.navigate;
    }
    if (target.scheme != 'http' && target.scheme != 'https') {
      return NavigationDecision.prevent;
    }
    const blockedAdHosts = [
      'doubleclick.net',
      'googlesyndication.com',
      'popads.net',
      'popcash.net',
      'onclicka.com',
      'propellerads.com',
      'adsterra.com',
    ];
    final isAdHost = blockedAdHosts.any(
      (host) => target.host == host || target.host.endsWith('.$host'),
    );
    if (isAdHost) return NavigationDecision.prevent;
    if (!request.isMainFrame) return NavigationDecision.navigate;
    if (target.host != Uri.parse(source.host).host) {
      return NavigationDecision.prevent;
    }

    // Once the provider has loaded, keep ad clicks from replacing the player
    // in the main frame. Subframe navigation remains available to the player.
    if (playerPageReady) {
      final expected = Uri.parse(_embedUrl());
      final staysOnPlayer =
          target.host == expected.host && target.path == expected.path;
      if (!staysOnPlayer) return NavigationDecision.prevent;
    }

    return NavigationDecision.navigate;
  }

  Future<void> _enterImmersive() async {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _showFullscreen() async {
    if (mounted) setState(() => immersive = true);
    await _enterImmersive();
  }

  Future<void> _restoreSystemUi() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    await SystemChrome.setPreferredOrientations(const []);
  }

  Future<void> _showDetails() async {
    if (mounted) setState(() => immersive = false);
    await _restoreSystemUi();
  }

  void _handleBridgeMessage(String raw) {
    if (!playerPageReady) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final type = decoded['type']?.toString();
      if (type == 'cinesrc:error') {
        // A video error may be recoverable by CineSrc. It does not prove the
        // title is unavailable and must not remove it from the catalog.
        if (mounted) {
          setState(() {
            buffering = true;
          });
        }
        return;
      }
      if (type?.startsWith('cinesrc:') == true) {
        _handleCineSrcEvent(type!, decoded);
        return;
      }
      final data = decoded['data'];
      if (data is! Map) return;
      if (type != 'PLAYER_EVENT' && type != 'KRZENE_PROGRESS') return;
      final nextPosition = _seconds(
        type == 'PLAYER_EVENT' ? data['player_progress'] : data['position'],
      );
      final nextDuration = _seconds(
        type == 'PLAYER_EVENT' ? data['player_duration'] : data['duration'],
      );
      if (nextPosition == null) return;

      final acceptedPosition = _acceptPlayerPosition(
        nextPosition,
        seekFinished: type == 'KRZENE_PROGRESS' && data['phase'] == 'seeked',
      );
      if (acceptedPosition) position = nextPosition;
      if (nextDuration != null && nextDuration > 0) duration = nextDuration;
      lastExactProgressAt = DateTime.now();
      lastProgressTick = lastExactProgressAt;
      if (type == 'PLAYER_EVENT') {
        final status = data['player_status']?.toString().toLowerCase();
        if (status == 'playing') playerReportedPlaying = true;
        if (status == 'paused' || status == 'completed') {
          playerReportedPlaying = false;
        }
      } else if (type == 'KRZENE_PROGRESS') {
        playerReportedPlaying = data['paused'] == false;
        final readyState = (data['readyState'] as num?)?.toInt() ?? 0;
        playerReady = readyState > 0;
        loadingSource = readyState < 2;
        buffering =
            pendingSeekTarget != null ||
            data['buffering'] == true ||
            data['phase'] == 'error';
        muted = data['muted'] == true;
        final rate = _seconds(data['playbackRate']);
        if (rate != null && rate > 0) playbackRate = rate;
        if (data['phase'] == 'playing') _scheduleControlsHide();
        if (data['phase'] == 'autoplayblocked') {
          loadingSource = false;
          buffering = false;
          controlsVisible = true;
        }
        if (mounted) setState(() {});
      }

      if (type == 'PLAYER_EVENT' &&
          mounted &&
          (loadingSource ||
              (buffering && acceptedPosition && pendingSeekTarget == null))) {
        setState(() {
          loadingSource = false;
          buffering = false;
        });
      }

      _persistIfNeeded();
    } catch (_) {
      // Provider messages are untrusted and can use unrelated payload formats.
    }
  }

  void _handleCineSrcEvent(String type, Map<dynamic, dynamic> event) {
    final nextPosition = _seconds(event['currentTime']);
    final nextDuration = _seconds(event['duration']);
    final acceptedPosition =
        nextPosition == null ||
        _acceptPlayerPosition(
          nextPosition,
          seekFinished: type == 'cinesrc:seeked',
        );
    if (nextPosition != null && acceptedPosition) position = nextPosition;
    if (nextDuration != null && nextDuration > 0) duration = nextDuration;
    if (nextPosition != null || nextDuration != null) {
      lastExactProgressAt = DateTime.now();
      lastProgressTick = lastExactProgressAt;
    }

    var changed = false;
    switch (type) {
      case 'cinesrc:ready':
      case 'cinesrc:loadedmetadata':
        playerReady = true;
        loadingSource = false;
        buffering = false;
        changed = true;
        if (playbackRate != 1) _sendCommand('setPlaybackRate', [playbackRate]);
        if (muted) _sendCommand('setMuted', [true]);
        if (volumeBoost != 1) unawaited(_applyVolumeBoost(volumeBoost));
      case 'cinesrc:play':
        playerReportedPlaying = true;
        loadingSource = false;
        buffering = false;
        changed = true;
        _scheduleControlsHide();
      case 'cinesrc:pause':
      case 'cinesrc:ended':
        playerReportedPlaying = false;
        buffering = false;
        controlsVisible = true;
        controlsTimer?.cancel();
        changed = true;
      case 'cinesrc:timeupdate':
        if (pendingSeekTarget == null) buffering = false;
        changed = true;
      case 'cinesrc:seeked':
        _clearPendingSeek();
        buffering = false;
        changed = true;
      case 'cinesrc:seeking':
        buffering = true;
        changed = true;
      case 'cinesrc:volumechange':
        muted = event['muted'] == true;
        changed = true;
      case 'cinesrc:ratechange':
        final rate = _seconds(event['playbackRate']);
        if (rate != null && rate >= .25 && rate <= 2) playbackRate = rate;
        changed = true;
      case 'cinesrc:response':
        final command = event['command']?.toString();
        if (command == 'getPaused' && event['result'] is bool) {
          playerReportedPlaying = event['result'] != true;
          changed = true;
        }
      case 'cinesrc:nextepisode':
        final nextSeason = (event['season'] as num?)?.toInt();
        final nextEpisode = (event['episode'] as num?)?.toInt();
        if (nextSeason != null &&
            nextEpisode != null &&
            nextSeason > 0 &&
            nextEpisode > 0) {
          season = nextSeason;
          episode = nextEpisode;
          position = 0;
          duration = 0;
          changed = true;
        }
    }
    if (changed && mounted) setState(() {});
    _persistIfNeeded();
  }

  Future<void> _sendCommand(
    String command, [
    List<Object?> args = const [],
  ]) async {
    if (widget.playerPreview != null || !playerPageReady) return;
    final message = jsonEncode({
      'type': 'cinesrc:command',
      'command': command,
      'args': args,
    });
    try {
      await web.runJavaScript(
        "window.postMessage($message, 'https://cinesrc.st');",
      );
    } catch (_) {
      // The source can be between navigations; the next visible action retries.
    }
  }

  void _toggleControls() {
    setState(() => controlsVisible = !controlsVisible);
    if (controlsVisible) _scheduleControlsHide();
  }

  void _scheduleControlsHide() {
    controlsTimer?.cancel();
    if (playerReportedPlaying != true) return;
    controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && playerReportedPlaying == true) {
        setState(() => controlsVisible = false);
      }
    });
  }

  void _togglePlayback() {
    final play = playerReportedPlaying != true;
    setState(() {
      playerReportedPlaying = play;
      controlsVisible = true;
    });
    _sendCommand(play ? 'play' : 'pause');
    if (play) _scheduleControlsHide();
  }

  bool _acceptPlayerPosition(double candidate, {bool seekFinished = false}) {
    final target = pendingSeekTarget;
    if (target == null) return true;
    final elapsed = pendingSeekStartedAt == null
        ? Duration.zero
        : DateTime.now().difference(pendingSeekStartedAt!);
    final reachedTarget = (candidate - target).abs() <= 2;
    if (seekFinished ||
        reachedTarget ||
        elapsed >= const Duration(seconds: 5)) {
      _clearPendingSeek();
      return true;
    }
    // CineSrc can emit one or more time updates from the old position after a
    // seek command. Keep the scrubber at the requested position until the
    // provider confirms it instead of making the UI jump backwards.
    return false;
  }

  void _clearPendingSeek() {
    pendingSeekTarget = null;
    pendingSeekStartedAt = null;
    seekTimeoutTimer?.cancel();
    seekTimeoutTimer = null;
  }

  Future<void> _dispatchSeek(double target) async {
    if (widget.playerPreview != null || !playerPageReady) return;
    final message = jsonEncode({
      'type': 'cinesrc:command',
      'command': 'seek',
      'args': [target],
    });
    try {
      // Seek the accessible media directly, or use CineSrc's command as a
      // fallback. Never do both: duplicate seeks can restart buffering.
      await web.runJavaScript('''
        (() => {
          const target = ${target.toStringAsFixed(3)};
          let applied = false;
          const seekVideos = (root) => {
            try {
              root.querySelectorAll('video').forEach((video) => {
                if (!applied && video.readyState > 0) {
                  video.currentTime = target;
                  applied = true;
                }
              });
              root.querySelectorAll('iframe').forEach((frame) => {
                try {
                  if (frame.contentDocument) seekVideos(frame.contentDocument);
                } catch (_) {}
              });
            } catch (_) {}
          };
          seekVideos(document);
          if (!applied) window.postMessage($message, 'https://cinesrc.st');
        })();
      ''');
    } catch (_) {
      await _sendCommand('seek', [target]);
    }
  }

  void _seekTo(double seconds) {
    final target = seconds
        .clamp(0, duration > 0 ? duration : double.infinity)
        .toDouble();
    setState(() {
      position = target;
      scrubPosition = target;
      buffering = true;
      pendingSeekTarget = target;
      pendingSeekStartedAt = DateTime.now();
      lastExactProgressAt = pendingSeekStartedAt;
    });
    seekTimeoutTimer?.cancel();
    seekTimeoutTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || pendingSeekTarget != target) return;
      setState(() {
        _clearPendingSeek();
        buffering = false;
      });
    });
    unawaited(_dispatchSeek(target));
    _scheduleControlsHide();
  }

  void _seekBy(double delta) => _seekTo(position + delta);

  void _tickProgress() {
    final now = DateTime.now();
    final previousTick = lastProgressTick ?? now;
    lastProgressTick = now;
    if (!playerPageReady || !appActive) return;
    if (pendingSeekTarget != null) return;

    // Loading is not playback. Never create fake resume timestamps while a
    // server is resolving, or seek that invented time into the next attempt.
    if (playerReportedPlaying != true || loadingSource || buffering) return;

    final stalled =
        playerReportedPlaying == true &&
        lastExactProgressAt != null &&
        now.difference(lastExactProgressAt!) > const Duration(seconds: 6);
    if (stalled != buffering && mounted) setState(() => buffering = stalled);
    if (stalled) return;

    final elapsed = now.difference(previousTick).inMilliseconds / 1000;
    if (elapsed > 0 && elapsed < 3) {
      position += elapsed * playbackRate;
      // Playback time is intentionally kept outside setState so provider
      // events remain cheap. Local subtitles still need their own repaint
      // clock after the transport fades out, otherwise the visible cue freezes
      // until the user taps the player again.
      if (mounted && (subtitleTrack != null || controlsVisible)) {
        setState(() {});
      }
    }
    _persistIfNeeded();
  }

  void _persistIfNeeded() {
    final bucket = (position / 10).floor();
    if (bucket > savedProgressBucket) {
      savedProgressBucket = bucket;
      unawaited(_persistProgress());
    }
  }

  double? _seconds(Object? value) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    return parsed != null && parsed.isFinite && parsed >= 0 ? parsed : null;
  }

  Future<void> _persistProgress() => widget.controller.saveWatchProgress(
    widget.media,
    position,
    duration,
    season: widget.media.isSeries ? season : null,
    episode: widget.media.isSeries ? episode : null,
  );

  List<Media> _watchNextItems(MediaDetail? detail) {
    final catalog = widget.controller.catalog;
    final seen = <String>{widget.media.key};
    final items = <Media>[];
    final candidates = <Media>[
      ...?detail?.recommendations,
      if (!widget.controller.kidsMode) ...?catalog?.hero.recommendations,
      ...?catalog?.rails
          .where(
            (rail) =>
                !widget.controller.kidsMode || rail.id.startsWith('kids-'),
          )
          .expand((rail) => rail.items),
    ];
    for (final item in candidates) {
      if (widget.controller.kidsMode && !item.isKidsSafe) continue;
      if (item.key.isNotEmpty && seen.add(item.key)) items.add(item);
      if (items.length == 12) break;
    }
    return items;
  }

  String _embedUrl() {
    return playbackUri(
      source: source,
      media: widget.media,
      season: season,
      episode: episode,
      resumeAt: position.floor(),
      quality: qualityPreference,
    ).toString();
  }

  Future<void> _loadSelectedSource() async {
    final generation = ++loadGeneration;
    _clearPendingSeek();
    setState(() {
      loadingSource = true;
      playerPageReady = false;
      playerReady = false;
      playerReportedPlaying = null;
      lastExactProgressAt = null;
      lastProgressTick = DateTime.now();
    });
    if (!mounted || generation != loadGeneration) return;
    if (widget.playerPreview == null) {
      try {
        await web.loadRequest(Uri.parse(_embedUrl()));
      } catch (_) {
        if (mounted && generation == loadGeneration) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to open the player. Please try again.'),
            ),
          );
        }
      }
    }
  }

  void _selectEpisode({required int nextSeason, required int nextEpisode}) {
    if (position >= 5) unawaited(_persistProgress());
    _clearPendingSeek();
    setState(() {
      if (nextSeason != season) {
        episodesFuture = widget.controller.catalogApi.seasonEpisodes(
          widget.media.tmdbId,
          nextSeason,
          widget.controller.language,
        );
      }
      season = nextSeason;
      episode = nextEpisode;
      position = 0;
      duration = 0;
      savedProgressBucket = 0;
      playerPageReady = false;
      playerReportedPlaying = null;
      lastExactProgressAt = null;
      lastProgressTick = DateTime.now();
      subtitleTrack = null;
      subtitleEnabled = true;
      subtitleOffset = 0;
      subtitleSpeed = 1;
    });
    unawaited(
      widget.controller.saveWatchProgress(
        widget.media,
        0,
        0,
        season: nextSeason,
        episode: nextEpisode,
        force: true,
      ),
    );
    unawaited(_restoreLocalSubtitle());
    unawaited(_loadSelectedSource());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasActive = appActive;
    appActive = state == AppLifecycleState.resumed;
    lastProgressTick = DateTime.now();
    if (wasActive && !appActive && position >= 5) {
      unawaited(_persistProgress());
    }
    if (wasActive && !appActive) unawaited(_sendCommand('pause'));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    progressTimer?.cancel();
    controlsTimer?.cancel();
    seekTimeoutTimer?.cancel();
    if (position >= 5) unawaited(_persistProgress());
    if (immersive) unawaited(_restoreSystemUi());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (immersive) return _buildImmersivePlayer(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.media.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xffffbd36),
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              widget.media.isSeries ? 'SERIES · S$season · E$episode' : 'MOVIE',
              style: const TextStyle(
                fontSize: 9,
                letterSpacing: 2,
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          children: [
            AspectRatio(aspectRatio: 16 / 9, child: _buildPlayerSurface()),
            FutureBuilder<MediaDetail>(
              future: detailFuture,
              builder: (context, snapshot) {
                final detail = snapshot.data;
                final watchNext = _watchNextItems(detail);
                return Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'NOW WATCHING',
                        style: TextStyle(
                          color: Color(0xff47c98d),
                          fontSize: 11,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.media.title,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (widget.media.score > 0)
                            Text(
                              '★ ${widget.media.score.toStringAsFixed(1)}',
                              style: const TextStyle(color: Color(0xff47c98d)),
                            ),
                          if (widget.media.year != null)
                            Text('${widget.media.year}'),
                          if (detail?.runtime.isNotEmpty == true)
                            Text(detail!.runtime),
                        ],
                      ),
                      if (detail?.tagline.isNotEmpty == true) ...[
                        const SizedBox(height: 12),
                        Text(
                          '“${detail!.tagline}”',
                          style: const TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Text(
                        detail?.overview ?? widget.media.overview,
                        style: const TextStyle(
                          height: 1.6,
                          color: Colors.white60,
                        ),
                      ),
                      if (widget.media.isSeries && detail != null) ...[
                        const SizedBox(height: 34),
                        _EpisodeBrowser(
                          seasons: detail.seasons,
                          episodes: episodesFuture,
                          selectedSeason: season,
                          selectedEpisode: episode,
                          onSelect: (nextSeason, nextEpisode) => _selectEpisode(
                            nextSeason: nextSeason,
                            nextEpisode: nextEpisode,
                          ),
                        ),
                      ],
                      if (widget.controller.activeProfile != null) ...[
                        const SizedBox(height: 28),
                        ListenableBuilder(
                          listenable: widget.controller,
                          builder: (context, _) {
                            final saved = widget.controller.libraryKeys
                                .contains(widget.media.key);
                            final updating = widget.controller
                                .isLibraryUpdating(widget.media.key);
                            return SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: updating
                                    ? null
                                    : () async {
                                        try {
                                          await widget.controller.toggleLibrary(
                                            widget.media,
                                          );
                                        } catch (exception) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                exception
                                                    .toString()
                                                    .replaceFirst(
                                                      'Exception: ',
                                                      '',
                                                    ),
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                icon: updating
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(saved ? Icons.check : Icons.add),
                                label: Text(
                                  saved ? 'Saved to my list' : 'Add to my list',
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                      if (detail != null && detail.cast.isNotEmpty) ...[
                        const SizedBox(height: 34),
                        _CastGrid(cast: detail.cast),
                      ],
                      if (watchNext.isNotEmpty) ...[
                        const SizedBox(height: 30),
                        Row(
                          children: [
                            Text(
                              'Watch next',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const Spacer(),
                            const Text(
                              'RECOMMENDED',
                              style: TextStyle(
                                color: Color(0xff47c98d),
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 218,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: watchNext.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final item = watchNext[index];
                              return _WatchNextCard(
                                media: item,
                                onTap: () =>
                                    Navigator.of(context).pushReplacement(
                                      MaterialPageRoute(
                                        builder: (_) => WatchScreen(
                                          media: item,
                                          controller: widget.controller,
                                        ),
                                      ),
                                    ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setPlaybackRate(double rate) async {
    if (mounted) setState(() => playbackRate = rate);
    await _sendCommand('setPlaybackRate', [rate]);
  }

  Future<void> _setQuality(String? quality) async {
    if (qualityPreference == quality) return;
    if (mounted) {
      setState(() => qualityPreference = quality);
    }
    await _loadSelectedSource();
  }

  Future<void> _applyVolumeBoost(double boost) async {
    if (widget.playerPreview != null || !playerPageReady) return;
    try {
      await web.runJavaScript(
        'if (window.__krzeneSetBoost) window.__krzeneSetBoost(${boost.toStringAsFixed(2)});',
      );
    } catch (_) {
      // Some provider mirrors do not expose their media element to Web Audio.
    }
  }

  Future<void> _setVolumeBoost(double boost) async {
    if (mounted) setState(() => volumeBoost = boost);
    await _applyVolumeBoost(boost);
  }

  int get _subtitleSeason => widget.media.isSeries ? season : 0;
  int get _subtitleEpisode => widget.media.isSeries ? episode : 0;

  Future<void> _restoreLocalSubtitle() async {
    final generation = ++subtitleLoadGeneration;
    final storedSeason = _subtitleSeason;
    final storedEpisode = _subtitleEpisode;
    try {
      final stored = await SubtitleLocalStore.instance.load(
        mediaKey: widget.media.key,
        season: storedSeason,
        episode: storedEpisode,
      );
      if (!mounted ||
          generation != subtitleLoadGeneration ||
          storedSeason != _subtitleSeason ||
          storedEpisode != _subtitleEpisode) {
        return;
      }
      setState(() {
        subtitleTrack = stored?.track;
        subtitleEnabled = stored?.enabled ?? true;
        subtitleOffset = stored?.offset ?? 0;
        subtitleSpeed = stored?.speed ?? 1;
        subtitleFontSize = stored?.fontSize ?? 20;
        subtitleBackground = stored?.background ?? .68;
        subtitleBackgroundColor = stored == null
            ? Colors.black
            : Color(stored.backgroundColorValue);
        subtitleColor = stored == null
            ? Colors.white
            : Color(stored.colorValue);
      });
    } catch (_) {
      // Playback remains available if local subtitle storage cannot be opened.
    }
  }

  Future<void> _saveSubtitleLocally() async {
    final track = subtitleTrack;
    if (track == null) return;
    try {
      await SubtitleLocalStore.instance.save(
        mediaKey: widget.media.key,
        season: _subtitleSeason,
        episode: _subtitleEpisode,
        subtitle: StoredSubtitle(
          track: track,
          enabled: subtitleEnabled,
          offset: subtitleOffset,
          speed: subtitleSpeed,
          fontSize: subtitleFontSize,
          background: subtitleBackground,
          backgroundColorValue: subtitleBackgroundColor.toARGB32(),
          colorValue: subtitleColor.toARGB32(),
        ),
      );
    } catch (_) {
      _showPlayerMessage(
        'The subtitle is active but could not be saved locally.',
      );
    }
  }

  void _showPlayerMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _importSubtitle() async {
    try {
      const group = XTypeGroup(
        label: 'Subtitles',
        extensions: <String>['srt', 'vtt'],
        mimeTypes: <String>['application/x-subrip', 'text/vtt', 'text/plain'],
        // Downloaded .srt files often have no registered iOS text UTI and are
        // greyed out by UIDocumentPicker. Let iOS select any document, then
        // validate its actual subtitle contents with SubtitleTrack below.
        uniformTypeIdentifiers: <String>['public.data'],
      );
      final file = await openFile(acceptedTypeGroups: const [group]);
      if (file == null) return;
      final track = SubtitleTrack.parseBytes(
        await file.readAsBytes(),
        file.name,
      );
      if (!mounted) return;
      setState(() {
        subtitleTrack = track;
        subtitleEnabled = true;
        subtitleOffset = 0;
        subtitleSpeed = 1;
      });
      unawaited(_saveSubtitleLocally());
      _showPlayerMessage(
        '${track.name} loaded with ${track.cues.length} cues.',
      );
    } on FormatException catch (error) {
      _showPlayerMessage(error.message);
    } on PlatformException catch (error) {
      _showPlayerMessage(
        error.message ?? 'The phone file picker could not be opened.',
      );
    } on ArgumentError catch (error) {
      _showPlayerMessage(
        'The subtitle picker could not open: ${error.message}',
      );
    } catch (_) {
      _showPlayerMessage('Krzene could not read the selected subtitle file.');
    }
  }

  Future<void> _findSubtitleAutomatically() async {
    if (findingSubtitle) return;
    setState(() => findingSubtitle = true);
    try {
      final track = await subtitleService.findAutomatic(
        media: widget.media,
        season: season,
        episode: episode,
        language: widget.controller.language,
      );
      if (!mounted) return;
      setState(() {
        subtitleTrack = track;
        subtitleEnabled = true;
        subtitleOffset = 0;
        subtitleSpeed = 1;
      });
      unawaited(_saveSubtitleLocally());
      _showPlayerMessage('${track.name} loaded automatically.');
    } catch (error) {
      _showPlayerMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => findingSubtitle = false);
    }
  }

  Future<void> _openSubtitleCat() async {
    final query = [
      widget.media.title,
      if (widget.media.year != null) '${widget.media.year}',
      if (widget.media.isSeries) 'S${season.toString().padLeft(2, '0')}',
      if (widget.media.isSeries) 'E${episode.toString().padLeft(2, '0')}',
    ].join(' ');
    final uri = Uri.https('www.subtitlecat.com', '/index.php', {
      'search': query,
    });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showPlayerMessage('Unable to open Subtitle Cat.');
    }
  }

  Future<void> _removeLocalSubtitle() async {
    try {
      await SubtitleLocalStore.instance.delete(
        mediaKey: widget.media.key,
        season: _subtitleSeason,
        episode: _subtitleEpisode,
      );
      if (!mounted) return;
      setState(() {
        subtitleTrack = null;
        subtitleEnabled = true;
        subtitleOffset = 0;
        subtitleSpeed = 1;
      });
      _showPlayerMessage('The local subtitle was removed.');
    } catch (_) {
      _showPlayerMessage('The local subtitle could not be removed.');
    }
  }

  Future<void> _showSubtitleSettings() async {
    controlsTimer?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: krzeneBackground,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        side: BorderSide(color: krzeneRed, width: 1.2),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, modalSetState) {
          void update(VoidCallback change) {
            if (mounted) setState(change);
            modalSetState(() {});
          }

          return SafeArea(
            top: false,
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * .58,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 2, 12, 10),
                    child: _SettingsHeading(
                      icon: Icons.closed_caption_rounded,
                      title: 'Subtitle settings',
                      subtitle: 'Independent Krzene subtitles',
                      onClose: () => Navigator.pop(sheetContext),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 10, 22, 26),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SettingsSlider(
                            label: 'Subtitle timing',
                            valueLabel:
                                '${subtitleOffset >= 0 ? '+' : ''}${subtitleOffset.toStringAsFixed(1)}s',
                            value: subtitleOffset,
                            min: -10,
                            max: 10,
                            divisions: 40,
                            onChanged: (value) =>
                                update(() => subtitleOffset = value),
                          ),
                          _SettingsSlider(
                            label: 'Subtitle speed',
                            valueLabel: '${subtitleSpeed.toStringAsFixed(2)}x',
                            value: subtitleSpeed,
                            min: .8,
                            max: 1.2,
                            divisions: 16,
                            onChanged: (value) =>
                                update(() => subtitleSpeed = value),
                          ),
                          _SettingsSlider(
                            label: 'Text size',
                            valueLabel: '${subtitleFontSize.round()} pt',
                            value: subtitleFontSize,
                            min: 14,
                            max: 34,
                            divisions: 10,
                            onChanged: (value) =>
                                update(() => subtitleFontSize = value),
                          ),
                          _SettingsSlider(
                            label: 'Background opacity',
                            valueLabel:
                                '${(subtitleBackground * 100).round()}%',
                            value: subtitleBackground,
                            min: 0,
                            max: 1,
                            divisions: 10,
                            onChanged: (value) =>
                                update(() => subtitleBackground = value),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Background color',
                            style: TextStyle(
                              color: krzeneMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            children: [
                              for (final option in const [
                                Colors.black,
                                Color(0xff5b0b13),
                                Color(0xff10243c),
                              ])
                                ChoiceChip(
                                  label: Text(
                                    option == Colors.black
                                        ? 'Black'
                                        : option == const Color(0xff5b0b13)
                                        ? 'Red'
                                        : 'Blue',
                                  ),
                                  selected: subtitleBackgroundColor == option,
                                  selectedColor: krzeneRed,
                                  checkmarkColor: Colors.white,
                                  onSelected: (_) => update(
                                    () => subtitleBackgroundColor = option,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Text color',
                            style: TextStyle(
                              color: krzeneMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            children: [
                              for (final option in const [
                                Colors.white,
                                Color(0xffffdf45),
                                Color(0xff47c98d),
                              ])
                                ChoiceChip(
                                  label: Text(
                                    option == Colors.white
                                        ? 'White'
                                        : option == const Color(0xffffdf45)
                                        ? 'Yellow'
                                        : 'Green',
                                  ),
                                  selected: subtitleColor == option,
                                  selectedColor: krzeneRed,
                                  checkmarkColor: Colors.white,
                                  onSelected: (_) =>
                                      update(() => subtitleColor = option),
                                ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          Center(
                            child: _SubtitleCaption(
                              text: 'Your subtitles will look like this.',
                              fontSize: subtitleFontSize,
                              color: subtitleColor,
                              backgroundOpacity: subtitleBackground,
                              backgroundColor: subtitleBackgroundColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    unawaited(_saveSubtitleLocally());
    if (mounted) _scheduleControlsHide();
  }

  Future<void> _showPlaybackSettings() async {
    controlsTimer?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: krzeneBackground,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        side: BorderSide(color: krzeneRed, width: 1.2),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, modalSetState) {
          Widget choice(String label, bool selected, VoidCallback onTap) =>
              ChoiceChip(
                label: Text(label),
                selected: selected,
                selectedColor: krzeneRed,
                backgroundColor: krzenePanelRaised,
                checkmarkColor: Colors.white,
                side: BorderSide(color: selected ? krzeneRed : Colors.white24),
                labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                onSelected: (_) => onTap(),
              );

          return SafeArea(
            top: false,
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * .58,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 2, 12, 10),
                    child: _SettingsHeading(
                      icon: Icons.tune_rounded,
                      title: 'Playback settings',
                      subtitle: 'Tune your Krzene player',
                      onClose: () => Navigator.pop(sheetContext),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Speed',
                            style: TextStyle(
                              color: krzeneMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 9),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final rate in const [
                                .5,
                                .75,
                                1.0,
                                1.25,
                                1.5,
                                2.0,
                              ])
                                choice(
                                  rate == 1 ? 'Normal' : '${rate}x',
                                  playbackRate == rate,
                                  () {
                                    _setPlaybackRate(rate);
                                    modalSetState(() {});
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          const Text(
                            'Preferred quality',
                            style: TextStyle(
                              color: krzeneMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 9),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final option in const <String?>[
                                null,
                                '1080',
                                '720',
                                '480',
                              ])
                                choice(
                                  option == null ? 'Auto' : '${option}p',
                                  qualityPreference == option,
                                  () {
                                    _setQuality(option);
                                    modalSetState(() {});
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          _SettingsSlider(
                            label: 'Volume boost',
                            valueLabel: '${(volumeBoost * 100).round()}%',
                            value: volumeBoost,
                            min: 1,
                            max: 3,
                            divisions: 8,
                            onChanged: (value) {
                              if (mounted) setState(() => volumeBoost = value);
                              modalSetState(() {});
                            },
                            onChangeEnd: _setVolumeBoost,
                          ),
                          const Text(
                            'Boosting above 100% can cause distortion on some videos.',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: krzenePanelRaised,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.closed_caption_rounded,
                                      color: krzeneRed,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Krzene subtitles',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          Text(
                                            subtitleTrack?.name ??
                                                'No external subtitle loaded',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: krzeneMuted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value:
                                          subtitleEnabled &&
                                          subtitleTrack != null,
                                      activeTrackColor: krzeneRed,
                                      onChanged: subtitleTrack == null
                                          ? null
                                          : (value) {
                                              setState(
                                                () => subtitleEnabled = value,
                                              );
                                              modalSetState(() {});
                                              unawaited(_saveSubtitleLocally());
                                            },
                                    ),
                                  ],
                                ),
                                const Padding(
                                  padding: EdgeInsets.only(top: 6, bottom: 12),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.phone_iphone_rounded,
                                        size: 14,
                                        color: krzeneMuted,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'Stored only in Krzene on this phone',
                                        style: TextStyle(
                                          color: krzeneMuted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: krzeneRed,
                                          foregroundColor: Colors.white,
                                        ),
                                        onPressed: findingSubtitle
                                            ? null
                                            : () {
                                                Navigator.pop(sheetContext);
                                                _findSubtitleAutomatically();
                                              },
                                        icon: findingSubtitle
                                            ? const SizedBox.square(
                                                dimension: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.auto_awesome_rounded,
                                              ),
                                        label: const Text('Auto find'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () async {
                                          Navigator.pop(sheetContext);
                                          // Let the settings route finish dismissing
                                          // before iOS presents UIDocumentPicker.
                                          await Future<void>.delayed(
                                            const Duration(milliseconds: 250),
                                          );
                                          if (mounted) await _importSubtitle();
                                        },
                                        icon: const Icon(
                                          Icons.folder_open_rounded,
                                        ),
                                        label: const Text('Choose file'),
                                      ),
                                    ),
                                  ],
                                ),
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(
                                    'Auto find uses your OpenSubtitles developer consumer (up to 100 test downloads per day). No VIP plan is required.',
                                    style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 11,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.language_rounded),
                                  title: const Text('Find on Subtitle Cat'),
                                  subtitle: const Text(
                                    'Download an SRT, then import it here',
                                  ),
                                  trailing: const Icon(
                                    Icons.open_in_new_rounded,
                                  ),
                                  onTap: _openSubtitleCat,
                                ),
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.text_fields_rounded,
                                  ),
                                  title: const Text('Customize subtitles'),
                                  subtitle: const Text(
                                    'Text and background colors, timing and speed',
                                  ),
                                  trailing: const Icon(
                                    Icons.chevron_right_rounded,
                                  ),
                                  onTap: () {
                                    Navigator.pop(sheetContext);
                                    _showSubtitleSettings();
                                  },
                                ),
                                if (subtitleTrack != null)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: krzeneRed,
                                    ),
                                    title: const Text('Remove local subtitle'),
                                    onTap: () {
                                      Navigator.pop(sheetContext);
                                      _removeLocalSubtitle();
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (mounted) _scheduleControlsHide();
  }

  String _clock(double value) {
    final total = value.isFinite ? value.round().clamp(0, 359999) : 0;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildPlayerSurface({bool fullscreen = false}) {
    final player =
        widget.playerPreview ??
        WebViewWidget(
          controller: web,
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<EagerGestureRecognizer>(EagerGestureRecognizer.new),
          },
        );
    final shownPosition = scrubbing ? scrubPosition : position;
    final max = duration > 0 ? duration : 1.0;
    final subtitleText = subtitleEnabled
        ? subtitleTrack?.textAt(
            shownPosition,
            offsetSeconds: subtitleOffset,
            speed: subtitleSpeed,
          )
        : null;
    return Stack(
      fit: StackFit.expand,
      children: [
        player,
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            onDoubleTapDown: (details) {
              final rewind =
                  details.localPosition.dx <
                  MediaQuery.sizeOf(context).width / 2;
              _seekBy(rewind ? -10 : 10);
            },
          ),
        ),
        if (subtitleText != null && subtitleText.isNotEmpty)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 180),
            left: fullscreen ? 60 : 16,
            right: fullscreen ? 60 : 16,
            bottom: controlsVisible
                ? (fullscreen ? 74 : 58)
                : (fullscreen ? 24 : 12),
            child: IgnorePointer(
              child: Center(
                child: _SubtitleCaption(
                  text: subtitleText,
                  fontSize: fullscreen
                      ? subtitleFontSize
                      : subtitleFontSize.clamp(14, 18),
                  color: subtitleColor,
                  backgroundOpacity: subtitleBackground,
                  backgroundColor: subtitleBackgroundColor,
                ),
              ),
            ),
          ),
        IgnorePointer(
          ignoring: !controlsVisible,
          child: AnimatedOpacity(
            opacity: controlsVisible ? 1 : 0,
            duration: const Duration(milliseconds: 220),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xbb000000),
                    Color(0x18000000),
                    Color(0xd9000000),
                  ],
                  stops: [0, .48, 1],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    fullscreen ? 18 : 10,
                    8,
                    fullscreen ? 18 : 10,
                    8,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          if (fullscreen)
                            _PlayerOverlayButton(
                              tooltip: 'Back to details',
                              icon: Icons.arrow_back_rounded,
                              onPressed: _showDetails,
                            ),
                          if (fullscreen) const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.media.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Text(
                            widget.media.isSeries
                                ? 'S$season E$episode'
                                : 'MOVIE',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _PlayerTransportButton(
                            tooltip: 'Rewind 10 seconds',
                            icon: Icons.replay_10_rounded,
                            onPressed: () => _seekBy(-10),
                          ),
                          SizedBox(width: fullscreen ? 40 : 24),
                          if (!loadingSource && !buffering)
                            _PlayerTransportButton(
                              tooltip: playerReportedPlaying == true
                                  ? 'Pause'
                                  : 'Play',
                              icon: playerReportedPlaying == true
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              prominent: true,
                              onPressed: _togglePlayback,
                            )
                          else
                            const SizedBox.square(dimension: 69),
                          SizedBox(width: fullscreen ? 40 : 24),
                          _PlayerTransportButton(
                            tooltip: 'Forward 10 seconds',
                            icon: Icons.forward_10_rounded,
                            onPressed: () => _seekBy(10),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Text(
                            _clock(shownPosition),
                            style: const TextStyle(fontSize: 11),
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: const Color(0xffe21927),
                                inactiveTrackColor: Colors.white30,
                                thumbColor: const Color(0xffe21927),
                                overlayColor: const Color(0x44e21927),
                                trackHeight: 3,
                              ),
                              child: Slider(
                                value: shownPosition.clamp(0, max),
                                max: max,
                                onChangeStart: (value) => setState(() {
                                  scrubbing = true;
                                  scrubPosition = value;
                                  controlsTimer?.cancel();
                                }),
                                onChanged: (value) =>
                                    setState(() => scrubPosition = value),
                                onChangeEnd: (value) {
                                  setState(() => scrubbing = false);
                                  _seekTo(value);
                                },
                              ),
                            ),
                          ),
                          Text(
                            _clock(duration),
                            style: const TextStyle(fontSize: 11),
                          ),
                          IconButton(
                            tooltip: muted ? 'Unmute' : 'Mute',
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              setState(() => muted = !muted);
                              _sendCommand('setMuted', [muted]);
                            },
                            icon: Icon(
                              muted
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Playback settings',
                            visualDensity: VisualDensity.compact,
                            onPressed: _showPlaybackSettings,
                            icon: const Icon(Icons.settings_rounded),
                          ),
                          IconButton(
                            tooltip: fullscreen
                                ? 'Exit fullscreen'
                                : 'Fullscreen',
                            visualDensity: VisualDensity.compact,
                            onPressed: fullscreen
                                ? _showDetails
                                : _showFullscreen,
                            icon: Icon(
                              fullscreen
                                  ? Icons.fullscreen_exit_rounded
                                  : Icons.fullscreen_rounded,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (loadingSource || buffering)
          const IgnorePointer(
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xaa000000),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildImmersivePlayer(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(_showDetails());
    },
    child: Scaffold(
      backgroundColor: Colors.black,
      body: _buildPlayerSurface(fullscreen: true),
    ),
  );
}

class _SettingsHeading extends StatelessWidget {
  const _SettingsHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onClose,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: krzeneRed,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(color: Color(0x55e21927), blurRadius: 18),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            Text(
              subtitle,
              style: const TextStyle(color: krzeneMuted, fontSize: 12),
            ),
          ],
        ),
      ),
      if (onClose != null)
        IconButton(
          tooltip: 'Close settings',
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
        ),
    ],
  );
}

class _SettingsSlider extends StatelessWidget {
  const _SettingsSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.onChangeEnd,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: krzeneMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0x22e21927),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x66e21927)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Text(
                valueLabel,
                style: const TextStyle(
                  color: krzeneRed,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: krzeneRed,
          inactiveTrackColor: Colors.white12,
          thumbColor: krzeneRed,
          overlayColor: const Color(0x33e21927),
        ),
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ),
    ],
  );
}

class _SubtitleCaption extends StatelessWidget {
  const _SubtitleCaption({
    required this.text,
    required this.fontSize,
    required this.color,
    required this.backgroundOpacity,
    required this.backgroundColor,
  });

  final String text;
  final double fontSize;
  final Color color;
  final double backgroundOpacity;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: backgroundColor.withValues(alpha: backgroundOpacity),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          height: 1.24,
          fontWeight: FontWeight.w700,
          shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
    ),
  );
}

class _PlayerOverlayButton extends StatelessWidget {
  const _PlayerOverlayButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon),
    style: IconButton.styleFrom(
      backgroundColor: Colors.black.withValues(alpha: .74),
      foregroundColor: Colors.white,
      side: const BorderSide(color: Colors.white24),
    ),
  );
}

class _PlayerTransportButton extends StatelessWidget {
  const _PlayerTransportButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.prominent = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool prominent;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    iconSize: prominent ? 43 : 34,
    padding: EdgeInsets.all(prominent ? 13 : 10),
    icon: Icon(icon),
    style: IconButton.styleFrom(
      backgroundColor: prominent ? Colors.white : Colors.black45,
      foregroundColor: prominent ? Colors.black : Colors.white,
      side: prominent ? null : const BorderSide(color: Colors.white24),
    ),
  );
}

class _EpisodeBrowser extends StatelessWidget {
  const _EpisodeBrowser({
    required this.seasons,
    required this.episodes,
    required this.selectedSeason,
    required this.selectedEpisode,
    required this.onSelect,
  });
  final List<SeasonInfo> seasons;
  final Future<List<EpisodeInfo>> episodes;
  final int selectedSeason;
  final int selectedEpisode;
  final void Function(int season, int episode) onSelect;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Episodes',
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 14),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final item in seasons) ...[
              ChoiceChip(
                label: Text(item.name),
                selected: item.number == selectedSeason,
                onSelected: (_) => onSelect(item.number, 1),
                selectedColor: Colors.white,
                labelStyle: TextStyle(
                  color: item.number == selectedSeason
                      ? Colors.black
                      : Colors.white70,
                  fontWeight: FontWeight.w800,
                ),
                backgroundColor: const Color(0xff151515),
                side: BorderSide.none,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),
      FutureBuilder<List<EpisodeInfo>>(
        future: episodes,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: CircularProgressIndicator(),
              ),
            );
          }
          final items = snapshot.data ?? const <EpisodeInfo>[];
          if (items.isEmpty) {
            return const Text(
              'Episode information is temporarily unavailable.',
              style: TextStyle(color: Colors.white54),
            );
          }
          return Column(
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _EpisodeCard(
                    item: item,
                    selected: item.episodeNumber == selectedEpisode,
                    onTap: () =>
                        onSelect(item.seasonNumber, item.episodeNumber),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.item,
    required this.selected,
    required this.onTap,
  });
  final EpisodeInfo item;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0xff211d12) : const Color(0xff171717),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(
        color: selected ? const Color(0xffffbd36) : Colors.white10,
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.85,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (item.still != null)
                  Image.network(
                    item.still!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: Color(0xff202020)),
                  )
                else
                  const ColoredBox(color: Color(0xff202020)),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black54],
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      child: Text(
                        'S${item.seasonNumber} E${item.episodeNumber}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ),
                if (selected)
                  const Center(
                    child: CircleAvatar(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      child: Icon(Icons.play_arrow_rounded),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  [
                    if (item.airDate != null) item.airDate!,
                    if (item.runtime != null) '${item.runtime}m',
                  ].join(' · '),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                if (item.overview.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    item.overview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, height: 1.45),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _CastGrid extends StatelessWidget {
  const _CastGrid({required this.cast});
  final List<CastMember> cast;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Cast',
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 18),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: cast.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: .68,
          crossAxisSpacing: 14,
          mainAxisSpacing: 16,
        ),
        itemBuilder: (context, index) {
          final person = cast[index];
          return Column(
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipOval(
                  child: person.profile == null
                      ? ColoredBox(
                          color: const Color(0xff202020),
                          child: Center(
                            child: Text(
                              person.name.characters.first,
                              style: const TextStyle(fontSize: 26),
                            ),
                          ),
                        )
                      : Image.network(
                          person.profile!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const ColoredBox(color: Color(0xff202020)),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                person.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              Text(
                person.character,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ],
          );
        },
      ),
    ],
  );
}

class _WatchNextCard extends StatelessWidget {
  const _WatchNextCard({required this.media, required this.onTap});

  final Media media;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 132,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 132,
              height: 166,
              child: media.poster == null
                  ? _WatchNextFallback(title: media.title)
                  : Image.network(
                      media.poster!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          _WatchNextFallback(title: media.title),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            media.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: 3),
          Text(
            [
              if (media.year != null) '${media.year}',
              if (media.genres.isNotEmpty) media.genres.first,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ],
      ),
    ),
  );
}

class _WatchNextFallback extends StatelessWidget {
  const _WatchNextFallback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xff171717),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ),
  );
}
