import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:ticademy/ui/app_scaffold.dart';
import 'package:ticademy/user_profile_page.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});
  static const routeName = '/friends';

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseDatabase.instance;

  final _searchCtrl = TextEditingController();
  final _inviteCtrl = TextEditingController();
  final Set<String> _removing = {};


  FriendsView _view = FriendsView.friends;

  // Amigos
  List<_FriendVM> _friends = [];
  Set<String> _friendIds = {};
  final Map<String, StreamSubscription<DatabaseEvent>> _statusSubs = {};
  StreamSubscription<DatabaseEvent>? _friendsSub;

  // Invitaciones
  List<_InviteVM> _incoming = [];
  List<_InviteVM> _outgoing = [];
  StreamSubscription<DatabaseEvent>? _invitesSub;

  // Estados UI
  String _searchTerm = '';
  String? _inviteFeedback; // texto
  _InviteTone _inviteTone = _InviteTone.muted;
  bool _inviteBusy = false;
  _InviteLookup? _inviteLookup;

  @override
  void initState() {
    super.initState();
    _wire();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _inviteCtrl.dispose();
    _friendsSub?.cancel();
    _invitesSub?.cancel();
    for (final s in _statusSubs.values) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _wire() async {
    final user = _auth.currentUser;
    if (user == null) return;

    _attachFriendsListener(user.uid);
    _attachInvitesListener(user.uid);
  }

  // ======== LISTEN FRIENDS ========
  void _attachFriendsListener(String uid) {
    _friendsSub?.cancel();
    _friendsSub = _db.ref('friends/$uid').onValue.listen((event) async {
      // Limpia subs de amigos removidos
      final existingIds = Set<String>.from(_statusSubs.keys);

      if (!event.snapshot.exists) {
        for (final id in existingIds) {
          _statusSubs.remove(id)?.cancel();
        }
        setState(() {
          _friends = [];
          _friendIds = {};
        });
        return;
      }

      final entries = (event.snapshot.value as Map).entries.toList();
      final List<_FriendVM> vms = [];
      for (final e in entries) {
        final friendId = e.key.toString();
        try {
          final profileSnap = await _db.ref('users/$friendId/profile').get();
          final progressSnap = await _db.ref('users/$friendId/progress').get();

          final profile = (profileSnap.value as Map?) ?? {};
          final progress = (progressSnap.value as Map?) ?? {};

          vms.add(
            _FriendVM(
              id: friendId,
              name: (profile['displayName'] ?? friendId).toString(),
              email: (profile['email'] ?? '').toString(),
              photoUrl: (profile['photoURL'] ?? '').toString(),
              lastAccess: (progress['lastAccess']),
              online: false, // actualizará el listener de estado
            ),
          );
        } catch (_) {
          vms.add(
            _FriendVM(
              id: friendId,
              name: friendId,
              email: '',
              photoUrl: '',
              lastAccess: null,
              online: false,
            ),
          );
        }
      }

      // Suscribir estado en vivo
      final newIds = vms.map((e) => e.id).toSet();

      // cancelar subs de removidos
      for (final id in existingIds) {
        if (!newIds.contains(id)) {
          _statusSubs.remove(id)?.cancel();
        }
      }

      // agregar subs nuevos
      for (final id in newIds) {
        if (_statusSubs.containsKey(id)) continue;
        _statusSubs[id] = _db.ref('userStatus/$id').onValue.listen((snap) {
          final v = (snap.snapshot.value as Map?) ?? {};
          final online = (v['online'] ?? false) == true;
          final last = v['lastActive'];
          _updateFriendPresence(id, online, last);
        });
      }

      setState(() {
        _friends = vms;
        _friendIds = newIds;
      });
    });
  }

  void _updateFriendPresence(String id, bool online, dynamic lastActive) {
    final i = _friends.indexWhere((f) => f.id == id);
    if (i == -1) return;
    setState(() {
      _friends[i] = _friends[i].copyWith(
        online: online,
        lastAccess: lastActive ?? _friends[i].lastAccess,
      );
    });
  }

  // ======== LISTEN INVITES ========
  void _attachInvitesListener(String uid) {
    _invitesSub?.cancel();
    _invitesSub = _db.ref('friendRequests').onValue.listen((snap) async {
      final List<_InviteVM> incoming = [];
      final List<_InviteVM> outgoing = [];

      if (snap.snapshot.exists) {
        final map = (snap.snapshot.value as Map).cast<Object?, Object?>();
        for (final e in map.entries) {
          final id = e.key.toString();
          final m = (e.value as Map).cast<String, dynamic>();
          final status = (m['status'] ?? 'pending').toString();
          if (status != 'pending') continue;

          if (m['to'] == uid) {
            // entrante
            final fromId = (m['from'] ?? '').toString();
            final prof = await _db.ref('users/$fromId/profile').get();
            final p = (prof.value as Map?) ?? {};
            incoming.add(
              _InviteVM(
                requestId: id,
                otherUserId: fromId,
                otherName: (p['displayName'] ?? fromId).toString(),
                otherEmail: (p['email'] ?? '').toString(),
                createdAtIso: (m['createdAt'] ?? '').toString(),
                kind: _InviteKind.incoming,
              ),
            );
          } else if (m['from'] == uid) {
            // saliente
            final toId = (m['to'] ?? '').toString();
            final prof = await _db.ref('users/$toId/profile').get();
            final p = (prof.value as Map?) ?? {};
            outgoing.add(
              _InviteVM(
                requestId: id,
                otherUserId: toId,
                otherName: (p['displayName'] ?? toId).toString(),
                otherEmail: (p['email'] ?? '').toString(),
                createdAtIso: (m['createdAt'] ?? '').toString(),
                kind: _InviteKind.outgoing,
              ),
            );
          }
        }
      }

      setState(() {
        _incoming = incoming;
        _outgoing = outgoing;
      });
    });
  }

  // ======== INVITE FLOW ========
  void _setInviteFeedback(String? text, _InviteTone tone) {
    setState(() {
      _inviteFeedback = text;
      _inviteTone = tone;
    });
  }

  Future<void> _searchUserById() async {
    final me = _auth.currentUser?.uid;
    final id = _inviteCtrl.text.trim();
    _setInviteFeedback(null, _InviteTone.muted);
    setState(() => _inviteLookup = null);

    if (me == null) {
      _setInviteFeedback('Debes iniciar sesión.', _InviteTone.error);
      return;
    }
    if (id.isEmpty) {
      _setInviteFeedback('Escribe el ID del usuario.', _InviteTone.error);
      return;
    }
    if (id == me) {
      _setInviteFeedback('No puedes invitarte a ti mismo.', _InviteTone.error);
      return;
    }

    setState(() => _inviteBusy = true);
    try {
      // Ya amigo
      if (_friendIds.contains(id)) {
        _inviteLookup = _InviteLookup(
          userId: id,
          name: '',
          email: '',
          canSend: false,
          reason: 'Ya son amigos',
        );
        _setInviteFeedback(
          'Ya tienes a esta persona en tu lista.',
          _InviteTone.error,
        );
        return;
      }

      // Perfil
      final profSnap = await _db.ref('users/$id/profile').get();
      if (!profSnap.exists) {
        _setInviteFeedback(
          'No encontramos un usuario con ese ID.',
          _InviteTone.error,
        );
        return;
      }
      final p = (profSnap.value as Map?) ?? {};
      final name = (p['displayName'] ?? id).toString();
      final email = (p['email'] ?? '').toString();

      // Revisar pending existentes
      final reqSnap = await _db.ref('friendRequests').get();
      bool pendingOut = false;
      bool pendingIn = false;
      if (reqSnap.exists) {
        final map = (reqSnap.value as Map).cast<Object?, Object?>();
        for (final e in map.entries) {
          final m = (e.value as Map).cast<String, dynamic>();
          if ((m['status'] ?? 'pending') != 'pending') continue;
          if (m['from'] == me && m['to'] == id) pendingOut = true;
          if (m['from'] == id && m['to'] == me) pendingIn = true;
        }
      }

      if (pendingOut) {
        _inviteLookup = _InviteLookup(
          userId: id,
          name: name,
          email: email,
          canSend: false,
          reason: 'Invitación enviada',
        );
        _setInviteFeedback(
          'Ya enviaste una invitación a este usuario.',
          _InviteTone.info,
        );
      } else if (pendingIn) {
        _inviteLookup = _InviteLookup(
          userId: id,
          name: name,
          email: email,
          canSend: false,
          reason: 'Invitación recibida',
        );
        _setInviteFeedback(
          'Este usuario ya te envió una invitación pendiente.',
          _InviteTone.info,
        );
      } else {
        _inviteLookup = _InviteLookup(
          userId: id,
          name: name,
          email: email,
          canSend: true,
          reason: 'Disponible para invitar',
        );
        _setInviteFeedback(
          'Puedes enviar la invitación cuando quieras.',
          _InviteTone.success,
        );
      }
    } catch (_) {
      _setInviteFeedback(
        'Ocurrió un error durante la búsqueda.',
        _InviteTone.error,
      );
    } finally {
      setState(() => _inviteBusy = false);
    }
  }

  Future<void> _sendInvite() async {
    final me = _auth.currentUser?.uid;
    final lookup = _inviteLookup;
    if (me == null || lookup == null || !lookup.canSend) return;
    setState(() => _inviteBusy = true);
    try {
      final ref = _db.ref('friendRequests').push();
      await ref.set({
        'from': me,
        'to': lookup.userId,
        'status': 'pending',
        'createdAt': DateTime.now().toIso8601String(),
      });
      _inviteLookup = _inviteLookup!.copyWith(
        canSend: false,
        reason: 'Invitación enviada',
      );
      _setInviteFeedback(
        'Invitación enviada correctamente.',
        _InviteTone.success,
      );
    } catch (_) {
      _setInviteFeedback('No se pudo enviar la invitación.', _InviteTone.error);
    } finally {
      setState(() => _inviteBusy = false);
    }
  }

  Future<void> _acceptInvite(_InviteVM invite) async {
    final me = _auth.currentUser?.uid;
    if (me == null) return;
    try {
      final now = DateTime.now().toIso8601String();
      await _db.ref().update({
        'friendRequests/${invite.requestId}/status': 'accepted',
        'friendRequests/${invite.requestId}/respondedAt': now,
        'friends/$me/${invite.otherUserId}': {'addedAt': now},
        'friends/${invite.otherUserId}/$me': {'addedAt': now},
      });
    } catch (_) {
      _snack('No se pudo aceptar la invitación.');
    }
  }

  Future<void> _rejectInvite(_InviteVM invite) async {
    try {
      await _db.ref('friendRequests/${invite.requestId}').update({
        'status': 'rejected',
        'respondedAt': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      _snack('No se pudo rechazar la invitación.');
    }
  }

  Future<void> _cancelInvite(_InviteVM invite) async {
    try {
      await _db.ref('friendRequests/${invite.requestId}').update({
        'status': 'cancelled',
        'respondedAt': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      _snack('No se pudo cancelar la invitación.');
    }
  }

  Future<void> _askRemoveFriend(_FriendVM friend) async {
  if (!mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Eliminar amigo'),
      content: Text(
        '¿Seguro que quieres eliminar a "${friend.name.isNotEmpty ? friend.name : friend.id}" de tu lista de amigos?\n\n'
        'No hay penalización: podréis enviar o recibir solicitudes de nuevo cuando quieran.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFEF4444),
          ),
          child: const Text('Eliminar'),
        ),
      ],
    ),
  );

  if (ok == true) {
    await _removeFriend(friend);
  }
}

Future<void> _removeFriend(_FriendVM friend) async {
  final me = _auth.currentUser?.uid;
  if (me == null) {
    _snack('Debes iniciar sesión.');
    return;
  }
  setState(() => _removing.add(friend.id));
  try {
    // Borra relación en ambos sentidos
    await _db.ref('friends/$me/${friend.id}').remove();
    await _db.ref('friends/${friend.id}/$me').remove();

    // El listener de friends se encargará de refrescar la lista y cancelar los subs
    _snack('Amigo eliminado.');
  } catch (_) {
    _snack('No se pudo eliminar. Intenta de nuevo.');
  } finally {
    if (mounted) {
      setState(() => _removing.remove(friend.id));
    }
  }
}


  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ======== UI ========
  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      currentTab: AppTab.friends,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // _buildHeader(),   <-- QUITAR (esto es lo que sale en rojo en tu captura)
              _buildToolbar(),
              const SizedBox(height: 16),
              if (_view == FriendsView.friends) _buildFriendsPanel(),
              if (_view == FriendsView.invites) _buildInvitesPanel(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Búsqueda
        SizedBox(
          width: 360,
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) =>
                setState(() => _searchTerm = v.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Busca por nombre, correo o ID',
              prefixIcon: const Icon(Icons.search, color: Color(0xFF98A2B3)),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 10,
                horizontal: 20,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        // Toggle
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF3FB),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _toggleChip(
                label: 'Mis amigos',
                active: _view == FriendsView.friends,
                onTap: () => setState(() => _view = FriendsView.friends),
              ),
              _toggleChip(
                label: 'Invitaciones',
                active: _view == FriendsView.invites,
                onTap: () => setState(() => _view = FriendsView.invites),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _toggleChip({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: const Color(
                        0xFF5564F2,
                      ).withOpacity(.25), // antes: withValues(alpha: .25)
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: active ? const Color(0xFF5564F2) : const Color(0xFF6B7280),
            ),
          ),
        ),
      ),
    );
  }

  // ======== FRIENDS PANEL ========
  Widget _buildFriendsPanel() {
    final filtered = _friends.where((f) {
      if (_searchTerm.isEmpty) return true;
      final haystack = '${f.name} ${f.email} ${f.id}'.toLowerCase();
      return haystack.contains(_searchTerm);
    }).toList();

    return Container(
      decoration: _panelDecor(),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelHead(
            'Tus conexiones',
            'Observa quién está en línea y visita sus perfiles para conocer su progreso.',
          ),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            _empty(
              'Aún no tienes amigos agregados o no hay coincidencias para tu búsqueda.',
            )
          else
            Column(
              children: [
                for (final f in filtered) ...[
                  _friendTile(f),
                  const SizedBox(height: 12),
                ],
              ],
            ),
        ],
      ),
    );
  }

