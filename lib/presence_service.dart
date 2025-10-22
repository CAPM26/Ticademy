import 'dart:async';
import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
class PresenceService with WidgetsBindingObserver {
  PresenceService._();
  static final PresenceService instance = PresenceService._();

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseDatabase.instance;

  StreamSubscription<User?>? _authSub;
  bool _started = false;

  // Conexión ligada al usuario actual
  String? _boundUid;
  String? _connectionId;              // id único por sesión/conexión
  DatabaseReference? _connRef;        // /status/<uid>/<connectionId>

  /// Inicia el servicio (idempotente) y se suscribe a cambios de auth.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);

    _authSub = _auth.authStateChanges().listen((user) async {
      await handleAuthChange(user);
    });
  }

  /// Limpia listeners/observer. (No fuerza offline: onDisconnect ya lo hará.)
  Future<void> dispose() async {
    await _authSub?.cancel();
    _authSub = null;
    WidgetsBinding.instance.removeObserver(this);
    _started = false;
  }

  /// Llamado automáticamente cuando cambia el usuario autenticado.
  /// - Si user==null: marca offline y desenlaza la conexión previa.
  /// - Si hay nuevo user: lo marca online y enlaza su conexión.
  Future<void> handleAuthChange(User? user) async {
    if (user == null) {
      await markOfflineAndUnbind();
      return;
    }
    await setOnlineAndBind(user);
  }

  /// Marca online y enlaza presencia para [user] (o currentUser).
  /// Crea un connectionId, escribe /status/<uid>/<id>=true y programa onDisconnect.
  Future<void> setOnlineAndBind([User? user]) async {
    user ??= _auth.currentUser;
    if (user == null) return;

    // Si venimos de otro UID, limpia primero
    if (_boundUid != null && _boundUid != user.uid) {
      await markOfflineAndUnbind();
    }

    _boundUid = user.uid;
    _connectionId ??= _makeConnectionId();
    _connRef = _db.ref('status/${user.uid}/${_connectionId!}');

    // Marca esta conexión activa
    await _connRef!.set(true);
    await _connRef!.onDisconnect().remove();

    // Nodo cómodo para UI: users/<uid>/presence
    final presenceRef = _db.ref('users/${user.uid}/presence');
    await presenceRef.update({
      'state': 'online',
      'lastSeen': ServerValue.timestamp,
    });
    await presenceRef.onDisconnect().update({
      'state': 'offline',
      'lastSeen': ServerValue.timestamp,
    });

    // (Compat) userStatus/<uid>
    final statusRef = _db.ref('userStatus/${user.uid}');
    await statusRef.update({
      'online': true,
      'lastActive': ServerValue.timestamp,
    });
    await statusRef.onDisconnect().update({
      'online': false,
      'lastActive': ServerValue.timestamp,
    });

    // Refresca lastAccess (tu lógica existente)
    await _db.ref('users/${user.uid}/progress').update({
      'lastAccess': ServerValue.timestamp,
    });
  }

  /// Marca offline INMEDIATAMENTE para el usuario actual y desenlaza.
  /// Úsalo justo antes de FirebaseAuth.instance.signOut().
  Future<void> setOffline() async {
    await markOfflineAndUnbind();
  }

  /// Marca offline y elimina handlers/nodos de conexión de quien esté enlazado.
  Future<void> markOfflineAndUnbind() async {
    final uid = _boundUid ?? _auth.currentUser?.uid;
    if (uid != null) {
      // users/<uid>/presence
      await _db.ref('users/$uid/presence').update({
        'state': 'offline',
        'lastSeen': ServerValue.timestamp,
      });
      // (Compat) userStatus/<uid>
      await _db.ref('userStatus/$uid').update({
        'online': false,
        'lastActive': ServerValue.timestamp,
      });
    }

    // Cancela onDisconnect de la conexión y borra el nodo /status/<uid>/<connectionId>
    await _cancelOnDisconnectAndRemoveConn();

    _boundUid = null;
    _connectionId = null;
    _connRef = null;
  }

  Future<void> _cancelOnDisconnectAndRemoveConn() async {
    try {
      await _connRef?.onDisconnect().cancel();
    } catch (_) {/* noop */}
    try {
      await _connRef?.remove();
    } catch (_) {/* noop */}
  }

  // Ciclo de vida app: al volver al foreground reafirma presencia y actualiza lastSeen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final user = _auth.currentUser;
    if (user == null) return;

    if (state == AppLifecycleState.resumed) {
      // Reafirma el bind (útil tras suspender/reanudar)
      setOnlineAndBind(user);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      // No forzamos offline; sólo registramos actividad.
      _db.ref('users/${user.uid}/presence').update({
        'lastSeen': ServerValue.timestamp,
      });
      _db.ref('userStatus/${user.uid}').update({
        'lastActive': ServerValue.timestamp,
      });
    }
  }

  String _makeConnectionId() {
    final rnd = Random();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(20, (_) => chars[rnd.nextInt(chars.length)]).join();
  }
}
