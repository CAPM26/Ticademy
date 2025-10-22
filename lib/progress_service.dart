import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

const List<BadgeThreshold> badgeThresholds = [
  BadgeThreshold(points: 0, alias: 'Tic-Novato'),
  BadgeThreshold(points: 500, alias: 'Tic-Fanático'),
  BadgeThreshold(points: 1000, alias: 'Tic-Maestro'),
  BadgeThreshold(points: 1500, alias: 'Tic-Campeón'),
  BadgeThreshold(points: 2000, alias: 'Tic-Leyenda'),
];

class UserAnswer {
  const UserAnswer._({
    required this.questionId,
    this.selectedOptionId,
    this.textAnswer,
  });

  factory UserAnswer.choice({
    required String questionId,
    required String selectedOptionId,
  }) {
    return UserAnswer._(
      questionId: questionId,
      selectedOptionId: selectedOptionId,
    );
  }

  factory UserAnswer.text({
    required String questionId,
    required String textAnswer,
  }) {
    return UserAnswer._(
      questionId: questionId,
      textAnswer: textAnswer,
    );
  }

  final String questionId;
  final String? selectedOptionId;
  final String? textAnswer;
}

Future<void> onQuizSubmitted({
  required String uid,
  required String moduleId,
  required String sectionId,
  required String quizId,
  required List<UserAnswer> answers,
}) async {
  final db = FirebaseDatabase.instance;
  final catalog = await _CatalogData.load(db);
  final quiz = catalog.findQuiz(moduleId, sectionId, quizId);
  if (quiz == null) {
    throw StateError(
      'Quiz $quizId no encontrado en $moduleId/$sectionId.',
    );
  }

  final evaluation = _evaluateQuiz(quiz, answers);
  final nowIso = DateTime.now().toUtc().toIso8601String();

  final progressRef = db.ref('users/$uid/progress');
  await progressRef.runTransaction((current) {
    final progress = _ensureMap(current);
    _applyQuizSubmission(
      progress: progress,
      moduleId: moduleId,
      sectionId: sectionId,
      quiz: quiz,
      evaluation: evaluation,
      catalog: catalog,
      attemptedAtIso: nowIso,
    );
    return Transaction.success(progress);
  });

  await updateBadgesAndAlias(uid);
}

Future<void> recalcUserProgressDerivedFields(String uid) async {
  final db = FirebaseDatabase.instance;
  final catalog = await _CatalogData.load(db);
  final progressRef = db.ref('users/$uid/progress');
  await progressRef.runTransaction((current) {
    final progress = _ensureMap(current);
    _recomputeProgress(progress, catalog);
    return Transaction.success(progress);
  });
  await updateBadgesAndAlias(uid);
}

Future<void> updateBadgesAndAlias(String uid) async {
  final db = FirebaseDatabase.instance;
  final pointsSnap = await db.ref('users/$uid/progress/points').get();
  final pointsVal = pointsSnap.value;
  final points = pointsVal is num ? pointsVal.toInt() : 0;
  final threshold = badgeThresholds.lastWhere(
    (t) => points >= t.points,
    orElse: () => badgeThresholds.first,
  );
  final unlocked = badgeThresholds.where((t) => points >= t.points);
  final nowIso = DateTime.now().toUtc().toIso8601String();

  final achievementsRef = db.ref('users/$uid/achievements');
  await achievementsRef.runTransaction((current) {
    final map = _ensureMap(current);
    final badges = _ensureMap(map['badges']);
    var changed = false;
    for (final badge in unlocked) {
      final existing = badges[badge.alias];
      if (existing is Map && existing['earnedAt'] != null) continue;
      badges[badge.alias] = {'earnedAt': nowIso};
      changed = true;
    }
    map['badges'] = badges;
    map['highestAlias'] = threshold.alias;
    if (changed) {
      map['lastUpdatedAt'] = nowIso;
    }
    return Transaction.success(map);
  });

  final profileRef = db.ref('users/$uid/profile');
  await profileRef.runTransaction((current) {
    final map = _ensureMap(current);
    final aliasSource = (map['aliasSource'] ?? 'auto').toString();
    if (aliasSource != 'manual') {
      map['alias'] = threshold.alias;
      map['aliasSource'] = 'auto';
      map['aliasAutoUpdatedAt'] = nowIso;
    }
    return Transaction.success(map);
  });
}

