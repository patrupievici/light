// Zvelt — Onboarding 2 · ACT 1 (Hook & Sign-in). Screens 0–4.
//
// Faithful 1:1 Flutter port of the design bundle's `onboarding-screens-1.jsx`
// (ScrSplash · ScrProblem · ScrPromise · ScrSocialProof · ScrAuth), built on
// ZveltTokens / ZType + the foundation kit (OnbShell / OnbHead / OnbField /
// SelectCard / OnbPrimaryButton).
//
// ScrAuth is FUNCTIONAL: it calls AuthService().signup / login /
// loginWithGoogle (same contract as login_screen.dart) and only advances on
// success. Apple sign-in is suppressed on Android (per [isAndroid]).

part of 'onboarding2.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Local helpers — small visual primitives ported from ui.jsx (Avatar / GoogleG
// / SocialAuthBtn) + a brand-halo pulse used on the splash. Kept private to the
// intro act; the shared kit lives in onboarding2.dart.
// ─────────────────────────────────────────────────────────────────────────────

/// Wordmark logo asset (the design bundle's `assets/logo-wordmark.png`).
const String _kLogoWordmark = 'assets/images/welcome_wordmark.png';

/// Initials avatar with the brand gradient fill + optional conic ring.
/// JSX `Avatar`.
class _IntroAvatar extends StatelessWidget {
  const _IntroAvatar({
    required this.initials,
    this.size = 42,
    this.accent = true,
    this.ringBorder = false,
  });

  final String initials;
  final double size;
  final bool accent;

  /// Surface-colored ring (the overlapping-stack look in ScrSocialProof).
  final bool ringBorder;

  @override
  Widget build(BuildContext context) {
    final circle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: accent ? ZveltTokens.gradBrand : null,
        color: accent ? null : ZveltTokens.surface3,
      ),
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: ZveltTokens.fontPrimary,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.4,
          color: accent ? Colors.white : ZveltTokens.text,
        ),
      ),
    );
    if (!ringBorder) return circle;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ZveltTokens.surface,
      ),
      padding: const EdgeInsets.all(3),
      child: circle,
    );
  }
}

/// Standard multi-color Google "G" mark — the official sign-in asset, rendered
/// 1:1 from the design bundle's inline SVG (see onboarding-screens-1.jsx).
class _GoogleG extends StatelessWidget {
  const _GoogleG();

  static const double _size = 18;

  static const String _svg = '''
<svg width="48" height="48" viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">
<path fill="#4285F4" d="M45 24c0-1.6-.1-2.8-.4-4H24v7.6h12c-.2 2-1.6 5-4.6 7l7 5.4C42.5 42 45 33.9 45 24z"/>
<path fill="#34A853" d="M24 46c6 0 11-2 14.6-5.4l-7-5.4c-2 1.3-4.5 2.1-7.6 2.1-5.8 0-10.7-3.9-12.5-9.2l-7.3 5.6C7.7 41 15.2 46 24 46z"/>
<path fill="#FBBC05" d="M11.5 28.1c-.5-1.4-.7-2.9-.7-4.1s.3-2.8.7-4.1l-7.3-5.7C2.8 17 2 20.4 2 24s.8 7 2.2 9.8l7.3-5.7z"/>
<path fill="#EA4335" d="M24 10.7c3.3 0 6.2 1.1 8.5 3.3l6.3-6.3C35 4 30 2 24 2 15.2 2 7.7 7 4.2 14.2l7.3 5.7C13.3 14.6 18.2 10.7 24 10.7z"/>
</svg>''';

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(_svg, width: _size, height: _size);
  }
}

/// Full-width OAuth button — light (Google) or dark (Apple). JSX `SocialAuthBtn`.
class _SocialAuthBtn extends StatelessWidget {
  const _SocialAuthBtn({
    required this.label,
    required this.leading,
    required this.onTap,
    this.dark = false,
    this.enabled = true,
  });

  final String label;
  final Widget leading;
  final VoidCallback onTap;
  final bool dark;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onTap();
              }
            : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: enabled ? 1 : 0.55,
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF0A0A0C) : ZveltTokens.surface,
              borderRadius: BorderRadius.circular(ZveltTokens.rPill),
              border: Border.all(
                color: dark ? const Color(0xFF0A0A0C) : ZveltTokens.borderStrong,
              ),
              boxShadow: ZveltTokens.shadowCard,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                leading,
                const SizedBox(width: ZveltTokens.s3),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: dark ? Colors.white : ZveltTokens.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "or continue with" hairline divider. JSX divider row in ScrAuth.
