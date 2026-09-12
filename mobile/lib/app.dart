import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'config.dart';
import 'controller.dart';
import 'design.dart';
import 'models.dart';
import 'player.dart';
import 'ios_navigation.dart';
import 'ios_genre_menu.dart';
import 'ios_search_bar.dart';
import 'welcome.dart';

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

const _providerFallbacks = <WatchProviderShelf>[
  WatchProviderShelf(
    8,
    'Netflix',
    'https://image.tmdb.org/t/p/w154/pbpMk2JmcoNnQwx5JGpXngfoWtp.jpg',
    [],
  ),
  WatchProviderShelf(
    337,
    'Disney+',
    'https://image.tmdb.org/t/p/w154/97yvRBw1GzX7fXprcF80er19ot.jpg',
    [],
  ),
  WatchProviderShelf(
    1899,
    'Max',
    'https://image.tmdb.org/t/p/w154/jbe4gVSfRlbPTdESXhEKpornsfu.jpg',
    [],
  ),
  WatchProviderShelf(
    9,
    'Prime Video',
    'https://image.tmdb.org/t/p/w154/pvske1MyAoymrs5bguRfVqYiM9a.jpg',
    [],
  ),
  WatchProviderShelf(
    350,
    'Apple TV+',
    'https://image.tmdb.org/t/p/w154/2E03IAZsX4ZaUqM7tXlctEPMGWS.jpg',
    [],
  ),
];

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
      child: WelcomeGate(
        builder: (context) => AnimatedBuilder(
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
              child: controller.passwordRecoveryMode
                  ? _ChangePasswordScreen(
                      key: const ValueKey('password-recovery'),
                      controller: controller,
                      passwordRecovery: true,
                    )
                  : controller.signedIn
                  ? HomeShell(
                      key: const ValueKey('home'),
                      controller: controller,
                    )
                  : KrzeneLoginPage(
                      key: const ValueKey('login'),
                      controller: controller,
                    ),
            );
          },
        ),
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
  bool openingApple = false;
  bool submittingEmail = false;
  bool registrationMode = false;
  bool obscurePassword = true;
  bool staySignedIn = true;
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.account.staySignedIn().then((value) {
      if (mounted) setState(() => staySignedIn = value);
    });
  }

  bool get openingAuthentication =>
      openingGoogle || openingApple || submittingEmail;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submitEmail() async {
    if (openingAuthentication) return;
    final name = nameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text;
    final emailLooksValid = RegExp(
      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
    ).hasMatch(email);
    if (registrationMode && (name.length < 2 || name.length > 64)) {
      _showMessage('Enter your name using 2 to 64 characters.', isError: true);
      return;
    }
    if (!emailLooksValid) {
      _showMessage('Enter a valid email address.', isError: true);
      return;
    }
    if (password.length < 8) {
      _showMessage(
        'Password must contain at least 8 characters.',
        isError: true,
      );
      return;
    }
    if (registrationMode && password != confirmPasswordController.text) {
      _showMessage('The passwords do not match.', isError: true);
      return;
    }

    setState(() => submittingEmail = true);
    try {
      await widget.controller.account.setStaySignedIn(staySignedIn);
      if (registrationMode) {
        final result = await widget.controller.account.signUpWithEmail(
          name: name,
          email: email,
          password: password,
        );
        if (result.confirmationRequired && mounted) {
          setState(() {
            registrationMode = false;
            passwordController.clear();
            confirmPasswordController.clear();
          });
          _showMessage(
            'Check ${result.email} and confirm your email, then sign in.',
          );
        }
      } else {
        await widget.controller.account.signInWithEmail(
          email: email,
          password: password,
        );
      }
    } catch (exception) {
      _showSignInError(exception);
    } finally {
      if (mounted) setState(() => submittingEmail = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (openingAuthentication) return;
    setState(() => openingGoogle = true);
    try {
      await widget.controller.account.setStaySignedIn(staySignedIn);
      await widget.controller.account.signInWithGoogle();
    } catch (exception) {
      _showSignInError(exception);
    } finally {
      if (mounted) setState(() => openingGoogle = false);
    }
  }

  Future<void> _signInWithApple() async {
    if (openingAuthentication) return;
    setState(() => openingApple = true);
    try {
      await widget.controller.account.setStaySignedIn(staySignedIn);
      await widget.controller.account.signInWithApple();
    } catch (exception) {
      _showSignInError(exception);
    } finally {
      if (mounted) setState(() => openingApple = false);
    }
  }

  Future<void> _forgotPassword() async {
    final sentTo = await showDialog<String>(
      context: context,
      builder: (_) => _ForgotPasswordDialog(
        initialEmail: emailController.text.trim(),
        onSend: widget.controller.account.requestPasswordReset,
      ),
    );
    if (sentTo != null) {
      _showMessage(
        'If an account exists for $sentTo, a reset link has been sent.',
      );
    }
  }

  void _showSignInError(Object exception) {
    _showMessage(
      exception.toString().replaceFirst('Exception: ', ''),
      isError: true,
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(18),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, height: 1.35),
        ),
        backgroundColor: isError
            ? const Color(0xff541a20)
            : const Color(0xff174d38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _passwordField({required bool confirmation}) => TextField(
    controller: confirmation ? confirmPasswordController : passwordController,
    obscureText: obscurePassword,
    autofillHints: confirmation
        ? null
        : registrationMode
        ? const [AutofillHints.newPassword]
        : const [AutofillHints.password],
    textInputAction: confirmation ? TextInputAction.done : TextInputAction.next,
    onSubmitted: confirmation || !registrationMode
        ? (_) => _submitEmail()
        : null,
    decoration: InputDecoration(
      labelText: confirmation ? 'Confirm password' : 'Password',
      prefixIcon: const Icon(Icons.lock_outline_rounded),
      suffixIcon: confirmation
          ? null
          : IconButton(
              tooltip: obscurePassword ? 'Show password' : 'Hide password',
              onPressed: () =>
                  setState(() => obscurePassword = !obscurePassword),
              icon: Icon(
                obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          // No scrolling when the page fits; keep fields reachable with the
          // keyboard open, larger accessibility text, or a smaller display.
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 32).clamp(
                0.0,
                double.infinity,
              ),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 450),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const KrzeneMark(size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Welcome to Krzene',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          for (final mode in const [false, true])
                            Expanded(
                              child: TextButton(
                                onPressed: openingAuthentication
                                    ? null
                                    : () => setState(() {
                                        registrationMode = mode;
                                        passwordController.clear();
                                        confirmPasswordController.clear();
                                      }),
                                style: TextButton.styleFrom(
                                  backgroundColor: registrationMode == mode
                                      ? Colors.white12
                                      : Colors.transparent,
                                  foregroundColor: registrationMode == mode
                                      ? Colors.white
                                      : krzeneMuted,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: Text(
                                  mode ? 'Create account' : 'Sign in',
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    AutofillGroup(
                      child: Column(
                        children: [
                          if (registrationMode) ...[
                            TextField(
                              controller: nameController,
                              autofillHints: const [AutofillHints.name],
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Name',
                                prefixIcon: Icon(Icons.person_outline_rounded),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          TextField(
                            controller: emailController,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            autofillHints: const [AutofillHints.email],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.mail_outline_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _passwordField(confirmation: false),
                          if (registrationMode) ...[
                            const SizedBox(height: 12),
                            _passwordField(confirmation: true),
                          ],
                          if (!registrationMode) ...[
                            const SizedBox(height: 5),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: openingAuthentication
                                    ? null
                                    : _forgotPassword,
                                child: const Text('Forgot password?'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!registrationMode)
                      CheckboxListTile(
                        value: staySignedIn,
                        onChanged: openingAuthentication
                            ? null
                            : (value) =>
                                  setState(() => staySignedIn = value ?? false),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text(
                          'Stay signed in',
                          style: TextStyle(fontSize: 14),
                        ),
                        subtitle: const Text(
                          'Keep this device signed in after closing Krzene.',
                          style: TextStyle(color: krzeneMuted, fontSize: 11),
                        ),
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: openingAuthentication ? null : _submitEmail,
                        icon: submittingEmail
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : Icon(
                                registrationMode
                                    ? Icons.person_add_alt_1_rounded
                                    : Icons.login_rounded,
                              ),
                        label: Text(
                          registrationMode
                              ? 'Create account'
                              : 'Sign in with email',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Row(
                      children: [
                        Expanded(child: Divider(color: Colors.white12)),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'OR',
                            style: TextStyle(
                              color: Color(0xff77736e),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: Colors.white12)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: openingAuthentication
                            ? null
                            : _signInWithGoogle,
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
                              : const FittedBox(
                                  key: ValueKey('google'),
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _GoogleBadge(),
                                      SizedBox(width: 11),
                                      Text('Continue with Google'),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                    ),
                    if (Platform.isIOS) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: openingAuthentication
                              ? null
                              : _signInWithApple,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                          ),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _AppleBadge(),
                                SizedBox(width: 11),
                                Text('Continue with Apple'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
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
        ),
      ),
    ),
  );
}

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({
    required this.initialEmail,
    required this.onSend,
  });

  final String initialEmail;
  final Future<void> Function(String email) onSend;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final TextEditingController emailController;
  bool sending = false;
  String? error;

  @override
  void initState() {
    super.initState();
    emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = emailController.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      sending = true;
      error = null;
    });
    try {
      await widget.onSend(email);
      if (mounted) Navigator.pop(context, email);
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        sending = false;
        error = exception.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Reset password'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Enter your email and we’ll send a secure reset link.',
          style: TextStyle(color: krzeneMuted, height: 1.45),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          autofocus: true,
          onSubmitted: sending ? null : (_) => _send(),
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.mail_outline_rounded),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            style: const TextStyle(color: Color(0xffff8b93), fontSize: 12),
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: sending ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: sending ? null : _send,
        child: sending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black,
                ),
              )
            : const Text('Send reset link'),
      ),
    ],
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller, this.initialIndex = 0});
  final KrzeneController controller;
  final int initialIndex;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int index;
  String? browseGenre;
  int? browseProviderId;
  bool headerVisible = true;
  double headerScrollTravel = 0;
  double featureHeight = 530;
  final featureKey = GlobalKey();

  bool _handlePageScroll(int pageIndex, ScrollNotification notification) {
    if (pageIndex != index ||
        index == 1 ||
        notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical ||
        notification is! ScrollUpdateNotification) {
      return false;
    }
    final delta = notification.scrollDelta ?? 0;
    // Ignore iOS overscroll/bounce so it doesn't flicker the header.
    final metrics = notification.metrics;
    if (metrics.pixels < metrics.minScrollExtent ||
        metrics.pixels > metrics.maxScrollExtent) {
      return false;
    }
    final feature = featureKey.currentContext?.findRenderObject();
    if (index == 0 && feature is RenderBox && feature.hasSize) {
      featureHeight = feature.size.height;
    }
    if (metrics.pixels <= metrics.minScrollExtent) {
      _setHeaderVisible(true);
      headerScrollTravel = 0;
      return false;
    }
    if (delta == 0) return false;
    if (headerScrollTravel.sign != delta.sign) headerScrollTravel = 0;
    headerScrollTravel += delta;
    if (delta < 0 && headerScrollTravel <= -8) {
      _setHeaderVisible(true);
    } else if (delta > 0 && headerScrollTravel >= 12) {
      // Browse retains its header while any of the feature is below it.
      final featureVisible = index == 0 && metrics.pixels < featureHeight;
      if (!featureVisible) _setHeaderVisible(false);
    }
    return false;
  }

  void _setHeaderVisible(bool visible) {
    if (headerVisible == visible) return;
    setState(() => headerVisible = visible);
  }

  @override
  void initState() {
    super.initState();
    index = widget.initialIndex.clamp(0, 3);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final browseGenres = _genresFor(_browseMediaFor(controller));
    final activeBrowseGenre = browseGenres.contains(browseGenre)
        ? browseGenre
        : null;
    final pages = [
      BrowsePage(
        controller: controller,
        selectedGenre: activeBrowseGenre,
        selectedProviderId: browseProviderId,
        onProviderSelected: (value) => setState(() => browseProviderId = value),
        featureKey: featureKey,
      ),
      SearchPage(controller: controller),
      LibraryPage(controller: controller),
      KrzeneAccountPage(controller: controller),
    ];
    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(68),
        child: AnimatedSlide(
          key: const Key('catalog-header-motion'),
          offset: headerVisible ? Offset.zero : const Offset(0, -1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: IgnorePointer(
            ignoring: !headerVisible,
            child: ExcludeSemantics(
              excluding: !headerVisible,
              child: AppBar(
                toolbarHeight: 68,
                titleSpacing: 18,
                backgroundColor: index == 0 ? Colors.transparent : Colors.black,
                elevation: 0,
                scrolledUnderElevation: 0,
                surfaceTintColor: Colors.transparent,
                systemOverlayStyle: SystemUiOverlayStyle.light,
                title: const KrzeneLogo(markSize: 38),
                actions: [
                  if (index == 0 && browseGenres.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 18),
                      child: Center(
                        child: Platform.isIOS
                            ? IosGenreMenu(
                                genres: browseGenres,
                                selectedGenre: activeBrowseGenre,
                                onSelected: (value) => setState(() {
                                  browseGenre = value;
                                  headerVisible = true;
                                  headerScrollTravel = 0;
                                }),
                              )
                            : _GenreFilterButton(
                                buttonKey: const Key('browse-genre-filter'),
                                compact: true,
                                genres: browseGenres,
                                selectedGenre: activeBrowseGenre,
                                onSelected: (value) => setState(() {
                                  browseGenre = value;
                                  headerVisible = true;
                                  headerScrollTravel = 0;
                                }),
                              ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
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
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (notification) =>
                              _handlePageScroll(pageIndex, notification),
                          child: pages[pageIndex],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Platform.isIOS
          ? IosNavigation(
              index: index,
              onChanged: (value) => setState(() {
                index = value;
                headerVisible = true;
                headerScrollTravel = 0;
              }),
            )
          : _KrzeneNavigation(
              index: index,
              onChanged: (value) => setState(() {
                index = value;
                headerVisible = true;
                headerScrollTravel = 0;
              }),
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
                size: 23,
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
                  size: 23,
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

List<String> _genresFor(Iterable<Media> media) {
  final genres = <String>{};
  for (final item in media) {
    for (final genre in item.genres) {
      final value = genre.trim();
      if (value.isNotEmpty) genres.add(value);
    }
  }
  return genres.toList()
    ..sort((left, right) => left.toLowerCase().compareTo(right.toLowerCase()));
}

Iterable<Media> _browseMediaFor(KrzeneController controller) sync* {
  final catalog = controller.catalog;
  if (catalog == null) return;
  final kids = controller.kidsMode;
  if (!kids) yield catalog.hero;
  for (final rail in catalog.rails) {
    final isKidsRail = rail.id.startsWith('kids-');
    if (kids != isKidsRail) continue;
    for (final item in rail.items) {
      if (!kids || item.isKidsSafe) yield item;
    }
  }
}

bool _matchesGenre(Media media, String? genre) {
  if (genre == null) return true;
  final selected = genre.trim().toLowerCase();
  return media.genres.any((value) {
    final candidate = value.trim().toLowerCase();
    return candidate == selected ||
        candidate.split('&').any((part) => part.trim() == selected);
  });
}

class _GenreFilterButton extends StatelessWidget {
  const _GenreFilterButton({
    required this.genres,
    required this.selectedGenre,
    required this.onSelected,
    required this.buttonKey,
    this.compact = false,
  });

  final List<String> genres;
  final String? selectedGenre;
  final ValueChanged<String?> onSelected;
  final Key buttonKey;
  final bool compact;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    key: buttonKey,
    tooltip: selectedGenre == null
        ? 'Filter by genre'
        : 'Genre: $selectedGenre',
    initialValue: selectedGenre ?? '',
    onSelected: (value) => onSelected(value.isEmpty ? null : value),
    itemBuilder: (_) => [
      const PopupMenuItem(value: '', child: Text('All genres')),
      for (final genre in genres)
        PopupMenuItem(value: genre, child: Text(genre)),
    ],
    child: Semantics(
      button: true,
      label: selectedGenre == null
          ? 'Filter by genre'
          : 'Genre: $selectedGenre',
      child: Padding(
        // Keep a comfortable tap target around the logo-sized header control.
        padding: EdgeInsets.all(compact ? 5 : 0),
        child: Container(
          constraints: BoxConstraints(
            minWidth: compact ? 38 : 52,
            minHeight: compact ? 38 : 52,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : (selectedGenre == null ? 13 : 14),
            vertical: compact ? 8 : 11,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .76),
            borderRadius: BorderRadius.circular(compact ? 12 : 18),
            border: Border.all(
              color: selectedGenre == null ? Colors.white24 : krzeneGreen,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black45,
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune_rounded,
                size: compact ? 20 : 24,
                color: selectedGenre == null ? Colors.white : krzeneGreen,
              ),
              if (selectedGenre != null && !compact) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 112),
                  child: Text(
                    selectedGenre!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class BrowsePage extends StatelessWidget {
  const BrowsePage({
    super.key,
    required this.controller,
    this.selectedGenre,
    this.selectedProviderId,
    this.onProviderSelected,
    this.featureKey,
  });
  final KrzeneController controller;
  final String? selectedGenre;
  final int? selectedProviderId;
  final ValueChanged<int>? onProviderSelected;
  final Key? featureKey;

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
    final kids = controller.kidsMode;
    final availableRails = catalog.rails
        .where(
          (rail) =>
              kids ? rail.id.startsWith('kids-') : !rail.id.startsWith('kids-'),
        )
        .map(
          (rail) => kids
              ? MediaRail(
                  rail.id,
                  rail.kicker,
                  rail.heading,
                  rail.items
                      .where(
                        (item) =>
                            item.isKidsSafe &&
                            controller.isCineSrcAvailable(item),
                      )
                      .toList(),
                )
              : MediaRail(
                  rail.id,
                  rail.kicker,
                  rail.heading,
                  rail.items.where(controller.isCineSrcAvailable).toList(),
                ),
        )
        .where((rail) => rail.items.isNotEmpty)
        .toList();
    final availableMedia = <Media>[
      if (!kids && controller.isCineSrcAvailable(catalog.hero)) catalog.hero,
      ...availableRails.expand((rail) => rail.items),
    ];
    final genres = _genresFor(availableMedia);
    final activeGenre = genres.contains(selectedGenre) ? selectedGenre : null;
    final rails = availableRails
        .map(
          (rail) => MediaRail(
            rail.id,
            rail.kicker,
            rail.heading,
            rail.items
                .where((item) => _matchesGenre(item, activeGenre))
                .toList(),
          ),
        )
        .where((rail) => rail.items.isNotEmpty)
        .toList();
    final hero = activeGenre == null && !kids
        ? catalog.hero
        : availableMedia
              .where((item) => _matchesGenre(item, activeGenre))
              .firstOrNull;
    final featureItems = <Media>[];
    final featureKeys = <String>{};
    for (final item in [?hero, ...availableMedia]) {
      if (_matchesGenre(item, activeGenre) && featureKeys.add(item.key)) {
        featureItems.add(item);
      }
      if (featureItems.length == 6) break;
    }
    final usesProviderFallback = catalog.watchProviders.isEmpty;
    final providerSource = usesProviderFallback
        ? _providerFallbacks
        : catalog.watchProviders;
    final providers = providerSource
        .map(
          (provider) => WatchProviderShelf(
            provider.id,
            provider.name,
            provider.logo,
            provider.items
                .where(
                  (item) =>
                      (!kids || item.isKidsSafe) &&
                      _matchesGenre(item, activeGenre),
                )
                .toList(),
          ),
        )
        .where((provider) => usesProviderFallback || provider.items.isNotEmpty)
        .toList();
    final activeProvider = providers.firstWhere(
      (provider) => provider.id == selectedProviderId,
      orElse: () =>
          providers.firstOrNull ?? const WatchProviderShelf(0, '', null, []),
    );
    return RefreshIndicator(
      onRefresh: controller.loadCatalog,
      child: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: ListView(
          primary: false,
          padding: EdgeInsets.zero,
          children: [
            SizedBox(
              key: featureKey,
              child: featureItems.isNotEmpty
                  ? _HeroBanner(items: featureItems, controller: controller)
                  : const _KidsCatalogEmpty(),
            ),
            if (controller.signedIn &&
                controller.activeProfile != null &&
                controller.continueWatching.isNotEmpty)
              _ContinueRail(controller: controller),
            if (activeProvider.id != 0)
              _WatchProviderSection(
                providers: providers,
                selected: activeProvider,
                controller: controller,
                onSelected: onProviderSelected ?? (_) {},
              ),
            for (final rail in rails)
              _RailView(rail: rail, controller: controller),
            const SizedBox(height: 112),
          ],
        ),
      ),
    );
  }
}

class _KidsCatalogEmpty extends StatelessWidget {
  const _KidsCatalogEmpty();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 460,
    child: Padding(
      padding: EdgeInsets.fromLTRB(28, 150, 28, 30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.child_care_rounded, size: 48, color: krzeneGreen),
          SizedBox(height: 18),
          Text(
            'Kids catalog unavailable',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 10),
          Text(
            'Krzene will not substitute unrestricted titles. Pull down to try again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: krzeneMuted, height: 1.5),
          ),
        ],
      ),
    ),
  );
}

class _HeroBanner extends StatefulWidget {
  const _HeroBanner({required this.items, required this.controller});
  final List<Media> items;
  final KrzeneController controller;

  @override
  State<_HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<_HeroBanner> {
  int index = 0;

  @override
  void didUpdateWidget(_HeroBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (index >= widget.items.length ||
        !widget.items.any(
          (item) =>
              item.key ==
              oldWidget.items[index.clamp(0, oldWidget.items.length - 1)].key,
        )) {
      index = 0;
    }
  }

  void move(int direction) => setState(() {
    index = (index + direction) % widget.items.length;
    if (index < 0) index += widget.items.length;
  });

  @override
  Widget build(BuildContext context) {
    final media = widget.items[index];
    return SizedBox(
      // The artwork extends beneath the status bar, while the extra height
      // keeps the title and primary action comfortably below the header.
      height: 474 + MediaQuery.paddingOf(context).top,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 420),
            layoutBuilder: (current, previous) =>
                Stack(fit: StackFit.expand, children: [...previous, ?current]),
            child: media.art == null
                ? const ColoredBox(key: ValueKey('empty'), color: Colors.black)
                : Image.network(
                    media.art!,
                    key: ValueKey(media.key),
                    fit: BoxFit.cover,
                  ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: [Color(0x22000000), Color(0xbf070707)],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x18000000),
                  Color(0x05000000),
                  Color(0xe8070707),
                ],
                stops: [0, .55, 1],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'FEATURE FILM',
                        style: TextStyle(color: krzeneGreen),
                      ),
                      TextSpan(
                        text: '  ·  TRENDING NOW',
                        style: TextStyle(color: Colors.white60),
                      ),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .7,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  media.title,
                  style: const TextStyle(
                    fontSize: 38,
                    height: .95,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (media.score > 0)
                      Text(
                        '★ ${media.score.toStringAsFixed(1)}',
                        style: const TextStyle(
                          color: krzeneGreen,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    if (media.year != null) _HeroMeta('${media.year}'),
                    for (final genre in media.genres.take(2)) _HeroMeta(genre),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  media.overview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    height: 1.4,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _watch(context, media, widget.controller),
                    icon: const Icon(Icons.play_arrow_outlined, size: 18),
                    label: const Text('Watch now'),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _CarouselArrow(
                      icon: Icons.chevron_left,
                      onTap: () => move(-1),
                    ),
                    const SizedBox(width: 10),
                    for (var dot = 0; dot < widget.items.length; dot++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: dot == index ? 25 : 5,
                        height: 5,
                        margin: const EdgeInsets.only(right: 5),
                        decoration: BoxDecoration(
                          color: dot == index ? Colors.white : Colors.white38,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    const SizedBox(width: 5),
                    _CarouselArrow(
                      icon: Icons.chevron_right,
                      onTap: () => move(1),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMeta extends StatelessWidget {
  const _HeroMeta(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: Colors.white30),
      borderRadius: BorderRadius.circular(5),
      color: Colors.black26,
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, color: Colors.white70),
      ),
    ),
  );
}

class _CarouselArrow extends StatelessWidget {
  const _CarouselArrow({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.black54,
        border: Border.all(color: Colors.white24),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 18),
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

class _WatchProviderSection extends StatelessWidget {
  const _WatchProviderSection({
    required this.providers,
    required this.selected,
    required this.controller,
    required this.onSelected,
  });
  final List<WatchProviderShelf> providers;
  final WatchProviderShelf selected;
  final KrzeneController controller;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 34),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            'Watch on',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 68,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            scrollDirection: Axis.horizontal,
            itemCount: providers.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final provider = providers[index];
              final active = provider.id == selected.id;
              return InkWell(
                onTap: () => onSelected(provider.id),
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 132,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: active ? Colors.white : const Color(0xff191919),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: active ? Colors.white : Colors.white12,
                    ),
                  ),
                  child: provider.logo == null
                      ? Center(
                          child: Text(
                            provider.name,
                            style: TextStyle(
                              color: active ? Colors.black : Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        )
                      : Image.network(
                          provider.logo!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => Center(
                            child: Text(
                              provider.name,
                              style: TextStyle(
                                color: active ? Colors.black : Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                ),
              );
            },
          ),
        ),
        if (selected.items.isNotEmpty)
          _RailView(
            rail: MediaRail(
              'provider-${selected.id}',
              'STREAMING PICKS',
              'Popular on ${selected.name}',
              selected.items,
            ),
            controller: controller,
          )
        else
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 0),
            child: Text(
              'Provider titles will appear after the catalog service finishes updating.',
              style: TextStyle(color: Colors.white54, height: 1.45),
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
  String? selectedGenre;

  List<Media> get recommendations {
    final catalog = widget.controller.catalog;
    if (catalog == null) return const [];
    final kids = widget.controller.kidsMode;
    final seen = <String>{};
    final items = <Media>[];
    for (final item in [
      if (!kids) ...catalog.hero.recommendations,
      ...catalog.rails
          .where((rail) => !kids || rail.id.startsWith('kids-'))
          .expand((rail) => rail.items),
    ]) {
      if (kids && !item.isKidsSafe) continue;
      if (!widget.controller.isCineSrcAvailable(item)) continue;
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
          kidsOnly: widget.controller.kidsMode,
        );
        if (mounted && currentRequest == requestId) {
          setState(
            () => results = nextResults
                .where(widget.controller.isCineSrcAvailable)
                .toList(),
          );
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
    final unfilteredItems = query.isEmpty ? recommendations : results;
    final availableItems = unfilteredItems
        .where(widget.controller.isCineSrcAvailable)
        .toList();
    final profileSafeItems = widget.controller.kidsMode
        ? availableItems.where((item) => item.isKidsSafe).toList()
        : availableItems;
    final genreSource = <Media>[
      ...recommendations,
      ...results,
    ].where((item) => !widget.controller.kidsMode || item.isKidsSafe);
    final genres = _genresFor(genreSource);
    final activeGenre = genres.contains(selectedGenre) ? selectedGenre : null;
    final displayedItems = profileSafeItems
        .where((item) => _matchesGenre(item, activeGenre))
        .toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(context).top + 12,
        16,
        16,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Platform.isIOS
                    ? IosSearchBar(onChanged: search)
                    : TextField(
                        autofocus: false,
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
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
              ),
              const SizedBox(width: 10),
              _GenreFilterButton(
                buttonKey: const Key('search-genre-filter'),
                genres: genres,
                selectedGenre: activeGenre,
                onSelected: (value) => setState(() => selectedGenre = value),
              ),
            ],
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
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 12),
        ),
        if (controller.continueWatching.isNotEmpty)
          SliverToBoxAdapter(child: _ContinueRail(controller: controller)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 28, 18, 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MY LIST',
                  style: TextStyle(
                    color: krzeneMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Saved titles',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
        ),
        if (controller.library.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              child: Text(
                'Tap + on a title to keep it here.',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 132),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisExtent: 198,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: controller.library.length,
              itemBuilder: (_, index) => _MediaCard(
                media: controller.library[index],
                controller: controller,
                compact: true,
              ),
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
                onTap: () => _selectViewerProfile(context, controller, profile),
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
                        )
                      else if (controller.hasKidsProfile)
                        const Icon(
                          Icons.lock_rounded,
                          size: 12,
                          color: krzeneMuted,
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
    final provider = user.appMetadata['provider'];
    final authProvider = switch (provider) {
      'apple' => 'Apple account',
      'email' => 'Email account',
      _ => 'Google account',
    };

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
                    Row(
                      children: [
                        const Icon(
                          Icons.verified_rounded,
                          size: 15,
                          color: krzeneGreen,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          authProvider,
                          style: const TextStyle(
                            color: krzeneGreen,
                            fontSize: 11,
                          ),
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
                locked: !profile.isKids && controller.hasKidsProfile,
                onTap: () => _selectViewerProfile(context, controller, profile),
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
                ManageProfilesScreen(controller: controller),
              ),
            ),
            _SettingsTile(
              icon: Icons.pin_rounded,
              title: 'Parental PIN',
              subtitle: 'Protect standard profiles from Kids mode',
              onTap: () => _changeParentalPin(context, controller),
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
              subtitle: 'Contact support or delete your account',
              onTap: () => _openAccountPage(
                context,
                _SupportScreen(controller: controller),
              ),
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
            _SettingsTile(
              icon: Icons.copyright_rounded,
              title: 'Copyright & credits',
              subtitle: 'Catalog and playback acknowledgements',
              onTap: () => _openAccountPage(context, const _CreditsScreen()),
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

class _SupportScreen extends StatefulWidget {
  const _SupportScreen({required this.controller});

  final KrzeneController controller;

  @override
  State<_SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<_SupportScreen> {
  static const email = 'support@krzene.site';
  bool _deleting = false;

  Future<void> _deleteAccount() async {
    final provider = widget.controller.account.user?.appMetadata['provider'];
    final usesApple = provider == 'apple';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.delete_forever_rounded,
          color: krzeneRed,
          size: 42,
        ),
        title: const Text('Delete your account?'),
        content: Text(
          'This permanently deletes your Krzene account, profiles, saved '
          'library, and viewing progress. This cannot be undone.'
          '${usesApple ? '\n\nIf you signed in with Apple, you can also remove Krzene from Settings > Apple Account > Sign in with Apple.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: krzeneRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await widget.controller.account.deleteAccount();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_readableError(error))));
    }
  }

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
            const SizedBox(height: 28),
            const Divider(color: Colors.white10),
            const SizedBox(height: 20),
            const Text(
              'Account deletion',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Permanently remove your account and all data connected to it.',
              textAlign: TextAlign.center,
              style: TextStyle(color: krzeneMuted, height: 1.45),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _deleting ? null : _deleteAccount,
                style: OutlinedButton.styleFrom(
                  foregroundColor: krzeneRed,
                  side: BorderSide(color: krzeneRed.withValues(alpha: .55)),
                ),
                icon: _deleting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_forever_rounded, size: 19),
                label: Text(
                  _deleting ? 'Deleting account...' : 'Delete my account',
                ),
              ),
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
          'When you sign in, Krzene uses Supabase to store your account identifier, name, viewer profiles, library, and viewing progress. You can use email and password, Apple, or Google. Krzene never stores your password.',
        ),
        (
          'Service providers',
          'Krzene uses Supabase for authentication and data storage, Apple and Google for optional social sign-in, TMDB for catalog metadata, Watchmode for streaming availability, and third-party playback providers.',
        ),
        (
          'Your choices',
          'You can delete your account and its connected data from Help & support. Contact support@krzene.site to request access or correction of account data.',
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

class _CreditsScreen extends StatelessWidget {
  const _CreditsScreen();

  @override
  Widget build(BuildContext context) => const _AccountSubpage(
    title: 'Copyright & credits',
    child: _LegalCopy(
      sections: [
        (
          'TMDB (The Movie Database)',
          'Catalog metadata and artwork are provided through TMDB. This product uses the TMDB API but is not endorsed or certified by TMDB.\n\nwww.themoviedb.org',
        ),
        (
          'IMDb',
          'IMDb is a trademark of IMDb.com, Inc. IMDb content, where displayed, belongs to IMDb or its respective rights holders. Krzene is not endorsed or certified by IMDb.\n\nwww.imdb.com',
        ),
        (
          'CineSrc',
          'Embedded playback is provided through CineSrc. The CineSrc name and branding belong to their respective owners. This acknowledgement does not imply endorsement or ownership of the films and shows available through the service.\n\ncinesrc.st',
        ),
        (
          'Content ownership',
          'All movie and television titles, posters, artwork, videos, and third-party trademarks belong to their respective rights holders. Krzene does not claim ownership of this content. These credits do not grant permission to use or distribute third-party content.',
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

class ManageProfilesScreen extends StatelessWidget {
  const ManageProfilesScreen({super.key, required this.controller});

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
          const SizedBox(height: 34),
          Text(
            'Account security',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 7),
          const Text(
            'Manage the password used to sign in to Krzene.',
            style: TextStyle(color: krzeneMuted, height: 1.5),
          ),
          const SizedBox(height: 16),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: krzenePanelRaised,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: _SettingsTile(
              icon: Icons.password_rounded,
              title: 'Change password',
              subtitle: controller.account.usesEmailPassword
                  ? 'Update your Krzene email password'
                  : 'Create or update a password for this account',
              onTap: () => _openAccountPage(
                context,
                _ChangePasswordScreen(controller: controller),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ChangePasswordScreen extends StatefulWidget {
  const _ChangePasswordScreen({
    super.key,
    required this.controller,
    this.passwordRecovery = false,
  });

  final KrzeneController controller;
  final bool passwordRecovery;

  @override
  State<_ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<_ChangePasswordScreen> {
  final currentPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  bool obscure = true;
  bool submitting = false;
  String? status;
  bool statusIsError = false;

  bool get requiresCurrentPassword =>
      !widget.passwordRecovery && widget.controller.account.usesEmailPassword;

  @override
  void dispose() {
    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (submitting) return;
    final currentPassword = currentPasswordController.text;
    final newPassword = newPasswordController.text;
    if (requiresCurrentPassword && currentPassword.isEmpty) {
      setState(() {
        status = 'Enter your current password.';
        statusIsError = true;
      });
      return;
    }
    if (newPassword.length < 8) {
      setState(() {
        status = 'Your new password must contain at least 8 characters.';
        statusIsError = true;
      });
      return;
    }
    if (newPassword != confirmPasswordController.text) {
      setState(() {
        status = 'The new passwords do not match.';
        statusIsError = true;
      });
      return;
    }
    if (currentPassword.isNotEmpty && currentPassword == newPassword) {
      setState(() {
        status = 'Choose a password different from your current password.';
        statusIsError = true;
      });
      return;
    }

    setState(() {
      submitting = true;
      status = null;
    });
    try {
      await widget.controller.account.changePassword(
        newPassword: newPassword,
        currentPassword: requiresCurrentPassword ? currentPassword : null,
      );
      currentPasswordController.clear();
      newPasswordController.clear();
      confirmPasswordController.clear();
      if (!mounted) return;
      setState(() {
        status =
            'Password changed successfully. A security notification will be sent to your email.';
        statusIsError = false;
      });
      if (widget.passwordRecovery) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        widget.controller.finishPasswordRecovery();
      }
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        status = exception.toString().replaceFirst('Exception: ', '');
        statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _close() async {
    if (widget.passwordRecovery) {
      widget.controller.finishPasswordRecovery();
      await widget.controller.account.signOut();
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  Widget _passwordField(
    TextEditingController controller,
    String label, {
    TextInputAction action = TextInputAction.next,
  }) => TextField(
    controller: controller,
    obscureText: obscure,
    autocorrect: false,
    enableSuggestions: false,
    textInputAction: action,
    onSubmitted: action == TextInputAction.done ? (_) => _submit() : null,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.lock_outline_rounded),
      suffixIcon: IconButton(
        onPressed: () => setState(() => obscure = !obscure),
        tooltip: obscure ? 'Show passwords' : 'Hide passwords',
        icon: Icon(
          obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.passwordRecovery ? 'Reset password' : 'Change password',
      ),
      backgroundColor: krzeneBackground,
      leading: IconButton(
        onPressed: submitting ? null : _close,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
    ),
    body: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: krzenePanelRaised,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white10),
            ),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const KrzeneMark(size: 48),
                  const SizedBox(height: 24),
                  Text(
                    widget.passwordRecovery
                        ? 'Choose a new password'
                        : 'Protect your account',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 9),
                  Text(
                    requiresCurrentPassword
                        ? 'Enter your current password, then choose a new password with at least 8 characters.'
                        : 'Choose a new password with at least 8 characters.',
                    style: const TextStyle(color: krzeneMuted, height: 1.5),
                  ),
                  const SizedBox(height: 22),
                  if (requiresCurrentPassword) ...[
                    _passwordField(
                      currentPasswordController,
                      'Current password',
                    ),
                    const SizedBox(height: 13),
                  ],
                  _passwordField(newPasswordController, 'New password'),
                  const SizedBox(height: 13),
                  _passwordField(
                    confirmPasswordController,
                    'Confirm new password',
                    action: TextInputAction.done,
                  ),
                  if (status != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      status!,
                      style: TextStyle(
                        color: statusIsError
                            ? const Color(0xffff8b93)
                            : krzeneGreen,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: submitting ? null : _submit,
                      icon: submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Icon(Icons.password_rounded),
                      label: Text(
                        widget.passwordRecovery
                            ? 'Save new password'
                            : 'Change password',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
      [if (active) 'CURRENT', if (profile.isKids) 'KIDS'].join(' · '),
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
    required this.locked,
    required this.onTap,
  });
  final ViewerProfile profile;
  final bool selected;
  final bool locked;
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
            )
          else if (locked)
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_rounded, size: 10, color: krzeneMuted),
                SizedBox(width: 3),
                Text('PIN', style: TextStyle(fontSize: 8, color: krzeneMuted)),
              ],
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

class _AppleBadge extends StatelessWidget {
  const _AppleBadge();

  @override
  Widget build(BuildContext context) => const SizedBox(
    // The package's Apple artwork uses a 25:31 aspect ratio, not a square.
    width: 22 * (25 / 31),
    height: 22,
    child: CustomPaint(painter: AppleLogoPainter(color: Colors.black)),
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
  if (controller.kidsMode && !media.isKidsSafe) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This title is not available in a Kids profile.'),
      ),
    );
    return;
  }
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

Future<void> _selectViewerProfile(
  BuildContext context,
  KrzeneController controller,
  ViewerProfile profile,
) async {
  if (!controller.requiresParentalUnlock(profile)) {
    await controller.selectProfile(profile);
    return;
  }

  final hasPin = await controller.account.hasParentalPin();
  if (!context.mounted) return;
  if (!hasPin) {
    final configured = await _setNewParentalPin(
      context,
      controller,
      title: 'Set a parental PIN',
      message:
          'Create a four-digit PIN before opening standard profiles from Kids mode.',
    );
    if (!configured || !context.mounted) return;
  } else {
    final entered = await _showParentalPinDialog(
      context,
      title: 'Enter parental PIN',
      message: 'Unlock ${profile.name} to leave Kids mode.',
      actionLabel: 'Unlock profile',
    );
    if (entered == null || !context.mounted) return;
    if (!await controller.account.verifyParentalPin(entered)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That parental PIN is incorrect.')),
      );
      return;
    }
  }

  await controller.selectProfile(profile, parentalUnlock: true);
}

Future<void> _changeParentalPin(
  BuildContext context,
  KrzeneController controller,
) async {
  final hasPin = await controller.account.hasParentalPin();
  if (!context.mounted) return;
  if (hasPin) {
    final current = await _showParentalPinDialog(
      context,
      title: 'Current parental PIN',
      message: 'Enter the current PIN before replacing it.',
      actionLabel: 'Continue',
    );
    if (current == null || !context.mounted) return;
    if (!await controller.account.verifyParentalPin(current)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That parental PIN is incorrect.')),
      );
      return;
    }
  }

  if (!context.mounted) return;
  final saved = await _setNewParentalPin(
    context,
    controller,
    title: hasPin ? 'Choose a new PIN' : 'Set a parental PIN',
    message: 'This four-digit PIN unlocks standard profiles from Kids mode.',
  );
  if (!saved || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(hasPin ? 'Parental PIN updated.' : 'Parental PIN enabled.'),
    ),
  );
}

Future<bool> _setNewParentalPin(
  BuildContext context,
  KrzeneController controller, {
  required String title,
  required String message,
}) async {
  final pin = await _showParentalPinDialog(
    context,
    title: title,
    message: message,
    actionLabel: 'Save PIN',
    confirmPin: true,
  );
  if (pin == null) return false;
  await controller.account.setParentalPin(pin);
  return true;
}

Future<String?> _showParentalPinDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
  bool confirmPin = false,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ParentalPinDialog(
    title: title,
    message: message,
    actionLabel: actionLabel,
    confirmPin: confirmPin,
  ),
);

class _ParentalPinDialog extends StatefulWidget {
  const _ParentalPinDialog({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.confirmPin,
  });

  final String title;
  final String message;
  final String actionLabel;
  final bool confirmPin;

  @override
  State<_ParentalPinDialog> createState() => _ParentalPinDialogState();
}

class _ParentalPinDialogState extends State<_ParentalPinDialog> {
  final pin = TextEditingController();
  final confirmation = TextEditingController();
  String? error;

  @override
  void dispose() {
    pin.dispose();
    confirmation.dispose();
    super.dispose();
  }

  void submit() {
    if (!RegExp(r'^\d{4}$').hasMatch(pin.text)) {
      setState(() => error = 'Enter exactly four numbers.');
      return;
    }
    if (widget.confirmPin && confirmation.text != pin.text) {
      setState(() => error = 'The PINs do not match.');
      return;
    }
    Navigator.pop(context, pin.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.lock_rounded, color: krzeneRed, size: 38),
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: krzeneMuted, height: 1.45),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: pin,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          textInputAction: widget.confirmPin
              ? TextInputAction.next
              : TextInputAction.done,
          maxLength: 4,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() => error = null),
          onSubmitted: (_) {
            if (!widget.confirmPin) submit();
          },
          decoration: const InputDecoration(
            labelText: '4-digit PIN',
            counterText: '',
          ),
        ),
        if (widget.confirmPin) ...[
          const SizedBox(height: 12),
          TextField(
            controller: confirmation,
            obscureText: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLength: 4,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() => error = null),
            onSubmitted: (_) => submit(),
            decoration: const InputDecoration(
              labelText: 'Confirm PIN',
              counterText: '',
            ),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(
            error!,
            style: const TextStyle(color: Color(0xffff8b93), fontSize: 12),
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: submit, child: Text(widget.actionLabel)),
    ],
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
