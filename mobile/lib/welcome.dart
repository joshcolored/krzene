import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'design.dart';

/// Device-level onboarding: signing out must not reset the welcome flow.
class WelcomeGate extends StatefulWidget {
  const WelcomeGate({super.key, required this.builder});
  final WidgetBuilder builder;
  static const completedKey = 'krzene.welcome.completed';

  @override
  State<WelcomeGate> createState() => _WelcomeGateState();
}

class _WelcomeGateState extends State<WelcomeGate> {
  bool? completed;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var value = false;
    try {
      value =
          (await SharedPreferences.getInstance()).getBool(
            WelcomeGate.completedKey,
          ) ??
          false;
    } catch (error) {
      debugPrint('Could not read welcome preference: $error');
    }
    if (mounted) setState(() => completed = value);
  }

  Future<void> _finish() async {
    try {
      await (await SharedPreferences.getInstance()).setBool(
        WelcomeGate.completedKey,
        true,
      );
    } catch (error) {
      // A storage failure must not prevent access to sign-in in this session.
      debugPrint('Could not save welcome preference: $error');
    }
    if (mounted) setState(() => completed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (completed == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return completed!
        ? widget.builder(context)
        : WelcomeScreen(onFinish: _finish);
  }
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onFinish});
  final Future<void> Function() onFinish;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final pages = PageController();
  int index = 0;
  bool finishing = false;

  static const slides = [
    (
      Icons.movie_outlined,
      'Welcome to Krzene',
      'Discover movies and shows, explore genres, and find your next watch.',
      krzeneRed,
    ),
    (
      Icons.bookmarks_outlined,
      'Make it yours',
      'Create your profile and save the movies and shows you love to your library.',
      krzeneGreen,
    ),
    (
      Icons.play_circle_outline_rounded,
      'Pick up where you left off',
      'Continue watching your last episode, or choose another from the episode list.',
      Color(0xffe8b757),
    ),
  ];

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  Future<void> finish() async {
    if (finishing) return;
    setState(() => finishing = true);
    await widget.onFinish();
    if (mounted) setState(() => finishing = false);
  }

  void goTo(int page) {
    if (MediaQuery.disableAnimationsOf(context)) {
      pages.jumpToPage(page);
    } else {
      pages.animateToPage(
        page,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 16, 0),
            child: Row(
              children: [
                const KrzeneMark(size: 36),
                const Spacer(),
                TextButton(
                  onPressed: finishing ? null : finish,
                  child: const Text('Skip'),
                ),
              ],
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: pages,
              itemCount: slides.length,
              onPageChanged: (value) => setState(() => index = value),
              itemBuilder: (context, page) {
                final slide = slides[page];
                return LayoutBuilder(
                  builder: (context, bounds) => SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 20,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: (bounds.maxHeight - 40).clamp(
                          0,
                          double.infinity,
                        ),
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 150,
                                height: 150,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(44),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      slide.$4.withValues(alpha: .28),
                                      krzenePanel,
                                    ],
                                  ),
                                  border: Border.all(
                                    color: slide.$4.withValues(alpha: .35),
                                  ),
                                ),
                                child: Icon(
                                  slide.$1,
                                  size: 72,
                                  color: slide.$4,
                                ),
                              ),
                              const SizedBox(height: 36),
                              Text(
                                slide.$2,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.headlineLarge
                                    ?.copyWith(fontSize: 34, height: 1.12),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                slide.$3,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: krzeneMuted,
                                  fontSize: 17,
                                  height: 1.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      label: 'Page ${index + 1} of ${slides.length}',
                      liveRegion: true,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var page = 0; page < slides.length; page++)
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: index == page ? 26 : 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: index == page
                                    ? krzeneRed
                                    : Colors.white24,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                    Row(
                      children: [
                        if (index > 0) ...[
                          TextButton(
                            onPressed: finishing ? null : () => goTo(index - 1),
                            child: const Text('Back'),
                          ),
                          const SizedBox(width: 16),
                        ],
                        Expanded(
                          child: FilledButton(
                            onPressed: finishing
                                ? null
                                : () {
                                    if (index == slides.length - 1) {
                                      finish();
                                    } else {
                                      goTo(index + 1);
                                    }
                                  },
                            child: Text(
                              finishing
                                  ? 'Opening…'
                                  : index == slides.length - 1
                                  ? 'Get started'
                                  : 'Next',
                            ),
                          ),
                        ),
                      ],
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