Stream<UserProfileVM> watchUserProfile(String uid) {
  final ref = FirebaseDatabase.instance.ref('users/$uid/profile');
  return ref.onValue.map((event) {
    final data = _ensureMap(event.snapshot.value);
    return UserProfileVM.fromMap(uid, data);
  });
}

Stream<UserAchievementsVM> watchUserAchievements(String uid) {
  final ref = FirebaseDatabase.instance.ref('users/$uid/achievements');
  return ref.onValue.map((event) {
    final data = _ensureMap(event.snapshot.value);
    return UserAchievementsVM.fromMap(data);
  });
}

Stream<UserProgressVM> watchUserProgress(String uid) {
  final ref = FirebaseDatabase.instance.ref('users/$uid/progress');
  return ref.onValue.map((event) {
    final data = _ensureMap(event.snapshot.value);
    return UserProgressVM.fromMap(data);
  });
}

Future<void> collaboratorAddBadge(String uid, String badgeName) async {
  await _ensureCollaboratorRole();
  final db = FirebaseDatabase.instance;
  final nowIso = DateTime.now().toUtc().toIso8601String();
  final ref = db.ref('users/$uid/achievements/badges/$badgeName');
  await ref.runTransaction((current) {
    if (current is Map && current['earnedAt'] != null) {
      return Transaction.abort();
    }
    return Transaction.success({
      'earnedAt': nowIso,
      'assignedManually': true,
    });
  });
}

Future<void> collaboratorRemoveBadge(String uid, String badgeName) async {
  await _ensureCollaboratorRole();
  final db = FirebaseDatabase.instance;
  await db.ref('users/$uid/achievements/badges/$badgeName').remove();
}

Future<void> collaboratorSetAlias(String uid, String alias) async {
  await _ensureCollaboratorRole();
  final db = FirebaseDatabase.instance;
  final profileRef = db.ref('users/$uid/profile');
  await profileRef.update({
    'alias': alias.trim(),
    'aliasSource': 'manual',
    'aliasManualUpdatedAt': DateTime.now().toUtc().toIso8601String(),
  });
}

class UserProfileVM {
  UserProfileVM({
    required this.uid,
    required this.displayName,
    required this.alias,
    required this.aliasSource,
    required this.email,
    required this.photoUrl,
    required this.role,
    required this.language,
    required this.timeZone,
  });

  factory UserProfileVM.fromMap(String uid, Map<String, dynamic> map) {
    return UserProfileVM(
      uid: uid,
      displayName: (map['displayName'] ?? '').toString(),
      alias: (map['alias'] ?? 'Tic-Novato').toString(),
      aliasSource: (map['aliasSource'] ?? 'auto').toString(),
      email: (map['email'] ?? '').toString(),
      photoUrl: (map['photoURL'] ?? '').toString(),
      role: (map['role'] ?? 'aprendiz').toString(),
      language: (map['language'] ?? 'es').toString(),
      timeZone: (map['timeZone'] ?? '').toString(),
    );
  }

  final String uid;
  final String displayName;
  final String alias;
  final String aliasSource;
  final String email;
  final String photoUrl;
  final String role;
  final String language;
  final String timeZone;
}

class UserAchievementsVM {
  UserAchievementsVM({
    required this.badges,
    required this.highestAlias,
  });

  factory UserAchievementsVM.fromMap(Map<String, dynamic> map) {
    final badgesMap = _ensureMap(map['badges']);
    final badges = badgesMap.entries
        .map(
          (entry) => UserBadgeVM(
            name: entry.key,
            earnedAt: _parseDate(
              entry.value is Map ? (entry.value as Map)['earnedAt'] : entry.value,
            ),
            metadata: entry.value is Map
                ? Map<String, dynamic>.from(entry.value as Map)
                : const <String, dynamic>{},
          ),
        )
        .toList()
      ..sort((a, b) {
        final aTime = a.earnedAt?.millisecondsSinceEpoch ?? 0;
        final bTime = b.earnedAt?.millisecondsSinceEpoch ?? 0;
        return aTime.compareTo(bTime);
      });
    return UserAchievementsVM(
      badges: badges,
      highestAlias: (map['highestAlias'] ?? '').toString(),
    );
  }

  final List<UserBadgeVM> badges;
  final String highestAlias;
}

class UserBadgeVM {
  const UserBadgeVM({
    required this.name,
    required this.earnedAt,
    required this.metadata,
  });

