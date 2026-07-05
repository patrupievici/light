import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../theme/zvelt_tokens.dart';

/// Two-step password recovery, matching the LoginScreen visual language.
///
/// Step 1: email → POST /v1/auth/password/forgot. The server always answers a
/// generic 200 (no account enumeration), so on success we always advance and
/// show the generic "if that email exists" message.
///
/// Step 2: 6-digit code + new password → POST /v1/auth/password/reset. A
/// rejected code surfaces as an inline field error; network/server failures
/// show a banner and the button becomes "try again" — no silent failures and
/// no fake success. Pops with `true` when the password was actually changed
/// so LoginScreen can show its confirmation snackbar.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  /// Prefilled from whatever the user already typed on the login screen.
  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _auth = AuthService();

  /// false = email step, true = code + new password step.
  bool _codeStep = false;
  bool _loading = false;

  /// Banner error (network / rate limit / server) — retry by tapping again.
  String? _error;

  /// Inline error on the code field (wrong or expired code).
  String? _codeError;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_loading) return; // double-tap guard
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await _auth.requestPasswordReset(_emailController.text.trim());
      if (!mounted) return;
      setState(() {
        _codeStep = true;
        _codeError = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _resetPassword() async {
    if (_loading) return; // double-tap guard
    setState(() {
      _error = null;
      _codeError = null;
      _loading = true;
    });
    try {
      await _auth.resetPassword(
        _emailController.text.trim(),
        _codeController.text.trim(),
        _passwordController.text,
      );
      if (!mounted) return;
      // Real success only — the server confirmed the password change.
      Navigator.of(context).pop(true);
    } on PasswordResetException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.invalidCode) {
          _codeError = e.message;
        } else {
          _error = e.message;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_codeStep) {
      _resetPassword();
    } else {
      _sendCode();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _codeStep ? 'Check your email' : 'Forgot your password?',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: ZveltTokens.s2),
                  Text(
                    _codeStep
                        ? 'If an account exists for ${_emailController.text.trim()}, '
                            'we sent a 6-digit code. Enter it below with your new '
                            'password. The code expires in 15 minutes.'
                        : 'Enter your account email and we will send you a '
                            '6-digit reset code.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: ZveltTokens.s8),
                  if (!_codeStep) ...[
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      enabled: !_loading,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'you@example.com',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Enter your email';
                        if (!v.contains('@')) return 'Invalid email';
                        return null;
                      },
                    ),
                  ] else ...[
                    TextFormField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      enabled: !_loading,
                      decoration: InputDecoration(
                        labelText: '6-digit code',
                        hintText: '123456',
                        counterText: '',
                        errorText: _codeError,
                        errorMaxLines: 3,
                      ),
                      onChanged: (_) {
                        if (_codeError != null) setState(() => _codeError = null);
                      },
                      validator: (v) {
                        if (v == null || v.trim().length != 6) {
                          return 'Enter the 6-digit code from the email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: ZveltTokens.s4),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      enabled: !_loading,
                      decoration: const InputDecoration(
                        labelText: 'New password',
                        hintText: 'Min. 8 characters',
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Enter a new password';
                        if (v.length < 8) return 'Minimum 8 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: ZveltTokens.s4),
                    TextFormField(
                      controller: _confirmController,
                      obscureText: true,
                      enabled: !_loading,
                      decoration: const InputDecoration(
                        labelText: 'Confirm new password',
                      ),
                      validator: (v) {
                        if (v != _passwordController.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: ZveltTokens.s4),
                    Container(
                      padding: const EdgeInsets.all(ZveltTokens.s3),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppTheme.error, fontSize: 14),
                      ),
                    ),
                  ],
                  const SizedBox(height: ZveltTokens.s6),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.textPrimary,
                            ),
                          )
                        : Text(
                            _codeStep
                                ? 'Reset password'
                                : (_error == null ? 'Send code' : 'Try again'),
                          ),
                  ),
                  if (_codeStep) ...[
                    const SizedBox(height: ZveltTokens.s4),
                    TextButton(
                      onPressed: _loading ? null : _sendCode,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 44), // 44pt touch target
                      ),
                      child: const Text(
                        'Send a new code',
                        style: TextStyle(color: ZveltTokens.brand),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
