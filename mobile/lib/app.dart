import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'config.dart';
import 'controller.dart';
import 'design.dart';
import 'models.dart';
import 'player.dart';

const _languages = {
  'en-US': 'English · United States',
  'tl-PH': 'Filipino · Philippines',
  'ja-JP': 'Japanese · Japan',
  'ko-KR': 'Korean · South Korea',
  'es-ES': 'Spanish · Spain',
  'fr-FR': 'French · France',
  'de-DE': 'German · Germany',
  'hi-IN': 'Hindi · India',
  'zh-CN': 'Chinese · China',
};

class KrzeneApp extends StatefulWidget {
  const KrzeneApp({super.key});

  @override
  State<KrzeneApp> createState() => _KrzeneAppState();
}

class _KrzeneAppState extends State<KrzeneApp> {
  late final KrzeneController controller;

  @override
  void initState() {
    super.initState();
    controller = KrzeneController()..initialize();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Krzene',
    theme: krzeneTheme(),
    home: KrzeneLaunchGate(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          if (!controller.initialized) {
            return const ColoredBox(
              color: krzeneBackground,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 420),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: controller.signedIn
                ? HomeShell(key: const ValueKey('home'), controller: controller)
                : KrzeneLoginPage(
                    key: const ValueKey('login'),
                    controller: controller,
                  ),
          );
        },
      ),
    ),
  );
}

class KrzeneLoginPage extends StatefulWidget {
  const KrzeneLoginPage({super.key, required this.controller});
  final KrzeneController controller;

  @override
  State<KrzeneLoginPage> createState() => _KrzeneLoginPageState();
}

class _KrzeneLoginPageState extends State<KrzeneLoginPage> {
  bool openingGoogle = false;