  final String name;
  final DateTime? earnedAt;
  final Map<String, dynamic> metadata;
}

class UserProgressVM {
  UserProgressVM({
    required this.points,
    required this.overallPercent,
    required this.totalQuizzesFinished,
    required this.modules,
    required this.currentModuleId,
    required this.currentSectionId,
    required this.lastAccess,
  });

  factory UserProgressVM.fromMap(Map<String, dynamic> map) {
    final modulesMap = _ensureMap(map['modules']);
    final modules = modulesMap.entries
        .map(
          (entry) => ModuleProgressVM.fromMap(
            id: entry.key,
            data: _ensureMap(entry.value),
          ),
        )
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return UserProgressVM(
      points: _ensureInt(map['points']),
      overallPercent: map['overallPercent'] is num
          ? _roundPercent((map['overallPercent'] as num).toDouble())
          : 0.0,
      totalQuizzesFinished: _ensureInt(map['TotalQuizzesFinished']),
      modules: modules,
      currentModuleId: (map['currentModuleId'] ?? '').toString(),
      currentSectionId: (map['currentSectionId'] ?? '').toString(),
      lastAccess: _parseDate(map['lastAccess']),
    );
  }

  final int points;
  final double overallPercent;
  final int totalQuizzesFinished;
  final List<ModuleProgressVM> modules;
  final String currentModuleId;
  final String currentSectionId;
  final DateTime? lastAccess;
}

class ModuleProgressVM {
  ModuleProgressVM({
    required this.id,
    required this.percent,
    required this.points,
    required this.completedQuizzes,
    required this.totalQuizzes,
    required this.lastUpdated,
    required this.sections,
  });

  factory ModuleProgressVM.fromMap({
    required String id,
    required Map<String, dynamic> data,
  }) {
    final sectionsMap = _ensureMap(data['sections']);
    final sections = sectionsMap.entries
        .map(
          (entry) => SectionProgressVM.fromMap(
            id: entry.key,
            data: _ensureMap(entry.value),
          ),
        )
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return ModuleProgressVM(
      id: id,
      percent: data['percent'] is num
          ? _roundPercent((data['percent'] as num).toDouble())
          : 0.0,
      points: _ensureInt(data['points']),
      completedQuizzes: _ensureInt(data['completedQuizzes']),
      totalQuizzes: _ensureInt(data['totalQuizzes']),
      lastUpdated: _parseDate(data['lastUpdated'] ?? data['completedAt']),
      sections: sections,
    );
  }

  final String id;
  final double percent;
  final int points;
  final int completedQuizzes;
  final int totalQuizzes;
  final DateTime? lastUpdated;
  final List<SectionProgressVM> sections;
}

class SectionProgressVM {
  SectionProgressVM({
    required this.id,
    required this.percent,
    required this.points,
    required this.completedQuizzes,
    required this.totalQuizzes,
    required this.lastUpdated,
    required this.quizzes,
  });

  factory SectionProgressVM.fromMap({
    required String id,
    required Map<String, dynamic> data,
  }) {
    final quizzesMap = _ensureMap(data['quizzes']);
    final quizzes = quizzesMap.entries
        .map(
          (entry) => QuizProgressVM.fromMap(
            id: entry.key,
            data: _ensureMap(entry.value),
          ),
        )
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return SectionProgressVM(
      id: id,
      percent: data['percent'] is num
          ? _roundPercent((data['percent'] as num).toDouble())
          : 0.0,
      points: _ensureInt(data['points']),
      completedQuizzes: _ensureInt(data['completedQuizzes']),
      totalQuizzes: _ensureInt(data['totalQuizzes']),
      lastUpdated: _parseDate(data['lastUpdated'] ?? data['completedAt']),
      quizzes: quizzes,
    );
  }

  final String id;
  final double percent;
  final int points;
  final int completedQuizzes;
  final int totalQuizzes;
  final DateTime? lastUpdated;
  final List<QuizProgressVM> quizzes;
}

class QuizProgressVM {
  QuizProgressVM({
    required this.id,
    required this.bestPoints,
    required this.bestPercent,
    required this.completed,
    required this.attempts,
    required this.lastAttemptAt,
    required this.maxPoints,
  });

