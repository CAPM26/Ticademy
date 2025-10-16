import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

/// Servicio de presencia: mantiene userStatus/{uid} y lastAccess.
/// - Marca online=true al autenticar.
/// - Usa onDisconnect() para dejar offline si la app muere/perde conexión.
/// - Escucha ciclo de vida (foreground/background) para actualizar lastActive.
class PresenceService with WidgetsBindingObserver {
  PresenceService._();
  static final PresenceService instance = PresenceService._();

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseDatabase.instance;

  StreamSubscription<User?>? _authSub;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);

    _authSub = _auth.authStateChanges().listen((user) async {
      if (user == null) {
        // usuario salió
        await _clearOnDisconnect();
        return;
      }
      // usuario entró
      await setOnlineAndBind(user);
    });
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    _authSub = null;
    WidgetsBinding.instance.removeObserver(this);
    _started = false;
  }

  /// Marca online y configura onDisconnect para este usuario.
  Future<void> setOnlineAndBind([User? user]) async {
    user ??= _auth.currentUser;
    if (user == null) return;

    final statusRef = _db.ref('userStatus/${user.uid}');
    final now = ServerValue.timestamp;

    // Asegura onDisconnect: al perderse la conexión/quitar app, quedará offline
    await statusRef.onDisconnect().update({
      'online': false,
      'lastActive': ServerValue.timestamp,
    });

    // Marca online inmediatamente
    await statusRef.update({
      'online': true,
      'lastActive': now,
    });

    // También refresca lastAccess del usuario
    await _db.ref('users/${user.uid}/progress').update({
      'lastAccess': now,
    });
  }

  /// Marca offline explícitamente (antes de cerrar sesión).
  Future<void> setOffline() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final statusRef = _db.ref('userStatus/${user.uid}');
    await statusRef.update({
      'online': false,
      'lastActive': ServerValue.timestamp,
    });
    await _clearOnDisconnect();
  }

  Future<void> _clearOnDisconnect() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final statusRef = _db.ref('userStatus/${user.uid}');
    // Limpia cualquier handler anterior
    await statusRef.onDisconnect().cancel();
  }

  // Ciclo de vida: cuando vuelve a foreground, actualiza a online
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final user = _auth.currentUser;
    if (user == null) return;
    if (state == AppLifecycleState.resumed) {
      setOnlineAndBind(user);
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.inactive ||
               state == AppLifecycleState.hidden) {
      // No forzamos offline (onDisconnect ya cubre cierre brusco), pero
      // actualizamos lastActive para tener “última actividad”.
      _db.ref('userStatus/${user.uid}').update({
        'lastActive': ServerValue.timestamp,
      });
    }
  }
}