  Future<void> _signIn() async {
    if (openingGoogle) return;
    setState(() => openingGoogle = true);
    try {
      await widget.controller.account.signInWithGoogle();
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(18),
          content: Text(
            exception.toString().replaceFirst('Exception: ', ''),
            style: const TextStyle(color: Colors.white, height: 1.35),
          ),
          backgroundColor: const Color(0xff541a20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => openingGoogle = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned(top: 22, left: 22, child: KrzeneLogo(markSize: 39)),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 104, 22, 30),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 450),
                padding: const EdgeInsets.fromLTRB(25, 38, 25, 30),
                decoration: BoxDecoration(
                  gradient: const RadialGradient(
                    center: Alignment(-.5, -.8),
                    radius: 1.55,
                    colors: [Color(0xff1f302e), Color(0xff101212)],
                  ),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white12),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 42,
                      offset: Offset(0, 20),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const KrzeneMark(size: 62),
                    const SizedBox(height: 27),
                    Text(
                      'Welcome to Krzene',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Sign in first to browse, create viewer profiles, save your library, and continue watching.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: krzeneMuted, height: 1.55),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: openingGoogle ? null : _signIn,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: openingGoogle
                              ? const SizedBox(
                                  key: ValueKey('loading'),
                                  width: 21,
                                  height: 21,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.3,
                                    color: Colors.black,
                                  ),
                                )
                              : const Row(
                                  key: ValueKey('google'),
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _GoogleBadge(),
                                    SizedBox(width: 11),
                                    Text('Continue with Google'),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'A secure browser panel will return you directly to Krzene after sign-in.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xff77736e), fontSize: 11),
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () =>
                              _openAccountPage(context, const _PrivacyScreen()),
                          child: const Text('Privacy'),
                        ),
                        TextButton(
                          onPressed: () =>
                              _openAccountPage(context, const _TermsScreen()),
                          child: const Text('Terms'),
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

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller});
  final KrzeneController controller;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final pages = [
      BrowsePage(controller: controller),
      SearchPage(controller: controller),
      LibraryPage(controller: controller),
      KrzeneAccountPage(controller: controller),
    ];
    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 18,
        backgroundColor: Colors.transparent,
        title: const KrzeneLogo(markSize: 38),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          for (var pageIndex = 0; pageIndex < pages.length; pageIndex++)
            IgnorePointer(
              ignoring: pageIndex != index,
              child: ExcludeSemantics(
                excluding: pageIndex != index,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  offset: pageIndex == index
                      ? Offset.zero
                      : Offset(pageIndex < index ? -.045 : .045, 0),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOut,
                    opacity: pageIndex == index ? 1 : 0,
                    child: TickerMode(
                      enabled: pageIndex == index,
                      child: ColoredBox(
                        color: krzeneBackground,
                        child: pages[pageIndex],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _KrzeneNavigation(
        index: index,
        onChanged: (value) => setState(() => index = value),
      ),
    );
  }
}

class _KrzeneNavigation extends StatelessWidget {
  const _KrzeneNavigation({required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;

  static const items = [
    (KrzeneGlyph.home, 'Browse'),
    (KrzeneGlyph.search, 'Search'),
    (KrzeneGlyph.library, 'Library'),
  ];

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xf20f0f0f),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white12),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 28,
                  offset: Offset(0, 13),
                ),
              ],
            ),
            child: Row(
              children: [
                for (var itemIndex = 0; itemIndex < items.length; itemIndex++)
                  Expanded(child: _destination(itemIndex)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 11),
        SizedBox(width: 74, child: _profileDestination()),
      ],
    ),
  );

  Widget _destination(int itemIndex) {
    final selected = itemIndex == index;
    return Semantics(
      label: items[itemIndex].$2,
      button: true,
      selected: selected,
      child: InkWell(
        onTap: () => onChanged(itemIndex),
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: selected
                    ? krzeneRed.withValues(alpha: .16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: KrzeneIcon(
                items[itemIndex].$1,
                size: 19,
                color: selected ? krzeneRed : krzeneMuted,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              style: TextStyle(
                color: selected ? krzeneText : krzeneMuted,
                fontSize: 9.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
              child: Text(items[itemIndex].$2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileDestination() {
    final selected = index == 3;
    return Semantics(
      label: 'Profile',
      button: true,
      selected: selected,
      child: InkWell(
        onTap: () => onChanged(3),
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          height: 72,
          decoration: BoxDecoration(
            color: selected ? const Color(0xfff01f2e) : krzeneRed,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xfff33a46)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x6b000000),
                blurRadius: 28,
                offset: Offset(0, 13),
              ),
              BoxShadow(color: Color(0x35e21927), blurRadius: 18),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: selected ? 1.08 : 1,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                child: const KrzeneIcon(
                  KrzeneGlyph.profile,
                  size: 19,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Profile',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showLanguageSheet(
  BuildContext context,
  KrzeneController controller,
) async {
  final selected = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Language & region',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 7),
            const Text(
              'Choose the catalog language you want to browse.',
              style: TextStyle(color: krzeneMuted),
            ),
            const SizedBox(height: 18),
            for (final entry in _languages.entries)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Icon(
                  controller.language == entry.key
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: controller.language == entry.key
                      ? krzeneRed
                      : krzeneMuted,
                ),
                title: Text(entry.value),
                onTap: () => Navigator.pop(context, entry.key),
              ),
          ],
        ),
      ),
    ),
  );
  if (selected != null) await controller.changeLanguage(selected);
}

class BrowsePage extends StatelessWidget {
  const BrowsePage({super.key, required this.controller});
  final KrzeneController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.loading && controller.catalog == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.catalog == null) {
      return _ErrorView(
        message: controller.error ?? 'Catalog unavailable',
        onRetry: controller.loadCatalog,
      );
    }
    final catalog = controller.catalog!;
    final kids = controller.activeProfile?.isKids == true;
    final rails = catalog.rails
        .where(
          (rail) =>
              kids ? rail.id.startsWith('kids-') : !rail.id.startsWith('kids-'),
        )
        .toList();
    return RefreshIndicator(
      onRefresh: controller.loadCatalog,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _HeroBanner(media: catalog.hero, controller: controller),
          if (controller.signedIn &&
              controller.activeProfile != null &&
              controller.continueWatching.isNotEmpty)
            _ContinueRail(controller: controller),
          for (final rail in rails)
            _RailView(rail: rail, controller: controller),
          const SizedBox(height: 112),
        ],
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.media, required this.controller});
  final Media media;
  final KrzeneController controller;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 530,
    child: Stack(
      fit: StackFit.expand,
      children: [
        if (media.art != null) Image.network(media.art!, fit: BoxFit.cover),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black12, Color(0x33000000), Color(0xff070707)],
              stops: [0, .48, 1],
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 34,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'FEATURE FILM · TRENDING NOW',
                style: TextStyle(
                  color: Color(0xff47c98d),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                media.title,
                style: const TextStyle(
                  fontSize: 43,
                  height: .95,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                [
                  if (media.score > 0) '★ ${media.score.toStringAsFixed(1)}',
                  if (media.year != null) '${media.year}',
                  ...media.genres.take(2),
                ].join('  ·  '),
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Text(
                media.overview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, height: 1.45),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _watch(context, media, controller),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Watch now'),
                    ),
                  ),
                  if (controller.activeProfile != null) ...[
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      onPressed: () => controller.toggleLibrary(media),
                      icon: Icon(
                        controller.libraryKeys.contains(media.key)
                            ? Icons.check
                            : Icons.add,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _RailView extends StatelessWidget {
  const _RailView({required this.rail, required this.controller});
  final MediaRail rail;
  final KrzeneController controller;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                rail.kicker,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 9,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                rail.heading,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 198,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            scrollDirection: Axis.horizontal,
            itemCount: rail.items.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (_, index) =>
                _MediaCard(media: rail.items[index], controller: controller),
          ),
        ),
      ],
    ),
  );
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({
    required this.media,
    required this.controller,
    this.compact = false,
  });
  final Media media;
  final KrzeneController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: compact ? null : 245,
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _watch(context, media, controller),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: compact ? 1.35 : 1.77,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                color: krzenePanelRaised,
                child: media.art == null
                    ? _ArtworkFallback(title: media.title)
                    : Image.network(
                        media.art!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (context, error, stackTrace) =>
                            _ArtworkFallback(title: media.title),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            media.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            [
              if (media.year != null) '${media.year}',
              if (media.genres.isNotEmpty) media.genres.first,
            ].join(' · '),
            style: const TextStyle(fontSize: 11, color: Colors.white38),
          ),
        ],
      ),
    ),
  );
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xff242424), Color(0xff101010)],
      ),
    ),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: krzeneMuted),
        ),
      ),
    ),
  );
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.controller});
  final KrzeneController controller;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  Timer? timer;
  bool loading = false;
  List<Media> results = [];
  String? error;
  int requestId = 0;
  String query = '';

  List<Media> get recommendations {
    final catalog = widget.controller.catalog;
    if (catalog == null) return const [];
    final seen = <String>{};
    final items = <Media>[];
    for (final item in [
      ...catalog.hero.recommendations,
      ...catalog.rails.expand((rail) => rail.items),
    ]) {
      if (item.key.isNotEmpty && seen.add(item.key)) items.add(item);
      if (items.length == 18) break;
    }
    return items;
  }

  void search(String value) {
    timer?.cancel();
    final nextQuery = value.trim();
    if (nextQuery.isEmpty) {
      requestId++;
      setState(() {
        query = '';
        results = [];
        error = null;
        loading = false;
      });
      return;
    }
    setState(() {
      query = nextQuery;
      error = null;
    });
    timer = Timer(const Duration(milliseconds: 350), () async {
      final currentRequest = ++requestId;
      setState(() {
        loading = true;
        error = null;
      });
      try {
        final nextResults = await widget.controller.catalogApi.search(
          nextQuery,
          widget.controller.language,
        );
        if (mounted && currentRequest == requestId) {
          setState(() => results = nextResults);
        }
      } catch (exception) {
        if (mounted && currentRequest == requestId) {
          setState(() {
            results = [];
            error = exception.toString().replaceFirst('Exception: ', '');
          });
        }
      } finally {
        if (mounted && currentRequest == requestId) {
          setState(() => loading = false);
        }
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayedItems = query.isEmpty ? recommendations : results;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(context).top + 12,
        16,
        16,
      ),
      child: Column(
        children: [
          TextField(
            autofocus: false,
            onChanged: search,
            decoration: InputDecoration(
              hintText: 'Search every movie and show',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: const Color(0xff171717),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xffff8b93), fontSize: 12),
              ),
            ),
          const SizedBox(height: 14),
          if (query.isEmpty && displayedItems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Recommended to watch',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'FOR YOU',
                    style: TextStyle(
                      color: krzeneGreen,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          if (query.isNotEmpty &&
              !loading &&
              error == null &&
              displayedItems.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Text(
                'No movies or shows matched your search.',
                style: TextStyle(color: krzeneMuted),
              ),
            ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.only(bottom: 132),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisExtent: 198,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: displayedItems.length,
              itemBuilder: (_, index) => _MediaCard(
                media: displayedItems[index],
                controller: widget.controller,
                compact: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key, required this.controller});
  final KrzeneController controller;

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.hasSupabase) {
      return const _ConfigNotice();
    }
    if (!controller.signedIn) return const SizedBox.shrink();
    if (controller.activeProfile == null) {
      return const Center(child: Text('Choose or create a profile first.'));
    }
    return ListView(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + 12,
        bottom: 112,
      ),
      children: [
        if (controller.continueWatching.isNotEmpty)
          _ContinueRail(controller: controller),
        _RailView(
          rail: MediaRail(
            'library',
            'MY LIST',
            'Saved titles',
            controller.library,
          ),
          controller: controller,
        ),
        if (controller.library.isEmpty)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Text(
              'Tap + on a title to keep it here.',
              style: TextStyle(color: Colors.white54),
            ),
          ),
      ],
    );
  }
}

