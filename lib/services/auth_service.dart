import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

/// Thin wrapper around FirebaseAuth with friendly error messages.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Stream<User?> get authState => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<void> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_message(e));
    }
  }

  Future<void> signUp(String name, String email, String password) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final display = name.trim();
      if (display.isNotEmpty) {
        await cred.user?.updateDisplayName(display);
      }
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_message(e));
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_message(e));
    }
  }

  /// Sign in with Google. Uses the web popup flow on web and the native
  /// account picker on mobile/desktop.
  Future<void> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider()
          ..addScope('email')
          ..addScope('profile');
        await _auth.signInWithPopup(provider);
        return;
      }

      final account = await _googleSignIn.signIn();
      if (account == null) {
        // User aborted the picker — surface as a friendly cancel.
        throw AuthFailure('Google sign-in was cancelled.');
      }
      final googleAuth = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );
      await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_message(e));
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw AuthFailure('Could not sign in with Google. Try again.');
    }
  }

  Future<void> signOut() async {
    try {
      if (!kIsWeb) {
        await _googleSignIn.signOut();
      }
    } catch (_) {/* ignore Google session cleanup errors */}
    await _auth.signOut();
  }

  String _message(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'weak-password':
        return 'Password is too weak — use at least 6 characters.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error — check your connection.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled in Firebase.';
      default:
        return e.message ?? 'Authentication failed. Please try again.';
    }
  }
}

/// Carries a user-friendly authentication error message.
class AuthFailure implements Exception {
  final String message;
  AuthFailure(this.message);
  @override
  String toString() => message;
}
