// lib/module_page.dart
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:ticademy/friends_page.dart';
import 'package:ticademy/ui/app_scaffold.dart';
import 'package:ticademy/progress_service.dart'; // Se usa onQuizSubmitted y recalcUserProgressDerivedFields
import 'package:ticademy/user_profile_page.dart';

class ModulePage extends StatefulWidget {
  const ModulePage({super.key});
  static const routeName = '/module';

  @override
  State<ModulePage> createState() => _ModulePageState();
}

class _ModulePageState extends State<ModulePage> {
  final _db = FirebaseDatabase.instance;
  final _auth = FirebaseAuth.instance;

  // IMPORTANTE: llega por argumentos (String) al hacer pushNamed(ModulePage.routeName, arguments: moduleId)
  String _moduleId = 'windows_basics';

  Map<String, dynamic> _module = {};
  Map<String, dynamic>? _moduleProgress; // users/<uid>/progress/modules/<moduleId>
  Map<String, dynamic>? _quizAttemptsForModule; // users/<uid>/quizAttempts/<moduleId>
  bool _loading = true;
  String? _error;

  // para expand/collapse por sección
  final Set<String> _openSections = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is String && args.trim().isNotEmpty) {
      _moduleId = args;
    }
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final moduleSnap = await _db.ref('learningModules/$_moduleId').get();
      Map<String, dynamic> moduleData = {};
      if (moduleSnap.exists && moduleSnap.value is Map) {
        moduleData = Map<String, dynamic>.from(moduleSnap.value as Map);
      }

      Map<String, dynamic>? moduleProgress;
      Map<String, dynamic>? quizAttemptsModule;
      final user = _auth.currentUser;
      if (user != null) {
        final progressSnap =
            await _db.ref('users/${user.uid}/progress/modules/$_moduleId').get();
        if (progressSnap.exists && progressSnap.value is Map) {
          moduleProgress = Map<String, dynamic>.from(progressSnap.value as Map);
        }
        // 🔄 Ahora leemos SOLO los intentos del módulo actual:
        final attemptsSnap =
            await _db.ref('users/${user.uid}/quizAttempts/$_moduleId').get();
        if (attemptsSnap.exists && attemptsSnap.value is Map) {
          quizAttemptsModule =
              Map<String, dynamic>.from(attemptsSnap.value as Map);
        }
      }

      setState(() {
        _module = moduleData;
        _moduleProgress = moduleProgress;
        _quizAttemptsForModule = quizAttemptsModule; // sectionId -> intento
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar el módulo. Intenta nuevamente.';
      });
    }
  }

  // ===== helpers =====
  int _clampPercent(num? v) {
    final n = (v ?? 0).toInt();
    if (n < 0) return 0;
    if (n > 100) return 100;
    return n;
  }

  String _formatRelative(dynamic value) {
    DateTime? dt;
    if (value is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(value);
    } else if (value is String) {
      dt = DateTime.tryParse(value);
    }
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 2) return 'Hace un momento';
    if (diff.inHours < 1) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    if (diff.inDays < 7) return 'Hace ${diff.inDays} días';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  _SectionProgress _getSectionProgress(String sectionId) {
    final base = _moduleProgress ?? {};
    final sections = (base['sections'] as Map?)?.cast<String, dynamic>() ?? {};
    final current =
        (sections[sectionId] as Map?)?.cast<String, dynamic>() ?? {};
    final percent = _clampPercent(
      current['percent'] ?? (current['completed'] == true ? 100 : 0),
    );
    final completed = (current['completed'] == true) || percent >= 100;
    final last = current['lastUpdated'] ?? current['completedAt'];
    return _SectionProgress(
      percent: percent,
      completed: completed,
      lastUpdated: last,
    );
  }

  /// Antes: recibía quizId global (sec_01, sec_02) y chocaba con otros módulos.
  /// Ahora miramos directamente bajo users/<uid>/quizAttempts/<moduleId>/<sectionId>
  Map<String, dynamic>? _getQuizAttempt(String sectionId) {
    final attempts = _quizAttemptsForModule;
    if (attempts == null) return null;
    final entry = attempts[sectionId];
    if (entry is Map) {
      return Map<String, dynamic>.from(entry);
    }
    return null;
  }

  int _overallPercent() {
    final p = _moduleProgress;
    if (p != null && p['percent'] is num) {
      return _clampPercent(p['percent']);
    }
    final sections =
        (_module['sections'] as Map?)?.cast<String, dynamic>() ?? {};
    if (sections.isEmpty) return 0;
    final entries = sections.entries.toList()
      ..sort((a, b) {
        final ao = ((a.value as Map)['order'] ?? 0) as num;
        final bo = ((b.value as Map)['order'] ?? 0) as num;
        return ao.compareTo(bo);
      });

    int completed = 0;
    for (final e in entries) {
      if (_getSectionProgress(e.key).completed) completed++;
    }
    return _clampPercent(
      entries.isEmpty ? 0 : (completed / entries.length * 100),
    );
  }

  List<String> _normalizedTags(dynamic tags) {
    if (tags == null) return const [];
    if (tags is List) return tags.map((e) => e.toString()).toList();
    if (tags is Map) {
      return tags.values.map((e) => e.toString()).toList();
    }
    return const [];
  }

  // Guardado de resultados de quiz
  Future<void> _saveQuizResult({
    required String sectionId,
    required Map<String, dynamic> quiz,
    required QuizEval evaluation,
    required List<UserAnswer> answers,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final mid = _moduleId;
    final now = DateTime.now().toIso8601String();

    // Usamos el sectionId como quizId lógico
    final quizId = sectionId;

    try {
      await onQuizSubmitted(
        uid: user.uid,
        moduleId: mid,
        sectionId: sectionId,
        quizId: quizId,
        answers: answers,
      );
    } catch (e) {
      // Fallback para mantener consistencia
      await recalcUserProgressDerivedFields(user.uid);
      rethrow;
    }

    Map<String, dynamic>? newAttemptState;
    // 🔄 Nueva ruta: users/<uid>/quizAttempts/<moduleId>/<sectionId>
    final attemptsRef =
        _db.ref('users/${user.uid}/quizAttempts/$mid/$sectionId');

    await attemptsRef.runTransaction((current) {
      final map = current is Map
          ? Map<String, dynamic>.from(current)
          : <String, dynamic>{};

      final prevBest =
          map['bestScore'] is num ? (map['bestScore'] as num).toDouble() : 0.0;

      final earnedRounded = round2(evaluation.earnedPoints);
      final totalPointsRounded =
          evaluation.totalPoints != null ? round2(evaluation.totalPoints!) : null;
      final perQuestionRounded =
          evaluation.perQuestion != null ? round2(evaluation.perQuestion!) : null;

      final newBest = earnedRounded > prevBest ? earnedRounded : prevBest;
      final completedPerfect = map['completedPerfect'] == true ||
          (totalPointsRounded != null && earnedRounded == totalPointsRounded);

      map['attempted'] = true;
      map['bestScore'] = newBest;
      map['completedPerfect'] = completedPerfect;
      map['updatedAt'] = now;
      map['lastScore'] = earnedRounded;
      map['correct'] = evaluation.correct;
      map['totalQuestions'] = evaluation.total;
      if (totalPointsRounded != null) map['totalPoints'] = totalPointsRounded;
      if (perQuestionRounded != null) map['perQuestion'] = perQuestionRounded;
      map.removeWhere((key, value) => value == null);

      newAttemptState = Map<String, dynamic>.from(map);
      return Transaction.success(map);
    });

    // Refrescamos progreso del usuario para el módulo
    final userProg =
        await _db.ref('users/${user.uid}/progress/modules/$mid').get();

    if (userProg.exists && userProg.value is Map) {
      setState(() {
        _moduleProgress = Map<String, dynamic>.from(userProg.value as Map);
        final currentAttempts =
            Map<String, dynamic>.from(_quizAttemptsForModule ?? {});
        if (newAttemptState != null) {
          currentAttempts[sectionId] = newAttemptState;
        }
        _quizAttemptsForModule = currentAttempts;
      });
    } else {
      setState(() {
        _moduleProgress = {'lastUpdated': now};
        final currentAttempts =
            Map<String, dynamic>.from(_quizAttemptsForModule ?? {});
        if (newAttemptState != null) {
          currentAttempts[sectionId] = newAttemptState;
        }
        _quizAttemptsForModule = currentAttempts;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = (_module['title'] ?? 'Módulo').toString();
    final description =
        (_module['description'] ?? 'En breve tendremos más información.').toString();
    final level = (_module['level'] ?? '').toString();
    final hours = (_module['estimatedHours'] ?? '').toString();
    final sections =
        (_module['sections'] as Map?)?.cast<String, dynamic>() ?? {};
    final tags = _normalizedTags(_module['tags']);
    final overall = _overallPercent();

    return AppScaffold(
      currentTab: AppTab.home,
      onNavigateToTab: (tab) async {
        switch (tab) {
          case AppTab.home:
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.pushReplacementNamed(context, '/app');
            }
            break;
          case AppTab.achievements:
            if (!mounted) return;
            await Navigator.of(context).pushNamed('/achievements');
            break;
          case AppTab.friends:
            if (!mounted) return;
            await Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const FriendsPage()));
            break;
          case AppTab.profile:
            if (!mounted) return;
            await Navigator.of(context).pushNamed(UserProfilePage.routeName);
            break;
        }
      },
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _loadAll)
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HeroCard(
                          title: title,
                          description: description,
                          level: level.isEmpty ? null : 'Nivel $level',
                          hours: hours.isEmpty ? null : 'Duración estimada: $hours h',
                          sectionsCount: sections.length,
                          completedCount: sections.isEmpty
                              ? 0
                              : sections.keys
                                  .where((sid) => _getSectionProgress(sid).completed)
                                  .length,
                          overallPercent: overall,
                          tags: tags,
                        ),
                        const SizedBox(height: 18),
                        if (sections.isEmpty)
                          const _EmptyHint(
                            text: 'Aún no se registran lecciones para este módulo.',
                          )
                        else
                          _SectionsGrid(
                            sections: sections,
                            isOpen: (id) => _openSections.contains(id),
                            toggle: (id) {
                              setState(() {
                                if (_openSections.contains(id)) {
                                  _openSections.remove(id);
                                } else {
                                  _openSections.add(id);
                                }
                              });
                            },
                            getProgress: _getSectionProgress,
                            formatRelative: _formatRelative,
                            // 🔄 Ahora la consulta toma sectionId directamente
                            getQuizAttempt: _getQuizAttempt,
                            onSaveQuiz: (sectionId, quiz, evaluation, answers) async {
                              await _saveQuizResult(
                                sectionId: sectionId,
                                quiz: quiz,
                                evaluation: evaluation,
                                answers: answers,
                              );
                            },
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

// ====== UI ======

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.description,
    required this.sectionsCount,
    required this.completedCount,
    required this.overallPercent,
    this.level,
    this.hours,
    this.tags = const [],
  });

  final String title;
  final String description;
  final String? level;
  final String? hours;
  final int sectionsCount;
  final int completedCount;
  final int overallPercent;
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5564F2), Color(0xFF7B61FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5564F2).withOpacity(.28),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
              color: Color(0xFFE6ECFF),
              fontSize: 13.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (level != null) _chip(level!),
              if (hours != null) _chip(hours!),
              _chip('Lecciones: $completedCount/$sectionsCount'),
              _chip('Progreso: $overallPercent%'),
              for (final t in tags) _chip(t),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.25),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (overallPercent.clamp(0, 100)) / 100,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF9DFF5A), Color(0xFF48F1A8)],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SectionsGrid extends StatelessWidget {
  const _SectionsGrid({
    required this.sections,
    required this.isOpen,
    required this.toggle,
    required this.getProgress,
    required this.formatRelative,
    required this.getQuizAttempt,
    required this.onSaveQuiz,
  });

  final Map<String, dynamic> sections;
  final bool Function(String id) isOpen;
  final void Function(String id) toggle;
  final _SectionProgress Function(String id) getProgress;
  final String Function(dynamic v) formatRelative;
  final Map<String, dynamic>? Function(String sectionId) getQuizAttempt;
  final Future<void> Function(
    String sectionId,
    Map<String, dynamic> quiz,
    QuizEval evaluation,
    List<UserAnswer> answers,
  ) onSaveQuiz;

  @override
  Widget build(BuildContext context) {
    final entries = sections.entries
        .map((e) => MapEntry(e.key, (e.value as Map).cast<String, dynamic>()))
        .toList()
      ..sort((a, b) {
        final ao = (a.value['order'] ?? 0) as num;
        final bo = (b.value['order'] ?? 0) as num;
        return ao.compareTo(bo);
      });

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final id = entries[index].key;
        final m = entries[index].value;
        final title = (m['title'] ?? 'Lección').toString();
        final objective = (m['objective'] ?? 'Sin objetivo registrado.').toString();
        final progress = getProgress(id);
        final open = isOpen(id);

        final resources = (m['resources'] as Map?)?.cast<String, dynamic>() ?? {};
        final checklist = (m['checklist'] as Map?)?.cast<String, dynamic>() ?? {};
        final checkpoints =
            (m['checkpoints'] as Map?)?.cast<String, dynamic>() ?? {};
        final activities =
            (m['activities'] as Map?)?.cast<String, dynamic>() ?? {};
        final body = (m['body'] ?? '').toString();

        final orderValue = m['order'];
        final orderText = orderValue != null ? 'Lección $orderValue' : null;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 18,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111827),
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _CompactProgress(percent: progress.percent),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => toggle(id),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFEFF3FB),
                        foregroundColor: const Color(0xFF1D2536),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      child: Text(
                        open ? 'Ocultar' : (progress.percent <= 0 ? 'Empezar' : 'Continuar'),
                      ),
                    ),
                  ],
                ),

                // Meta de estado
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color:
                            progress.completed ? const Color(0xFFD1FAE5) : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        progress.completed ? 'Completada' : 'Pendiente',
                        style: TextStyle(
                          color: progress.completed
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFD97706),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        progress.completed
                            ? (progress.lastUpdated != null
                                ? 'Terminaste esta lección • ${formatRelative(progress.lastUpdated)}'
                                : 'Terminaste esta lección.')
                            : 'Lección en progreso.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),

                // Contenido expandible
                if (open) ...[
                  const SizedBox(height: 12),
                  Text(
                    objective,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Progreso barra
                  _ProgressBar(percent: progress.percent),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${progress.percent}% completado',
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                        ),
                      ),
                      if (orderText != null)
                        Text(
                          orderText,
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),

                  // BODY
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Contenido de la lección',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    ...body
                        .split(RegExp(r'\n{2,}| {2,}'))
                        .map((p) => p.trim())
                        .where((p) => p.isNotEmpty)
                        .map(
                          (p) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              p,
                              style: const TextStyle(
                                color: Color(0xFF475569),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                  ],

                  // Recursos
                  if (resources.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Recursos',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    _BulletList(
                      items: resources.values.map((e) => e.toString()).toList(),
                    ),
                  ],

                  // Checklist
                  if (checklist.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Checklist',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    _PillList(
                      items: checklist.values.map((e) => e.toString()).toList(),
                    ),
                  ],

                  // Checkpoints (read-only)
                  if (checkpoints.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Puntos de verificación',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Column(
                      children: checkpoints.values.map((e) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.check_circle,
                                size: 18,
                                color: Color(0xFF16A34A),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  e.toString(),
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    color: Color(0xFF1F2937),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],

                  // ACTIVIDADES
                  if (activities.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Actividades',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Column(
                      children: activities.entries.map((actEntry) {
                        final act = (actEntry.value as Map).cast<String, dynamic>();
                        final actTitle = (act['title'] ?? 'Actividad').toString();
                        final stepsMap =
                            (act['steps'] as Map?)?.cast<String, dynamic>() ?? {};
                        final steps = stepsMap.entries.toList()
                          ..sort((a, b) => a.key.compareTo(b.key)); // step_01...

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF3FB),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      actTitle,
                                      style: const TextStyle(
                                        color: Color(0xFF1D2536),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),      
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.info_outline,
                                    size: 16,
                                    color: Color(0xFF3B82F6),
                                  ),
                                  Expanded(
                                    child: Text(
                                      'Guía paso a paso de la actividad:',
                                      style: const TextStyle(
                                        color: Color(0xFF475569),
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Column(
                                children: steps.map((s) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Checkbox(
                                          value: true,
                                          onChanged: null, // solo lectura
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            s.value.toString(),
                                            style: const TextStyle(
                                              fontSize: 13.5,
                                              color: Color(0xFF1F2937),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],

                  const SizedBox(height: 14),

                  // ===== EVALUACIÓN =====
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: Builder(
                        builder: (_) {
                          // Ahora usamos el sectionId como quizId lógico
                          final quizMap =
                              (m['quizz'] as Map?)?.cast<String, dynamic>();
                          final quizId = id; // << clave por sección
                          final quizAttempt = getQuizAttempt(id);
                          return _SectionQuiz(
                            sectionId: id,
                            quizId: quizId,
                            sectionMap: m,
                            quizStatus: quizAttempt,
                            onSave: (quiz, evaluation, answers) async {
                              await onSaveQuiz(id, quiz, evaluation, answers);
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CompactProgress extends StatelessWidget {
  const _CompactProgress({required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 6,
          decoration: BoxDecoration(
            color: const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: percent.clamp(0, 100) / 100,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7B61FF), Color(0xFF44E4A9)],
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '$percent% completado',
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: percent.clamp(0, 100) / 100,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7B61FF), Color(0xFF38BDF8)],
              ),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ),
    );
  }
}

class _PillList extends StatelessWidget {
  const _PillList({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF3FB),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              t,
              style: const TextStyle(
                color: Color(0xFF5564F2),
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
      ],
    );
  }
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final s in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.circle, size: 7, color: Color(0xFF6B7280)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s,
                    style: const TextStyle(
                      color: Color(0xFF1F2937),
                      fontSize: 13.5,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF6B7280)),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

// ===== modelos / util =====
double round2(double v) => double.parse(v.toStringAsFixed(2));

class _SectionProgress {
  final int percent;
  final bool completed;
  final dynamic lastUpdated;
  _SectionProgress({
    required this.percent,
    required this.completed,
    required this.lastUpdated,
  });
}

// ====== QUIZ util de evaluación y reportes ======

class QuizEval {
  final int correct;
  final int total;
  final int percent;
  final double earnedPoints;
  final double? perQuestion;
  final double? totalPoints;
  final Map<String, bool> byQuestion; // qid -> correcto?
  QuizEval({
    required this.correct,
    required this.total,
    required this.percent,
    required this.earnedPoints,
    required this.perQuestion,
    required this.totalPoints,
    required this.byQuestion,
  });
}

class ReportItem {
  final int idx;
  final String prompt;
  final bool correct;
  final String? userText;
  final String? correctText;
  final String? explanation;
  ReportItem({
    required this.idx,
    required this.prompt,
    required this.correct,
    this.userText,
    this.correctText,
    this.explanation,
  });
}

String formatSeconds(int s) {
  s = s < 0 ? 0 : s;
  final m = (s ~/ 60);
  final r = s % 60;
  return '$m:${r.toString().padLeft(2, '0')}';
}

QuizEval evaluateQuizDetailed(
  Map<String, dynamic> quiz,
  Map<String, dynamic> answers,
) {
  final qs = (quiz['questions'] as Map?)?.cast<String, dynamic>() ?? {};
  int ok = 0;
  final per = <String, bool>{};
  double? totalPoints;
  final rawTotal = quiz['points'] ?? quiz['maxPoints'] ?? quiz['totalPoints'];
  if (rawTotal is num) {
    totalPoints = rawTotal.toDouble();
  }
  double? perQuestion = quiz['perQuestionPoints'] is num
      ? (quiz['perQuestionPoints'] as num).toDouble()
      : null;

  for (final e in qs.entries) {
    final qid = e.key;
    final q = (e.value as Map).cast<String, dynamic>();
    final type = (q['type'] ?? '').toString();
    bool isCorrect = false;
    if (type == 'completar') {
      final user = (answers[qid] ?? '').toString().trim().toLowerCase();
      final expected =
          (q['answerText'] ?? (q['options']?['option_0'] ?? ''))
              .toString()
              .trim()
              .toLowerCase();
      isCorrect = user.isNotEmpty && expected.isNotEmpty && user == expected;
    } else {
      final correctOption = (q['correctOption'] ?? '').toString();
      isCorrect = answers[qid] != null && answers[qid].toString() == correctOption;
    }
    per[qid] = isCorrect;
    if (isCorrect) ok++;
  }

  final total = qs.length;
  if (perQuestion == null && totalPoints != null && total > 0) {
    perQuestion = round2(totalPoints / total);
  } else if (perQuestion != null) {
    perQuestion = round2(perQuestion);
  }

  final pct = total == 0 ? 0 : ((ok / total) * 100).round();
  double earned;
  if (perQuestion != null && total > 0) {
    if (ok == total && totalPoints != null) {
      earned = round2(totalPoints);
    } else {
      earned = round2(ok * perQuestion);
    }
  } else {
    earned = round2(ok.toDouble());
  }
  final totalRounded = totalPoints != null ? round2(totalPoints) : null;

  return QuizEval(
    correct: ok,
    total: total,
    percent: pct,
    earnedPoints: earned,
    perQuestion: perQuestion,
    totalPoints: totalRounded,
    byQuestion: per,
  );
}

String? _optionText(Map<String, dynamic> q, String? optionId) {
  if ((q['type'] ?? '') == 'completar') return null;
  final opts = (q['options'] as Map?)?.cast<String, dynamic>() ?? {};
  if (optionId == null) return null;
  final v = opts[optionId];
  return v?.toString();
}

List<ReportItem> buildReportItems(
  List<MapEntry<String, Map<String, dynamic>>> list,
  Map<String, dynamic> answers,
  Map<String, dynamic> quiz,
  QuizEval detailed,
) {
  return List.generate(list.length, (i) {
    final qid = list[i].key;
    final q = list[i].value;
    final type = (q['type'] ?? '').toString();

    final userId = answers[qid]?.toString();
    final userText =
        type == 'completar' ? (answers[qid]?.toString() ?? '') : _optionText(q, userId);

    final correctId = type == 'completar' ? null : (q['correctOption'] ?? '').toString();
    final correctText = type == 'completar'
        ? (q['answerText'] ?? (q['options']?['option_0'] ?? '')).toString()
        : _optionText(q, correctId);

    final explanation = (q['explanation'] ?? '').toString();
    final exp = explanation.isEmpty ? null : explanation;

    return ReportItem(
      idx: i + 1,
      prompt: (q['prompt'] ?? 'Pregunta').toString(),
      correct: detailed.byQuestion[qid] == true,
      userText: userText,
      correctText: correctText,
      explanation: exp,
    );
  });
}

// ======== WIDGET DE QUIZ ========

class _SectionQuiz extends StatefulWidget {
  const _SectionQuiz({
    required this.sectionId,
    required this.sectionMap,
    required this.quizId,
    this.quizStatus,
    required this.onSave,
  });

  final String sectionId;
  final Map<String, dynamic> sectionMap;
  final String quizId; // aquí igualamos sectionId
  final Map<String, dynamic>? quizStatus;
  final Future<void> Function(
    Map<String, dynamic> quiz,
    QuizEval evaluation,
    List<UserAnswer> answers,
  ) onSave;

  @override
  State<_SectionQuiz> createState() => _SectionQuizState();
}

class _SectionQuizState extends State<_SectionQuiz> {
  Map<String, dynamic>? _quiz;
  bool _started = false;
  int _remaining = 0;
  Timer? _timer;
  double? _perQuestionPoints;
  double? _totalPointsRaw;
  int _totalQuestions = 0;
  bool _attemptedOnce = false;
  bool _perfectLocked = false;

  // respuestas del usuario
  final Map<String, dynamic> _answers = {};
  QuizEval? _lastResult;

  List<ReportItem>? _lastReportItems;
  String _lastReportSummary = '';
  String _lastReportTitle = '';
  bool _reportOpen = false;

  @override
  void initState() {
    super.initState();
    _prepareQuiz((widget.sectionMap['quizz'] as Map?)?.cast<String, dynamic>());
    _syncStatus();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _syncStatus() {
    final status = widget.quizStatus;
    if (status == null) return;
    if (status['attempted'] == true) {
      _attemptedOnce = true;
    }
    if (status['completedPerfect'] == true) {
      _perfectLocked = true;
    }
  }

  void _prepareQuiz(Map<String, dynamic>? raw) {
    _totalPointsRaw = null;
    _perQuestionPoints = null;
    _totalQuestions = 0;
    if (raw == null) {
      _quiz = null;
      _remaining = 0;
      return;
    }

    final quizCopy = Map<String, dynamic>.from(raw);
    final rawPoints = raw['points'] ?? raw['maxPoints'];
    if (rawPoints is num) {
      _totalPointsRaw = rawPoints.toDouble();
    }

    final timeLimit = raw['timeLimitSeconds'];
    _remaining = timeLimit is num ? timeLimit.toInt() : 0;

    final questionsRaw = raw['questions'];
    if (questionsRaw is Map) {
      final questionMap = <String, dynamic>{};
      questionsRaw.forEach((key, value) {
        if (value is Map) {
          questionMap[key.toString()] = Map<String, dynamic>.from(value);
        } else {
          questionMap[key.toString()] = value;
        }
      });
      _totalQuestions = questionMap.length;
      if (_totalPointsRaw != null && _totalQuestions > 0) {
        _perQuestionPoints = round2(_totalPointsRaw! / _totalQuestions);
        questionMap.updateAll((_, value) {
          if (value is Map<String, dynamic>) {
            final updated = Map<String, dynamic>.from(value);
            updated['perQuestionPoints'] = _perQuestionPoints;
            return updated;
          }
          return value;
        });
      }
      quizCopy['questions'] = questionMap;
    } else if (questionsRaw is List) {
      final questionList = <dynamic>[];
      for (final item in questionsRaw) {
        if (item is Map) {
          questionList.add(Map<String, dynamic>.from(item));
        } else {
          questionList.add(item);
        }
      }
      _totalQuestions = questionList.length;
      if (_totalPointsRaw != null && _totalQuestions > 0) {
        _perQuestionPoints = round2(_totalPointsRaw! / _totalQuestions);
        for (var i = 0; i < questionList.length; i++) {
          final value = questionList[i];
          if (value is Map<String, dynamic>) {
            final updated = Map<String, dynamic>.from(value);
            updated['perQuestionPoints'] = _perQuestionPoints;
            questionList[i] = updated;
          }
        }
      }
      quizCopy['questions'] = questionList;
    } else {
      _totalQuestions = 0;
    }

    if (_perQuestionPoints != null) {
      quizCopy['perQuestionPoints'] = _perQuestionPoints;
    }

    _quiz = quizCopy;
  }

  bool get _isLocked => _perfectLocked;

  String? _formatPoints(double? value) {
    if (value == null) return null;
    final rounded = round2(value);
    return rounded == rounded.truncateToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(2);
  }

  @override
  void didUpdateWidget(covariant _SectionQuiz oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.sectionMap, oldWidget.sectionMap)) {
      _prepareQuiz((widget.sectionMap['quizz'] as Map?)?.cast<String, dynamic>());
    }
    _syncStatus();
  }

  void _start() {
    if (_quiz == null) return;
    setState(() {
      _started = true;
      _lastResult = null;
      _answers.clear();
      _remaining = (_quiz!['timeLimitSeconds'] is num)
          ? (_quiz!['timeLimitSeconds'] as num).toInt()
          : 0;
    });
    _timer?.cancel();
    if (_remaining > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_remaining <= 0) {
          t.cancel();
          _submit(); // auto-enviar
        } else {
          setState(() => _remaining--);
        }
      });
    }
  }

  void _submit() async {
    if (_quiz == null) return;
    _timer?.cancel();

    final qs = (_quiz!['questions'] as Map?)?.cast<String, dynamic>() ?? {};
    final entries = qs.entries
        .map((e) => MapEntry(e.key, (e.value as Map).cast<String, dynamic>()))
        .toList()
      ..sort((a, b) {
        final ao = (a.value['order'] ?? 9999) as num;
        final bo = (b.value['order'] ?? 9999) as num;
        final cmp = ao.compareTo(bo);
        if (cmp != 0) return cmp;
        return a.key.compareTo(b.key);
      });

    final result = evaluateQuizDetailed(_quiz!, _answers);
    final userAnswers = entries.map<UserAnswer?>((entry) {
      final qid = entry.key;
      final q = entry.value;
      final type = (q['type'] ?? '').toString();
      final value = _answers[qid];
      if (type == 'completar') {
        return UserAnswer.text(
          questionId: qid,
          textAnswer: (value ?? '').toString(),
        );
      }
      if (value == null || value.toString().isEmpty) return null;
      return UserAnswer.choice(
        questionId: qid,
        selectedOptionId: value.toString(),
      );
    }).whereType<UserAnswer>().toList();

    final isPerfect =
        result.totalPoints != null && round2(result.earnedPoints) == round2(result.totalPoints!);

    setState(() {
      _lastResult = result;
      _attemptedOnce = true;
      if (isPerfect) {
        _perfectLocked = true;
      }
    });

    try {
      await widget.onSave(_quiz!, result, userAnswers);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar el resultado: $e'),
        ),
      );
    }

    // Informe
    final items = buildReportItems(entries, _answers, _quiz!, result);
    final quizTitle = (_quiz!['title'] ?? 'Informe de evaluación').toString();
    final summaryText =
        'Resultado: ${result.correct}/${result.total} correctas (${result.percent}%)';

    setState(() {
      _lastReportItems = items;
      _lastReportSummary = summaryText;
      _lastReportTitle = quizTitle;
    });

    _showReportDialog();
  }

  void _showReportDialog() {
    if (_reportOpen) return;
    if (_lastReportItems == null) return;

    _reportOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogCtx) {
        final items = _lastReportItems!;
        final quizTitle = _lastReportTitle;
        final summaryText = _lastReportSummary;

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860, maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    quizTitle,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    summaryText,
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final it = items[i];
                        final yourAnswerText =
                            'Tu respuesta: ${it.userText ?? '(sin respuesta)'}';
                        final correctAnswerText =
                            'Respuesta correcta: ${it.correctText ?? '-'}';
                        final hasExpl =
                            (it.explanation != null && it.explanation!.isNotEmpty);
                        final explText =
                            hasExpl ? 'Explicación: ${it.explanation!}' : '';

                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: it.correct
                                ? const Color(0xFFF0FDF4)
                                : const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: it.correct
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFF87171),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${it.idx}. ${it.prompt}',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              Text(yourAnswerText),
                              Text(correctAnswerText),
                              if (hasExpl) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                    border: const Border(
                                      left:
                                          BorderSide(color: Color(0xFF38BDF8), width: 3),
                                    ),
                                  ),
                                  child: Text(
                                    explText,
                                    style: const TextStyle(
                                      color: Color(0xFF334155),
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () {
                        _reportOpen = false;
                        Navigator.of(dialogCtx).pop();
                      },
                      child: const Text('Cerrar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).then((_) => _reportOpen = false);
  }

  Color _timerColor() {
    if (_remaining <= 20) return const Color(0xFF991B1B);
    if (_remaining <= 60) return const Color(0xFF92400E);
    return const Color(0xFF111827);
  }

  @override
  Widget build(BuildContext context) {
    if (_quiz == null) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFF),
          border: Border.all(color: const Color(0xFFD6DAE6)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Text(
          'No hay una evaluación disponible para esta lección por el momento.',
          style: TextStyle(color: Color(0xFF334155)),
        ),
      );
    }

    final qs = (_quiz!['questions'] as Map?)?.cast<String, dynamic>() ?? {};
    final entries = qs.entries
        .map((e) => MapEntry(e.key, (e.value as Map).cast<String, dynamic>()))
        .toList()
      ..sort((a, b) {
        final ao = (a.value['order'] ?? 9999) as num;
        final bo = (b.value['order'] ?? 9999) as num;
        final cmp = ao.compareTo(bo);
        if (cmp != 0) return cmp;
        return a.key.compareTo(b.key);
      });

    final difficulty = (_quiz!['difficulty'] ?? '').toString();
    final totalPointsLabel = _formatPoints(_totalPointsRaw);
    final perQuestionLabel = _formatPoints(_perQuestionPoints);
    final bestScoreNum = (widget.quizStatus?['bestScore'] as num?)?.toDouble();
    final bestScoreLabel = _formatPoints(bestScoreNum);
    final locked = _isLocked;
    final buttonLabel = _attemptedOnce ? 'Repetir evaluación' : 'Realizar evaluación';
    final Widget? lockNotice = locked
        ? Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF38BDF8)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Icon(Icons.emoji_events_outlined, color: Color(0xFF0284C7)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ya alcanzaste el puntaje máximo en este quiz. \nPuedes volver a intentarlo para practicar, pero no ganarás puntos adicionales.',
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          )
        : null;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE8E7FF), Color(0xFFE6FAFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFB7C1F5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7B61FF).withOpacity(0.12),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Evaluación de la lección',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if ((_quiz!['title'] ?? '').toString().isNotEmpty)
                _chipBlue((_quiz!['title']).toString()),
              if (difficulty.isNotEmpty) _chipBlue('Dificultad: $difficulty'),
              if (totalPointsLabel != null) _chipBlue('Puntaje total: $totalPointsLabel'),
              if (perQuestionLabel != null)
                _chipBlue('Puntos por pregunta: $perQuestionLabel'),
              if (bestScoreLabel != null) _chipBlue('Mejor puntaje: $bestScoreLabel'),
              _timerChip(),
            ],
          ),
          const SizedBox(height: 12),
          if (lockNotice != null) lockNotice,
          if (!_started)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _start,
                child: Text(buttonLabel),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // preguntas (sin shuffle)
                ...entries.map((e) {
                  final qid = e.key;
                  final q = e.value;
                  final type = (q['type'] ?? '').toString();
                  final prompt = (q['prompt'] ?? 'Pregunta').toString();

                  final isCorrect = _lastResult?.byQuestion[qid];
                  final explanationString = (q['explanation'] ?? '').toString();

                  final options =
                      ((q['options'] as Map?)?.cast<String, dynamic>() ?? {})
                          .entries
                          .toList()
                        ..sort((a, b) => a.key.compareTo(b.key)); // option_0...

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFF),
                      border: Border.all(color: const Color(0xFFD6DAE6)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(prompt, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        if (type == 'completar')
                          TextField(
                            enabled: _lastResult == null,
                            onChanged: (v) => _answers[qid] = v,
                            decoration: const InputDecoration(
                              hintText: 'Escribe tu respuesta…',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          )
                        else
                          Column(
                            children: options.map<Widget>((opt) {
                              final oid = opt.key.toString();
                              final text = opt.value.toString();
                              return RadioListTile<String>(
                                dense: true,
                                title: Text(text),
                                value: oid,
                                groupValue: _answers[qid]?.toString(),
                                onChanged:
                                    _lastResult == null ? (val) => setState(() => _answers[qid] = val) : null,
                              );
                            }).toList(),
                          ),

                        // feedback por pregunta
                        if (_lastResult != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: (isCorrect == true)
                                  ? const Color(0xFFF0FDF4)
                                  : const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: (isCorrect == true)
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFF87171),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (isCorrect == true) ? '¡Correcto!' : 'Incorrecto',
                                  style: TextStyle(
                                    color: (isCorrect == true)
                                        ? const Color(0xFF16A34A)
                                        : const Color(0xFFDC2626),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (explanationString.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Explicación: $explanationString',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _lastResult == null ? _submit : null,
                        child: const Text('Enviar respuestas'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _lastResult == null
                            ? () => setState(() {
                                  _answers.clear();
                                })
                            : null,
                        child: const Text('Limpiar'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_lastResult != null)
                  Builder(
                    builder: (_) {
                      final r = _lastResult!;
                      final good = r.percent >= 70;
                      final mid = r.percent >= 40 && r.percent < 70;
                      final msg = good
                          ? '¡Excelente! Obtuviste ${r.correct}/${r.total} (${r.percent}%). ¡Sigue así!'
                          : (mid
                              ? 'Vas por buen camino: ${r.correct}/${r.total} (${r.percent}%). Revisa y vuelve a intentarlo.'
                              : 'No te desanimes: ${r.correct}/${r.total} (${r.percent}%). Aprende de las explicaciones y reintenta.');
                      final color = good
                          ? const Color(0xFF16A34A)
                          : (mid ? const Color(0xFFD97706) : const Color(0xFFDC2626));
                      final earnedLabel =
                          _formatPoints(r.earnedPoints) ?? r.earnedPoints.toStringAsFixed(2);
                      final totalLabel = _formatPoints(r.totalPoints);
                      final scoreText = totalLabel != null
                          ? 'Puntaje obtenido: $earnedLabel / $totalLabel'
                          : 'Puntaje obtenido: $earnedLabel';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            msg,
                            style: TextStyle(color: color, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            scoreText,
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                if (_lastResult != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _showReportDialog,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Ver informes'),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _chipBlue(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF3FB),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF1D2536),
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      ),
    );
  }

  Widget _timerChip() {
    final unlimited = _quiz == null ||
        (_quiz!['timeLimitSeconds'] == null) ||
        (_quiz!['timeLimitSeconds'] == 0);
    final text = unlimited ? 'Sin límite de tiempo' : 'Tiempo: ${formatSeconds(_remaining)}';
    final color = unlimited ? const Color(0xFF111827) : _timerColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEDEEF2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      ),
    );
  }
}