class _ContinueRail extends StatelessWidget {
  const _ContinueRail({required this.controller});
  final KrzeneController controller;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            'Continue watching',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 198,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            scrollDirection: Axis.horizontal,
            itemCount: controller.continueWatching.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (_, index) {
              final item = controller.continueWatching[index];
              return Stack(
                children: [
                  _MediaCard(media: item.media, controller: controller),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 138,
                    child: LinearProgressIndicator(
                      minHeight: 4,
                      value: item.duration > 0
                          ? (item.position / item.duration).clamp(0, 1)
                          : 0,
                      backgroundColor: Colors.white12,
                      color: const Color(0xffe21927),
                    ),
                  ),
                  Positioned.fill(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () =>
                            _watch(context, item.media, controller, item),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

class AccountPage extends StatelessWidget {
  const AccountPage({super.key, required this.controller});
  final KrzeneController controller;

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.hasSupabase) {
      return const _ConfigNotice();
    }
    if (!controller.signedIn) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          controller.account.user?.email ?? 'Krzene account',
          style: const TextStyle(color: Colors.white54),
        ),
        const SizedBox(height: 18),
        const Text(
          'Who’s watching?',
          style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final profile in controller.profiles)
              InkWell(
                onTap: () => controller.selectProfile(profile),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 105,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: controller.activeProfile?.id == profile.id
                        ? Colors.white12
                        : const Color(0xff151515),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: controller.activeProfile?.id == profile.id
                          ? Colors.white54
                          : Colors.white10,
                    ),
                  ),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundImage: profile.avatarUrl == null
                            ? null
                            : NetworkImage(profile.avatarUrl!),
                        child: profile.avatarUrl == null
                            ? Text(
                                profile.name.characters.first.toUpperCase(),
                                style: const TextStyle(fontSize: 24),
                              )
                            : null,
                      ),
                      const SizedBox(height: 9),
                      Text(
                        profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (profile.isKids)
                        const Text(
                          'KIDS',
                          style: TextStyle(
                            fontSize: 8,
                            color: Color(0xff47c98d),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            InkWell(
              onTap: () => _createProfile(context, controller),
              child: const SizedBox(
                width: 105,
                child: Column(
                  children: [
                    CircleAvatar(radius: 34, child: Icon(Icons.add, size: 30)),
                    SizedBox(height: 9),
                    Text('Add profile'),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 30),
        OutlinedButton.icon(
          onPressed: controller.account.signOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}

class KrzeneAccountPage extends StatelessWidget {
  const KrzeneAccountPage({super.key, required this.controller});
  final KrzeneController controller;

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.hasSupabase) return const _ConfigNotice();
    if (!controller.signedIn) return const SizedBox.shrink();

    final user = controller.account.user!;
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final email = user.email ?? 'Krzene account';
    final displayName = _firstMetadataValue(metadata, const [
      'full_name',
      'name',
      'user_name',
    ], fallback: email.split('@').first);
    final avatarUrl = _firstMetadataValue(metadata, const [
      'avatar_url',
      'picture',
    ]);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 12,
        20,
        MediaQuery.paddingOf(context).bottom + 164,
      ),
      children: [
        Text('MY PROFILE', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xff20322f), Color(0xff111514)],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Container(
                width: 76,
                height: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: krzeneRed,
                  shape: BoxShape.circle,
                  image: avatarUrl.isEmpty
                      ? null
                      : DecorationImage(
                          image: NetworkImage(avatarUrl),
                          fit: BoxFit.cover,
                        ),
                ),
                child: avatarUrl.isEmpty
                    ? Text(
                        displayName.characters.first.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 17),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      email,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: krzeneMuted, fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    const Row(
                      children: [
                        Icon(
                          Icons.verified_rounded,
                          size: 15,
                          color: krzeneGreen,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Google account',
                          style: TextStyle(color: krzeneGreen, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Text('Viewer profiles', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 7),
        const Text(
          'Choose who is watching or add another profile.',
          style: TextStyle(color: krzeneMuted),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 18,
          runSpacing: 24,
          children: [
            for (final profile in controller.profiles)
              _ProfileTile(
                profile: profile,
                selected: controller.activeProfile?.id == profile.id,
                onTap: () => controller.selectProfile(profile),
              ),
            _AddProfileTile(
              onTap: () => _createProfileSheet(context, controller),
            ),
          ],
        ),
        const SizedBox(height: 34),
        _SettingsSection(
          title: 'Preferences',
          subtitle: 'Control how Krzene looks and feels for you.',
          children: [
            _SettingsTile(
              icon: Icons.language_rounded,
              title: 'Language & region',
              subtitle: _languages[controller.language] ?? controller.language,
              onTap: () => _showLanguageSheet(context, controller),
            ),
            _SettingsTile(
              icon: Icons.manage_accounts_rounded,
              title: 'Manage profiles',
              subtitle: 'Edit profile names and account profiles',
              onTap: () => _openAccountPage(
                context,
                _ManageProfilesScreen(controller: controller),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        _SettingsSection(
          title: 'Safety & support',
          subtitle: 'Help, policies, and account details.',
          children: [
            _SettingsTile(
              icon: Icons.support_agent_rounded,
              title: 'Help & support',
              subtitle: 'Contact Krzene by email',
              onTap: () => _openAccountPage(context, const _SupportScreen()),
            ),
            _SettingsTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy policy',
              subtitle: 'How Krzene handles your information',
              onTap: () => _openAccountPage(context, const _PrivacyScreen()),
            ),
            _SettingsTile(
              icon: Icons.description_outlined,
              title: 'Terms of use',
              subtitle: 'Rules for using Krzene',
              onTap: () => _openAccountPage(context, const _TermsScreen()),
            ),
          ],
        ),
        const SizedBox(height: 28),
        OutlinedButton.icon(
          onPressed: () => _confirmSignOut(context, controller),
          icon: const Icon(Icons.logout_rounded, size: 20),
          label: const Text('Sign out'),
          style: OutlinedButton.styleFrom(
            foregroundColor: krzeneRed,
            side: BorderSide(color: krzeneRed.withValues(alpha: .55)),
          ),
        ),
      ],
    );
  }
}

String _firstMetadataValue(
  Map<String, dynamic> metadata,
  List<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = metadata[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return fallback;
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.subtitle,
    required this.children,
  });
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 5),
      Text(subtitle, style: const TextStyle(color: krzeneMuted, fontSize: 12)),
      const SizedBox(height: 13),
      Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: krzenePanelRaised,
          borderRadius: BorderRadius.circular(23),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index != children.length - 1)
                const Divider(height: 1, indent: 72),
            ],
          ],
        ),
      ),
    ],
  );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 76,
    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
    leading: Container(
      width: 43,
      height: 43,
      decoration: BoxDecoration(
        color: krzeneRed.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, size: 21, color: krzeneRed),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
    subtitle: Text(
      subtitle,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: krzeneMuted, fontSize: 11.5),
    ),
    trailing: const Icon(Icons.chevron_right_rounded, color: krzeneMuted),
    onTap: onTap,
  );
}