class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s5),
      child: Row(
        children: [
          Expanded(child: Divider(color: ZveltTokens.border, height: 1)),
          const SizedBox(width: ZveltTokens.s3),
          const OnbEyebrow('or continue with'),
          const SizedBox(width: ZveltTokens.s3),
          Expanded(child: Divider(color: ZveltTokens.border, height: 1)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 00 · ScrSplash — brand reveal. No header, no scroll, centered, brand halo.
// ─────────────────────────────────────────────────────────────────────────────
class ScrSplash extends StatefulWidget {
  const ScrSplash({super.key, required this.args});
  final OnbScreenArgs args;

  @override
  State<ScrSplash> createState() => _ScrSplashState();
}

class _ScrSplashState extends State<ScrSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OnbShell(
      scroll: false,
      footer: OnbPrimaryButton(label: 'Get started', onTap: widget.args.next),
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Brand halo — pulsing radial glow behind the wordmark.
            FadeTransition(
              opacity: Tween<double>(begin: 0.45, end: 1.0).animate(
                CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
              ),
              child: Container(
                width: 320,
                height: 320,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [ZveltTokens.brandGlow, Color(0x00FF7A2F)],
                    stops: [0.0, 0.65],
                  ),
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  label: 'Zvelt',
                  image: true,
                  child: Image.asset(
                    _kLogoWordmark,
                    height: 64,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: ZveltTokens.s4),
                Text(
                  'Train · Fuel · Evolve',
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontSize: 14,
                    color: ZveltTokens.text,
                    letterSpacing: 0.56,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 01 · ScrProblem — five apps, zero clarity. Old way vs With Zvelt.
// ─────────────────────────────────────────────────────────────────────────────
class ScrProblem extends StatelessWidget {
  const ScrProblem({super.key, required this.args});
  final OnbScreenArgs args;

  static const _oldApps = [
    'Workout log',
    'Calorie app',
    'Sleep tracker',
    'Group chat',
    'Spreadsheet',
  ];
  static const _pillars = [
    AppIcons.gym,
    AppIcons.restaurant,
    AppIcons.heart,
    AppIcons.globe,
  ];

  @override
  Widget build(BuildContext context) {
    return OnbShell(
      onBack: args.back,
      footer: OnbPrimaryButton(label: 'I want this', onTap: args.next),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OnbHead(
            eyebrow: 'The problem',
            title: 'Five apps. Zero clarity.',
            sub: 'Your training, food, recovery and community live in different '
                'places that never talk to each other.',
          ),
          // The old way — disconnected chips.
          Container(
            padding: const EdgeInsets.all(ZveltTokens.s4),
            decoration: BoxDecoration(
              color: ZveltTokens.bg2,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const OnbEyebrow('The old way'),
                const SizedBox(height: ZveltTokens.s3),
                Wrap(
                  spacing: ZveltTokens.s2,
                  runSpacing: ZveltTokens.s2,
                  children: [
                    for (final t in _oldApps)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: ZveltTokens.s3, vertical: 6),
                        decoration: BoxDecoration(
                          color: ZveltTokens.surface,
                          borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                        ),
                        child: Text(
                          t,
                          style: TextStyle(
                            fontFamily: ZveltTokens.fontPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: ZveltTokens.text3,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: ZveltTokens.s3),
                Text(
                  'Disconnected data. No insight. Easy to quit.',
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontSize: 12.5,
                    height: 1.5,
                    color: ZveltTokens.text3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: ZveltTokens.s3),
          // With Zvelt — one system, brand border.
          Container(
            padding: const EdgeInsets.all(ZveltTokens.s4),
            decoration: BoxDecoration(
              color: ZveltTokens.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: ZveltTokens.brand, width: 2),
              boxShadow: ZveltTokens.shadowCard,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const OnbEyebrow('With Zvelt', color: ZveltTokens.brandDeep),
                const SizedBox(height: ZveltTokens.s3),
                Row(
                  children: [
                    for (final ic in _pillars) ...[
                      OnbTileIcon(
                          icon: ic, size: 40, iconSize: 20),
                      const SizedBox(width: ZveltTokens.s2),
                    ],
                    Icon(AppIcons.arrow_small_right,
                        size: 16, color: ZveltTokens.text3),
                    const SizedBox(width: ZveltTokens.s2),
                    Flexible(
                      child: Text(
                        'One system',
                        style: TextStyle(
                          fontFamily: ZveltTokens.fontPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: ZveltTokens.text,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ZveltTokens.s3),
                Text(
                  'Everything connected, learning from you, in one place.',
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontSize: 12.5,
                    height: 1.5,
                    color: ZveltTokens.text2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 02 · ScrPromise — one app, four pillars (2×2 grid).
// ─────────────────────────────────────────────────────────────────────────────
class _Pillar {
  const _Pillar(this.icon, this.title, this.sub, this.color, this.bg);
  final IconData icon;
  final String title;
  final String sub;
  final Color color;
  final Color bg;
}

class ScrPromise extends StatelessWidget {
  const ScrPromise({super.key, required this.args});
  final OnbScreenArgs args;

  static final _pillars = [
    _Pillar(AppIcons.globe, 'Social', 'Train together',
        ZveltTokens.brand, ZveltTokens.brandTint),
    const _Pillar(AppIcons.restaurant, 'Nutrition', 'Fuel smarter',
        ZveltTokens.strength, ZveltTokens.strength2),
    const _Pillar(AppIcons.sparkles, 'AI Coach', 'In your pocket',
        ZveltTokens.recovery, ZveltTokens.recovery2),
    const _Pillar(AppIcons.heart, 'Tracking', 'See progress',
        ZveltTokens.sleep, ZveltTokens.sleep2),
  ];

  @override
  Widget build(BuildContext context) {
    return OnbShell(
      onBack: args.back,
      footer: OnbPrimaryButton(label: 'Show me how', onTap: args.next),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OnbHead(
            eyebrow: 'The promise',
            title: 'One app. Four pillars.',
            sub: 'Zvelt unifies the whole picture — and an AI coach connects '
                'the dots for you.',
          ),
          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: ZveltTokens.s3,
            crossAxisSpacing: ZveltTokens.s3,
            childAspectRatio: 1.18,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final p in _pillars)
                Container(
                  padding: const EdgeInsets.all(ZveltTokens.s4),
                  decoration: BoxDecoration(
                    color: ZveltTokens.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: ZveltTokens.shadowCard,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OnbTileIcon(
                          icon: p.icon,
                          color: p.color,
                          bg: p.bg,
                          size: 46,
                          iconSize: 23),
                      const Spacer(),
                      Text(
                        p.title,
                        style: TextStyle(
                          fontFamily: ZveltTokens.fontPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: ZveltTokens.text,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        p.sub,
                        style: TextStyle(
                          fontFamily: ZveltTokens.fontPrimary,
                          fontSize: 12,
                          color: ZveltTokens.text3,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 03 · ScrSocialProof — stacked avatars + stat row + testimonial.
// ─────────────────────────────────────────────────────────────────────────────
class ScrSocialProof extends StatelessWidget {
  const ScrSocialProof({super.key, required this.args});
  final OnbScreenArgs args;

  static const _initials = ['L', 'A', 'Y', 'M', 'R'];
  static const _stats = [
    ('248k', 'Members'),
    ('12.4M', 'Workouts'),
    ('4.9', 'App rating'),
  ];

  @override
  Widget build(BuildContext context) {
    return OnbShell(
      onBack: args.back,
      footer: OnbPrimaryButton(label: 'Join them', onTap: args.next),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OnbHead(
            eyebrow: 'The community',
            title: "You won't train alone.",
            sub: 'A quarter of a million people show up every day — and so '
                'will you.',
          ),
          // Avatar stack + stats card.
          Container(
            padding: const EdgeInsets.all(ZveltTokens.s5),
            decoration: BoxDecoration(
              color: ZveltTokens.surface,
              borderRadius: BorderRadius.circular(ZveltTokens.rLg),
              boxShadow: ZveltTokens.shadowCard,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    SizedBox(
                      height: 48,
                      width: 48.0 + (_initials.length - 1) * 30,
                      child: Stack(
                        children: [
                          for (var i = 0; i < _initials.length; i++)
                            Positioned(
                              left: i * 30.0,
                              child: _IntroAvatar(
                                initials: _initials[i],
                                size: 42,
                                accent: i.isEven,
                                ringBorder: true,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: ZveltTokens.s3),
                    Flexible(
                      child: Text(
                        '+248k training now',
                        style: TextStyle(
                          fontFamily: ZveltTokens.fontPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: ZveltTokens.text2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ZveltTokens.s4),
                Divider(color: ZveltTokens.border, height: 1),
                const SizedBox(height: ZveltTokens.s4),
                Row(
                  children: [
                    for (final s in _stats)
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              s.$1,
                              style: ZType.stat.copyWith(fontSize: 24),
                            ),
                            const SizedBox(height: 5),
                            OnbEyebrow(s.$2),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: ZveltTokens.s3),
          // Testimonial.
          Container(
            padding: const EdgeInsets.all(ZveltTokens.s4),
            decoration: BoxDecoration(
              color: ZveltTokens.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: ZveltTokens.shadowCard,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _IntroAvatar(initials: 'Y', size: 40),
                const SizedBox(width: ZveltTokens.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '"Hit my first 100kg bench with my Zvelt crew '
                        'cheering."',
                        style: TextStyle(
                          fontFamily: ZveltTokens.fontPrimary,
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: ZveltTokens.text,
                        ),
                      ),
                      const SizedBox(height: ZveltTokens.s1),
                      Text(
                        'Yusuf · 14-week streak',
                        style: TextStyle(
                          fontFamily: ZveltTokens.fontPrimary,
                          fontSize: 11,
                          color: ZveltTokens.text3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 04 · ScrAuth — login / sign-up. FUNCTIONAL: AuthService email/password +
// Google. Auth lives INSIDE the flow; advances only on success. Apple is shown
// on iOS only (suppressed on Android) and routed through the same OAuth path —
// real Apple sign-in is wired by the platform integration layer later.
// ─────────────────────────────────────────────────────────────────────────────
class ScrAuth extends StatefulWidget {
  const ScrAuth({super.key, required this.args});
  final OnbScreenArgs args;

  @override
  State<ScrAuth> createState() => _ScrAuthState();
}

enum _AuthMode { signup, login }

class _ScrAuthState extends State<ScrAuth> {
  final AuthService _auth = AuthService();
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  _AuthMode _mode = _AuthMode.signup;
  bool _loading = false;
  String? _error;

  OnbData get _data => widget.args.data;

  static final RegExp _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  // The auth screen keeps its credentials LOCAL (never persisted to the resume
  // snapshot) so passwords don't get written to SharedPreferences.
  String _emailField = '';
  String _passField = '';

  bool get _emailValid => _emailRe.hasMatch(_emailField.trim());
  bool get _passValid => _passField.length >= 6;
  bool get _ready => _emailValid && _passValid && !_loading;

  void _setMode(_AuthMode m) {
    HapticFeedback.selectionClick();
    setState(() {
      _mode = m;
      _error = null;
    });
  }

  String _friendlyError(Object e) {
    final msg = e.toString().replaceFirst('Exception: ', '');
    return authErrorToEnglish(msg);
  }

  /// After a successful auth: a RETURNING user who already completed onboarding
  /// (new key or legacy v3/v2, per-user) skips straight into the app; a new
  /// account continues into personalization.
  Future<void> _afterAuth() async {
    if (!mounted) return;
    try {
      final uid = await _auth.getStoredUserId();
      final suffix = (uid == null || uid.isEmpty) ? 'guest' : uid;
      final prefs = await SharedPreferences.getInstance();
      final done = (prefs.getBool('${kOnboarding2CompletedKey}_$suffix') ?? false) ||
          (prefs.getBool('onboarding_v3_completed_$suffix') ?? false) ||
          (prefs.getBool('zvelt_onboarding_v2_completed_$suffix') ?? false);
      if (!mounted) return;
      done ? widget.args.complete() : widget.args.next();
    } catch (_) {
      if (mounted) widget.args.next();
    }
  }

  Future<void> _submitEmail() async {
    if (!_emailValid || !_passValid) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final email = _emailField.trim();
      if (_mode == _AuthMode.signup) {
        await _auth.signup(
          email: email,
          password: _passField,
          displayName: _data.name.trim().isEmpty ? null : _data.name.trim(),
        );
      } else {
        await _auth.login(email, _passField);
      }
      if (!mounted) return;
      await _afterAuth();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _loading = false;
      });
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        // User dismissed the Google sheet — not an error.
        if (mounted) setState(() => _loading = false);
        return;
      }
      final googleAuth = await account.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        throw Exception('Google sign-in failed. Try again.');
      }
      await _auth.loginWithGoogle(idToken);
      if (!mounted) return;
      await _afterAuth();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _loading = false;
      });
    }
  }

  void _appleSignIn() {
    // Real Apple sign-in is provided by the platform integration layer; the
    // button is iOS-only and currently surfaces a friendly notice so the user
    // is never left tapping a dead control.
    HapticFeedback.selectionClick();
    setState(() => _error = 'Apple sign-in is coming soon — use email '
        'or Google for now.');
  }

  @override
  Widget build(BuildContext context) {
    final isSignup = _mode == _AuthMode.signup;
    return OnbShell(
      onBack: widget.args.back,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OnbPrimaryButton(
            label: isSignup ? 'Create account' : 'Log in',
            busy: _loading,
            onTap: _ready ? _submitEmail : null,
          ),
          const SizedBox(height: ZveltTokens.s3),
          _ModeToggle(
            prompt:
                isSignup ? 'Already have an account? ' : 'New to Zvelt? ',
            action: isSignup ? 'Log in' : 'Sign up',
            onTap: () =>
                _setMode(isSignup ? _AuthMode.login : _AuthMode.signup),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: ZveltTokens.s4),
              child: Semantics(
                label: 'Zvelt',
                image: true,
                child: Image.asset(_kLogoWordmark, height: 40),
              ),
            ),
          ),
          OnbHead(
            eyebrow: isSignup ? 'Create your account' : 'Welcome back',
            title: isSignup ? 'Start your journey.' : 'Log in.',
            sub: isSignup
                ? 'Sign up with your email — or continue in one tap.'
                : 'Good to see you again.',
          ),
          OnbField(
            label: 'Email',
            value: _emailField,
            onChanged: (v) {
              setState(() {
                _emailField = v;
                _error = null;
              });
            },
            placeholder: 'you@email.com',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: ZveltTokens.s3),
          OnbField(
            label: 'Password',
            value: _passField,
            onChanged: (v) {
              setState(() {
                _passField = v;
                _error = null;
              });
            },
            placeholder: 'At least 6 characters',
            obscure: true,
            hint: (_passField.isNotEmpty && !_passValid)
                ? 'Password needs at least 6 characters.'
                : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: ZveltTokens.s3),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(ZveltTokens.s3),
              decoration: BoxDecoration(
                color: ZveltTokens.error.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(ZveltTokens.rMd),
              ),
              child: Text(
                _error!,
                style: const TextStyle(
                  fontFamily: ZveltTokens.fontPrimary,
                  fontSize: 12.5,
                  height: 1.4,
                  color: ZveltTokens.error,
                ),
              ),
            ),
          ],
          const _OrDivider(),
          _SocialAuthBtn(
            label: 'Continue with Google',
            leading: const _GoogleG(),
            enabled: !_loading,
            onTap: _signInWithGoogle,
          ),
          if (!isAndroid) ...[
            const SizedBox(height: ZveltTokens.s3),
            _SocialAuthBtn(
              label: 'Continue with Apple',
              dark: true,
              enabled: !_loading,
              leading: const Icon(Icons.apple, size: 20, color: Colors.white),
              onTap: _appleSignIn,
            ),
          ],
          const SizedBox(height: ZveltTokens.s5),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3),
            child: Text(
              "By continuing you agree to Zvelt's Terms of Service & "
              'Privacy Policy.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: ZveltTokens.fontPrimary,
                fontSize: 10.5,
                height: 1.5,
                color: ZveltTokens.text4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Centered "prompt + tappable action" row (the sign-up / log-in toggle).
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.prompt,
    required this.action,
    required this.onTap,
  });

  final String prompt;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        button: true,
        label: '$prompt$action',
        excludeSemantics: true,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: prompt),
              TextSpan(
                text: action,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: ZveltTokens.brandDeep,
                ),
              ),
            ],
            style: TextStyle(
              fontFamily: ZveltTokens.fontPrimary,
              fontSize: 12.5,
              color: ZveltTokens.text3,
            ),
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
