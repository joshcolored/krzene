import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'controller.dart';
import 'models.dart';
import 'playback.dart';

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
  PlaybackSource source = PlaybackSource.cineSrc;
  List<AnimeMapping> animeMappings = const [];
  int loadGeneration = 0;
  bool loadingSource = false;
  int season = 1;
  int episode = 1;
  Timer? progressTimer;
  double position = 0;
  double resumeTarget = 0;
  double duration = 0;
  int savedProgressBucket = 0;
  bool resumeSent = false;
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
    resumeTarget = position;
    duration = widget.resume?.duration ?? 0;
    immersive =
        widget.playerPreview == null &&
        defaultTargetPlatform == TargetPlatform.android;
    savedProgressBucket = (position / 10).floor();
    lastProgressTick = DateTime.now();
    progressTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tickProgress(),
    );
    detailFuture = widget.controller.catalogApi.detail(
      widget.media,
      widget.controller.language,
    );
    if (widget.playerPreview == null) {
      web = WebViewController()
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
              lastProgressTick = DateTime.now();
            },
            onPageFinished: (_) {
              playerPageReady = true;
              lastProgressTick = DateTime.now();
              _installPlaybackBridge();
              _preparePlayerPage();
            },
            onNavigationRequest: _handleNavigation,
          ),
        );
      if (web.platform is AndroidWebViewController) {
        final android = web.platform as AndroidWebViewController;
        unawaited(android.setMediaPlaybackRequiresUserGesture(false));
      }
      web.loadRequest(Uri.parse(_embedUrl()));
    }
    if (immersive) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _enterImmersive());
    }
  }

  Future<void> _installPlaybackBridge() async {
    final resumeAt = _resumePositionForSelection().round();
    try {
      await web.runJavaScript('''
        if (!window.__krzeneBridgeInstalled) {
          window.__krzeneBridgeInstalled = true;
          window.addEventListener('message', function (event) {
            try {
              KrzeneBridge.postMessage(
                typeof event.data === 'string'
                  ? event.data
                  : JSON.stringify(event.data)
              );
            } catch (_) {}
          });

          const resumeAt = $resumeAt;
          let resumeApplied = resumeAt < 5;
          const reportVideos = function (root) {
            try {
              root.querySelectorAll('video').forEach(function (video) {
                if (!resumeApplied && video.readyState > 0) {
                  video.currentTime = Math.min(resumeAt, video.duration || resumeAt);
                  resumeApplied = true;
                }
                KrzeneBridge.postMessage(JSON.stringify({
                  type: 'KRZENE_PROGRESS',
                  data: {
                    position: video.currentTime || 0,
                    duration: Number.isFinite(video.duration) ? video.duration : 0,
                    paused: video.paused
                  }
                }));
              });
              root.querySelectorAll('iframe').forEach(function (frame) {
                try {
                  if (frame.contentDocument) reportVideos(frame.contentDocument);
                } catch (_) {}
              });
            } catch (_) {}
          };
          window.setInterval(function () { reportVideos(document); }, 1500);
        }
      ''');
    } catch (_) {
      // Mirrors without script access still play; they simply cannot sync progress.
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

  Future<void> _preparePlayerPage() async {
    try {
      await web.runJavaScript(r'''
        (() => {
          if (window.__krzenePlayerPrepared) return;
          window.__krzenePlayerPrepared = true;
          window.open = () => null;

          const removeAds = () => {
            const selectors = [
              '[class*="popunder" i]', '[id*="popunder" i]',
              '[class*="popup-ad" i]', '[id*="popup-ad" i]',
              '[class*="ad-overlay" i]', '[id*="ad-overlay" i]',
              'iframe[src*="doubleclick.net"]',
              'iframe[src*="googlesyndication.com"]',
              'iframe[src*="popads.net"]'
            ];
            document.querySelectorAll(selectors.join(',')).forEach((node) => node.remove());
          };

          const startPlayback = () => {
            document.querySelectorAll('video').forEach((video) => {
              video.autoplay = true;
              video.playsInline = false;
              video.play().catch(() => {
                video.muted = true;
                video.play().catch(() => {});
              });
            });
            const buttons = document.querySelectorAll([
              '.vjs-big-play-button', '.jw-icon-playback',
              'button[aria-label*="play" i]', '[class*="play-button" i]'
            ].join(','));
            buttons.forEach((button) => {
              if (button.offsetWidth > 0 && button.offsetHeight > 0) button.click();
            });
          };

          removeAds();
          new MutationObserver(removeAds).observe(document.documentElement, {
            childList: true, subtree: true
          });
          startPlayback();
          [500, 1400, 2800].forEach((delay) => setTimeout(() => {
            removeAds();
            startPlayback();
          }, delay));
        })();
      ''');
    } catch (_) {
      // Cross-origin provider internals may reject script access; URL autoplay
      // and the native WebView media setting still apply in that case.
    }
  }

  Future<void> _enterImmersive() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _restoreSystemUi() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await SystemChrome.setPreferredOrientations(const []);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _showDetails() async {
    if (mounted) setState(() => immersive = false);
    await _restoreSystemUi();
  }

  void _handleBridgeMessage(String raw) {
    if (!playerPageReady || loadingSource) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final data = decoded['data'];
      if (data is! Map) return;
      final type = decoded['type'];
      if (type != 'PLAYER_EVENT' && type != 'KRZENE_PROGRESS') return;
      final nextPosition = _seconds(
        type == 'PLAYER_EVENT' ? data['player_progress'] : data['position'],
      );
      final nextDuration = _seconds(
        type == 'PLAYER_EVENT' ? data['player_duration'] : data['duration'],
      );
      if (nextPosition == null) return;

      position = nextPosition;
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
      }

      if (!resumeSent && resumeTarget >= 5) {
        resumeSent = true;
        final target = resumeTarget.round();
        web.runJavaScript(
          '''window.postMessage({player:true,action:'seek$target'}, '*');''',
        );
      }

      _persistIfNeeded();
    } catch (_) {
      // Provider messages are untrusted and can use unrelated payload formats.
    }
  }

  void _tickProgress() {
    final now = DateTime.now();
    final previousTick = lastProgressTick ?? now;
    lastProgressTick = now;
    if (!playerPageReady || !appActive) return;

    final exactIsFresh =
        lastExactProgressAt != null &&
        now.difference(lastExactProgressAt!) < const Duration(seconds: 8);
    if (exactIsFresh && playerReportedPlaying == false) return;

    final elapsed = now.difference(previousTick).inMilliseconds / 1000;
    if (elapsed > 0 && elapsed < 3) position += elapsed;
    _persistIfNeeded();
  }

  void _persistIfNeeded() {
    final bucket = (position / 10).floor();
    if (bucket > savedProgressBucket) {
      savedProgressBucket = bucket;
      unawaited(_persistProgress());
    }
  }

  double _resumePositionForSelection() {
    return resumeTarget;
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
      animeMappings: animeMappings,
    ).toString();
  }

  Future<void> _loadSelectedSource() async {
    final generation = ++loadGeneration;
    setState(() {
      loadingSource = true;
      resumeTarget = position;
      playerPageReady = false;
      resumeSent = false;
      playerReportedPlaying = null;
      lastExactProgressAt = null;
      lastProgressTick = DateTime.now();
    });
    if (source == PlaybackSource.zoryva) {
      try {
        final detail = await detailFuture.timeout(const Duration(seconds: 10));
        if (!mounted || generation != loadGeneration) return;
        animeMappings = detail.animeMappings;
      } catch (_) {
        // Missing mappings use the provider's TMDB movie/TV endpoint.
      }
    }
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
    if (mounted && generation == loadGeneration) {
      setState(() => loadingSource = false);
    }
  }

  void _selectSource(PlaybackSource next) {
    if (next == source && playerPageReady) return;
    if (position >= 5) unawaited(_persistProgress());
    setState(() => source = next);
    unawaited(_loadSelectedSource());
  }

  Widget _sourceSelector() => PopupMenuButton<PlaybackSource>(
    tooltip: 'Playback source',
    initialValue: source,
    onSelected: _selectSource,
    itemBuilder: (_) => [
      for (final option in PlaybackSource.values)
        CheckedPopupMenuItem(
          value: option,
          checked: source == option,
          child: Text(option.label),
        ),
    ],
    child: _ToolChip(
      icon: Icons.dns_outlined,
      label: loadingSource
          ? 'Loading ${source.label}…'
          : 'Source · ${source.label}',
    ),
  );

  void _selectEpisode({required int nextSeason, required int nextEpisode}) {
    if (position >= 5) unawaited(_persistProgress());
    setState(() {
      season = nextSeason;
      episode = nextEpisode;
      position = 0;
      duration = 0;
      savedProgressBucket = 0;
      resumeSent = false;
      playerPageReady = false;
      playerReportedPlaying = null;
      lastExactProgressAt = null;
      lastProgressTick = DateTime.now();
    });
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    progressTimer?.cancel();
    if (position >= 5) unawaited(_persistProgress());
    unawaited(_restoreSystemUi());
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _sourceSelector(),
                  if (widget.media.isSeries) ...[
                    FutureBuilder<MediaDetail>(
                      future: detailFuture,
                      builder: (context, snapshot) => PopupMenuButton<int>(
                        onSelected: (value) =>
                            _selectEpisode(nextSeason: value, nextEpisode: 1),
                        itemBuilder: (_) => [
                          for (final item
                              in snapshot.data?.seasons ?? const <SeasonInfo>[])
                            PopupMenuItem(
                              value: item.number,
                              child: Text(item.name),
                            ),
                        ],
                        child: _ToolChip(
                          icon: Icons.video_collection_outlined,
                          label: 'Season $season',
                        ),
                      ),
                    ),
                    _ToolChip(
                      icon: Icons.skip_next,
                      label: 'Episode $episode',
                      onTap: () => _selectEpisode(
                        nextSeason: season,
                        nextEpisode: episode + 1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
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
                      const SizedBox(height: 22),
                      if (widget.controller.activeProfile != null)
                        ListenableBuilder(
                          listenable: widget.controller,
                          builder: (context, _) {
                            final saved = widget.controller.libraryKeys
                                .contains(widget.media.key);
                            final updating = widget.controller
                                .isLibraryUpdating(widget.media.key);
                            return FilledButton.icon(
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
                                              exception.toString().replaceFirst(
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
                            );
                          },
                        ),
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

  Widget _buildPlayerSurface() =>
      widget.playerPreview ??
      WebViewWidget(
        controller: web,
        // Keep swipes and slider drags inside the embedded player. Otherwise the
        // surrounding ListView wins vertical drags meant for player settings.
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<EagerGestureRecognizer>(EagerGestureRecognizer.new),
        },
      );

  Widget _buildImmersivePlayer(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(_showDetails());
    },
    child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildPlayerSurface(),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    _PlayerOverlayButton(
                      tooltip: 'Back',
                      icon: Icons.arrow_back_rounded,
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        widget.media.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    _sourceSelector(),
                    const SizedBox(width: 9),
                    _PlayerOverlayButton(
                      tooltip: 'Show details',
                      icon: Icons.fullscreen_exit_rounded,
                      onPressed: _showDetails,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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

class _ToolChip extends StatelessWidget {
  const _ToolChip({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xff171717),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}