Future<void> _confirmSignOut(
  BuildContext context,
  KrzeneController controller,
) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const KrzeneMark(size: 48),
            const SizedBox(height: 18),
            Text(
              'Sign out of Krzene?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Your saved library will remain connected to your account.',
              textAlign: TextAlign.center,
              style: TextStyle(color: krzeneMuted),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: krzeneRed,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Sign out'),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ),
  );
  if (confirmed == true) await controller.account.signOut();
}

void _openAccountPage(BuildContext context, Widget page) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      pageBuilder: (_, animation, secondaryAnimation) => page,
      transitionsBuilder: (_, animation, secondaryAnimation, child) =>
          FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: SlideTransition(
              position: Tween(begin: const Offset(.04, 0), end: Offset.zero)
                  .animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            ),
          ),
      transitionDuration: const Duration(milliseconds: 300),
    ),
  );
}

class _SupportScreen extends StatelessWidget {
  const _SupportScreen();
  static const email = 'support@krzene.site';

  @override
  Widget build(BuildContext context) => _AccountSubpage(
    title: 'Help & support',
    child: Center(
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 430),
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: krzenePanelRaised,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mail_outline_rounded, size: 38, color: krzeneRed),
            const SizedBox(height: 17),
            const Text(
              'Email support',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const SelectableText(email, style: TextStyle(color: krzeneMuted)),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(const ClipboardData(text: email));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Support email copied.')),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy email'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PrivacyScreen extends StatelessWidget {
  const _PrivacyScreen();

  @override
  Widget build(BuildContext context) => const _AccountSubpage(
    title: 'Privacy policy',
    child: _LegalCopy(
      sections: [
        (
          'Information we handle',
          'When you sign in, Krzene uses Supabase to store your account identifier, viewer profiles, library, and viewing progress. Google supplies the basic profile information you approve. Krzene never receives your Google password.',
        ),
        (
          'Service providers',
          'Krzene uses Supabase for authentication and data storage, Google for sign-in, TMDB for catalog metadata, Watchmode for streaming availability, and third-party playback providers.',
        ),
        (
          'Your choices',
          'You can remove profiles and library items in the app. Contact support@krzene.site to request access, correction, or deletion of account data.',
        ),
      ],
    ),
  );
}

class _TermsScreen extends StatelessWidget {
  const _TermsScreen();

  @override
  Widget build(BuildContext context) => const _AccountSubpage(
    title: 'Terms of use',
    child: _LegalCopy(
      sections: [
        (
          'Using Krzene',
          'Use Krzene only for lawful, personal purposes. Do not misuse, disrupt, scrape, reverse engineer, or attempt unauthorized access to the service or other accounts.',
        ),
        (
          'Third-party content',
          'Catalog information and playback are supplied by third parties. Availability, accuracy, subtitles, quality, and playback can change without notice.',
        ),
        (
          'Availability',
          'The service is provided as available. Features may change or be suspended for security, maintenance, legal, or operational reasons.',
        ),
      ],
    ),
  );
}

class _AccountSubpage extends StatelessWidget {
  const _AccountSubpage({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      backgroundColor: krzeneBackground,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        child: child,
      ),
    ),
  );
}

class _ManageProfilesScreen extends StatelessWidget {
  const _ManageProfilesScreen({required this.controller});