  factory QuizProgressVM.fromMap({
    required String id,
    required Map<String, dynamic> data,
  }) {
    return QuizProgressVM(
      id: id,
      bestPoints: _ensureInt(data['bestPoints']),
      bestPercent: data['bestPercent'] is num
          ? _roundPercent((data['bestPercent'] as num).toDouble())
          : 0.0,
      completed: data['completed'] == true,
      attempts: _ensureInt(data['attempts']),
      lastAttemptAt: _parseDate(data['lastAttemptAt']),
      maxPoints: _ensureInt(data['maxPoints']),
    );
  }

  final String id;
  final int bestPoints;
  final double bestPercent;
  final bool completed;
  final int attempts;
  final DateTime? lastAttemptAt;
  final int maxPoints;
}

Future<void> _ensureCollaboratorRole() async {
  final auth = FirebaseAuth.instance;
  final user = auth.currentUser;
  if (user == null) {
    throw StateError('No hay usuario autenticado.');
  }
  final db = FirebaseDatabase.instance;
  final roleSnap = await db.ref('users/${user.uid}/profile/role').get();
  final role = (roleSnap.value ?? '').toString().toLowerCase();
  if (!{'colaborador', 'teacher', 'docente', 'admin'}.contains(role)) {
    throw StateError('Acceso restringido a colaboradores o docentes.');
  }
}

Map<String, dynamic> _ensureMap(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return <String, dynamic>{};
}

int _ensureInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

double _ensureDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal();
  }
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true).toLocal();
  }
  if (value is String) {
    return DateTime.tryParse(value)?.toLocal();
  }
  return null;
}

double _roundPercent(double value) =>
    double.parse(value.clamp(0.0, 100.0).toStringAsFixed(2));

int _roundPoints(num value) => value.round();

class _CatalogData {
  _CatalogData(this.modules);

  final Map<String, Map<String, Map<String, _QuizCatalog>>> modules;

  int totalQuizzesInModule(String moduleId) {
    final sections = modules[moduleId];
    if (sections == null) return 0;
    return sections.values.fold<int>(0, (sum, quizzes) => sum + quizzes.length);
  }

  int totalQuizzesInSection(String moduleId, String sectionId) {
    return modules[moduleId]?[sectionId]?.length ?? 0;
  }

  int get totalQuizzes {
    var sum = 0;
    for (final sections in modules.values) {
      for (final quizzes in sections.values) {
        sum += quizzes.length;
      }
    }
    return sum;
  }

  _QuizCatalog? findQuiz(String moduleId, String sectionId, String quizId) {
    final section = modules[moduleId]?[sectionId];
    if (section == null || section.isEmpty) return null;
    return section[quizId] ??
        (section.length == 1 ? section.values.first : null) ??
        section[sectionId];
  }

  static Future<_CatalogData> load(FirebaseDatabase db) async {
    final catalogSnap = await db.ref('catalog/modules').get();
    if (catalogSnap.exists && catalogSnap.value is Map) {
      return _CatalogData(_parseStructured(Map<String, dynamic>.from(
        catalogSnap.value as Map,
      )));
    }

    final legacySnap = await db.ref('learningModules').get();
    if (legacySnap.exists && legacySnap.value is Map) {
      return _CatalogData(_parseLegacy(Map<String, dynamic>.from(
        legacySnap.value as Map,
      )));
    }

    return _CatalogData({});
  }

  static Map<String, Map<String, Map<String, _QuizCatalog>>> _parseStructured(
    Map<String, dynamic> data,
  ) {
    final result = <String, Map<String, Map<String, _QuizCatalog>>>{};
    data.forEach((moduleId, rawModule) {
      final moduleMap = _ensureMap(rawModule);
      final sectionsMap = _ensureMap(moduleMap['sections']);
      final sections = <String, Map<String, _QuizCatalog>>{};
      sectionsMap.forEach((sectionId, rawSection) {
        final sectionMap = _ensureMap(rawSection);
        final quizzesMap = _ensureMap(sectionMap['quizzes']);
        final quizzes = <String, _QuizCatalog>{};
        quizzesMap.forEach((quizKey, rawQuiz) {
          final quizMap = _ensureMap(rawQuiz);
          final quizId = (quizMap['quizId'] ?? quizKey ?? sectionId).toString();
          final parsed = _QuizCatalog.fromMap(
            quizId: quizId,
            data: quizMap,
          );
          if (parsed != null) {
            quizzes[quizId] = parsed;
          }
        });
        if (quizzes.isNotEmpty) {
          sections[sectionId] = quizzes;
        }
      });
      if (sections.isNotEmpty) {
        result[moduleId] = sections;
      }
    });
    return result;
  }

