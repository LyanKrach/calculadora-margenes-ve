import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

/// Servicio de autenticación con Firebase Auth y Google Sign-In (`google_sign_in` 7.x).
///
/// Soporta:
/// - Inicio de sesión con Google (`signInWithGoogle`).
/// - Registro e inicio de sesión con Correo y Contraseña.
/// - Inicio de sesión como invitado (Anónimo) o uso local sin cuenta.
/// - Restablecimiento de contraseña y cierre de sesión.
/// - Degradación elegante en entornos de prueba donde Firebase no esté inicializado.
class AuthService {
  static const String _webServerClientId =
      '799558799155-7e05jmfrm5glfnahti57ufb0gtvbh7a8.apps.googleusercontent.com';

  static bool _googleInitialized = false;

  static bool get isFirebaseInitialized {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  FirebaseAuth? get _auth =>
      isFirebaseInitialized ? FirebaseAuth.instance : null;

  User? get currentUser => _auth?.currentUser;

  bool get isSignedIn => currentUser != null;

  Stream<User?> get authStateChanges =>
      _auth?.authStateChanges() ?? const Stream<User?>.empty();

  Future<void> _ensureGoogleInitialized() async {
    if (kIsWeb || _googleInitialized) return;
    await GoogleSignIn.instance.initialize(
      serverClientId: _webServerClientId,
    );
    _googleInitialized = true;
  }

  /// Inicia sesión con Google (usa `authenticate()` de `google_sign_in` 7.2+ en móvil
  /// y `signInWithPopup` en Web).
  Future<UserCredential> signInWithGoogle() async {
    final auth = _auth;
    if (auth == null) {
      throw StateError('Firebase no está disponible en este entorno.');
    }

    if (kIsWeb) {
      final googleProvider = GoogleAuthProvider();
      return await auth.signInWithPopup(googleProvider);
    } else {
      await _ensureGoogleInitialized();
      final GoogleSignInAccount googleUser =
          await GoogleSignIn.instance.authenticate();
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      final AuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      return await auth.signInWithCredential(credential);
    }
  }

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final auth = _auth;
    if (auth == null) {
      throw StateError('Firebase no está disponible en este entorno.');
    }
    return await auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final auth = _auth;
    if (auth == null) {
      throw StateError('Firebase no está disponible en este entorno.');
    }
    final cred = await auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    if (displayName != null && displayName.trim().isNotEmpty) {
      await cred.user?.updateDisplayName(displayName.trim());
    }
    return cred;
  }

  Future<UserCredential> signInAnonymously() async {
    final auth = _auth;
    if (auth == null) {
      throw StateError('Firebase no está disponible en este entorno.');
    }
    return await auth.signInAnonymously();
  }

  static const String _customResetEndpoint =
      'https://sendcustompasswordresetemail-yqgkyclg5a-uc.a.run.app';

  /// Envía el correo de restablecimiento de contraseña.
  ///
  /// Intenta primero utilizar la función de backend personalizada con plantilla HTML prémium;
  /// si no está desplegada o no responde, degrada de forma transparente al envío nativo de Firebase.
  Future<void> sendPasswordReset(String email) async {
    final cleanEmail = email.trim();

    // 1. Intento con función de correo HTML personalizada
    try {
      final response = await http
          .post(
            Uri.parse(_customResetEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': cleanEmail}),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        return;
      }
    } catch (_) {
      // Si la Cloud Function no está disponible o falla la red, continúa al fallback estándar
    }

    // 2. Fallback estándar de Firebase Auth
    final auth = _auth;
    if (auth == null) {
      throw StateError('Firebase no está disponible en este entorno.');
    }
    await auth.sendPasswordResetEmail(email: cleanEmail);
  }

  /// Cambia la contraseña del usuario actualmente autenticado con email.
  /// Reautentica con [currentPassword] primero para prevenir el error `requires-recent-login`.
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final auth = _auth;
    final user = auth?.currentUser;
    if (user == null || user.email == null) {
      throw StateError('No hay una sesión activa con correo para cambiar la contraseña.');
    }
    final email = user.email!;
    final cred = EmailAuthProvider.credential(
      email: email,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(cred);
    await user.updatePassword(newPassword);
  }

  Future<void> signOut() async {
    final auth = _auth;
    if (!kIsWeb && _googleInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    if (auth != null) {
      await auth.signOut();
    }
  }

  /// Traduce códigos de error de `FirebaseAuthException` y `GoogleSignInException` a español.
  static String friendlyErrorMessage(Object error) {
    if (error is GoogleSignInException) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        return 'Inicio de sesión con Google cancelado.';
      }
      return 'No se pudo iniciar sesión con Google (${error.code.name}).';
    }
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return 'El formato del correo electrónico no es válido.';
        case 'user-disabled':
          return 'Esta cuenta ha sido deshabilitada.';
        case 'user-not-found':
        case 'invalid-credential':
        case 'wrong-password':
          return 'Correo o contraseña incorrectos.';
        case 'requires-recent-login':
          return 'Por seguridad, debes volver a iniciar sesión antes de realizar esta acción.';
        case 'email-already-in-use':
          return 'Ya existe una cuenta registrada con este correo.';
        case 'weak-password':
          return 'La contraseña es muy débil (usa al menos 6 caracteres).';
        case 'account-exists-with-different-credential':
          return 'Ya existe una cuenta asociada a este correo con otro método de acceso.';
        case 'network-request-failed':
          return 'Sin conexión a internet. Verifica tu red e intenta de nuevo.';
        case 'too-many-requests':
          return 'Demasiados intentos. Espera unos minutos antes de reintentar.';
        default:
          return error.message ?? 'Error de autenticación (${error.code}).';
      }
    }
    return error.toString();
  }
}
