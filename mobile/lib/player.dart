import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'controller.dart';
import 'models.dart';

class PlaybackSource {
  const PlaybackSource(this.name, this.host, this.provider);
  final String name;
  final String host;
  final String provider;
}

const playbackSources = [
  PlaybackSource('CineSrc', 'https://cinesrc.st', 'cinesrc'),
  PlaybackSource('MultiEmbed', 'https://multiembed.mov', 'multiembed'),
  PlaybackSource('VidSrc', 'https://vsembed.ru', 'vidsrc'),
  PlaybackSource('VidSrc Backup', 'https://vsembed.su', 'vidsrc'),
  PlaybackSource('VidSrc Legacy', 'https://vidsrc.me', 'vidsrc'),
];

class WatchScreen extends StatefulWidget {
  const WatchScreen({
    super.key,
    required this.media,
    required this.controller,
    this.resume,
  });
  final Media media;
  final KrzeneController controller;
  final ContinueItem? resume;

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  late final WebViewController web;
  late Future<MediaDetail> detailFuture;
  int sourceIndex = 0;
  int season = 1;
  int episode = 1;
  Timer? loadTimer;
  String? notice;
  double position = 0;
  double duration = 0;
  int savedProgressBucket = 0;
  bool resumeSent = false;

  @override
  void initState() {
    super.initState();
    season = widget.resume?.season ?? 1;
    episode = widget.resume?.episode ?? 1;
    position = widget.resume?.position ?? 0;
    duration = widget.resume?.duration ?? 0;
    savedProgressBucket = (position / 10).floor();
    detailFuture = widget.controller.catalogApi.detail(
      widget.media,
      widget.controller.language,
    );
    web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'KrzeneBridge',
        onMessageReceived: (message) => _handleBridgeMessage(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => _startWatchdog(),
          onPageFinished: (_) {
            loadTimer?.cancel();
            _installPlaybackBridge();
            if (mounted) {
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) setState(() => notice = null);
              });
            }
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) _tryNextSource();
          },
        ),
      )
      ..loadRequest(Uri.parse(_embedUrl()));
  }

  Future<void> _installPlaybackBridge() async {
    if (playbackSources[sourceIndex].provider != 'vidsrc') return;
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
        }
      ''');
    } catch (_) {
      // Mirrors without script access still play; they simply cannot sync progress.
    }
  }

  void _handleBridgeMessage(String raw) {
    if (playbackSources[sourceIndex].provider != 'vidsrc') return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['type'] != 'PLAYER_EVENT') return;
      final data = decoded['data'];
      if (data is! Map) return;
      final nextPosition = _seconds(data['player_progress']);
      final nextDuration = _seconds(data['player_duration']);
      if (nextPosition == null) return;

      position = nextPosition;
      if (nextDuration != null && nextDuration > 0) duration = nextDuration;

      if (!resumeSent && (widget.resume?.position ?? 0) >= 5) {
        resumeSent = true;
        final target = widget.resume!.position.round();
        web.runJavaScript(
          '''window.postMessage({player:true,action:'seek$target'}, '*');''',
        );
      }

      final bucket = (position / 10).floor();
      if (bucket > savedProgressBucket) {
        savedProgressBucket = bucket;
        unawaited(_persistProgress());
      }
    } catch (_) {
      // Provider messages are untrusted and can use unrelated payload formats.
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
      ...?catalog?.hero.recommendations,
      ...?catalog?.rails.expand((rail) => rail.items),
    ];
    for (final item in candidates) {
      if (item.key.isNotEmpty && seen.add(item.key)) items.add(item);
      if (items.length == 12) break;
    }
    return items;
  }

  String _embedUrl() {
    final source = playbackSources[sourceIndex];
    final id = widget.media.tmdbId;
    final resume = (widget.resume?.position ?? 0).floor();
    if (source.provider == 'cinesrc') {
      final path = widget.media.isSeries ? '/embed/tv/$id' : '/embed/movie/$id';
      return Uri.parse('${source.host}$path')
          .replace(
            queryParameters: {
              if (widget.media.isSeries) 's': '$season',
              if (widget.media.isSeries) 'e': '$episode',
              'autoplay': 'true',
              if (resume > 0) 't': '$resume',
            },
          )
          .toString();
    }
    if (source.provider == 'multiembed') {
      return Uri.parse(source.host)
          .replace(
            queryParameters: {
              'video_id': '$id',
              'tmdb': '1',
              if (widget.media.isSeries) 's': '$season',
              if (widget.media.isSeries) 'e': '$episode',
            },
          )
          .toString();
    }
    var path =
        '${source.host}/embed/${widget.media.isSeries ? "tv" : "movie"}/$id';
    if (widget.media.isSeries) path += '/$season/$episode';
    return '$path?autoplay=1&ds_lang=en';
  }

  void _startWatchdog() {
    loadTimer?.cancel();
    loadTimer = Timer(const Duration(seconds: 20), _tryNextSource);
  }

  void _tryNextSource() {
    loadTimer?.cancel();
    if (!mounted || sourceIndex >= playbackSources.length - 1) {
      if (mounted) setState(() => notice = 'No other source is available.');
      return;
    }
    setState(() {
      sourceIndex++;
      notice = 'Trying other sources…';
    });
    web.loadRequest(Uri.parse(_embedUrl()));
  }

  void _selectSource(int index) {
    setState(() {
      sourceIndex = index;
      notice = null;
      resumeSent = false;
    });
    web.loadRequest(Uri.parse(_embedUrl()));
  }

  @override
  void dispose() {
    loadTimer?.cancel();
    if (position >= 5) unawaited(_persistProgress());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = playbackSources[sourceIndex];
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
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                children: [
                  WebViewWidget(controller: web),
                  if (notice != null)
                    Positioned(
                      top: 12,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 9,
                            ),
                            child: Text(
                              notice!,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  PopupMenuButton<int>(
                    onSelected: _selectSource,
                    itemBuilder: (_) => [
                      for (var i = 0; i < playbackSources.length; i++)
                        PopupMenuItem(
                          value: i,
                          child: Text(playbackSources[i].name),
                        ),
                    ],
                    child: _ToolChip(
                      icon: Icons.dns_outlined,
                      label: 'Servers  ${source.name}',
                    ),
                  ),
                  if (widget.media.isSeries)
                    FutureBuilder<MediaDetail>(
                      future: detailFuture,
                      builder: (context, snapshot) => PopupMenuButton<int>(
                        onSelected: (value) {
                          setState(() {
                            season = value;
                            episode = 1;
                          });
                          web.loadRequest(Uri.parse(_embedUrl()));
                        },
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
                  if (widget.media.isSeries)
                    _ToolChip(
                      icon: Icons.skip_next,
                      label: 'Episode $episode',
                      onTap: () {
                        setState(() => episode++);
                        web.loadRequest(Uri.parse(_embedUrl()));
                      },
                    ),
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
                        FilledButton.icon(
                          onPressed: () =>
                              widget.controller.toggleLibrary(widget.media),
                          icon: Icon(
                            widget.controller.libraryKeys.contains(
                                  widget.media.key,
                                )
                                ? Icons.check
                                : Icons.add,
                          ),
                          label: Text(
                            widget.controller.libraryKeys.contains(
                                  widget.media.key,
                                )
                                ? 'Saved to my list'
                                : 'Add to my list',
                          ),
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
            ].join(' Â· '),
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