  static Map<String, Map<String, Map<String, _QuizCatalog>>> _parseLegacy(
    Map<String, dynamic> data,
  ) {
    final result = <String, Map<String, Map<String, _QuizCatalog>>>{};
    data.forEach((moduleId, rawModule) {
      final moduleMap = _ensureMap(rawModule);
      final sectionsMap = _ensureMap(moduleMap['sections']);
      final sections = <String, Map<String, _QuizCatalog>>{};
      sectionsMap.forEach((sectionId, rawSection) {
        final sectionMap = _ensureMap(rawSection);
        final rawQuiz = sectionMap['quizz'];
        if (rawQuiz is Map) {
          final quizMap = _ensureMap(rawQuiz);
          final quizId = (quizMap['quizId'] ?? sectionId).toString();
          final parsed = _QuizCatalog.fromMap(
            quizId: quizId,
            data: quizMap,
          );
          if (parsed != null) {
            sections[sectionId] = {quizId: parsed};
          }
        }
      });
      if (sections.isNotEmpty) {
        result[moduleId] = sections;
      }
    });
    return result;
  }
}

class _QuizCatalog {
  _QuizCatalog({
    required this.quizId,
    required this.maxPoints,
    required this.allowRetake,
    required this.questions,
  });

  final String quizId;
  final int maxPoints;
  final bool allowRetake;
  final List<_QuestionMeta> questions;

  int get totalQuestions => questions.length;

  static _QuizCatalog? fromMap({
    required String quizId,
    required Map<String, dynamic> data,
  }) {
    final maxPoints = max(0, _ensureInt(data['maxPoints'] ?? data['points']));
    final questions = _QuestionMeta.parseList(data['questions'], maxPoints);
    if (questions.isEmpty) return null;
    return _QuizCatalog(
      quizId: quizId,
      maxPoints: maxPoints,
      allowRetake: data['allowRetake'] == true,
      questions: questions,
    );
  }
}

class _QuestionMeta {
  _QuestionMeta({
    required this.id,
    required this.type,
    required this.weight,
    required this.correctOption,
    required this.correctOptions,
    required this.answerText,
  });

  final String id;
  final String type;
  final double weight;
  final String? correctOption;
  final Set<String> correctOptions;
  final String? answerText;

  _QuestionMeta copyWith({double? weight}) {
    return _QuestionMeta(
      id: id,
      type: type,
      weight: weight ?? this.weight,
      correctOption: correctOption,
      correctOptions: correctOptions,
      answerText: answerText,
    );
  }

  static List<_QuestionMeta> parseList(dynamic raw, int maxPoints) {
    final list = <_QuestionMeta>[];
    if (raw is List) {
      for (var i = 0; i < raw.length; i++) {
        final q = raw[i];
        if (q is! Map) continue;
        final map = _ensureMap(q);
        final id = (map['qid'] ?? 'q${i + 1}').toString();
        final meta = _fromMap(id, map, maxPoints);
        if (meta != null) list.add(meta);
      }
    } else if (raw is Map) {
      final ordered = raw.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      for (final entry in ordered) {
        if (entry.value is! Map) continue;
        final map = _ensureMap(entry.value);
        final id = (map['qid'] ?? entry.key).toString();
        final meta = _fromMap(id, map, maxPoints);
        if (meta != null) list.add(meta);
      }
    }
    _normalizeWeights(list, maxPoints);
    return list;
  }

  static _QuestionMeta? _fromMap(
    String id,
    Map<String, dynamic> data,
    int fallbackPoints,
  ) {
    final type = (data['type'] ?? '').toString();
    if (type.isEmpty) return null;
    final weight = _ensureDouble(data['weight']);
    final correctOption = data['correctOption']?.toString();
    final answerText = data['answerText']?.toString();
    final correctOptions = <String>{};
    if (data['correctOptions'] is List) {
      for (final item in data['correctOptions']) {
        if (item == null) continue;
        correctOptions.add(item.toString());
      }
    }
    return _QuestionMeta(
      id: id,
      type: type,
      weight: weight > 0 ? weight : fallbackPoints.toDouble(),
      correctOption: correctOption,
      correctOptions: correctOptions,
      answerText: answerText,
    );
  }

