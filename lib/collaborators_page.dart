// lib/collaborators_page.dart
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

class CollaboratorsPage extends StatefulWidget {
  const CollaboratorsPage({super.key});

  static const routeName = '/collaborators';

  @override
  State<CollaboratorsPage> createState() => _CollaboratorsPageState();
}

class _CollaboratorsPageState extends State<CollaboratorsPage>
    with SingleTickerProviderStateMixin {
  final _db = FirebaseDatabase.instance;
  final _auth = FirebaseAuth.instance;

  bool _checking = true;
  bool _allowed = false;
  String _status = 'Validando…';

  // Data
  Map<String, dynamic> _modules = {};
  String? _activeModuleId;

  // Sección activa para el editor de Quizz:
  String? _activeSectionId;

  // ---- helpers comunes (como en tu HTML) ----
  List<String> _objectToArray(dynamic obj) {
    if (obj == null || obj is! Map) return [];
    return obj.values.map((e) => e.toString()).toList();
  }

  Map<String, dynamic> _arrayToObject(List<String> arr, String keyPrefix) {
    final res = <String, dynamic>{};
    for (var i = 0; i < arr.length; i++) {
      res['${keyPrefix}_${(i + 1).toString().padLeft(2, '0')}'] = arr[i];
    }
    return res;
  }

  String _sanitizeId(String raw) {
    final a = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    final b = a.replaceAll(RegExp(r'__+'), '_');
    return b.replaceAll(RegExp(r'^_+|_+$'), '');
    }

  Future<void> _checkRole() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) {
        setState(() {
          _checking = false;
          _allowed = false;
          _status = 'No autenticado.';
        });
        return;
      }
      final snap = await _db.ref('users/$uid/profile/role').get();
      final role = snap.value?.toString() ?? '';
      setState(() {
        _allowed = (role == 'colaborador');
        _checking = false;
        _status = _allowed ? 'Acceso concedido' : 'No tienes permisos';
      });
      if (_allowed) {
        await _loadModules();
      }
    } catch (e) {
      setState(() {
        _checking = false;
        _allowed = false;
        _status = 'Error verificando permisos';
      });
    }
  }

  Future<void> _loadModules({String? preferId}) async {
    final snap = await _db.ref('learningModules').get();
    final data = (snap.exists && snap.value is Map)
        ? Map<String, dynamic>.from(snap.value as Map)
        : <String, dynamic>{};
    final sortedIds = data.keys.toList()
      ..sort((a, b) {
        final ao = (data[a]?['order'] ?? 0) as num;
        final bo = (data[b]?['order'] ?? 0) as num;
        return ao.compareTo(bo);
      });
    setState(() {
      _modules = data;
      if (sortedIds.isEmpty) {
        _activeModuleId = null;
        _activeSectionId = null;
      } else {
        _activeModuleId =
            (preferId != null && data.containsKey(preferId)) ? preferId : sortedIds.first;
        // cuando cambie módulo, limpia selección de sección para quizz
        _activeSectionId = null;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _checkRole();
  }

  // ---------------- UI helpers ----------------

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

  Widget _card(Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 18,
            offset: const Offset(0, 12),
          )
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: child,
    );
  }

  // ---------------- TAB 1: MÓDULO ----------------

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Colaboradores'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_allowed) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Colaboradores'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              _status,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Color(0xFF6B7280)),
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(
            children: [
              const SizedBox(width: 12),
              _badge('Colaboradores'),
              const SizedBox(width: 8),
              const Text(
                'Panel',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Módulo'),
              Tab(text: 'Secciones'),
              Tab(text: 'Quizz de sección'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _tabModulo(context),
            _tabSecciones(context),
            _tabQuizz(context),
          ],
        ),
      ),
    );
  }

  // ---------- TAB MÓDULO ----------
  Widget _tabModulo(BuildContext context) {
    final ids = _modules.keys.toList()
      ..sort((a, b) {
        final ao = (_modules[a]?['order'] ?? 0) as num;
        final bo = (_modules[b]?['order'] ?? 0) as num;
        return ao.compareTo(bo);
      });

    final m = _activeModuleId != null ? (_modules[_activeModuleId!] as Map?)?.cast<String, dynamic>() ?? {} : {};

    final titleCtl = TextEditingController(text: (m['title'] ?? '').toString());
    final descCtl = TextEditingController(text: (m['description'] ?? '').toString());
    final hoursCtl = TextEditingController(text: ((m['estimatedHours'] ?? 0).toString()));
    final orderCtl = TextEditingController(text: ((m['order'] ?? 1).toString()));

    String level = (m['level'] ?? 'basico').toString();
    String status = (m['module_status'] ?? 'borrador').toString();

    final tags = _objectToArray(m['tags']);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Módulo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _activeModuleId != null && ids.contains(_activeModuleId) ? _activeModuleId : (ids.isEmpty ? null : ids.first),
                  items: [
                    for (final id in ids)
                      DropdownMenuItem(value: id, child: Text(_modules[id]?['title']?.toString() ?? id)),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Seleccionar módulo',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    setState(() {
                      _activeModuleId = v;
                      _activeSectionId = null; // reseteo para quizz
                    });
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _loadModules(preferId: _activeModuleId),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Recargar'),
                    ),
                    const SizedBox(width: 8),
                    if (_activeModuleId != null)
                      OutlinedButton.icon(
                        onPressed: () async {
                          final confirm = await _confirm(context, '¿Eliminar módulo "$_activeModuleId" y su contenido?');
                          if (confirm) {
                            await _db.ref('learningModules/$_activeModuleId').remove();
                            await _loadModules();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Módulo eliminado')));
                            }
                          }
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Eliminar módulo'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Datos del módulo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 10),
                if (_activeModuleId != null) Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _badge('ID: $_activeModuleId'),
                    _badge('Estado: ${status.isEmpty ? '-' : status}'),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: titleCtl,
                  decoration: const InputDecoration(
                    labelText: 'Título',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtl,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: level,
                        items: const [
                          DropdownMenuItem(value: 'basico', child: Text('Básico')),
                          DropdownMenuItem(value: 'intermedio', child: Text('Intermedio')),
                          DropdownMenuItem(value: 'avanzado', child: Text('Avanzado')),
                        ],
                        onChanged: (v) => level = v ?? 'basico',
                        decoration: const InputDecoration(labelText: 'Nivel', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: hoursCtl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Horas estimadas', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: orderCtl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Orden', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: status,
                  items: const [
                    DropdownMenuItem(value: 'borrador', child: Text('borrador')),
                    DropdownMenuItem(value: 'publicado', child: Text('publicado')),
                    DropdownMenuItem(value: 'archivado', child: Text('archivado')),
                  ],
                  onChanged: (v) => status = v ?? 'borrador',
                  decoration: const InputDecoration(labelText: 'Estado del módulo', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ElevatedButton.icon(
                    onPressed: _activeModuleId == null
                        ? null
                        : () async {
                            final payload = {
                              'title': titleCtl.text.trim(),
                              'description': descCtl.text.trim(),
                              'level': level,
                              'estimatedHours': int.tryParse(hoursCtl.text.trim()) ?? 0,
                              'order': int.tryParse(orderCtl.text.trim()) ?? 1,
                              'module_status': status,
                              'updatedAt': ServerValue.timestamp,
                            };
                            await _db.ref('learningModules/$_activeModuleId').update(payload);
                            await _loadModules(preferId: _activeModuleId);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Módulo guardado')));
                            }
                          },
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Guardar módulo'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            _ModuleTagsEditor(
              tags: tags,
              onAdd: (tag) async {
                if (_activeModuleId == null) return;
                final current = _objectToArray(_modules[_activeModuleId!]?['tags']);
                if (current.contains(tag)) return;
                final next = _arrayToObject([...current, tag], 'tag');
                await _db.ref('learningModules/$_activeModuleId/tags').set(next);
                await _loadModules(preferId: _activeModuleId);
              },
              onRemove: (tag) async {
                if (_activeModuleId == null) return;
                final current = _objectToArray(_modules[_activeModuleId!]?['tags'])..remove(tag);
                final next = _arrayToObject(current, 'tag');
                await _db.ref('learningModules/$_activeModuleId/tags').set(next);
                await _loadModules(preferId: _activeModuleId);
              },
            ),
          ),
          const SizedBox(height: 12),
          _card(
            _CreateModuleForm(
              onCreate: (id, title, order, level, hours, desc) async {
                final moduleId = _sanitizeId(id);
                if (moduleId.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ID inválido')));
                  return;
                }
                final payload = {
                  'title': title.isEmpty ? '(Sin título)' : title,
                  'description': desc,
                  'level': level,
                  'estimatedHours': hours,
                  'order': order,
                  'module_status': 'borrador',
                  'createdAt': ServerValue.timestamp,
                  'updatedAt': ServerValue.timestamp,
                };
                await _db.ref('learningModules/$moduleId').set(payload);
                await _loadModules(preferId: moduleId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Módulo creado')));
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------- TAB SECCIONES ----------
  Widget _tabSecciones(BuildContext context) {
    final module = _activeModuleId != null
        ? (_modules[_activeModuleId!] as Map?)?.cast<String, dynamic>() ?? {}
        : {};
    final sections = (module['sections'] as Map?)?.cast<String, dynamic>() ?? {};
    final entries = sections.entries
        .map((e) => MapEntry(e.key, (e.value as Map).cast<String, dynamic>()))
        .toList()
      ..sort((a, b) => ((a.value['order'] ?? 0) as num).compareTo((b.value['order'] ?? 0) as num));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Secciones del módulo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 8),
                if (_activeModuleId == null)
                  const Text('Selecciona o crea un módulo en la primera pestaña.', style: TextStyle(color: Color(0xFF64748B)))
                else if (entries.isEmpty)
                  const Text('Este módulo no tiene secciones todavía.', style: TextStyle(color: Color(0xFF64748B)))
                else
                  Column(
                    children: [
                      for (final e in entries)
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${e.key} — ${e.value['title'] ?? '(sin título)'}  '
                                  '(${e.value['contentType'] ?? '-'})  [${e.value['order'] ?? 0}]',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: () {
                                  _openSectionEditor(context, e.key);
                                },
                                child: const Text('Editar'),
                              ),
                              const SizedBox(width: 6),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFDC2626),
                                ),
                                onPressed: () async {
                                  final ok = await _confirm(context, '¿Eliminar la sección "${e.key}"?');
                                  if (!ok) return;
                                  await _db.ref('learningModules/$_activeModuleId/sections/${e.key}').remove();
                                  await _db
                                      .ref('learningModules/$_activeModuleId')
                                      .update({'updatedAt': ServerValue.timestamp});
                                  await _loadModules(preferId: _activeModuleId);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sección eliminada')));
                                  }
                                },
                                child: const Text('Eliminar'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            _SectionEditorLauncher(
              hasModule: _activeModuleId != null,
              onCreateNew: () {
                _openSectionEditor(context, null); // nueva
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSectionEditor(BuildContext context, String? sectionId) async {
    // Navega a un editor en pantalla completa (bottom sheet o page).
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SectionEditorPage(
          moduleId: _activeModuleId!,
          sectionId: sectionId, // null => nueva
          onSaved: () async {
            await _loadModules(preferId: _activeModuleId);
            // sincroniza pestaña de Quizz con la sección recién editada/creada
            setState(() {
              _activeSectionId = sectionId;
            });
          },
        ),
      ),
    );
  }

  // ---------- TAB QUIZZ ----------
  Widget _tabQuizz(BuildContext context) {
    if (_activeModuleId == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Text('Selecciona o crea un módulo primero.'),
        ),
      );
    }
    final sections =
        ((_modules[_activeModuleId!]?['sections'] as Map?)?.cast<String, dynamic>()) ?? {};
    final secIds = sections.keys.toList()
      ..sort((a, b) {
        final ao = (sections[a]?['order'] ?? 0) as num;
        final bo = (sections[b]?['order'] ?? 0) as num;
        return ao.compareTo(bo);
      });

    // si no hay selección, elige la primera para facilitar
    final selSecId = _activeSectionId ?? (secIds.isNotEmpty ? secIds.first : null);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Quizz de la sección', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 8),
                if (secIds.isEmpty)
                  const Text('Este módulo no tiene secciones.', style: TextStyle(color: Color(0xFF64748B)))
                else
                  DropdownButtonFormField<String>(
                    value: selSecId,
                    items: [
                      for (final id in secIds)
                        DropdownMenuItem(
                          value: id,
                          child: Text('${sections[id]?['title'] ?? id}  (${sections[id]?['contentType'] ?? '-'})'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _activeSectionId = v),
                    decoration: const InputDecoration(
                      labelText: 'Selecciona una sección',
                      border: OutlineInputBorder(),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (selSecId != null)
            _card(
              _QuizEditor(
                moduleId: _activeModuleId!,
                sectionId: selSecId,
                section: Map<String, dynamic>.from(sections[selSecId] as Map),
                onSaved: () async {
                  await _loadModules(preferId: _activeModuleId);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quizz guardado')));
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<bool> _confirm(BuildContext ctx, String msg) async {
    final v = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Confirmar'),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sí')),
        ],
      ),
    );
    return v ?? false;
  }
}

// ============== Widgets auxiliares ==============

// --- Tags de módulo ---
class _ModuleTagsEditor extends StatefulWidget {
  const _ModuleTagsEditor({
    required this.tags,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> tags;
  final Future<void> Function(String) onAdd;
  final Future<void> Function(String) onRemove;

  @override
  State<_ModuleTagsEditor> createState() => _ModuleTagsEditorState();
}

class _ModuleTagsEditorState extends State<_ModuleTagsEditor> {
  final _tagCtl = TextEditingController();

  @override
  void dispose() {
    _tagCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Etiquetas del módulo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (widget.tags.isEmpty)
              _chipDisabled('Sin etiquetas'),
            for (final t in widget.tags)
              _tagChip(t, onRemove: () => widget.onRemove(t)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tagCtl,
                decoration: const InputDecoration(
                  labelText: 'Nueva etiqueta',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () async {
                final v = _tagCtl.text.trim();
                if (v.isEmpty) return;
                await widget.onAdd(v);
                if (mounted) _tagCtl.clear();
              },
              child: const Text('Agregar'),
            )
          ],
        ),
      ],
    );
  }

  Widget _tagChip(String t, {required VoidCallback onRemove}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF3FB),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t, style: const TextStyle(color: Color(0xFF1D2536), fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          InkWell(
            onTap: onRemove,
            child: const Icon(Icons.close, size: 16, color: Color(0xFFDC2626)),
          ),
        ],
      ),
    );
  }

  Widget _chipDisabled(String t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(t, style: const TextStyle(color: Color(0xFF64748B))),
    );
  }
}

