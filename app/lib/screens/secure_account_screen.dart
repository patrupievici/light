import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../theme/zvelt_tokens.dart';

/// Attach real, recoverable credentials (email + password) to the current
/// auto-created account, so it can be signed into on another device. Matches
/// the LoginScreen / ForgotPassword visual language. Pops `true` on success.
class SecureAccountScreen extends StatefulWidget {
  const SecureAccountScreen({super.key});

  @override
  State<SecureAccountScreen> createState() => _SecureAccountScreenState();
}

class _SecureAccountScreenState extends State<SecureAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _auth = AuthService();

  bool _loading = false;

  /// Banner error (network / server) — retry by tapping again.
  String? _error;

  /// Inline error on the email field (already in use).
  String? _emailError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return; // double-tap guard
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
      _emailError = null;
    });
    try {
      await _auth.attachEmail(
        _emailController.text.trim(),
        _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AttachEmailException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (e.emailTaken) {
          _emailError = e.message;
        } else {
          _error = e.message;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(title: const Text('Secure your account')),
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
                    'Save your progress',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: ZveltTokens.s2),
                  Text(
                    'Add an email and password so you can sign in on another '
                    'device and never lose your workouts. Your account and data '
                    'stay exactly as they are.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: ZveltTokens.s8),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    enabled: !_loading,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      hintText: 'you@example.com',
                      errorText: _emailError,
                      errorMaxLines: 2,
                    ),
                    onChanged: (_) {
                      if (_emailError != null) setState(() => _emailError = null);
                    },
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Enter your email';
                      if (!v.contains('@')) return 'Invalid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: ZveltTokens.s4),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    enabled: !_loading,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      hintText: 'Min. 8 characters',
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Choose a password';
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
                      labelText: 'Confirm password',
                    ),
                    validator: (v) {
                      if (v != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
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
                        : Text(_error == null ? 'Secure account' : 'Try again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