Widget _friendTile(_FriendVM f) {
  final dotColor = f.online ? const Color(0xFF22C55E) : const Color(0xFF94A3B8);
  final meta = f.online ? 'En línea' : _relative(f.lastAccess);

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE8ECF6)), // más sutil
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Avatar
        _avatar(photoUrl: f.photoUrl, name: f.name),

        const SizedBox(width: 12),

        // Nombre + estado (ocupa todo el ancho disponible)
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Nombre
              Text(
                f.name.isNotEmpty ? f.name : (f.email.isNotEmpty ? f.email : f.id),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1D2536),
                ),
              ),
              const SizedBox(height: 4),
              // Estado
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 13,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(width: 12),

        // Acciones compactas
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Botón "Ver perfil" compacto
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).pushNamed(
                  UserProfilePage.routeName,
                  arguments: f.id,
                );
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                side: const BorderSide(color: Color(0xFFE5E7EB)),
                foregroundColor: const Color(0xFF4C5FD7),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Ver perfil'),
            ),
            const SizedBox(height: 4),
            // Menú de opciones (eliminar)
            SizedBox(
              height: 36,
              width: 36,
              child: PopupMenuButton<String>(
                enabled: !_removing.contains(f.id),
                tooltip: 'Opciones',
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (value) {
                  if (value == 'delete') _askRemoveFriend(f);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'Eliminar amigo',
                      style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                icon: _removing.contains(f.id)
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.more_vert_rounded, size: 20, color: Color(0xFF6B7280)),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}



  // ======== INVITES PANEL ========
  Widget _buildInvitesPanel() {
    return Container(
      decoration: _panelDecor(),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelHead(
            'Invitaciones',
            'Acepta solicitudes pendientes o envía nuevas invitaciones utilizando el ID de un usuario.',
          ),
          const SizedBox(height: 16),
          // Pendientes
          const Text(
            'Pendientes',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (_incoming.isEmpty)
            _empty('No tienes invitaciones recibidas.')
          else
            Column(
              children: [
                for (final i in _incoming) ...[
                  _inviteCard(i),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          const SizedBox(height: 16),
          // Enviadas
          const Text(
            'Enviadas',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (_outgoing.isEmpty)
            _empty('No has enviado invitaciones recientemente.')
          else
            Column(
              children: [
                for (final i in _outgoing) ...[
                  _inviteCard(i),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          const SizedBox(height: 18),
          // Enviar invitación
          _inviteForm(),
        ],
      ),
    );
  }

  Widget _inviteCard(_InviteVM i) {
    final title = i.otherName.isNotEmpty
        ? i.otherName
        : (i.otherEmail.isNotEmpty ? i.otherEmail : i.otherUserId);
    final isIncoming = i.kind == _InviteKind.incoming;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        border: Border.all(color: const Color(0xFFE0E7FF)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _avatar(photoUrl: '', name: title),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1D2536),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isIncoming
                          ? 'Te envió una invitación • ${_relative(i.createdAtIso)}'
                          : 'Invitación enviada • ${_relative(i.createdAtIso)}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (isIncoming) ...[
                FilledButton(
                  onPressed: () => _acceptInvite(i),
                  child: const Text('Aceptar'),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () => _rejectInvite(i),
                  child: const Text('Rechazar'),
                ),
              ] else ...[
                OutlinedButton(
                  onPressed: () => _cancelInvite(i),
                  child: const Text('Cancelar'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _inviteForm() {
    final Color toneColor;
    switch (_inviteTone) {
      case _InviteTone.success:
        toneColor = const Color(0xFF10B981);
        break;
      case _InviteTone.info:
        toneColor = const Color(0xFF2563EB);
        break;
      case _InviteTone.error:
        toneColor = const Color(0xFFEF4444);
        break;
      case _InviteTone.muted:
      default:
        toneColor = const Color(0xFF6B7280);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        border: Border.all(color: const Color(0xFFE0E7FF)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enviar invitación',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _inviteCtrl,
            decoration: InputDecoration(
              labelText: 'Ingresa el ID del usuario',
              hintText: 'Ej. abcd1234',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _inviteFeedback ?? '',
            style: TextStyle(color: toneColor, fontSize: 13),
          ),
          const SizedBox(height: 10),
          if (_inviteLookup != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _inviteLookup!.nameOrId,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (_inviteLookup!.email.isNotEmpty)
                    Text(
                      _inviteLookup!.email,
                      style: const TextStyle(color: Color(0xFF6B7280)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              OutlinedButton(
                onPressed: _inviteBusy ? null : _searchUserById,
                child: Text(_inviteBusy ? 'Buscando...' : 'Buscar'),
              ),
              const SizedBox(width: 9),
              FilledButton(
                onPressed: (_inviteBusy || _inviteLookup?.canSend != true)
                    ? null
                    : _sendInvite,
                child: Text(_inviteBusy ? 'Enviando...' : 'Enviar invitación'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ======== Helpers UI ========
  BoxDecoration _panelDecor() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFFE5E7EB)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(
            0.05,
          ), // antes: withValues(alpha: 0.05)
          blurRadius: 18,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }

  Widget _panelHead(String title, String hint) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1D2536),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hint,
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _empty(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: const Color(0xFFE5E7EB),
          style: BorderStyle.solid,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF6B7280)),
      ),
    );
  }

  Widget _avatar({required String photoUrl, required String name}) {
    Widget child;
    if (photoUrl.isNotEmpty) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.network(
          photoUrl,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            return _initialsBox(name);
          },
        ),
      );
    } else {
      child = _initialsBox(name);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Color(0xFFDBEAFE), Color(0xFFDDD6FE)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _initialsBox(String name) {
    final initials = _initials(name);
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
      ),
      child: Text(
        initials,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: Color(0xFF4F46E5),
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '??';
    final a = parts[0][0].toUpperCase();
    final b = parts.length > 1 ? parts[1][0].toUpperCase() : '';
    return '$a$b';
  }

  String _relative(dynamic v) {
    DateTime? dt;
    if (v is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(v);
    } else if (v is String) {
      dt = DateTime.tryParse(v);
    }
    if (dt == null) return 'Sin actividad reciente';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 2) return 'Hace un momento';
    if (diff.inHours < 1) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    if (diff.inDays < 7) return 'Hace ${diff.inDays} días';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }
}

// ======== MODELOS ========
enum FriendsView { friends, invites }

class _FriendVM {
  final String id;
  final String name;
  final String email;
  final String photoUrl;
  final dynamic lastAccess;
  final bool online;

  _FriendVM({
    required this.id,
    required this.name,
    required this.email,
    required this.photoUrl,
    required this.lastAccess,
    required this.online,
  });

  _FriendVM copyWith({bool? online, dynamic lastAccess}) => _FriendVM(
    id: id,
    name: name,
    email: email,
    photoUrl: photoUrl,
    lastAccess: lastAccess ?? this.lastAccess,
    online: online ?? this.online,
  );
}

enum _InviteKind { incoming, outgoing }

class _InviteVM {
  final String requestId;
  final String otherUserId;
  final String otherName;
  final String otherEmail;
  final String createdAtIso;
  final _InviteKind kind;

  _InviteVM({
    required this.requestId,
    required this.otherUserId,
    required this.otherName,
    required this.otherEmail,
    required this.createdAtIso,
    required this.kind,
  });
}

class _InviteLookup {
  final String userId;
  final String name;
  final String email;
  final bool canSend;
  final String reason;

  _InviteLookup({
    required this.userId,
    required this.name,
    required this.email,
    required this.canSend,
    required this.reason,
  });

  String get nameOrId => name.isNotEmpty ? name : userId;

  _InviteLookup copyWith({bool? canSend, String? reason}) => _InviteLookup(
    userId: userId,
    name: name,
    email: email,
    canSend: canSend ?? this.canSend,
    reason: reason ?? this.reason,
  );
}

enum _InviteTone { muted, success, info, error }