// --- Crear nuevo módulo ---
class _CreateModuleForm extends StatefulWidget {
  const _CreateModuleForm({required this.onCreate});
  final Future<void> Function(
    String id,
    String title,
    int order,
    String level,
    int hours,
    String desc,
  ) onCreate;

  @override
  State<_CreateModuleForm> createState() => _CreateModuleFormState();
}

class _CreateModuleFormState extends State<_CreateModuleForm> {
  final idCtl = TextEditingController();
  final titleCtl = TextEditingController();
  final orderCtl = TextEditingController(text: '1');
  final levelCtl = ValueNotifier<String>('basico');
  final hoursCtl = TextEditingController(text: '6');
  final descCtl = TextEditingController();

  @override
  void dispose() {
    idCtl.dispose();
    titleCtl.dispose();
    orderCtl.dispose();
    levelCtl.dispose();
    hoursCtl.dispose();
    descCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Crear nuevo módulo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: idCtl,
                decoration: const InputDecoration(
                  labelText: 'Identificador (único)',
                  hintText: 'windows_basics',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: titleCtl,
                decoration: const InputDecoration(
                  labelText: 'Título',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: orderCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Orden', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: levelCtl,
                builder: (_, value, __) => DropdownButtonFormField<String>(
                  value: value,
                  items: const [
                    DropdownMenuItem(value: 'basico', child: Text('Básico')),
                    DropdownMenuItem(value: 'intermedio', child: Text('Intermedio')),
                    DropdownMenuItem(value: 'avanzado', child: Text('Avanzado')),
                  ],
                  onChanged: (v) => levelCtl.value = v ?? 'basico',
                  decoration: const InputDecoration(labelText: 'Nivel', border: OutlineInputBorder()),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: hoursCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Horas', border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: descCtl,
          decoration: const InputDecoration(labelText: 'Descripción', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton.icon(
            onPressed: () async {
              await widget.onCreate(
                idCtl.text.trim(),
                titleCtl.text.trim(),
                int.tryParse(orderCtl.text.trim()) ?? 1,
                levelCtl.value,
                int.tryParse(hoursCtl.text.trim()) ?? 0,
                descCtl.text.trim(),
              );
              if (!mounted) return;
              idCtl.clear();
              titleCtl.clear();
              orderCtl.text = '1';
              levelCtl.value = 'basico';
              hoursCtl.text = '6';
              descCtl.clear();
            },
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Crear módulo'),
          ),
        ),
      ],
    );
  }
}

// --- Launcher del editor de sección ---
class _SectionEditorLauncher extends StatelessWidget {
  const _SectionEditorLauncher({required this.hasModule, required this.onCreateNew});
  final bool hasModule;
  final VoidCallback onCreateNew;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Nueva / Editar sección', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: hasModule ? onCreateNew : null,
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Crear sección'),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Tip: toca “Editar” en la lista superior para cargar una sección existente.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// --- Página de editor de sección (pantalla completa) ---
class _SectionEditorPage extends StatefulWidget {
  const _SectionEditorPage({
    required this.moduleId,
    required this.sectionId,
    required this.onSaved,
  });

