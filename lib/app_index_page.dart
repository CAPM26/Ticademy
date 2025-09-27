import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ticademy/auth_service.dart';
import 'package:ticademy/welcome_page.dart';

class AppIndexPage extends StatefulWidget {
  const AppIndexPage({super.key});

  @override
  State<AppIndexPage> createState() => _AppIndexPageState();
}

class _AppIndexPageState extends State<AppIndexPage> {
  static const List<_CourseInfo> _courses = [
    _CourseInfo(
      title: 'Windows',
      lessons: 3,
      progress: 0.30,
      color: Color(0xFF3A7BFF),
      iconPath: 'assets/images/iconos/windows.png',
    ),
    _CourseInfo(
      title: 'Internet',
      lessons: 5,
      progress: 0.65,
      color: Color(0xFF4ECB71),
      iconPath: 'assets/images/iconos/internet.png',
    ),
    _CourseInfo(
      title: 'Ofimática',
      lessons: 80,
      progress: 0.80,
      color: Color(0xFFFD8B3E),
      iconPath: 'assets/images/iconos/office.png',
    ),
    _CourseInfo(
      title: 'IT seguridad',
      lessons: 50,
      progress: 0.50,
      color: Color(0xFF7B62FF),
      iconPath: 'assets/images/iconos/ciber.png',
    ),
  ];

  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    try {
      await authService.value.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomePage()),
        (_) => false,
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      final message = error.message ?? 'Ocurrió un error al cerrar sesión';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  List<_CourseInfo> get _visibleCourses {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _courses;
    }
    return _courses
        .where((course) => course.title.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 15),
              _buildSearchField(),
              const SizedBox(height: 15),
              _buildCoursesGrid(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0B1726).withOpacity(0.15),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Image.asset(
              'assets/images/logos/Ticademy_Logo.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF8AF0A7), Color(0xFF7FD1FF)],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'hi',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0B1726),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            'Ticademy',
            style:
                Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0B1726),
                ) ??
                const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0B1726),
                ),
          ),
        ),
        PopupMenuButton<String>(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          tooltip: 'Menú',
          onSelected: (value) {
            switch (value) {
              case 'profile':
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Perfil próximamente disponible'),
                  ),
                );
                break;
              case 'help':
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Centro de ayuda en construcción'),
                  ),
                );
                break;
              case 'logout':
                _logout();
                break;
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'profile', child: Text('Perfil')),
            PopupMenuItem(value: 'help', child: Text('Ayuda')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'logout', child: Text('Cerrar sesión')),
          ],
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF0B1726),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.more_horiz, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: 'Buscar',
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
    );
  }

  Widget _buildCoursesGrid() {
    final courses = _visibleCourses;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
        childAspectRatio: 0.58,
      ),
      itemCount: courses.length,
      itemBuilder: (context, index) {
        final course = courses[index];
        return _CourseCard(course: course);
      },
    );
  }
}

class _CourseInfo {
  final String title;
  final int lessons;
  final double progress;
  final Color color;
  final String iconPath;

  const _CourseInfo({
    required this.title,
    required this.lessons,
    required this.progress,
    required this.color,
    required this.iconPath,
  });
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course});

  final _CourseInfo course;

  @override
  Widget build(BuildContext context) {
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CourseProgress(
            color: course.color,
            progress: course.progress,
            iconPath: course.iconPath,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 5, 18, 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1D2536),
                    ),
                  ),
                  Text(
                    '${course.lessons} lecciones',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEFF3FB),
                        foregroundColor: const Color(0xFF1D2536),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Reanudar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseProgress extends StatelessWidget {
  const _CourseProgress({
    required this.color,
    required this.progress,
    required this.iconPath,
  });

  final Color color;
  final double progress;
  final String iconPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.white, 0.3) ?? color],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Center(
                child: Image.asset(
                  iconPath,
                  width: 108,
                  height: 108,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.image_not_supported_outlined,
                      size: 48,
                      color: Colors.white,
                    );
                  },
                ),
              ),
            ),
            _ProgressBar(progress: progress),
            Text(
              '${(progress * 100).round()}%',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 5,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(20),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: LinearProgressIndicator(
          value: progress.clamp(0, 1),
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          backgroundColor: Colors.transparent,
        ),
      ),
    );
  }
}
