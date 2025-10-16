import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:ticademy/ui/app_scaffold.dart';
import 'package:ticademy/app_index_page.dart';
import 'package:flutter/services.dart'; // <-- para copiar al portapapeles


class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});
  static const routeName = '/profile';

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseDatabase.instance;

  DatabaseReference get _usersRef => _db.ref('users');
  DatabaseReference get _statusRef => _db.ref('userStatus');
  DatabaseReference get _friendsRef => _db.ref('friends');
  DatabaseReference get _requestsRef => _db.ref('friendRequests');

  String? _targetUserId;
  bool _isOwnProfile = true;
  bool _loading = true;

  // Presencia
  String _presenceText = 'Sincronizando';
  bool _isOnline = false;

  // Datos de perfil
  Map<String, dynamic> _profile = {};
  Map<String, dynamic> _progress = {};
  Map<String, dynamic> _stats = {};
  String? _photoUrl;

  // Amistad
  bool _showFriendBtn = false;
  bool _friendBusy = false;
  String _friendLabel = 'Agregar amigo';

  // Subs
  StreamSubscription<DatabaseEvent>? _userSub;
  StreamSubscription<DatabaseEvent>? _presenceSub;
  StreamSubscription<DatabaseEvent>? _connectionSub;
  StreamSubscription<User?>? _authSub;

  bool _wired = false;
  String? _snack;

  @override
  void initState() {
    super.initState();
    // Cuando se desconecta la sesión, cierra presencia adecuadamente.
    _authSub = _auth.authStateChanges().listen((user) async {
      if (user == null) {
        try {
          final uid = _targetUserId;
          if (uid != null) {
            await _statusRef.child(uid).update({
              'online': false,
              'lastActive': ServerValue.timestamp,
            });
          }
        } catch (_) {}
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) return;

    final current = _auth.currentUser;
    if (current == null) return;

    final args = ModalRoute.of(context)?.settings.arguments;
    _targetUserId = (args is String ? args : null) ?? current.uid;
    _isOwnProfile = _targetUserId == current.uid;

    _listenUser();
    _listenPresenceOf(_targetUserId!);
    _setupPresenceForCurrentUser();

    if (_isOwnProfile) {
      _updateLastAccess();
    }

    _wired = true;
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _presenceSub?.cancel();
    _connectionSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  // -------- Presence wiring (current user) --------
  void _setupPresenceForCurrentUser() {
    final current = _auth.currentUser;
    if (current == null) return;

    final myStatusRef = _statusRef.child(current.uid);
    final connectedRef = _db.ref('.info/connected');

    _connectionSub = connectedRef.onValue.listen((event) async {
      final connected = (event.snapshot.value == true);
      if (!connected) return;

      await myStatusRef.onDisconnect().update({
        'online': false,
        'lastActive': ServerValue.timestamp,
      });

      await myStatusRef.set({
        'online': true,
        'lastActive': ServerValue.timestamp,
      });
    });
  }

  void _listenPresenceOf(String uid) {
    _presenceSub?.cancel();
    _presenceSub = _statusRef.child(uid).onValue.listen((event) {
      final val = event.snapshot.value as Map?;
      if (val == null) {
        setState(() {
          _isOnline = false;
          _presenceText = 'Sin estado disponible';
        });
        return;
      }
      final online = (val['online'] ?? false) == true;
      String text;
      if (online) {
        text = 'En línea';
      } else {
        final last = _formatDate(val['lastActive']);
        text = last != null
            ? 'Desconectado — Última actividad: $last'
            : 'Desconectado';
      }
      setState(() {
        _isOnline = online;
        _presenceText = text;
      });
    });
  }

  // -------- User data --------
  void _listenUser() {
    final uid = _targetUserId!;
    _userSub = _usersRef
        .child(uid)
        .onValue
        .listen(
          (event) async {
            final raw = (event.snapshot.value ?? {}) as Map? ?? {};
            final m = raw.map((k, v) => MapEntry(k.toString(), v));

            final profile =
                (m['profile'] as Map?)?.cast<String, dynamic>() ?? {};
            final progress =
                (m['progress'] as Map?)?.cast<String, dynamic>() ?? {};
            final stats = (m['stats'] as Map?)?.cast<String, dynamic>() ?? {};

            // --- FIX: resolver foto correctamente según sea propio u otro perfil ---
            final String? dbUrl = (profile['photoURL'] as String?)?.trim();
            String? resolvedPhoto;

            if (_isOwnProfile) {
              final String? authUrl = _auth.currentUser?.photoURL?.trim();
              // DB > Auth > null
              resolvedPhoto = (dbUrl != null && dbUrl.isNotEmpty)
                  ? dbUrl
                  : (authUrl != null && authUrl.isNotEmpty ? authUrl : null);

              // Sólo si es tu propio perfil, sincroniza de Auth -> DB si falta
              if ((dbUrl == null || dbUrl.isEmpty) &&
                  (authUrl != null && authUrl.isNotEmpty)) {
                try {
                  await _usersRef.child(uid).update({
                    'profile/photoURL': authUrl,
                  });
                } catch (_) {}
              }
            } else {
              // Perfil de un amigo: usa sólo lo que hay en DB
              resolvedPhoto = (dbUrl != null && dbUrl.isNotEmpty)
                  ? dbUrl
                  : null;
            }
            // ----------------------------------------------------------------------

            setState(() {
              _profile = profile;
              _progress = progress;
              _stats = stats;
              _photoUrl = resolvedPhoto; // <-- ahora correcto
              _loading = false;

              if (!_isOwnProfile) {
                _prepareFriendButton();
              } else {
                _showFriendBtn = false;
              }
            });
          },
          onError: (_) {
            setState(() {
              _loading = false;
              _snack = 'No se pudo cargar el perfil.';
            });
          },
        );
  }

  Future<void> _updateLastAccess() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    try {
      await _usersRef.child(uid).update({'progress/lastAccess': nowIso});
    } catch (_) {}
  }

  // -------- Helpers --------
  String _resolvedDisplayName() {
    final current = _auth.currentUser;
    final authName = _isOwnProfile
        ? (current?.displayName ?? current?.email?.split('@').first ?? '')
        : '';
    final profileName = (_profile['displayName'] ?? '') as String;
    final value = profileName.isNotEmpty ? profileName : authName;
    return value.isEmpty ? 'Aprendiz' : value;
  }

  String _resolvedRole() {
    final r = (_profile['role'] ?? 'aprendiz').toString().trim().toLowerCase();
    if (r == 'docente' || r == 'colaborador') return r;
    return 'aprendiz';
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'docente':
        return Icons.badge_rounded;
      case 'colaborador':
        return Icons.manage_accounts_rounded;
      default:
        return Icons.school_rounded;
    }
  }

  String _resolvedEmail() {
    final current = _auth.currentUser;
    final profileEmail = _profile['email'] as String?;
    final String email =
        profileEmail ?? (_isOwnProfile ? (current?.email ?? '') : '');
    return email.isEmpty ? '-' : email;
  }

  String? _formatDate(dynamic value) {
    try {
      DateTime dt;
      if (value is int) {
        dt = DateTime.fromMillisecondsSinceEpoch(value);
      } else if (value is String) {
        dt = DateTime.tryParse(value) ?? DateTime.now();
      } else {
        return null;
      }
      String two(int n) => n.toString().padLeft(2, '0');
      return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
    } catch (_) {
      return null;
    }
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '--';
    final a = parts[0][0].toUpperCase();
    final b = parts.length > 1 ? parts[1][0].toUpperCase() : '';
    return '$a$b';
  }

  // -------- Edit name (bottom sheet) --------
  Future<void> _openEditNameSheet() async {
    if (!_isOwnProfile) return;
    final current = _resolvedDisplayName();
    final controller = TextEditingController(text: current);
    String? error;
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final viewInsets = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: viewInsets),
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              Future<void> save() async {
                final newName = controller.text.trim();
                if (newName.isEmpty || newName.length < 3) {
                  setLocal(
                    () => error = 'El nombre debe tener al menos 3 caracteres.',
                  );
                  return;
                }
                setLocal(() {
                  saving = true;
                  error = null;
                });
                final user = _auth.currentUser;
                if (user == null) return;
                try {
                  await user.updateDisplayName(newName);
                  await _usersRef.child(user.uid).update({
                    'profile/displayName': newName,
                  });
                  if (mounted) Navigator.of(ctx).pop(true);
                } catch (e) {
                  setLocal(() {
                    saving = false;
                    error = 'No se pudo guardar. Intenta de nuevo.';
                  });
                }
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: const [
                        Icon(Icons.edit_outlined, color: Color(0xFF1D2536)),
                        SizedBox(width: 8),
                        Text(
                          'Editar nombre',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1D2536),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      maxLength: 60,
                      decoration: InputDecoration(
                        labelText: 'Nombre para mostrar',
                        errorText: error,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onSubmitted: (_) => save(),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: saving ? null : save,
                            icon: saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_rounded),
                            label: Text(saving ? 'Guardando...' : 'Guardar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: saving
                                ? null
                                : () => Navigator.of(ctx).pop(false),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('Cancelar'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          ),
        );
      },
    ).then((saved) {
      if (saved == true) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nombre actualizado correctamente.')),
        );
      }
    });
  }

  // -------- Friend request --------
  Future<void> _prepareFriendButton() async {
    final me = _auth.currentUser!.uid;
    final other = _targetUserId!;
    setState(() {
      _showFriendBtn = true;
      _friendBusy = true;
      _friendLabel = 'Verificando...';
    });

    try {
      final f = await _friendsRef.child('$me/$other').get();
      if (f.exists) {
        setState(() {
          _friendBusy = false;
          _friendLabel = 'Ya son amigos';
        });
        return;
      }

      final all = await _requestsRef.get();
      bool outgoing = false, incoming = false;
      if (all.exists) {
        final map = (all.value as Map).cast<Object?, Object?>();
        for (final entry in map.entries) {
          final m = (entry.value as Map).cast<String, dynamic>();
          if (m['status'] == 'pending') {
            if (m['from'] == me && m['to'] == other) outgoing = true;
            if (m['from'] == other && m['to'] == me) incoming = true;
          }
        }
      }

      if (outgoing) {
        setState(() {
          _friendBusy = false;
          _friendLabel = 'Invitación enviada';
        });
      } else if (incoming) {
        setState(() {
          _friendBusy = false;
          _friendLabel = 'Invitación recibida';
        });
      } else {
        setState(() {
          _friendBusy = false;
          _friendLabel = 'Agregar amigo';
        });
      }
    } catch (e) {
      setState(() {
        _friendBusy = false;
        _friendLabel = 'Agregar amigo';
        _snack = 'No se pudo verificar el estado de amistad.';
      });
    }
  }

  Future<void> _sendFriendRequest() async {
    if (_isOwnProfile || _friendBusy) return;
    final me = _auth.currentUser!.uid;
    final other = _targetUserId!;
    setState(() {
      _friendBusy = true;
      _friendLabel = 'Enviando...';
      _snack = null;
    });
    try {
      final ref = _requestsRef.push();
      await ref.set({
        'from': me,
        'to': other,
        'status': 'pending',
        'createdAt': DateTime.now().toIso8601String(),
      });
      setState(() {
        _friendBusy = false;
        _friendLabel = 'Invitación enviada';
      });
    } catch (e) {
      setState(() {
        _friendBusy = false;
        _friendLabel = 'Agregar amigo';
        _snack = 'No se pudo enviar la invitación.';
      });
    }
  }

  // -------- UI --------
  @override
  Widget build(BuildContext context) {
    final displayName = _resolvedDisplayName();
    final email = _resolvedEmail();
    final role = _resolvedRole();
    final plan = (_progress['currentModuleId'] ?? 'windows_basics').toString();
    final streakDays = (_progress['streakDays'] ?? 0).toString();
    final overall = (_progress['overallPercent'] ?? 0).toString();
    final points = (_stats['points'] ?? 0).toString();

    if (_snack != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_snack!)));
        _snack = null;
      });
    }

    return AppScaffold(
      currentTab: AppTab.profile,
      onNavigateToTab: (tab) async {
        switch (tab) {
          case AppTab.home:
            if (!mounted) return;
            await Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AppIndexPage()),
              (_) => false,
            );
            break;
          case AppTab.modules:
            if (!mounted) return;
            await Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AppIndexPage()),
              (_) => false,
            );
            break;
          case AppTab.friends:
            if (!mounted) return;
            // Navega a la pantalla real de Amigos por ruta
            await Navigator.of(context).pushReplacementNamed('/friends');
            break;
          case AppTab.profile:
            // ya estás aquí
            break;
        }
      },
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ProfileOverviewCard(
                      presenceText: _presenceText,
                      isOnline: _isOnline,
                      headerRole: role,
                      headerRoleIcon: _roleIcon(role),
                      displayName: displayName,
                      photoUrl: _photoUrl,
                      initials: _initials(displayName),
                      chips: [
                        _ProfileChip(
                          icon: Icons.local_fire_department_rounded,
                          label: 'Racha',
                          value: '$streakDays dias',
                        ),
                        _ProfileChip(
                          icon: Icons.bolt_rounded,
                          label: 'XP total',
                          value: points,
                        ),
                        _ProfileChip(
                          icon: Icons.check_circle_outline_rounded,
                          label: 'Progreso',
                          value: '$overall%',
                        ),
                      ],
                      onEditPressed: _isOwnProfile ? _openEditNameSheet : null,
                      showFriendButton: !_isOwnProfile && _showFriendBtn,
                      friendBusy: _friendBusy,
                      friendLabel: _friendLabel,
                      onFriendPressed: _friendLabel == 'Agregar amigo'
                          ? _sendFriendRequest
                          : null,
                    ),
                    const SizedBox(height: 18),
                    _detailsCard(
                      userId: _targetUserId ?? '-',
                      displayName: displayName,
                      email: email,
                      plan: plan,
                    ),
                    const SizedBox(height: 36),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _detailsCard({
    required String userId,
    required String displayName,
    required String email,
    required String plan,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          _detailsRow('Usuario', userId),
          _detailsRow('Nombre completo', displayName),
          _detailsRow('Correo', email),
          _detailsRow('Módulo actual', plan),
        ],
      ),
    );
  }