  final KrzeneController controller;

  @override
  Widget build(BuildContext context) => _AccountSubpage(
    title: 'Manage profiles',
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Viewer profiles',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 7),
          const Text(
            'Edit the names used for libraries and Continue Watching.',
            style: TextStyle(color: krzeneMuted, height: 1.5),
          ),
          const SizedBox(height: 22),
          if (controller.profiles.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: krzenePanelRaised,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white10),
              ),
              child: const Text(
                'No viewer profiles yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: krzeneMuted),
              ),
            )
          else
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: krzenePanelRaised,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  for (
                    var index = 0;
                    index < controller.profiles.length;
                    index++
                  ) ...[
                    _SwipeManagedProfileTile(
                      profile: controller.profiles[index],
                      active:
                          controller.activeProfile?.id ==
                          controller.profiles[index].id,
                      onEdit: () => _editProfileName(
                        context,
                        controller,
                        controller.profiles[index],
                      ),
                      onDelete: () => _confirmDeleteProfile(
                        context,
                        controller,
                        controller.profiles[index],
                      ),
                    ),
                    if (index != controller.profiles.length - 1)
                      const Divider(height: 1, indent: 76),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _createProfileSheet(context, controller),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add profile'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SwipeManagedProfileTile extends StatelessWidget {
  const _SwipeManagedProfileTile({
    required this.profile,
    required this.active,
    required this.onEdit,
    required this.onDelete,
  });

  final ViewerProfile profile;
  final bool active;
  final VoidCallback onEdit;
  final Future<bool> Function() onDelete;

  @override
  Widget build(BuildContext context) => Dismissible(
    key: ValueKey('managed-profile-${profile.id}'),
    direction: DismissDirection.endToStart,
    confirmDismiss: (_) => onDelete(),
    background: Container(
      color: const Color(0xff721821),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Delete',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          SizedBox(width: 9),
          Icon(Icons.delete_forever_rounded, color: Colors.white),
        ],
      ),
    ),
    child: _ManagedProfileTile(
      profile: profile,
      active: active,
      onEdit: onEdit,
    ),
  );
}