  final String moduleId;
  final String? sectionId; // null => nueva
  final Future<void> Function() onSaved;

  @override
  State<_SectionEditorPage> createState() => _SectionEditorPageState();
}

class _SectionEditorPageState extends State<_SectionEditorPage> {
  final _db = FirebaseDatabase.instance;

  bool _loading = true;
  String? _editingId; // si es edición

  // campos
  final titleCtl = TextEditingController();
  final objCtl = TextEditingController();
  final bodyCtl = TextEditingController();
  final minutesCtl = TextEditingController(text: '25');
  final orderCtl = TextEditingController(text: '1');
  String contentType = 'lectura';
  String secStatus = 'borrador';

  // colecciones
  final List<String> secTags = [];
  final List<String> expectedLearning = [];
  final List<String> checklist = [];
  final List<String> checkpoints = [];

  // actividades
  final List<_ActivityModel> activities = [];

  // recurso
  String resType = 'pdf';
  final resTitleCtl = TextEditingController();
  final resUrlCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.sectionId == null) {
      setState(() => _loading = false);
      return;
    }
    final snap = await _db.ref('learningModules/${widget.moduleId}/sections/${widget.sectionId}').get();
    if (snap.exists && snap.value is Map) {
      final s = Map<String, dynamic>.from(snap.value as Map);
      _editingId = widget.sectionId;

      titleCtl.text = (s['title'] ?? '').toString();
      objCtl.text = (s['objective'] ?? '').toString();
      bodyCtl.text = (s['body'] ?? '').toString();
      contentType = (s['contentType'] ?? 'lectura').toString();
      minutesCtl.text = ((s['estimatedMinutes'] ?? 25).toString());
      orderCtl.text = ((s['order'] ?? 1).toString());
      secStatus = (s['sec_status'] ?? 'borrador').toString();

      // tags
      secTags.clear();
      secTags.addAll((s['tags'] is Map) ? s['tags'].values.map((e) => e.toString()) : const Iterable.empty());

      // expected learning
      expectedLearning.clear();
      expectedLearning.addAll((s['expectedLearning'] is Map)
          ? s['expectedLearning'].values.map((e) => e.toString())
          : const Iterable.empty());

      // checklist
      checklist.clear();
      checklist.addAll((s['checklist'] is Map) ? s['checklist'].values.map((e) => e.toString()) : const Iterable.empty());

      // checkpoints
      checkpoints.clear();
      checkpoints.addAll((s['checkpoints'] is Map) ? s['checkpoints'].values.map((e) => e.toString()) : const Iterable.empty());

      // actividades
      activities.clear();
      if (s['activities'] is Map) {
        final acts = Map<String, dynamic>.from(s['activities'] as Map);
        final sorted = acts.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        for (final e in sorted) {
          final a = Map<String, dynamic>.from(e.value as Map);
          final steps = (a['steps'] is Map)
              ? List<String>.from(a['steps'].values.map((x) => x.toString()))
              : <String>[];
          activities.add(_ActivityModel(title: (a['title'] ?? 'Actividad').toString(), steps: steps));
        }
      }

      // recurso
      resType = (s['resources']?['type'] ?? 'pdf').toString();
      resTitleCtl.text = (s['resources']?['title'] ?? '').toString();
      resUrlCtl.text = (s['resources']?['url'] ?? '').toString();
    }
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    titleCtl.dispose();
    objCtl.dispose();
    bodyCtl.dispose();
    minutesCtl.dispose();
    orderCtl.dispose();
    resTitleCtl.dispose();
    resUrlCtl.dispose();
    super.dispose();
  }

