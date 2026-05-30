import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../theme/app_text.dart';
import '../../theme/palette.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/form_fields.dart';

/// Sign-in / sign-up screen (email + password).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _auth = AuthService();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _isSignUp = false;
  bool _busy = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
    });
    final email = _email.text.trim();
    final password = _password.text;

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (_isSignUp && _name.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your name.');
      return;
    }

    setState(() => _busy = true);
    try {
      if (_isSignUp) {
        await _auth.signUp(_name.text, email, password);
      } else {
        await _auth.signIn(email, password);
      }
      // AuthGate switches to the app automatically on success.
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _googleSignIn() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await _auth.signInWithGoogle();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not sign in with Google.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter your email above to reset the password.');
      return;
    }
    try {
      await _auth.sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Password reset link sent to $email')),
        );
      }
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _logo(),
                  const SizedBox(height: 22),
                  Text(
                    'FinTrack',
                    textAlign: TextAlign.center,
                    style: sans(
                        size: 28,
                        weight: FontWeight.w800,
                        color: colors.text),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isSignUp
                        ? 'Create your account to get started'
                        : 'Welcome back — sign in to continue',
                    textAlign: TextAlign.center,
                    style: sans(size: 14, color: colors.sub),
                  ),
                  const SizedBox(height: 30),
                  if (_isSignUp) ...[
                    AppTextField(
                      colors: colors,
                      controller: _name,
                      label: 'Name',
                      hint: 'Your name',
                    ),
                    const SizedBox(height: 14),
                  ],
                  AppTextField(
                    colors: colors,
                    controller: _email,
                    label: 'Email',
                    hint: 'you@example.com',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 14),
                  _passwordField(colors),
                  if (!_isSignUp)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy ? null : _forgotPassword,
                        child: Text(
                          'Forgot password?',
                          style: sans(
                              size: 12.5, color: const Color(0xFF3DEBA8)),
                        ),
                      ),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 6),
                    _errorBox(_error!),
                  ],
                  const SizedBox(height: 18),
                  PrimaryButton(
                    label: _isSignUp ? 'Create Account' : 'Sign In',
                    busy: _busy,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3DEBA8), Color(0xFF60A5FA)],
                    ),
                    onPressed: _submit,
                  ),
                  const SizedBox(height: 18),
                  _orDivider(colors),
                  const SizedBox(height: 14),
                  _googleButton(colors),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _isSignUp
                            ? 'Already have an account?'
                            : "Don't have an account?",
                        style: sans(size: 13, color: colors.sub),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _isSignUp = !_isSignUp;
                                  _error = null;
                                }),
                        child: Text(
                          _isSignUp ? 'Sign In' : 'Sign Up',
                          style: sans(
                            size: 13,
                            weight: FontWeight.w700,
                            color: const Color(0xFF3DEBA8),
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
      ),
    );
  }

  Widget _logo() {
    return Center(
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3DEBA8).withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Image.asset(
            'assets/logo.png',
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  Widget _passwordField(Palette colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel('Password', colors: colors),
        TextField(
          controller: _password,
          obscureText: _obscure,
          onSubmitted: (_) => _submit(),
          style: sans(size: 14, color: colors.text),
          cursorColor: const Color(0xFF3DEBA8),
          decoration: InputDecoration(
            isDense: true,
            hintText: '••••••••',
            hintStyle: sans(size: 14, color: colors.muted),
            filled: true,
            fillColor: colors.inputBg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            suffixIcon: IconButton(
              icon: Icon(
                _obscure ? Icons.visibility_off : Icons.visibility,
                size: 18,
                color: colors.sub,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
            border: _border(colors.inputBorder),
            enabledBorder: _border(colors.inputBorder),
            focusedBorder: _border(const Color(0xFF3DEBA8)),
          ),
        ),
      ],
    );
  }

  Widget _orDivider(Palette colors) {
    return Row(
      children: [
        Expanded(child: Divider(color: colors.inputBorder, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: sans(size: 12, color: colors.sub),
          ),
        ),
        Expanded(child: Divider(color: colors.inputBorder, height: 1)),
      ],
    );
  }

  Widget _googleButton(Palette colors) {
    return InkWell(
      onTap: _busy ? null : _googleSignIn,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: colors.inputBg,
          border: Border.all(color: colors.inputBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _googleGlyph(),
            const SizedBox(width: 10),
            Text(
              'Continue with Google',
              style: sans(
                size: 15,
                weight: FontWeight.w600,
                color: colors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _googleGlyph() {
    // Simple inline "G" mark — avoids shipping the Google logo asset.
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF4285F4),
            Color(0xFF34A853),
            Color(0xFFFBBC05),
            Color(0xFFEA4335),
          ],
          stops: [0.0, 0.35, 0.7, 1.0],
        ),
      ),
      child: Text(
        'G',
        style: sans(
          size: 13,
          weight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _errorBox(String msg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFF5C7A).withValues(alpha: 0.12),
        border: Border.all(color: const Color(0xFFFF5C7A).withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: Color(0xFFFF5C7A)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg,
                style: sans(size: 12.5, color: const Color(0xFFFF5C7A))),
          ),
        ],
      ),
    );
  }

  OutlineInputBorder _border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c),
      );
}