class _ManagedProfileTile extends StatelessWidget {
  const _ManagedProfileTile({
    required this.profile,
    required this.active,
    required this.onEdit,
  });

  final ViewerProfile profile;
  final bool active;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 78,
    contentPadding: const EdgeInsets.fromLTRB(15, 5, 10, 5),
    leading: CircleAvatar(
      radius: 25,
      backgroundColor: krzeneRed,
      backgroundImage: profile.avatarUrl == null
          ? null
          : NetworkImage(profile.avatarUrl!),
      child: profile.avatarUrl == null
          ? Text(
              profile.name.characters.first.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w900),
            )
          : null,
    ),
    title: Text(
      profile.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontWeight: FontWeight.w800),
    ),
    subtitle: Text(
      [if (active) 'CURRENT', if (profile.isKids) 'KIDS'].join(' Â· '),
      style: TextStyle(
        color: active ? krzeneGreen : krzeneMuted,
        fontSize: 9,
        fontWeight: FontWeight.w800,
        letterSpacing: .8,
      ),
    ),
    trailing: IconButton(
      tooltip: 'Edit ${profile.name}',
      onPressed: onEdit,
      icon: const Icon(Icons.edit_rounded, color: krzeneRed),
    ),
    onTap: onEdit,
  );
}

Future<bool> _confirmDeleteProfile(
  BuildContext context,
  KrzeneController controller,
  ViewerProfile profile,
) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.delete_forever_rounded,
              color: krzeneRed,
              size: 48,
            ),
            const SizedBox(height: 17),
            Text(
              'Delete ${profile.name}?',
              textAlign: TextAlign.center,
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 9),
            const Text(
              'This permanently deletes the profile, its saved library, and Continue Watching history. This cannot be undone.',
              textAlign: TextAlign.center,
              style: TextStyle(color: krzeneMuted, height: 1.5),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(sheetContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: krzeneRed,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.delete_forever_rounded),
                label: const Text('Delete profile'),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext, false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  try {
    await controller.deleteProfile(profile);
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_readableError(error))));
    }
    return false;
  }
}

