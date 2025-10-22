import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:ticademy/friends_page.dart';
import 'package:ticademy/progress_service.dart';
import 'package:ticademy/ui/app_scaffold.dart';
import 'package:ticademy/user_profile_page.dart';

class AchievementsPage extends StatefulWidget {
  const AchievementsPage({super.key});
  static const routeName = '/achievements';

  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends State<AchievementsPage> {
  final _auth = FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(
          child: Text('Inicia sesión para ver tus insignias.'),
        ),
      );
    }

    return AppScaffold(
      currentTab: AppTab.achievements,
      onNavigateToTab: (tab) => _onNavigate(context, tab),
      body: SafeArea(
        child: StreamBuilder<UserProfileVM>(
          stream: watchUserProfile(user.uid),
          builder: (context, profileSnap) {
            if (profileSnap.connectionState == ConnectionState.waiting &&
                !profileSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final profile =
                profileSnap.data ?? UserProfileVM.fromMap(user.uid, const {});

            return StreamBuilder<UserProgressVM>(
              stream: watchUserProgress(user.uid),
              builder: (context, progressSnap) {
                final progress =
                    progressSnap.data ?? UserProgressVM.fromMap(const {});

                return StreamBuilder<UserAchievementsVM>(
                  stream: watchUserAchievements(user.uid),
                  builder: (context, achievementsSnap) {
                    final achievements =
                        achievementsSnap.data ??
                            UserAchievementsVM.fromMap(const {});
                    return _AchievementsView(
                      profile: profile,
                      progress: progress,
                      achievements: achievements,
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _onNavigate(BuildContext context, AppTab tab) async {
    switch (tab) {
      case AppTab.home:
        if (!mounted) return;
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          Navigator.pushReplacementNamed(context, '/app');
        }
        break;
      case AppTab.achievements:
        // Ya estás en la vista de logros.
        break;
      case AppTab.friends:
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FriendsPage()),
        );
        break;
      case AppTab.profile:
        if (!mounted) return;
        await Navigator.of(context).pushReplacementNamed(
          UserProfilePage.routeName,
        );
        break;
    }
  }
}

class _AchievementsView extends StatelessWidget {
  const _AchievementsView({
    required this.profile,
    required this.progress,
    required this.achievements,
  });

  final UserProfileVM profile;
  final UserProgressVM progress;
  final UserAchievementsVM achievements;

  @override
  Widget build(BuildContext context) {
    final points = progress.points;
    final currentThreshold = badgeThresholds.lastWhere(
      (t) => points >= t.points,
      orElse: () => badgeThresholds.first,
    );
    final nextThreshold = badgeThresholds.firstWhere(
      (t) => points < t.points,
      orElse: () => currentThreshold,
    );

    final badgeMap = {
      for (final badge in achievements.badges) badge.name: badge,
    };

    final alias =
        profile.alias.isNotEmpty ? profile.alias : currentThreshold.alias;

    final nextGap = (nextThreshold.points - currentThreshold.points).clamp(1, 1 << 31);
    final progressDelta = points - currentThreshold.points;
    final ratio = nextThreshold.points == currentThreshold.points
        ? 1.0
        : (progressDelta / nextGap).clamp(0.0, 1.0);

    final pointsToNext = (nextThreshold.points - points).clamp(0, 1 << 31);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Insignias Ticademy',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Alias actual: $alias',
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          _StatsPanel(
            points: points,
            overallPercent: progress.overallPercent,
            totalQuizzes: progress.totalQuizzesFinished,
          ),
          const SizedBox(height: 20),
          _ProgressToNextBadge(
            current: currentThreshold,
            next: nextThreshold,
            ratio: ratio,
            points: points,
            pointsToNext: pointsToNext,
          ),
          const SizedBox(height: 26),
          Text(
            'Colección de Insignias',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final threshold in badgeThresholds)
                _BadgeTile(
                  threshold: threshold,
                  badge: badgeMap[threshold.alias],
                  isCurrent: threshold.alias == currentThreshold.alias,
                  isNext: threshold.alias == nextThreshold.alias &&
                      nextThreshold.alias != currentThreshold.alias,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatsPanel extends StatelessWidget {
  const _StatsPanel({
    required this.points,
    required this.overallPercent,
    required this.totalQuizzes,
  });

  final int points;
  final double overallPercent;
  final int totalQuizzes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A1E293B),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final items = [
            _StatChip(
              label: 'Puntos Totales',
              value: points.toString(),
              icon: Icons.bolt,
            ),
            _StatChip(
              label: 'Progreso Global',
              value: '${overallPercent.toStringAsFixed(1)}%',
              icon: Icons.track_changes,
            ),
            _StatChip(
              label: 'Quizzes Completados',
              value: totalQuizzes.toString(),
              icon: Icons.check_circle,
            ),
          ];

          if (constraints.maxWidth >= 560) {
            return Row(
              children: [
                Expanded(child: items[0]),
                const SizedBox(width: 16),
                Expanded(child: items[1]),
                const SizedBox(width: 16),
                Expanded(child: items[2]),
              ],
            );
          }

          final double itemWidth = constraints.maxWidth >= 360
              ? (constraints.maxWidth - 16) / 2
              : constraints.maxWidth;

          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: items
                .map(
                  (chip) => SizedBox(
                    width: itemWidth,
                    child: chip,
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF475569)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ProgressToNextBadge extends StatelessWidget {
  const _ProgressToNextBadge({
    required this.current,
    required this.next,
    required this.ratio,
    required this.points,
    required this.pointsToNext,
  });

  final BadgeThreshold current;
  final BadgeThreshold next;
  final double ratio;
  final int points;
  final int pointsToNext;

  @override
  Widget build(BuildContext context) {
    final isMaxed = current.alias == next.alias;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF312E81), Color(0xFF3730A3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isMaxed ? '¡Llegaste a la cima!' : 'Rumbo a ${next.alias}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isMaxed
                ? 'Has desbloqueado todas las insignias disponibles.'
                : 'Acumula $pointsToNext puntos adicionales para alcanzar ${next.alias}.',
            style: const TextStyle(
              color: Color(0xFFD1D5F6),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: isMaxed ? 1 : ratio,
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF60A5FA),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$points / ${next.points} pts',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({
    required this.threshold,
    required this.badge,
    required this.isCurrent,
    required this.isNext,
  });

  final BadgeThreshold threshold;
  final UserBadgeVM? badge;
  final bool isCurrent;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final unlocked = badge != null;
    final color = unlocked ? const Color(0xFF16A34A) : const Color(0xFF94A3B8);

    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent
              ? const Color(0xFF6366F1)
              : isNext
                  ? const Color(0xFF60A5FA)
                  : const Color(0xFFE2E8F0),
          width: isCurrent || isNext ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                unlocked ? Icons.emoji_events : Icons.lock,
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  threshold.alias,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            unlocked
                ? 'Obtenida el ${_formatDate(badge!.earnedAt)}'
                : 'Se desbloquea con ${threshold.points} puntos',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (isCurrent) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE0E7FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Alias actual',
                style: TextStyle(
                  color: Color(0xFF3730A3),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatDate(DateTime? date) {
  if (date == null) return 'Pendiente';
  final local = date.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final year = local.year.toString();
  return '$day/$month/$year';
}