  static void _normalizeWeights(List<_QuestionMeta> items, int maxPoints) {
    if (items.isEmpty || maxPoints <= 0) return;
    final sum = items.fold<double>(0, (acc, q) => acc + q.weight);
    if (sum <= 0) {
      final even = maxPoints / items.length;
      for (var i = 0; i < items.length; i++) {
        items[i] = items[i].copyWith(weight: even);
      }
      return;
    }
    if ((sum - maxPoints).abs() < 0.01) return;
    for (var i = 0; i < items.length; i++) {
      final scaled = (items[i].weight / sum) * maxPoints;
      items[i] = items[i].copyWith(weight: scaled);
    }
  }
}

class _QuizEvaluation {
  const _QuizEvaluation({
    required this.earnedPoints,
    required this.correctAnswers,
    required this.totalQuestions,
    required this.percent,
    required this.byQuestion,
  });

  final int earnedPoints;
  final int correctAnswers;
  final int totalQuestions;
  final double percent;
  final Map<String, bool> byQuestion;
}

_QuizEvaluation _evaluateQuiz(
  _QuizCatalog quiz,
  List<UserAnswer> answers,
) {
  final answersMap = {for (final answer in answers) answer.questionId: answer};
  var correct = 0;
  var weightSum = 0.0;
  final perQuestion = <String, bool>{};

  for (final question in quiz.questions) {
    final answer = answersMap[question.id];
    final isCorrect = _isAnswerCorrect(question, answer);
    perQuestion[question.id] = isCorrect;
    if (isCorrect) {
      correct++;
      weightSum += question.weight;
    }
  }

  final earned = min(quiz.maxPoints, _roundPoints(weightSum));
  final percent = quiz.totalQuestions == 0
      ? 0.0
      : _roundPercent((correct / quiz.totalQuestions) * 100);

  return _QuizEvaluation(
    earnedPoints: earned,
    correctAnswers: correct,
    totalQuestions: quiz.totalQuestions,
    percent: percent,
    byQuestion: perQuestion,
  );
}

bool _isAnswerCorrect(_QuestionMeta meta, UserAnswer? answer) {
  if (answer == null) return false;
  final type = meta.type.toLowerCase();
  if (type == 'completar' || type == 'input_text' || type == 'texto') {
    final expected = (meta.answerText ?? '').trim().toLowerCase();
    if (expected.isEmpty) return false;
    final provided =
        (answer.textAnswer ?? answer.selectedOptionId ?? '').trim().toLowerCase();
    return provided == expected && provided.isNotEmpty;
  }

  final provided = answer.selectedOptionId ?? answer.textAnswer;
  if (provided == null || provided.isEmpty) return false;
  if (meta.correctOptions.isNotEmpty) {
    return meta.correctOptions.contains(provided);
  }
  return meta.correctOption != null && meta.correctOption == provided;
}

void _applyQuizSubmission({
  required Map<String, dynamic> progress,
  required String moduleId,
  required String sectionId,
  required _QuizCatalog quiz,
  required _QuizEvaluation evaluation,
  required _CatalogData catalog,
  required String attemptedAtIso,
}) {
  final modules = _ensureMap(progress['modules']);
  final module = _ensureMap(modules[moduleId]);
  final sections = _ensureMap(module['sections']);
  final section = _ensureMap(sections[sectionId]);
  final quizzes = _ensureMap(section['quizzes']);
  final quizEntry = _ensureMap(quizzes[quiz.quizId]);

  final attempts = _ensureInt(quizEntry['attempts']);
  final alreadyCompleted = quizEntry['completed'] == true;
  final bestPoints = _ensureInt(quizEntry['bestPoints']);
  final bestPercent =
      quizEntry['bestPercent'] is num ? (quizEntry['bestPercent'] as num).toDouble() : 0.0;

  if (!quiz.allowRetake && alreadyCompleted) {
    quizEntry['attempts'] = attempts + 1;
    quizEntry['lastAttemptAt'] = attemptedAtIso;
    quizEntry['lastEarnedPoints'] = evaluation.earnedPoints;
    quizEntry['lastEarnedPercent'] = evaluation.percent;
  } else {
    final newBestPoints =
        quiz.allowRetake ? max(bestPoints, evaluation.earnedPoints) : evaluation.earnedPoints;
    final newBestPercent =
        quiz.allowRetake ? max(bestPercent, evaluation.percent) : evaluation.percent;

    quizEntry
      ..['attempts'] = attempts + 1
      ..['completed'] = true
      ..['completedAt'] ??= attemptedAtIso
      ..['lastAttemptAt'] = attemptedAtIso
      ..['lastEarnedPoints'] = evaluation.earnedPoints
      ..['lastEarnedPercent'] = evaluation.percent
      ..['bestPoints'] = newBestPoints
      ..['bestPercent'] = _roundPercent(newBestPercent)
      ..['maxPoints'] = quiz.maxPoints
      ..['totalQuestions'] = quiz.totalQuestions
      ..['allowRetake'] = quiz.allowRetake
      ..['perQuestion'] = evaluation.byQuestion;
  }

  quizzes[quiz.quizId] = quizEntry;
  section['quizzes'] = quizzes;
  section['lastUpdated'] = attemptedAtIso;
  sections[sectionId] = section;
  module['sections'] = sections;
  module['lastUpdated'] = attemptedAtIso;
  modules[moduleId] = module;

  progress['modules'] = modules;
  progress['currentModuleId'] = moduleId;
  progress['currentSectionId'] = sectionId;
  progress['lastAccess'] = attemptedAtIso;
  progress['lastUpdated'] = attemptedAtIso;

  _recomputeProgress(progress, catalog);
}