Future<void> _editProfileName(
  BuildContext context,
  KrzeneController controller,
  ViewerProfile profile,
) async {
  final name = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ProfileNameEditorSheet(profile: profile),
  );
  if (name == null || name == profile.name || !context.mounted) return;
  try {
    await controller.renameProfile(profile, name);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_readableError(error))));
  }
}

class _ProfileNameEditorSheet extends StatefulWidget {
  const _ProfileNameEditorSheet({required this.profile});

  final ViewerProfile profile;

  @override
  State<_ProfileNameEditorSheet> createState() =>
      _ProfileNameEditorSheetState();
}

class _ProfileNameEditorSheetState extends State<_ProfileNameEditorSheet> {
  late final TextEditingController text;

  @override
  void initState() {
    super.initState();
    text = TextEditingController(text: widget.profile.name);
    text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: text.text.length,
    );
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      22,
      8,
      22,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.edit_rounded, color: krzeneRed, size: 40),
          const SizedBox(height: 16),
          Text(
            'Edit profile name',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: text,
            autofocus: true,
            maxLength: 32,
            textAlign: TextAlign.center,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(counterText: ''),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: text.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, text.text.trim()),
              child: const Text('Save name'),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );
}

class _LegalCopy extends StatelessWidget {
  const _LegalCopy({required this.sections});
  final List<(String, String)> sections;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Last updated: August 27, 2026',
        style: TextStyle(
          color: krzeneGreen,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 26),
      for (final section in sections) ...[
        Text(section.$1, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 9),
        Text(
          section.$2,
          style: const TextStyle(color: Color(0xffb9b4ad), height: 1.7),
        ),
        const SizedBox(height: 28),
      ],
    ],
  );
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.profile,
    required this.selected,
    required this.onTap,
  });
  final ViewerProfile profile;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(24),
    child: SizedBox(
      width: 104,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              gradient: const RadialGradient(
                center: Alignment(-.4, -.5),
                colors: [Color(0xffee6972), krzeneRed],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: selected ? krzeneText : Colors.transparent,
                width: 3,
              ),
              image: profile.avatarUrl == null
                  ? null
                  : DecorationImage(
                      image: NetworkImage(profile.avatarUrl!),
                      fit: BoxFit.cover,
                    ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 28,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: profile.avatarUrl == null
                ? Center(
                    child: Text(
                      profile.name.characters.first.toUpperCase(),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 11),
          Text(
            profile.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? krzeneText : krzeneMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (profile.isKids)
            const Text(
              'KIDS',
              style: TextStyle(fontSize: 8, color: krzeneGreen),
            ),
        ],
      ),
    ),
  );
}

