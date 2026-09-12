import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'config.dart';
import 'models.dart';

/// Optional, muted official teaser. The artwork underneath is the fallback.
class HeroPreview extends StatefulWidget {
  const HeroPreview({super.key, required this.media});
  final Media media;
  @override
  State<HeroPreview> createState() => _HeroPreviewState();
}

class _HeroPreviewState extends State<HeroPreview> with WidgetsBindingObserver {
  Timer? timer;
  WebViewController? player;
  bool playing = false;
  bool finished = false;
  bool foreground = true;
  DateTime? visibleSince;
  DateTime? started;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (WebViewPlatform.instance != null) {
      timer = Timer.periodic(const Duration(milliseconds: 500), (_) => tick());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) stop();
  }

  void stop() {
    final previous = player;
    if (previous != null) {
      unawaited(
        previous
            .loadRequest(Uri.parse('about:blank'))
            .catchError((Object _) {}),
      );
    }
    if (mounted) {
      setState(() {
        player = null;
        playing = false;
      });
    }
    visibleSince = null;
    started = null;
  }

  void tick() {
    if (!mounted) return;
    final box = context.findRenderObject();
    final visible =
        foreground &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context) &&
        ModalRoute.of(context)?.isCurrent == true &&
        box is RenderBox &&
        box.hasSize &&
        box.localToGlobal(Offset.zero).dy > -box.size.height * .35;
    if (!visible) {
      if (player != null) stop();
      visibleSince = null;
      return;
    }
    if (finished) return;
    final now = DateTime.now();
    visibleSince ??= now;
    if (player == null && now.difference(visibleSince!).inSeconds >= 3) {
      unawaited(start());
    } else if (started != null &&
        now.difference(started!).inSeconds >= (playing ? 30 : 15)) {
      finished = true;
      stop();
    }
  }

  Future<void> start() async {
    final params = Platform.isIOS
        ? WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
          )
        : const PlatformWebViewControllerCreationParams();
    final controller = WebViewController.fromPlatformCreationParams(params);
    setState(() {
      player = controller;
      started = DateTime.now();
    });
    try {
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      if (controller.platform is AndroidWebViewController) {
        await (controller.platform as AndroidWebViewController)
            .setMediaPlaybackRequiresUserGesture(false);
      }
      await controller.addJavaScriptChannel(
        'KrzenePreview',
        onMessageReceived: (message) {
          if (!mounted || player != controller) return;
          if (message.message == 'playing') {
            setState(() => playing = true);
          } else {
            finished = true;
            stop();
          }
        },
      );
      if (!mounted || player != controller) return;
      await controller.loadRequest(
        Uri.parse(
          '${AppConfig.apiBaseUrl}/api/preview/${widget.media.kind}/${widget.media.tmdbId}',
        ),
      );
    } catch (_) {
      if (mounted && player == controller) {
        finished = true;
        stop();
      }
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (player != null) {
      unawaited(
        player!.loadRequest(Uri.parse('about:blank')).catchError((Object _) {}),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedOpacity(
      opacity: playing ? 1 : 0,
      duration: const Duration(milliseconds: 600),
      child: player == null
          ? const SizedBox.expand()
          : LayoutBuilder(
              builder: (context, bounds) {
                final width = (bounds.maxHeight * 16 / 9).clamp(
                  bounds.maxWidth,
                  double.infinity,
                );
                return ClipRect(
                  child: OverflowBox(
                    maxWidth: width,
                    maxHeight: bounds.maxHeight,
                    child: SizedBox(
                      width: width,
                      height: bounds.maxHeight,
                      child: WebViewWidget(controller: player!),
                    ),
                  ),
                );
              },
            ),
    ),
  );
}