Widget _detailsRow(String label, String value) {
  final isUserId = label.toLowerCase().trim() == 'usuario';

  Future<void> copy() async {
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ID copiado al portapapeles')),
    );
  }

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        SizedBox(
          width: 160,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onLongPress: isUserId ? copy : null, // long-press para copiar
                  child: Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF1D2536),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              if (isUserId)
                IconButton(
                  tooltip: 'Copiar ID',
                  onPressed: copy,
                  icon: const Icon(Icons.copy_rounded, size: 18, color: Color(0xFF5564F2)),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

}

// -------- Profile card con icono de estado --------
class _ProfileOverviewCard extends StatelessWidget {
  const _ProfileOverviewCard({
    required this.presenceText,
    required this.isOnline,
    required this.headerRole,
    required this.headerRoleIcon,
    required this.displayName,
    required this.photoUrl,
    required this.initials,
    required this.chips,
    required this.onEditPressed,
    required this.showFriendButton,
    required this.friendBusy,
    required this.friendLabel,
    required this.onFriendPressed,
  });

  final String presenceText;
  final bool isOnline;

  final String headerRole;
  final IconData headerRoleIcon;

  final String displayName;
  final String? photoUrl;
  final String initials;

  final List<_ProfileChip> chips;
  final VoidCallback? onEditPressed;

