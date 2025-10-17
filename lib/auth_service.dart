import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

ValueNotifier<AuthService> authService = ValueNotifier(AuthService());

class AuthService {
  AuthService();

  final FirebaseAuth firebaseAuth = FirebaseAuth.instance;
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  User? get currentUser => firebaseAuth.currentUser;
  Stream<User?> get authStateChanges => firebaseAuth.authStateChanges();

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return firebaseAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<UserCredential> createAccount({
    required String email,
    required String password,
  }) {
    return firebaseAuth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<UserCredential> signInWithGoogle() async {
    try {
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
        message: 'Ocurrió un error al intentar iniciar sesión con Google: $error',
      );
    }
  }

  Future<void> signOut() async {
    await firebaseAuth.signOut();
    try {
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.disconnect();
        await _googleSignIn.signOut();
      }
    } catch (_) {}
  }

  Future<void> resetPassword({required String email}) {
    return firebaseAuth.sendPasswordResetEmail(email: email);
  }

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

    final cred =
        EmailAuthProvider.credential(email: email, password: password);
    await user.reauthenticateWithCredential(cred);
    await user.delete();

    await signOut();
  }

  Future<void> resetPasswordfromCurrentPassword({
    required String currentPassword,
    required String newPassword,
    required String email,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('No hay usuario autenticado');

    final cred =
        EmailAuthProvider.credential(email: email, password: currentPassword);
    await user.reauthenticateWithCredential(cred);
    await user.updatePassword(newPassword);
  }

  Future<String> ensureUserRole({User? user}) async {
    user ??= currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No hay usuario autenticado.',
      );
    }

    final uid = user.uid;
    final ref = _database.ref('users/$uid');
    final snapshot = await ref.get();

    final displayName = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : (user.email != null ? user.email!.split('@').first : 'Aprendiz');
    final email = user.email ?? '';
    final photoURL = user.photoURL ?? '';
    final nowIso = DateTime.now().toIso8601String();

    if (!snapshot.exists) {
      await ref.set({
        'profile': {
          'displayName': displayName,
          'email': email,
          'photoURL': photoURL,
          'role': 'aprendiz',
          'language': 'es',
          'timeZone': DateTime.now().timeZoneName,
        },
        'progress': {
          'overallPercent': 0,
          'currentModuleId': 'windows_basics',
          'currentSectionId': 'sec_01_escritorio',
          'lastAccess': nowIso,
          'streakDays': 0,
        },
        'stats': {
          'points': 0,
          'badges': {},
          'totalStudySeconds': 0,
        },
        'settings': {
          'notifications': true,
          'weeklyReminder': '',
          'highContrast': false,
        },
      });
    } else {
      await ref.update({
        'profile/displayName': displayName,
        'profile/email': email,
        'profile/photoURL': photoURL,
        'progress/lastAccess': nowIso,
      });
    }

    if (email.isNotEmpty) {
      final sanitized = _sanitizeEmailKey(email);
      await _database.ref('emails/$sanitized').set(uid);
    }

    final roleSnap =
        await _database.ref('users/$uid/profile/role').get();
    final role = (roleSnap.value ?? 'aprendiz').toString().trim().toLowerCase();
    if (role.isEmpty) {
      await _database.ref('users/$uid/profile/role').set('aprendiz');
      return 'aprendiz';
    }
    return role;
  }

  String _sanitizeEmailKey(String email) {
    return email
        .trim()
        .toLowerCase()
        .replaceAll('.', ',')
        .replaceAll(RegExp(r'[^\w@+\-]'), '_');
  }
}
