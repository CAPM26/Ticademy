import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';

ValueNotifier<AuthService> authService = ValueNotifier(AuthService());

class AuthService {
  final FirebaseAuth firebaseAuth = FirebaseAuth.instance;
  // Usa el mismo objeto en toda la app para que comparta sesión interna.
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    // scopes si los usas: scopes: ['email'],
    // TIP: si quieres *siempre* forzar selector de cuenta, desconectamos abajo.
  );

  User? get currentUser => firebaseAuth.currentUser;
  Stream<User?> get authStateChanges => firebaseAuth.authStateChanges();

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) =>
      firebaseAuth.signInWithEmailAndPassword(email: email, password: password);

  Future<UserCredential> createAccount({
    required String email,
    required String password,
  }) =>
      firebaseAuth.createUserWithEmailAndPassword(email: email, password: password);

  Future<UserCredential> signInWithGoogle() async {
    try {
      // Opcional: asegurarte de no reusar silenciosamente un estado previo
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.disconnect().catchError((_) {});
        await _googleSignIn.signOut().catchError((_) {});
      }

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw FirebaseAuthException(
          code: 'ERROR_ABORTED_BY_USER',
          message: 'Inicio de sesión cancelado por el usuario',
        );
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      return await firebaseAuth.signInWithCredential(credential);
    } on FirebaseAuthException {
      rethrow;
    } catch (error) {
      throw FirebaseAuthException(
        code: 'ERROR_GOOGLE_SIGN_IN',
        message: 'Ocurrió un error al intentar iniciar sesión con Google: $error',
      );
    }
  }

  /// 🔐 Logout real: Firebase + Google (revoca token en la app)
  Future<void> signOut() async {
    // 1) Cierra sesión de Firebase
    await firebaseAuth.signOut();

    // 2) Cierra sesión de Google y además desconecta (revoca el consentimiento en esta app)
    //    Esto evita que el siguiente tap en "Ingresar con Google" te autentique
    //    automáticamente con la cuenta anterior.
    try {
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.disconnect(); // revoca en la app
        await _googleSignIn.signOut();    // limpia sesión local del SDK
      }
    } catch (_) {
      // Ignora errores cosméticos del SDK de Google
    }
  }

  Future<void> resetPassword({required String email}) =>
      firebaseAuth.sendPasswordResetEmail(email: email);

  Future<void> updateUsername({required String username}) async {
    final user = currentUser;
    if (user == null) throw Exception('No hay usuario autenticado');
    await user.updateDisplayName(username);
  }

  Future<void> deleteAccount({
    required String email,
    required String password,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('No hay usuario autenticado');

    final cred = EmailAuthProvider.credential(email: email, password: password);
    await user.reauthenticateWithCredential(cred);
    await user.delete();

    // Por si acaso, cierra también Google
    await signOut();
  }

  Future<void> resetPasswordfromCurrentPassword({
    required String currentPassword,
    required String newPassword,
    required String email,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('No hay usuario autenticado');

    final cred = EmailAuthProvider.credential(email: email, password: currentPassword);
    await user.reauthenticateWithCredential(cred);
    await user.updatePassword(newPassword);
  }
}
