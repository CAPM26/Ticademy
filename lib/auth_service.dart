import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

ValueNotifier<AuthService> authService = ValueNotifier(AuthService());

class AuthService {
  final FirebaseAuth firebaseAuth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  User? get currentUser => firebaseAuth.currentUser;

  Stream<User?> get authStateChanges => firebaseAuth.authStateChanges();

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    return await firebaseAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<UserCredential> createAccount({
    required String email,
    required String password,
  }) async {
    return await firebaseAuth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<UserCredential> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw FirebaseAuthException(
          code: 'ERROR_ABORTED_BY_USER',
          message: 'Inicio de sesion cancelado por el usuario',
        );
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

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
        message:
            'Ocurrio un error al intentar iniciar sesion con Google: $error',
      );
    }
  }

  Future<void> signOut() async {
    await firebaseAuth.signOut();
    if (await _googleSignIn.isSignedIn()) {
      await _googleSignIn.signOut();
    }
  }

  Future<void> resetPassword({required String email}) async {
    await firebaseAuth.sendPasswordResetEmail(email: email);
  }

  Future<void> updateUsername({required String username}) async {
    final user = currentUser;
    if (user != null) {
      await user.updateDisplayName(username);
    } else {
      throw Exception('No hay usuario autenticado');
    }
  }

  Future<void> deleteAccount({
    required String email,
    required String password,
  }) async {
    final user = currentUser;
    if (user != null) {
      AuthCredential credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );

      await user.reauthenticateWithCredential(credential);
      await user.delete();
      await firebaseAuth.signOut();
    } else {
      throw Exception('No hay usuario autenticado');
    }
  }

  Future<void> resetPasswordfromCurrentPassword({
    required String currentPassword,
    required String newPassword,
    required String email,
  }) async {
    final user = currentUser;
    if (user != null) {
      AuthCredential credential = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );

      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
    } else {
      throw Exception('No hay usuario autenticado');
    }
  }
}
