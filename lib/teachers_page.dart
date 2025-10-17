// lib/teachers_page.dart
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:ticademy/auth_service.dart';

class TeachersPage extends StatefulWidget {
  const TeachersPage({super.key});
  static const routeName = '/teachers';

  @override
  State<TeachersPage> createState() => _TeachersPageState();
}

class _TeachersPageState extends State<TeachersPage>
    with SingleTickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseDatabase.instance;

  final TextEditingController _classNameCtrl = TextEditingController();
  final TextEditingController _inviteEmailCtrl = TextEditingController();

  StreamSubscription<DatabaseEvent>? _modulesSub;
  StreamSubscription<DatabaseEvent>? _classroomsSub;
  StreamSubscription<DatabaseEvent>? _membersSub;
  StreamSubscription<DatabaseEvent>? _invitesSub;

  bool _checking = true;
  bool _allowed = false;
  String _status = 'Validando acceso...';

  Map<String, dynamic> _modules = {};
  String? _selectedModuleId;
  String? _selectedSectionId;

  Map<String, dynamic> _ownedClasses = {};
  String? _selectedClassId;

  Map<String, dynamic> _currentMembers = {};
  List<_ClassInvite> _currentInvites = [];

  bool _creatingClass = false;
  bool _sendingInvite = false;

  bool _reportLoading = false;
  List<_ReportRow> _reportRows = [];
  String? _reportMessage;
  int _reportVersion = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _classNameCtrl.dispose();
    _inviteEmailCtrl.dispose();
    _modulesSub?.cancel();
    _classroomsSub?.cancel();
    _membersSub?.cancel();
    _invitesSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _checking = false;
        _allowed = false;
        _status = 'No autenticado.';
      });
      return;
    }

    try {
      final role = await authService.value.ensureUserRole(user: user);
      if (!mounted) return;
      if (role != 'docente') {
        setState(() {
          _checking = false;
          _allowed = false;
          _status = 'Acceso restringido a docentes.';
        });
        return;
      }

      setState(() {
        _checking = false;
        _allowed = true;
        _status = 'Acceso docente aprobado';
      });

      _modulesSub = _db.ref('learningModules').onValue.listen((event) {
        final value = event.snapshot.value;
        if (!mounted) return;
        if (value is Map) {
          final map = Map<String, dynamic>.from(value);
          final sortedIds = map.keys.toList()
            ..sort((a, b) {
              final ao = (map[a]?['order'] ?? 0) as num;
              final bo = (map[b]?['order'] ?? 0) as num;
              return ao.compareTo(bo);
            });
          setState(() {
            _modules = map;
            _selectedModuleId = sortedIds.isNotEmpty
                ? (_selectedModuleId != null && map.containsKey(_selectedModuleId)
                    ? _selectedModuleId
                    : sortedIds.first)
                : null;
            _selectedSectionId = null;
          });
        } else {
          setState(() {
            _modules = {};
            _selectedModuleId = null;
            _selectedSectionId = null;
          });
        }
      });

      _classroomsSub = _db.ref('classrooms').onValue.listen((event) {
        final value = event.snapshot.value;
        if (!mounted) return;
        if (value is Map) {
          final map = Map<String, dynamic>.from(value)
            ..removeWhere((key, data) =>
                (data is Map ? data['ownerUid'] : null) != _auth.currentUser?.uid);
          final sortedIds = map.keys.toList()
            ..sort((a, b) {
              final ao = (map[a]?['createdAt'] ?? 0) as num? ?? 0;
              final bo = (map[b]?['createdAt'] ?? 0) as num? ?? 0;
              return bo.compareTo(ao);
            });
          final selected = _selectedClassId;
          setState(() {
            _ownedClasses = map;
            _selectedClassId =
                (selected != null && map.containsKey(selected)) ? selected : (sortedIds.isEmpty ? null : sortedIds.first);
          });
          _attachClassDetailListeners();
        } else {
          setState(() {
            _ownedClasses = {};
            _selectedClassId = null;
            _currentMembers = {};
            _currentInvites = [];
          });
          _membersSub?.cancel();
          _invitesSub?.cancel();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _allowed = false;
        _status = 'No se pudo verificar el rol';
      });
    }
  }

  void _attachClassDetailListeners() {
    final classId = _selectedClassId;
    if (classId == null) {
      _membersSub?.cancel();
      _invitesSub?.cancel();
      setState(() {
        _currentMembers = {};
        _currentInvites = [];
      });
      return;
    }

    _membersSub?.cancel();
    _membersSub = _db.ref('classroomMembers/$classId').onValue.listen((event) {
      final value = event.snapshot.value;
      if (!mounted) return;
      if (value is Map) {
        setState(() => _currentMembers = Map<String, dynamic>.from(value));
      } else {
        setState(() => _currentMembers = {});
      }
      _loadReport(classId);
    });

    _invitesSub?.cancel();
    _invitesSub = _db.ref('classroomInvites').onValue.listen((event) {
      final value = event.snapshot.value;
      if (!mounted) return;
      if (value is Map) {
        final invites = <_ClassInvite>[];
        value.forEach((key, raw) {
          if (raw is! Map) return;
          if ((raw['classId'] ?? '') != classId) return;
          if ((raw['ownerUid'] ?? '') != _auth.currentUser?.uid) return;
          invites.add(
            _ClassInvite(
              code: key,
              classId: raw['classId']?.toString() ?? '',
              email: raw['email']?.toString() ?? '',
              createdAt: raw['createdAt'],
            ),
          );
        });
        invites.sort((a, b) =>
            (b.createdAtNum ?? 0).compareTo(a.createdAtNum ?? 0));
        setState(() => _currentInvites = invites);
      } else {
        setState(() => _currentInvites = []);
      }
    });
  }

  Future<void> _createClass() async {
    final name = _classNameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Escribe un nombre para el aula.');
      return;
    }
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() => _creatingClass = true);
    try {
      final ref = _db.ref('classrooms').push();
      await ref.set({
        'name': name,
        'ownerUid': user.uid,
        'createdAt': ServerValue.timestamp,
      });
      _classNameCtrl.clear();
      _snack('Aula creada correctamente.');
    } catch (e) {
      _snack('No se pudo crear el aula. Intenta nuevamente.');
    } finally {
      if (mounted) setState(() => _creatingClass = false);
    }
  }

  Future<void> _deleteClass(String classId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar aula'),
        content: const Text(
          'Esta acción eliminará el aula, sus miembros y sus invitaciones. ¿Deseas continuar?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _status = 'Eliminando aula...');
    try {
      await Future.wait([
        _db.ref('classrooms/$classId').remove(),
        _db.ref('classroomMembers/$classId').remove(),
        _removeRelatedInvites(classId),
      ]);
      if (_selectedClassId == classId) {
        setState(() => _selectedClassId = null);
      }
      _snack('Aula eliminada.');
    } catch (e) {
      _snack('No se pudo eliminar el aula.');
    } finally {
      if (mounted) setState(() => _status = 'Acceso docente aprobado');
    }
  }

  Future<void> _removeRelatedInvites(String classId) async {
    final invitesSnap = await _db.ref('classroomInvites').get();
    if (!invitesSnap.exists) return;
    final batch = <Future>[];
    for (final child in invitesSnap.children) {
      final value = child.value;
      if (value is Map && value['classId'] == classId) {
        batch.add(child.ref.remove());
      }
    }
    await Future.wait(batch);
  }

  Future<void> _sendInvite() async {
    final email = _inviteEmailCtrl.text.trim().toLowerCase();
    if (email.isEmpty) {
      _snack('Escribe el correo del alumno.');
      return;
    }
    final classId = _selectedClassId;
    if (classId == null) {
      _snack('Selecciona un aula primero.');
      return;
    }
    setState(() => _sendingInvite = true);
    try {
      final emailKey = _sanitizeEmailKey(email);
      final uidSnap = await _db.ref('emails/$emailKey').get();
      if (!uidSnap.exists) {
        final code = _generateCode();
        await _db.ref('classroomInvites/$code').set({
          'classId': classId,
          'ownerUid': _auth.currentUser?.uid,
          'email': email,
          'createdAt': ServerValue.timestamp,
          'status': 'pending',
        });
        _inviteEmailCtrl.clear();
        _snack('Invitación generada. Código: $code');
        return;
      }

      final uid = uidSnap.value.toString();
      final roleSnap = await _db.ref('users/$uid/profile/role').get();
      final role = (roleSnap.value ?? '').toString();
      if (role != 'aprendiz') {
        _snack('El usuario debe tener rol aprendiz.');
        return;
      }

      await _db.ref('classroomMembers/$classId/$uid').set({
        'role': 'aprendiz',
        'joinedAt': ServerValue.timestamp,
      });
      _inviteEmailCtrl.clear();
      _snack('Alumno agregado al aula.');
    } catch (e) {
      _snack('No se pudo enviar la invitación.');
    } finally {
      if (mounted) setState(() => _sendingInvite = false);
    }
  }

  Future<void> _loadReport(String classId) async {
    final requestId = ++_reportVersion;
    setState(() {
      _reportLoading = true;
      _reportMessage = null;
      _reportRows = [];
    });
    try {
      final membershipSnap = await _db.ref('classroomMembers/$classId').get();
      if (!membershipSnap.exists) {
        if (!mounted || requestId != _reportVersion) return;
        setState(() {
          _reportRows = [];
          _reportMessage = 'Sin alumnos en el aula';
          _reportLoading = false;
        });
        return;
      }
      final memberIds = membershipSnap.children.map((e) => e.key!).toList();
      final rows = <_ReportRow>[];
      for (final uid in memberIds) {
        final profileSnap = await _db.ref('users/$uid/profile').get();
        final progressSnap = await _db.ref('users/$uid/progress').get();
        final statsSnap = await _db.ref('users/$uid/stats').get();
        rows.add(
          _ReportRow(
            uid: uid,
            name: (profileSnap.child('displayName').value ?? uid).toString(),
            email: (profileSnap.child('email').value ?? '').toString(),
            points: (statsSnap.child('points').value ?? 0).toString(),
            percent: (progressSnap.child('overallPercent').value ?? 0).toString(),
            lastAccess: progressSnap.child('lastAccess').value,
            currentModule: (progressSnap.child('currentModuleId').value ?? '-').toString(),
          ),
        );
      }
      if (!mounted || requestId != _reportVersion) return;
      rows.sort((a, b) => (int.tryParse(b.points) ?? 0).compareTo(int.tryParse(a.points) ?? 0));
      setState(() {
        _reportRows = rows;
        _reportLoading = false;
        _reportMessage = rows.isEmpty ? 'Sin alumnos en el aula' : null;
      });
    } catch (e) {
      if (!mounted || requestId != _reportVersion) return;
      setState(() {
        _reportRows = [];
        _reportLoading = false;
        _reportMessage = 'No se pudo generar el informe';
      });
    }
  }

  // ====================== ESTILO COMPARTIDO ======================
  Widget _badge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF3FB),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBFD9FF)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF1D2536),
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _panel(Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: child,
    );
  }

  // ====================== LOGOUT ======================
  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cerrar sesión: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_allowed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Panel docente')),
        body: Center(child: Text(_status)),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F7FF),
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(
            children: [
              const SizedBox(width: 12),
              _badge('Docentes'),
              const SizedBox(width: 8),
              const Text(
                'Panel',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Cerrar sesión',
              icon: const Icon(Icons.logout),
              onPressed: _logout,
            ),
            const SizedBox(width: 6),
          ],
          bottom: const TabBar(
            isScrollable: true,
            indicatorWeight: 3,
            tabs: [
              Tab(text: 'Contenido'),
              Tab(text: 'Aulas'),
              Tab(text: 'Informes'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildContentTab(),
            _buildClassesTab(),
            _buildReportsTab(),
          ],
        ),
      ),
    );
  }

  // ====================== TABS (RESPONSIVE) ======================

  Widget _buildContentTab() {
    if (_modules.isEmpty) {
      return const Center(child: Text('No hay módulos disponibles.'));
    }
    final moduleId = _selectedModuleId;
    final module = moduleId != null ? _modules[moduleId] as Map<dynamic, dynamic>? : null;
    final sections = module?['sections'] is Map
        ? Map<String, dynamic>.from(module!['sections'] as Map)
        : <String, dynamic>{};

    final sortedSections = sections.keys.toList()
      ..sort((a, b) {
        final ao = (sections[a]?['order'] ?? 0) as num? ?? 0;
        final bo = (sections[b]?['order'] ?? 0) as num? ?? 0;
        return ao.compareTo(bo);
      });

    final selectedSectionId = _selectedSectionId ?? (sortedSections.isNotEmpty ? sortedSections.first : null);
    final selectedSection =
        selectedSectionId != null ? Map<String, dynamic>.from(sections[selectedSectionId] ?? {}) : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 800;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _panel(
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Módulo',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                  value: moduleId,
                  items: _modules.keys
                      .map(
                        (id) => DropdownMenuItem(
                          value: id,
                          child: Text((_modules[id]?['title'] ?? id).toString()),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedModuleId = value;
                      _selectedSectionId = null;
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _sectionsListPanel(sortedSections, sections, selectedSectionId)),
                    const SizedBox(width: 12),
                    Expanded(flex: 3, child: _sectionDetailPanel(selectedSection, selectedSectionId)),
                  ],
                )
              else ...[
                _sectionsListPanel(sortedSections, sections, selectedSectionId),
                const SizedBox(height: 12),
                _sectionDetailPanel(selectedSection, selectedSectionId),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _sectionsListPanel(
    List<String> sortedSections,
    Map<String, dynamic> sections,
    String? selectedSectionId,
  ) {
    return _panel(
      ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(4),
        itemCount: sortedSections.length,
        separatorBuilder: (_, __) => const Divider(height: 10),
        itemBuilder: (_, index) {
          final id = sortedSections[index];
          final section = sections[id] as Map<dynamic, dynamic>? ?? {};
          final isSelected = id == selectedSectionId;
          return ListTile(
            selected: isSelected,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            tileColor: isSelected ? const Color(0xFFF1F5FF) : null,
            title: Text(
              section['title']?.toString() ?? '(Sin título)',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              'Tipo: ${section['contentType'] ?? '-'} · Orden: ${section['order'] ?? 0}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => setState(() => _selectedSectionId = id),
          );
        },
      ),
    );
  }

  Widget _sectionDetailPanel(Map<String, dynamic>? selectedSection, String? selectedSectionId) {
    return _panel(
      Padding(
        padding: const EdgeInsets.all(4),
        child: selectedSection == null
            ? const Center(child: Text('Selecciona una sección para ver los detalles.'))
            : _SectionDetail(sectionId: selectedSectionId!, data: selectedSection),
      ),
    );
  }

  Widget _buildClassesTab() {
    final classes = _ownedClasses.entries.toList()
      ..sort((a, b) => ((b.value['createdAt'] ?? 0) as num? ?? 0)
          .compareTo((a.value['createdAt'] ?? 0) as num? ?? 0));

    final members = _currentMembers.entries.toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 800;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _panel(
                TextField(
                  controller: _classNameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Nombre del aula',
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    suffixIcon: _creatingClass
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: _creatingClass ? null : _createClass,
                          ),
                  ),
                  onSubmitted: (_) => _createClass(),
                ),
              ),
              const SizedBox(height: 12),
              _panel(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mis aulas', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    if (classes.isEmpty)
                      const Text('Aún no has creado aulas.', style: TextStyle(color: Color(0xFF64748B)))
                    else
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: classes.map((entry) {
                          final id = entry.key;
                          final data = Map<String, dynamic>.from(entry.value as Map);
                          final isSelected = id == _selectedClassId;
                          return InputChip(
                            labelPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            selected: isSelected,
                            label: Text(
                              data['name']?.toString() ?? id,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onPressed: () => setState(() => _selectedClassId = id),
                            onDeleted: () => _deleteClass(id),
                            deleteIconColor: Colors.red,
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _membersPanel(members)),
                    const SizedBox(width: 12),
                    Expanded(child: _invitesPanel()),
                  ],
                )
              else ...[
                _membersPanel(members),
                const SizedBox(height: 12),
                _invitesPanel(),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _membersPanel(List<MapEntry<String, dynamic>> members) {
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Integrantes', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          if (members.isEmpty)
            const Text('Sin alumnos todavía.', style: TextStyle(color: Color(0xFF64748B)))
          else
            Column(
              children: members.map((entry) {
                final uid = entry.key;
                final data = Map<String, dynamic>.from(entry.value as Map);
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    title: Text(uid, overflow: TextOverflow.ellipsis),
                    subtitle: Text('Rol: ${data['role'] ?? '-'} · Ingreso: ${_formatDate(data['joinedAt'])}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                      onPressed: () => _db.ref('classroomMembers/$_selectedClassId/$uid').remove(),
                      tooltip: 'Eliminar de aula',
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _invitesPanel() {
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Invitar por correo', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          TextField(
            controller: _inviteEmailCtrl,
            decoration: InputDecoration(
              labelText: 'Correo del alumno',
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              suffixIcon: _sendingInvite
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.send_outlined),
                      onPressed: _sendInvite,
                    ),
            ),
            keyboardType: TextInputType.emailAddress,
            onSubmitted: (_) => _sendInvite(),
          ),
          const SizedBox(height: 16),
          Text('Invitaciones pendientes', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_currentInvites.isEmpty)
            const Text('Sin invitaciones pendientes.', style: TextStyle(color: Color(0xFF64748B)))
          else
            Column(
              children: _currentInvites.map((invite) {
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    title: Text(invite.email.isNotEmpty ? invite.email : invite.code, overflow: TextOverflow.ellipsis),
                    subtitle: Text('Código: ${invite.code} · Enviada: ${_formatDate(invite.createdAt)}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _db.ref('classroomInvites/${invite.code}').remove(),
                      tooltip: 'Eliminar invitación',
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildReportsTab() {
    final classId = _selectedClassId;
    if (_ownedClasses.isEmpty) {
      return const Center(child: Text('Crea un aula para comenzar.'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 800;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _panel(
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Aula',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                  value: classId,
                  items: _ownedClasses.keys
                      .map(
                        (id) => DropdownMenuItem(
                          value: id,
                          child: Text((_ownedClasses[id]?['name'] ?? id).toString()),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _selectedClassId = value),
                ),
              ),
              const SizedBox(height: 12),
              _panel(
                _reportLoading
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : _reportRows.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: Center(child: Text(_reportMessage ?? 'Sin datos')),
                          )
                        : (isWide ? _reportTable() : _reportCards()),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _reportTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Alumno')),
          DataColumn(label: Text('Correo')),
          DataColumn(label: Text('Puntos')),
          DataColumn(label: Text('Progreso')),
          DataColumn(label: Text('Último acceso')),
          DataColumn(label: Text('Módulo actual')),
        ],
        rows: _reportRows
            .map(
              (row) => DataRow(
                cells: [
                  DataCell(Text(row.name)),
                  DataCell(Text(row.email.isEmpty ? '-' : row.email)),
                  DataCell(Text(row.points)),
                  DataCell(Text('${row.percent}%')),
                  DataCell(Text(_formatDate(row.lastAccess))),
                  DataCell(Text(row.currentModule)),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _reportCards() {
    return Column(
      children: _reportRows.map((row) {
        return Card(
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            title: Text(row.name, overflow: TextOverflow.ellipsis),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                Text('Correo: ${row.email.isEmpty ? '-' : row.email}'),
                Text('Puntos: ${row.points} · Progreso: ${row.percent}%'),
                Text('Último acceso: ${_formatDate(row.lastAccess)}'),
                Text('Módulo actual: ${row.currentModule}'),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ====================== HELPERS ======================

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatDate(dynamic value) {
    if (value == null) return '-';
    DateTime? dt;
    if (value is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(value);
    } else if (value is String) {
      dt = DateTime.tryParse(value);
    }
    if (dt == null) return '-';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  String _sanitizeEmailKey(String email) {
    return email.trim().toLowerCase().replaceAll('.', ',').replaceAll(RegExp(r'[^\w@+\-]'), '_');
  }

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final buffer = StringBuffer();
    for (int i = 0; i < 6; i++) {
      buffer.write(chars[(chars.length * (DateTime.now().microsecondsSinceEpoch + i) % chars.length).abs() % chars.length]);
    }
    return buffer.toString();
  }
}

// ====================== WIDGETS AUX ======================

class _SectionDetail extends StatelessWidget {
  const _SectionDetail({required this.sectionId, required this.data});

  final String sectionId;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final tags = data['tags'] is Map ? List<String>.from((data['tags'] as Map).values) : const <String>[];
    final quizz = data['quizz'] is Map ? Map<String, dynamic>.from(data['quizz'] as Map) : null;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sectionId, style: Theme.of(context).textTheme.titleSmall),
            Text(
              data['title']?.toString() ?? '(Sin título)',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(data['objective']?.toString() ?? '(Sin objetivo)'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chipLocal('Tipo: ${data['contentType'] ?? '-'}'),
                _chipLocal('Minutos: ${data['estimatedMinutes'] ?? 0}'),
                _chipLocal('Orden: ${data['order'] ?? 1}'),
                _chipLocal('Estado: ${data['sec_status'] ?? '-'}'),
                for (final tag in tags) _chipLocal(tag),
              ],
            ),
            const SizedBox(height: 16),
            Text(data['body']?.toString() ?? '(Sin contenido)'),
            if (quizz != null) ...[
              const SizedBox(height: 24),
              Text('Quizz: ${quizz['title'] ?? 'Evaluación'}', style: Theme.of(context).textTheme.titleMedium),
              Text('Dificultad: ${quizz['difficulty'] ?? 'fácil'} · Puntos: ${quizz['points'] ?? 0} · Tiempo: ${quizz['timeLimitSeconds'] ?? 0}s'),
              const SizedBox(height: 12),
              if (quizz['questions'] is Map)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: (quizz['questions'] as Map).entries.map((entry) {
                    final q = entry.value as Map? ?? {};
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text('${entry.key}: ${q['prompt'] ?? '-'}'),
                    );
                  }).toList(),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chipLocal(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF3FB),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBFD9FF)),
      ),
      child: Text(text),
    );
  }
}

class _ClassInvite {
  _ClassInvite({required this.code, required this.classId, required this.email, required this.createdAt});
  final String code;
  final String classId;
  final String email;
  final dynamic createdAt;

  int? get createdAtNum => createdAt is int ? createdAt as int : int.tryParse(createdAt?.toString() ?? '');
}

class _ReportRow {
  _ReportRow({
    required this.uid,
    required this.name,
    required this.email,
    required this.points,
    required this.percent,
    required this.lastAccess,
    required this.currentModule,
  });

  final String uid;
  final String name;
  final String email;
  final String points;
  final String percent;
  final dynamic lastAccess;
  final String currentModule;
}