void _recomputeProgress(
  Map<String, dynamic> progress,
  _CatalogData catalog,
) {
  final modules = _ensureMap(progress['modules']);
  var totalPoints = 0;
  var totalCompleted = 0;
  var fallbackQuizzes = 0;

  modules.forEach((moduleId, moduleValue) {
    final module = _ensureMap(moduleValue);
    final sections = _ensureMap(module['sections']);
    final catalogTotal = catalog.totalQuizzesInModule(moduleId);
    var modulePoints = 0;
    var moduleCompleted = 0;
    var moduleQuizzes = catalogTotal;

    if (moduleQuizzes == 0) {
      moduleQuizzes = sections.values.fold<int>(0, (sum, sectionValue) {
        final section = _ensureMap(sectionValue);
        final quizzes = _ensureMap(section['quizzes']);
        return sum + quizzes.length;
      });
    }

    sections.forEach((sectionId, sectionValue) {
      final section = _ensureMap(sectionValue);
      final quizzes = _ensureMap(section['quizzes']);
      final catalogSectionTotal = catalog.totalQuizzesInSection(moduleId, sectionId);
      var sectionPoints = 0;
      var sectionCompleted = 0;
      var sectionQuizzes = catalogSectionTotal == 0 ? quizzes.length : catalogSectionTotal;

      quizzes.forEach((quizId, quizValue) {
        final quiz = _ensureMap(quizValue);
        final bestPoints = _ensureInt(quiz['bestPoints']);
        final completed = quiz['completed'] == true;
        if (completed) {
          sectionCompleted += 1;
          moduleCompleted += 1;
          totalCompleted += 1;
        }
        sectionPoints += bestPoints;
      });

      fallbackQuizzes += sectionQuizzes;

      section['points'] = sectionPoints;
      section['completedQuizzes'] = sectionCompleted;
      section['totalQuizzes'] = sectionQuizzes;
      section['percent'] =
          sectionQuizzes == 0 ? 0.0 : _roundPercent((sectionCompleted / sectionQuizzes) * 100);
      section['lastUpdated'] = section['lastUpdated'] ?? progress['lastUpdated'];

      modulePoints += sectionPoints;
      sections[sectionId] = section;
    });

    module['sections'] = sections;
    module['points'] = modulePoints;
    module['completedQuizzes'] = moduleCompleted;
    module['totalQuizzes'] = moduleQuizzes;
    module['percent'] =
        moduleQuizzes == 0 ? 0.0 : _roundPercent((moduleCompleted / moduleQuizzes) * 100);
    module['lastUpdated'] = module['lastUpdated'] ?? progress['lastUpdated'];

    totalPoints += modulePoints;
    modules[moduleId] = module;
  });

  progress['modules'] = modules;
  progress['points'] = totalPoints;
  progress['TotalQuizzesFinished'] = totalCompleted;

  final denom = catalog.totalQuizzes == 0 ? fallbackQuizzes : catalog.totalQuizzes;
  progress['overallPercent'] =
      denom == 0 ? 0.0 : _roundPercent((totalCompleted / denom) * 100);
}

class BadgeThreshold {
  const BadgeThreshold({required this.points, required this.alias});
  final int points;
  final String alias;
}