  final bool showFriendButton;
  final bool friendBusy;
  final String friendLabel;
  final VoidCallback? onFriendPressed;

  @override
  Widget build(BuildContext context) {
    final Color dotColor = isOnline
        ? const Color(0xFF22C55E)
        : const Color(0xFF94A3B8);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5564F2), Color(0xFF7B61FF)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5564F2).withOpacity(0.28),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Encabezado: rol + icono
          Row(
            children: [
              Icon(headerRoleIcon, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                _cap(headerRole),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (showFriendButton)
                FilledButton(
                  onPressed: onFriendPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF5564F2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(friendBusy ? '...' : friendLabel),
                ),
            ],
          ),
          const SizedBox(height: 6),

          // Presencia con icono de estado
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                ).copyWith(color: dotColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  presenceText,
                  style: const TextStyle(
                    color: Color(0xFFD8E0FF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Avatar + Nombre + botón editar abajo del nombre
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(photoUrl: photoUrl, initials: initials),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (onEditPressed != null)
                      FilledButton.tonalIcon(
                        onPressed: onEditPressed,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Editar nombre'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.16),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          Wrap(spacing: 12, runSpacing: 12, children: chips),
        ],
      ),
    );
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.photoUrl, required this.initials});
  final String? photoUrl;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.22),
        border: Border.all(color: Colors.white.withOpacity(0.35), width: 2),
      ),
      child: ClipOval(
        child: (photoUrl != null && photoUrl!.isNotEmpty)
            ? Image.network(
                photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _Initials(initials: initials),
              )
            : _Initials(initials: initials),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.initials});
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withOpacity(0.15),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFD7E3FF),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