class _AddProfileTile extends StatelessWidget {
  const _AddProfileTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(24),
    child: SizedBox(
      width: 104,
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .07),
              border: Border.all(color: Colors.white12, width: 2),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.add_rounded, size: 42, color: krzeneMuted),
          ),
          const SizedBox(height: 11),
          const Text(
            'Add profile',
            style: TextStyle(color: krzeneMuted, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

class _GoogleBadge extends StatelessWidget {
  const _GoogleBadge();

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/brand/google-g.svg',
    width: 22,
    height: 22,
    semanticsLabel: 'Google',
  );
}

class _ConfigNotice extends StatelessWidget {
  const _ConfigNotice();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          color: krzenePanel,
          border: Border.all(color: Colors.white10),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            KrzeneMark(size: 52),
            SizedBox(height: 20),
            Text(
              'Account sync is not configured',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 9),
            Text(
              'Add SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY with --dart-define to enable profiles and libraries.',
              textAlign: TextAlign.center,
              style: TextStyle(color: krzeneMuted, height: 1.5),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 430),
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          color: krzenePanel,
          border: Border.all(color: Colors.white10),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 42, color: krzeneMuted),
            const SizedBox(height: 17),
            Text(
              'The catalog could not load',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 9),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: krzeneMuted, height: 1.45),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 19),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    ),
  );
}

void _watch(
  BuildContext context,
  Media media,
  KrzeneController controller, [
  ContinueItem? resume,
]) {
  Navigator.of(context).push(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 520),
      reverseTransitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (context, animation, secondaryAnimation) =>
          WatchScreen(media: media, controller: controller, resume: resume),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          ScaleTransition(
            scale: Tween(begin: .88, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: FadeTransition(opacity: animation, child: child),
          ),
    ),
  );
}

Future<void> _createProfileSheet(
  BuildContext context,
  KrzeneController controller,
) async {
  final draft = await showModalBottomSheet<_ProfileDraft>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _CreateProfileEditorSheet(),
  );
  if (draft == null || !context.mounted) return;
  try {
    await controller.createProfile(draft.name, kids: draft.kids);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_readableError(error))));
  }
}

Future<void> _createProfile(
  BuildContext context,
  KrzeneController controller,
) => _createProfileSheet(context, controller);

String _readableError(Object error) =>
    error.toString().replaceFirst('Exception: ', '');

class _ProfileDraft {
  const _ProfileDraft(this.name, this.kids);
  final String name;
  final bool kids;
}

class _CreateProfileEditorSheet extends StatefulWidget {
  const _CreateProfileEditorSheet();

  @override
  State<_CreateProfileEditorSheet> createState() =>
      _CreateProfileEditorSheetState();
}

class _CreateProfileEditorSheetState extends State<_CreateProfileEditorSheet> {
  final text = TextEditingController();
  bool kids = false;

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      22,
      6,
      22,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const KrzeneMark(size: 62),
          const SizedBox(height: 18),
          Text(
            'Create a profile',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 7),
          const Text(
            'Give everyone their own library.',
            style: TextStyle(color: krzeneMuted),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: text,
            autofocus: true,
            maxLength: 32,
            textAlign: TextAlign.center,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Profile name',
              counterText: '',
            ),
          ),
          const SizedBox(height: 10),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            activeTrackColor: krzeneRed,
            title: const Text(
              'Kids profile',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'Show only kids catalog rails.',
              style: TextStyle(color: krzeneMuted, fontSize: 12),
            ),
            value: kids,
            onChanged: (value) => setState(() => kids = value),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: text.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(
                          context,
                          _ProfileDraft(text.text.trim(), kids),
                        ),
                  child: const Text('Create profile'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
