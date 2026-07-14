import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/screens/login_screen.dart';
import 'package:zvelt_app/services/auth_service.dart';

class _FakeAuthService extends AuthService {
  int convertCalls = 0;
  int replacementLoginCalls = 0;
  String? email;
  String? password;

  @override
  Future<Map<String, dynamic>?> convertGuestAccount({
    required String email,
    required String password,
  }) async {
    convertCalls++;
    this.email = email;
    this.password = password;
    return {
      'user': {'id': 'guest-user', 'email': email},
    };
  }

  @override
  Future<Map<String, dynamic>?> loginReplacingGuest(
    String email,
    String password,
  ) async {
    replacementLoginCalls++;
    this.email = email;
    this.password = password;
    return {
      'user': {'id': 'existing-user', 'email': email},
    };
  }
}

Future<void> _enterCredentials(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  final fields = find.byType(TextFormField);
  expect(fields, findsNWidgets(2));
  await tester.enterText(fields.at(0), email);
  await tester.enterText(fields.at(1), password);
}

void main() {
  testWidgets(
      'guest sign-up converts the current account instead of duplicating it',
      (tester) async {
    final auth = _FakeAuthService();
    bool? completedAsLogin;

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          authService: auth,
          replaceGuest: true,
          initialLogin: false,
          onLoggedIn: (wasLogin) => completedAsLogin = wasLogin,
        ),
      ),
    );
    expect(find.text('Continue with Google'), findsNothing);
    await _enterCredentials(
      tester,
      email: 'athlete@example.com',
      password: 'secure-password',
    );
    await tester.ensureVisible(find.text('Sign Up'));
    await tester.tap(find.text('Sign Up'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(auth.convertCalls, 1);
    expect(auth.replacementLoginCalls, 0);
    expect(auth.email, 'athlete@example.com');
    expect(auth.password, 'secure-password');
    expect(completedAsLogin, isFalse);
  });

  testWidgets('guest sign-in switches to the existing account path',
      (tester) async {
    final auth = _FakeAuthService();
    bool? completedAsLogin;

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          authService: auth,
          replaceGuest: true,
          onLoggedIn: (wasLogin) => completedAsLogin = wasLogin,
        ),
      ),
    );
    await _enterCredentials(
      tester,
      email: 'existing@example.com',
      password: 'secure-password',
    );
    await tester.ensureVisible(find.text('Sign In'));
    await tester.tap(find.text('Sign In'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(auth.replacementLoginCalls, 1);
    expect(auth.convertCalls, 0);
    expect(auth.email, 'existing@example.com');
    expect(completedAsLogin, isTrue);
  });

  testWidgets('profile account switch requires explicit data-loss confirmation',
      (tester) async {
    final auth = _FakeAuthService();

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          authService: auth,
          replaceGuest: true,
          confirmGuestReplacement: true,
          onLoggedIn: (_) {},
        ),
      ),
    );
    await _enterCredentials(
      tester,
      email: 'existing@example.com',
      password: 'secure-password',
    );
    await tester.ensureVisible(find.text('Sign In'));
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Switch accounts?'), findsOneWidget);
    expect(auth.replacementLoginCalls, 0);

    await tester.tap(find.text('Switch account'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(auth.replacementLoginCalls, 1);
  });
}