  String _nextSectionId(Map<String, dynamic> secs) {
    final nums = secs.keys.map((k) {
      final m = RegExp(r'^sec_(\d{2})$').firstMatch(k);
      return m != null ? int.tryParse(m.group(1)!) ?? 0 : 0;
    }).toList();
    final n = (nums.isEmpty ? 0 : nums.reduce(max)) + 1;
    return 'sec_${n.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    final moduleRef = _db.ref('learningModules/${widget.moduleId}');
    final moduleSnap = await moduleRef.get();
    if (!moduleSnap.exists) return;

    final data = Map<String, dynamic>.from(moduleSnap.value as Map);
    final secs = (data['sections'] as Map?)?.cast<String, dynamic>() ?? {};

    final secId = _editingId ?? _nextSectionId(secs);

    // payload
    final payload = <String, dynamic>{
      'title': titleCtl.text.trim(),
      'objective': objCtl.text.trim(),
      'contentType': contentType,
      'estimatedMinutes': int.tryParse(minutesCtl.text.trim()) ?? 25,
      'order': int.tryParse(orderCtl.text.trim()) ?? 1,
      'sec_status': secStatus,
      'body': bodyCtl.text.trim(),
    };

    if (secTags.isNotEmpty) payload['tags'] = _toObj(secTags, 'sec_tag');
    if (expectedLearning.isNotEmpty) payload['expectedLearning'] = _toObj(expectedLearning, 'exp_learn');
    if (checklist.isNotEmpty) payload['checklist'] = _toObj(checklist, 'chcklst');
    if (checkpoints.isNotEmpty) payload['checkpoints'] = _toObj(checkpoints, 'chkpnt');

    if (resTitleCtl.text.trim().isNotEmpty || resUrlCtl.text.trim().isNotEmpty) {
      payload['resources'] = {
        'title': resTitleCtl.text.trim(),
        'type': resType,
        'url': resUrlCtl.text.trim(),
      };
    }

    await _db.ref('learningModules/${widget.moduleId}/sections/$secId').update(payload);
    await moduleRef.update({'updatedAt': ServerValue.timestamp});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sección guardada')));
    }
    await widget.onSaved();
    if (mounted) Navigator.pop(context);
  }

  Map<String, dynamic> _toObj(List<String> list, String prefix) {
    final o = <String, dynamic>{};
    for (var i = 0; i < list.length; i++) {
      o['${prefix}_${(i + 1).toString().padLeft(2, '0')}'] = list[i];
    }
    return o;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editingId == null ? 'Nueva sección' : 'Editar sección ($_editingId)'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: const Text('Guardar'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Datos generales
                  _block(
                    title: 'Datos generales',
                    child: Column(
                      children: [
                        TextField(
                          controller: titleCtl,
                          decoration: const InputDecoration(labelText: 'Título', border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: objCtl,
                          decoration: const InputDecoration(labelText: 'Objetivo', border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: contentType,
                                items: const [
                                  DropdownMenuItem(value: 'lectura', child: Text('lectura')),
                                  DropdownMenuItem(value: 'practica', child: Text('practica')),
                                  DropdownMenuItem(value: 'video', child: Text('video')),
                                  DropdownMenuItem(value: 'evaluacion', child: Text('evaluacion')),
                                ],
                                onChanged: (v) => setState(() => contentType = v ?? 'lectura'),
                                decoration: const InputDecoration(labelText: 'Tipo de contenido', border: OutlineInputBorder()),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: minutesCtl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Minutos', border: OutlineInputBorder()),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: orderCtl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Orden', border: OutlineInputBorder()),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: secStatus,
                                items: const [
                                  DropdownMenuItem(value: 'borrador', child: Text('borrador')),
                                  DropdownMenuItem(value: 'publicada', child: Text('publicada')),
                                  DropdownMenuItem(value: 'archivada', child: Text('archivada')),
                                ],
                                onChanged: (v) => setState(() => secStatus = v ?? 'borrador'),
                                decoration: const InputDecoration(labelText: 'Estado', border: OutlineInputBorder()),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: bodyCtl,
                          maxLines: 6,
                          decoration: const InputDecoration(
                            labelText: 'Contenido (texto largo)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Tags / Expected / Checklist / Checkpoints
                  _block(
                    title: 'Etiquetas',
                    child: _EditableChips(
                      items: secTags,
                      onAdd: (v) => setState(() => secTags.add(v)),
                      onRemove: (v) => setState(() => secTags.remove(v)),
                      hint: 'Nueva etiqueta',
                    ),
                  ),
                  const SizedBox(height: 12),

                  _block(
                    title: 'Resultados de aprendizaje',
                    child: _EditableList(
                      items: expectedLearning,
                      placeholder: 'Nuevo resultado…',
                    ),
                  ),
                  const SizedBox(height: 12),

                  _block(
                    title: 'Checklist',
                    child: _EditableList(
                      items: checklist,
                      placeholder: 'Nuevo ítem…',
                    ),
                  ),
                  const SizedBox(height: 12),

                  _block(
                    title: 'Checkpoints',
                    child: _EditableList(
                      items: checkpoints,
                      placeholder: 'Nuevo checkpoint…',
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Actividades
                  _block(
                    title: 'Actividades',
                    child: Column(
                      children: [
                        for (var i = 0; i < activities.length; i++)
                          _ActivityEditor(
                            key: ValueKey('act_$i'),
                            model: activities[i],
                            onRemove: () => setState(() => activities.removeAt(i)),
                          ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () => setState(() => activities.add(_ActivityModel(title: 'Actividad', steps: []))),
                            icon: const Icon(Icons.add),
                            label: const Text('Agregar actividad'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Recurso
                  _block(
                    title: 'Recurso único',
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: resType,
                                items: const [
                                  DropdownMenuItem(value: 'pdf', child: Text('pdf')),
                                  DropdownMenuItem(value: 'video', child: Text('video')),
                                  DropdownMenuItem(value: 'enlace', child: Text('enlace')),
                                ],
                                onChanged: (v) => setState(() => resType = v ?? 'pdf'),
                                decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: resTitleCtl,
                                decoration: const InputDecoration(labelText: 'Título del recurso', border: OutlineInputBorder()),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: resUrlCtl,
                          decoration: const InputDecoration(labelText: 'URL', border: OutlineInputBorder()),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save),
                      label: const Text('Guardar sección'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _block({required String title, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _EditableChips extends StatefulWidget {
  const _EditableChips({
    required this.items,
    required this.onAdd,
    required this.onRemove,
    this.hint = 'Nuevo…',
  });

  final List<String> items;
  final void Function(String) onAdd;
  final void Function(String) onRemove;
  final String hint;

  @override
  State<_EditableChips> createState() => _EditableChipsState();
}

class _EditableChipsState extends State<_EditableChips> {
  final ctl = TextEditingController();

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (widget.items.isEmpty)
              const Text('Sin etiquetas', style: TextStyle(color: Color(0xFF64748B))),
            for (final t in widget.items)
              Chip(
                label: Text(t),
                onDeleted: () => widget.onRemove(t),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: ctl,
                decoration: InputDecoration(
                  labelText: widget.hint,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                final v = ctl.text.trim();
                if (v.isEmpty) return;
                widget.onAdd(v);
                ctl.clear();
                setState(() {});
              },
              child: const Text('Agregar'),
            )
          ],
        ),
      ],
    );
  }
}

class _EditableList extends StatefulWidget {
  const _EditableList({required this.items, this.placeholder = 'Nuevo…'});
  final List<String> items;
  final String placeholder;

  @override
  State<_EditableList> createState() => _EditableListState();
}

class _EditableListState extends State<_EditableList> {
  final ctl = TextEditingController();

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < widget.items.length; i++)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFF),
              border: Border.all(color: const Color(0xFFE5E7EB)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(child: Text(widget.items[i])),
                IconButton(
                  onPressed: () => setState(() => widget.items.removeAt(i)),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: ctl,
                decoration: InputDecoration(
                  labelText: widget.placeholder,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () {
                final v = ctl.text.trim();
                if (v.isEmpty) return;
                setState(() {
                  widget.items.add(v);
                  ctl.clear();
                });
              },
              child: const Text('Agregar'),
            ),
          ],
        )
      ],
    );
  }
}

class _ActivityModel {
  _ActivityModel({required this.title, required this.steps});
  String title;
  List<String> steps;
}

class _ActivityEditor extends StatefulWidget {
  const _ActivityEditor({super.key, required this.model, required this.onRemove});
  final _ActivityModel model;
  final VoidCallback onRemove;

  @override
  State<_ActivityEditor> createState() => _ActivityEditorState();
}

class _ActivityEditorState extends State<_ActivityEditor> {
  final titleCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    titleCtl.text = widget.model.title;
  }

  @override
  void dispose() {
    titleCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: titleCtl,
                  onChanged: (v) => widget.model.title = v,
                  decoration: const InputDecoration(labelText: 'Título de la actividad', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: widget.onRemove,
                icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < widget.model.steps.length; i++)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: widget.model.steps[i]),
                      onChanged: (v) => widget.model.steps[i] = v,
                      decoration: InputDecoration(
                        labelText: 'Paso ${i + 1}',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => setState(() => widget.model.steps.removeAt(i)),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => widget.model.steps.add('')),
              icon: const Icon(Icons.add),
              label: const Text('Agregar paso'),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Editor de Quizz (para una sección) ---
class _QuizEditor extends StatefulWidget {
  const _QuizEditor({
    required this.moduleId,
    required this.sectionId,
    required this.section,
    required this.onSaved,
  });

  final String moduleId;
  final String sectionId;
  final Map<String, dynamic> section;
  final Future<void> Function() onSaved;

  @override
  State<_QuizEditor> createState() => _QuizEditorState();
}

class _QuizEditorState extends State<_QuizEditor> {
  final _db = FirebaseDatabase.instance;

  final titleCtl = TextEditingController();
  final pointsCtl = TextEditingController(text: '100');
  final timeCtl = TextEditingController(text: '300');
  String difficulty = 'facil';
  bool shuffle = true;

  final List<_QuestionModel> questions = [];

  @override
  void initState() {
    super.initState();
    _loadFromSection(widget.section);
  }

  void _loadFromSection(Map<String, dynamic> s) {
    final qz = (s['quizz'] as Map?)?.cast<String, dynamic>() ?? {};
    titleCtl.text = (qz['title'] ?? '').toString();
    difficulty = (qz['difficulty'] ?? 'facil').toString();
    pointsCtl.text = ((qz['points'] ?? 100).toString());
    timeCtl.text = ((qz['timeLimitSeconds'] ?? 300).toString());
    shuffle = (qz['shuffleOptions'] == true);

    questions.clear();
    final qs = (qz['questions'] as Map?)?.cast<String, dynamic>() ?? {};
    final entries = qs.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    for (final e in entries) {
      final q = Map<String, dynamic>.from(e.value as Map);
      questions.add(_QuestionModel.fromMap(q));
    }
    setState(() {});
  }

  @override
  void dispose() {
    titleCtl.dispose();
    pointsCtl.dispose();
    timeCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final qs = <String, dynamic>{};
    for (var i = 0; i < questions.length; i++) {
      qs['q${i + 1}'] = questions[i].toMap();
    }
    final payload = {
      'title': titleCtl.text.trim().isEmpty ? 'Evaluación' : titleCtl.text.trim(),
      'difficulty': difficulty,
      'points': int.tryParse(pointsCtl.text.trim()) ?? 0,
      'timeLimitSeconds': int.tryParse(timeCtl.text.trim()) ?? 0,
      'shuffleOptions': shuffle,
      'questions': qs,
    };
    await _db.ref('learningModules/${widget.moduleId}/sections/${widget.sectionId}/quizz').set(payload);
    await _db.ref('learningModules/${widget.moduleId}').update({'updatedAt': ServerValue.timestamp});
    await widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: titleCtl,
          decoration: const InputDecoration(labelText: 'Título', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: difficulty,
                items: const [
                  DropdownMenuItem(value: 'facil', child: Text('facil')),
                  DropdownMenuItem(value: 'media', child: Text('media')),
                  DropdownMenuItem(value: 'dificil', child: Text('dificil')),
                ],
                onChanged: (v) => setState(() => difficulty = v ?? 'facil'),
                decoration: const InputDecoration(labelText: 'Dificultad', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: pointsCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Puntos', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: timeCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Tiempo (seg)', border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          value: shuffle,
          onChanged: (v) => setState(() => shuffle = v),
          title: const Text('Mezclar opciones'),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        const Text('Preguntas', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (var i = 0; i < questions.length; i++)
          _QuestionEditor(
            key: ValueKey('q$i'),
            model: questions[i],
            onRemove: () => setState(() => questions.removeAt(i)),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () => setState(() => questions.add(_QuestionModel(type: 'opcion_multiple'))),
              icon: const Icon(Icons.add),
              label: const Text('Agregar pregunta'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Guardar quizz'),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuestionModel {
  _QuestionModel({
    required this.type,
    this.prompt = '',
    this.correctOption = 'option_0',
    this.options,
    this.answerText = '',
    this.explanation = '',
  });

  String type; // opcion_multiple | vf | completar
  String prompt;
  String correctOption;
  Map<String, String>? options; // para opcion_multiple y vf
  String answerText; // para completar
  String explanation;

  factory _QuestionModel.fromMap(Map<String, dynamic> m) {
    final type = (m['type'] ?? 'opcion_multiple').toString();
    final prompt = (m['prompt'] ?? '').toString();
    final explanation = (m['explanation'] ?? '').toString();
    if (type == 'completar') {
      final ans = (m['answerText'] ?? (m['options']?['option_0'] ?? '')).toString();
      return _QuestionModel(
        type: 'completar',
        prompt: prompt,
        answerText: ans,
        explanation: explanation,
      );
    } else {
      final opts = (m['options'] as Map?)?.cast<String, dynamic>() ?? {};
      final map = <String, String>{};
      for (final e in opts.entries) {
        map[e.key] = e.value.toString();
      }
      final co = (m['correctOption'] ?? 'option_0').toString();
      return _QuestionModel(
        type: type,
        prompt: prompt,
        options: map,
        correctOption: co,
        explanation: explanation,
      );
    }
  }

  Map<String, dynamic> toMap() {
    if (type == 'completar') {
      final ans = (answerText.isEmpty ? (options?['option_0'] ?? '') : answerText);
      return {
        'type': 'completar',
        'prompt': prompt,
        'answerText': ans,
        'options': {'option_0': ans},
        'correctOption': 'option_0',
        if (explanation.trim().isNotEmpty) 'explanation': explanation.trim(),
      };
    } else if (type == 'vf') {
      return {
        'type': 'vf',
        'prompt': prompt,
        'options': {'option_0': 'Verdadero', 'option_1': 'Falso'},
        'correctOption': correctOption,
        if (explanation.trim().isNotEmpty) 'explanation': explanation.trim(),
      };
    } else {
      final opts = options ?? {'option_0': '', 'option_1': ''};
      return {
        'type': 'opcion_multiple',
        'prompt': prompt,
        'options': opts,
        'correctOption': correctOption,
        if (explanation.trim().isNotEmpty) 'explanation': explanation.trim(),
      };
    }
  }
}

class _QuestionEditor extends StatefulWidget {
  const _QuestionEditor({super.key, required this.model, required this.onRemove});
  final _QuestionModel model;
  final VoidCallback onRemove;

  @override
  State<_QuestionEditor> createState() => _QuestionEditorState();
}

class _QuestionEditorState extends State<_QuestionEditor> {
  late String t;
  final promptCtl = TextEditingController();
  final explCtl = TextEditingController();

  // opción múltiple
  final optA = TextEditingController();
  final optB = TextEditingController();
  final optC = TextEditingController();
  final optD = TextEditingController();
  String correct = 'option_0';

  // completar
  final ansCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    t = widget.model.type;
    promptCtl.text = widget.model.prompt;
    explCtl.text = widget.model.explanation;

    if (t == 'completar') {
      ansCtl.text = widget.model.answerText;
    } else if (t == 'vf') {
      correct = widget.model.correctOption;
    } else {
      final opts = widget.model.options ?? {};
      optA.text = opts['option_0'] ?? '';
      optB.text = opts['option_1'] ?? '';
      optC.text = opts['option_2'] ?? '';
      optD.text = opts['option_3'] ?? '';
      correct = widget.model.correctOption;
    }
  }

  @override
  void dispose() {
    promptCtl.dispose();
    explCtl.dispose();
    optA.dispose();
    optB.dispose();
    optC.dispose();
    optD.dispose();
    ansCtl.dispose();
    super.dispose();
  }

  void _persistBack() {
    widget.model.type = t;
    widget.model.prompt = promptCtl.text.trim();
    widget.model.explanation = explCtl.text.trim();
    if (t == 'completar') {
      widget.model.answerText = ansCtl.text.trim();
      widget.model.options = {'option_0': ansCtl.text.trim()};
      widget.model.correctOption = 'option_0';
    } else if (t == 'vf') {
      widget.model.options = {'option_0': 'Verdadero', 'option_1': 'Falso'};
      widget.model.correctOption = correct;
    } else {
      widget.model.options = {
        'option_0': optA.text.trim(),
        'option_1': optB.text.trim(),
        'option_2': optC.text.trim(),
        'option_3': optD.text.trim(),
      };
      widget.model.correctOption = correct;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: t,
                  items: const [
                    DropdownMenuItem(value: 'opcion_multiple', child: Text('opcion_multiple')),
                    DropdownMenuItem(value: 'vf', child: Text('vf')),
                    DropdownMenuItem(value: 'completar', child: Text('completar')),
                  ],
                  onChanged: (v) => setState(() {
                    t = v ?? 'opcion_multiple';
                  }),
                  decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: widget.onRemove,
                icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: promptCtl,
            decoration: const InputDecoration(labelText: 'Enunciado', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          if (t == 'completar') ...[
            TextField(
              controller: ansCtl,
              decoration: const InputDecoration(labelText: 'Respuesta correcta', border: OutlineInputBorder()),
            ),
          ] else if (t == 'vf') ...[
            DropdownButtonFormField<String>(
              value: correct,
              items: const [
                DropdownMenuItem(value: 'option_0', child: Text('Verdadero')),
                DropdownMenuItem(value: 'option_1', child: Text('Falso')),
              ],
              onChanged: (v) => setState(() => correct = v ?? 'option_0'),
              decoration: const InputDecoration(labelText: 'Respuesta correcta', border: OutlineInputBorder()),
            ),
          ] else ...[
            TextField(controller: optA, decoration: const InputDecoration(labelText: 'Opción A', border: OutlineInputBorder())),
            const SizedBox(height: 6),
            TextField(controller: optB, decoration: const InputDecoration(labelText: 'Opción B', border: OutlineInputBorder())),
            const SizedBox(height: 6),
            TextField(controller: optC, decoration: const InputDecoration(labelText: 'Opción C', border: OutlineInputBorder())),
            const SizedBox(height: 6),
            TextField(controller: optD, decoration: const InputDecoration(labelText: 'Opción D (opcional)', border: OutlineInputBorder())),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: correct,
              items: const [
                DropdownMenuItem(value: 'option_0', child: Text('Correcta: A')),
                DropdownMenuItem(value: 'option_1', child: Text('Correcta: B')),
                DropdownMenuItem(value: 'option_2', child: Text('Correcta: C')),
                DropdownMenuItem(value: 'option_3', child: Text('Correcta: D')),
              ],
              onChanged: (v) => setState(() => correct = v ?? 'option_0'),
              decoration: const InputDecoration(labelText: 'Correcta', border: OutlineInputBorder()),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: explCtl,
            decoration: const InputDecoration(labelText: 'Explicación (opcional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                _persistBack();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pregunta actualizada')));
              },
              icon: const Icon(Icons.check),
              label: const Text('Aplicar'),
            ),
          )
        ],
      ),
    );
  }
}
