import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../l10n/app_strings.dart';
import '../l10n/auth_error_messages.dart';
import '../services/auth_service.dart';
import '../theme/app_icons.dart';
import '../theme/zvelt_tokens.dart';
import '../widgets/z/z_card.dart';
import '../widgets/zvelt_primary_button.dart';
import '../widgets/zvelt_secondary_button.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onLoggedIn});

  final VoidCallback onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _auth = AuthService();
  final _googleSignIn = GoogleSignIn();

  bool _isLogin = true;
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      if (_isLogin) {
        await _auth.login(
          _emailController.text.trim(),
          _passwordController.text,
        );
      } else {
        await _auth.signup(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
      if (!mounted) return;
      widget.onLoggedIn();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final msg = e.toString().replaceFirst('Exception: ', '');
        _error = authErrorToEnglish(msg);
        _loading = false;
      });
    }
  }

  Future<void> _openForgotPassword() async {
    final reset = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(
          initialEmail: _emailController.text.trim(),
        ),
      ),
    );
    if (reset == true && mounted) {
      _passwordController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated. Sign in.')),
      );
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        setState(() => _loading = false);
        return;
      }
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) throw Exception(AppStrings.googleTokenError);
      await _auth.loginWithGoogle(idToken);
      if (!mounted) return;
      widget.onLoggedIn();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final msg = e.toString().replaceFirst('Exception: ', '');
        _error = authErrorToEnglish(msg);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: ZveltTokens.s6,
              vertical: ZveltTokens.s8,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(ZveltTokens.rXl),
                        child: AspectRatio(
                          aspectRatio: 1.02,
                          child: Image.asset(
                            'assets/images/zvelt_splash.png',
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            errorBuilder: (_, __, ___) => DecoratedBox(
                              decoration: BoxDecoration(
                                color: ZveltTokens.surfaceTinted,
                              ),
                              child: const Center(
                                child: Icon(
                                  AppIcons.bolt,
                                  size: 48,
                                  color: ZveltTokens.brand,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: ZveltTokens.s6),
                      Text(
                        AppStrings.appName,
                        textAlign: TextAlign.center,
                        style: textTheme.headlineMedium?.copyWith(
                          color: ZveltTokens.text,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: ZveltTokens.s2),
                      Text(
                        'Train stronger. Eat smarter. Stay consistent.',
                        textAlign: TextAlign.center,
                        style: ZType.bodyM.copyWith(color: ZveltTokens.text2),
                      ),
                      const SizedBox(height: ZveltTokens.s6),
                      ZCard(
                        padding: const EdgeInsets.all(ZveltTokens.s4),
                        shadow: ZveltTokens.shadowHero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                labelText: AppStrings.email,
                                hintText: AppStrings.emailHint,
                                prefixIcon: Icon(AppIcons.envelope),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return AppStrings.enterEmail;
                                }
                                if (!v.contains('@')) {
                                  return AppStrings.invalidEmail;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: ZveltTokens.s3),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              autofillHints: [
                                _isLogin
                                    ? AutofillHints.password
                                    : AutofillHints.newPassword,
                              ],
                              decoration: InputDecoration(
                                labelText: AppStrings.password,
                                hintText: _isLogin
                                    ? AppStrings.passwordHintLogin
                                    : AppStrings.passwordHintSignup,
                                prefixIcon: const Icon(AppIcons.lock),
                                suffixIcon: IconButton(
                                  tooltip: _obscurePassword
                                      ? 'Show password'
                                      : 'Hide password',
                                  onPressed: _loading
                                      ? null
                                      : () => setState(
                                            () => _obscurePassword =
                                                !_obscurePassword,
                                          ),
                                  icon: Icon(
                                    _obscurePassword
                                        ? AppIcons.eye
                                        : AppIcons.eye_crossed,
                                  ),
                                ),
                              ),
                              onFieldSubmitted: (_) {
                                if (!_loading &&
                                    (_formKey.currentState?.validate() ??
                                        false)) {
                                  _submit();
                                }
                              },
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return AppStrings.enterPassword;
                                }
                                if (!_isLogin && v.length < 8) {
                                  return AppStrings.minPassword;
                                }
                                return null;
                              },
                            ),
                            if (_isLogin) ...[
                              const SizedBox(height: ZveltTokens.s1),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed:
                                      _loading ? null : _openForgotPassword,
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(44, 44),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: ZveltTokens.s3,
                                      vertical: ZveltTokens.s2,
                                    ),
                                  ),
                                  child: const Text(
                                    'Forgot password?',
                                    style: TextStyle(
                                      color: ZveltTokens.brand,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: ZveltTokens.s3),
                              Container(
                                padding: const EdgeInsets.all(ZveltTokens.s3),
                                decoration: BoxDecoration(
                                  color:
                                      ZveltTokens.error.withValues(alpha: 0.1),
                                  borderRadius:
                                      BorderRadius.circular(ZveltTokens.rMd),
                                ),
                                child: Text(
                                  _error!,
                                  style: ZType.bodyS.copyWith(
                                    color: ZveltTokens.error,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: ZveltTokens.s5),
                            ZveltPrimaryButton(
                              label: _isLogin
                                  ? AppStrings.signIn
                                  : AppStrings.signUp,
                              onTap: () {
                                if (_formKey.currentState?.validate() ??
                                    false) {
                                  _submit();
                                }
                              },
                              enabled: !_loading,
                              busy: _loading,
                            ),
                            const SizedBox(height: ZveltTokens.s3),
                            ZveltSecondaryButton(
                              label: AppStrings.continueWithGoogle,
                              icon: Icons.g_mobiledata,
                              onTap: _signInWithGoogle,
                              enabled: !_loading,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: ZveltTokens.s3),
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () => setState(() {
                                  _error = null;
                                  _isLogin = !_isLogin;
                                }),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(44, 48),
                        ),
                        child: Text(
                          _isLogin
                              ? AppStrings.noAccount
                              : AppStrings.haveAccount,
                          style: const TextStyle(
                            color: ZveltTokens.brand,
                            fontWeight: FontWeight.w700,
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
      ),
    );
  }
}
