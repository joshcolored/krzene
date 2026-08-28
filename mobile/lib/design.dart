import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

const krzeneBackground = Color(0xff070707);
const krzenePanel = Color(0xff111111);
const krzenePanelRaised = Color(0xff181818);
const krzeneText = Color(0xfff7f4ef);
const krzeneMuted = Color(0xff9b9995);
const krzeneRed = Color(0xffe21927);
const krzeneGreen = Color(0xff47c98d);

enum KrzeneGlyph { home, search, library, profile, language }

class KrzeneIcon extends StatelessWidget {
  const KrzeneIcon(
    this.glyph, {
    super.key,
    this.size = 22,
    this.color = krzeneText,
  });
  final KrzeneGlyph glyph;
  final double size;
  final Color color;

  String get _content => switch (glyph) {
    KrzeneGlyph.home =>
      '''
          <path d='M3.5 10.5 12 3.8l8.5 6.7'/>
          <path d='M5.7 9.2v10.5h12.6V9.2M9.3 19.7v-6h5.4v6'/>
        ''',
    KrzeneGlyph.search =>
      '''
          <circle cx='10.5' cy='10.5' r='6.5'/>
          <path d='m15.4 15.4 4.6 4.6'/>
        ''',
    KrzeneGlyph.library =>
      '''
          <rect x='4' y='4' width='5' height='16' rx='1'/>
          <rect x='10.2' y='4' width='4.8' height='16' rx='1'/>
          <path d='m16.3 5.1 3.2-.8 2.8 14.3-3.2.7-2.8-14.2Z'/>
        ''',
    KrzeneGlyph.profile =>
      '''
          <circle cx='12' cy='8' r='3.5'/>
          <path d='M5.2 20c.5-4 2.8-6 6.8-6s6.3 2 6.8 6'/>
        ''',
    KrzeneGlyph.language =>
      '''
          <circle cx='12' cy='12' r='8.5'/>
          <path d='M3.8 12h16.4M12 3.5c2.2 2.3 3.3 5.1 3.3 8.5S14.2 18.2 12 20.5M12 3.5C9.8 5.8 8.7 8.6 8.7 12s1.1 6.2 3.3 8.5'/>
        ''',
  };

  @override
  Widget build(BuildContext context) => SvgPicture.string(
    '''
        <svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'
          fill='none' stroke='#ffffff' stroke-width='1.8'
          stroke-linecap='round' stroke-linejoin='round'>
          $_content
        </svg>
        ''',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
  );
}

ThemeData krzeneTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: krzeneBackground,
    colorScheme: const ColorScheme.dark(
      primary: krzeneRed,
      secondary: krzeneGreen,
      surface: krzenePanel,
      onSurface: krzeneText,
    ),
  );
  final body = GoogleFonts.dmSansTextTheme(
    base.textTheme,
  ).apply(bodyColor: krzeneText, displayColor: krzeneText);
  return base.copyWith(
    textTheme: body.copyWith(
      headlineLarge: GoogleFonts.manrope(
        fontSize: 42,
        height: .98,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.8,
      ),
      headlineMedium: GoogleFonts.manrope(
        fontSize: 29,
        height: 1.05,
        fontWeight: FontWeight.w800,
        letterSpacing: -1,
      ),
      titleLarge: GoogleFonts.manrope(
        fontSize: 21,
        fontWeight: FontWeight.w800,
        letterSpacing: -.4,
      ),
      titleMedium: GoogleFonts.manrope(fontWeight: FontWeight.w700),
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: Color(0xf2070707),
      foregroundColor: krzeneText,
      surfaceTintColor: Colors.transparent,
    ),
    dividerColor: Colors.white.withValues(alpha: .08),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: krzenePanelRaised,
      hintStyle: const TextStyle(color: Color(0xff77736e)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Colors.white10),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: krzeneRed, width: 1.3),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: krzeneText,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: krzeneText,
        side: const BorderSide(color: Colors.white12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: krzenePanel,
      modalBackgroundColor: krzenePanel,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: Colors.white24,
    ),
  );
}

class KrzeneMark extends StatelessWidget {
  const KrzeneMark({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      boxShadow: [
        BoxShadow(color: Color(0x35e21927), blurRadius: 22, spreadRadius: 1),
      ],
    ),
    child: SvgPicture.asset(
      'assets/brand/krzene-mark.svg',
      width: size,
      height: size,
    ),
  );
}

class KrzeneLogo extends StatelessWidget {
  const KrzeneLogo({super.key, this.markSize = 38});
  final double markSize;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      KrzeneMark(size: markSize),
      SizedBox(width: markSize * .28),
      Text(
        'krzene',
        style: GoogleFonts.manrope(
          color: krzeneText,
          fontSize: markSize * .47,
          fontWeight: FontWeight.w800,
          letterSpacing: -.8,
        ),
      ),
    ],
  );
}

class KrzeneLaunchGate extends StatefulWidget {
  const KrzeneLaunchGate({super.key, required this.child});
  final Widget child;

  @override
  State<KrzeneLaunchGate> createState() => _KrzeneLaunchGateState();
}

class _KrzeneLaunchGateState extends State<KrzeneLaunchGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation;
  late final Animation<double> scale;
  Timer? timer;
  bool complete = false;

  @override
  void initState() {
    super.initState();
    animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
    scale = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
    timer = Timer(const Duration(milliseconds: 1550), () {
      if (mounted) setState(() => complete = true);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 480),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    child: complete
        ? widget.child
        : ColoredBox(
            key: const ValueKey('launch'),
            color: krzeneBackground,
            child: Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: 210,
                child: FadeTransition(
                  opacity: CurvedAnimation(
                    parent: animation,
                    curve: const Interval(0, .65, curve: Curves.easeOut),
                  ),
                  child: ScaleTransition(
                    scale: Tween(begin: .72, end: 1.0).animate(scale),
                    child: SvgPicture.asset(
                      'assets/brand/krzene-logo.svg',
                      width: double.infinity,
                      semanticsLabel: 'Krzene',
                    ),
                  ),
                ),
              ),
            ),
          ),
  );
}
