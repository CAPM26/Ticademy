import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:ticademy/friends_page.dart';
import 'package:ticademy/presence_service.dart';
import 'package:ticademy/ui/app_scaffold.dart';
import 'package:ticademy/user_profile_page.dart';
import 'package:ticademy/module_page.dart';

class AppIndexPage extends StatefulWidget {
  const AppIndexPage({super.key});

  @override
  State<AppIndexPage> createState() => _AppIndexPageState();
}

class _AppIndexPageState extends State<AppIndexPage> {
  // Firebase
  final _db = FirebaseDatabase.instance;
  final _auth = FirebaseAuth.instance;

  // UI controllers
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _modulesKey = GlobalKey();
  Timer? _debouncer;

  // RTDB subscriptions
  StreamSubscription<DatabaseEvent>? _modulesSub;
  StreamSubscription<DatabaseEvent>? _userSub;

  // Estado
  Map<String, dynamic> _modules = {}; // learningModules
  Map<String, dynamic> _userData = {}; // users/{uid}
  bool _loadingModules = true;
  bool _loadingUser = true;

  // Filtro nivel
  static const _levels = ['todos', 'basico', 'intermedio', 'avanzado'];
  String _activeLevel = 'todos';

  @override
  void initState() {
    super.initState();

    // Presencia global
    PresenceService.instance.start();
    final user = _auth.currentUser;
    if (user != null) {
      PresenceService.instance.setOnlineAndBind(user);
      _listenUser(user.uid);
    }
    _listenModules();
  }

  @override
  void dispose() {
    _debouncer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    _modulesSub?.cancel();
    _userSub?.cancel();
    super.dispose();
  }

  // ================= RTDB listeners =================

  void _listenModules() {
    _modulesSub?.cancel();
    _modulesSub = _db
        .ref('learningModules')
        .onValue
        .listen(
          (event) {
            final data = event.snapshot.value;
            if (data is Map) {
              setState(() {
                _modules = Map<String, dynamic>.from(data);
                _loadingModules = false;
              });
            } else {
              setState(() {
                _modules = {};
                _loadingModules = false;
              });
            }
          },
          onError: (_) {
            setState(() {
              _modules = {};
              _loadingModules = false;
            });
          },
        );
  }

  void _listenUser(String uid) {
    _userSub?.cancel();
    _userSub = _db
        .ref('users/$uid')
        .onValue
        .listen(
          (event) {
            final data = event.snapshot.value;
            if (data is Map) {
              setState(() {
                _userData = Map<String, dynamic>.from(data);
                _loadingUser = false;
              });
            } else {
              setState(() {
                _userData = {};
                _loadingUser = false;
              });
            }
          },
          onError: (_) {
            setState(() {
              _userData = {};
              _loadingUser = false;
            });
          },
        );
  }

  // ================= Normalización + filtros + orden =================

  List<_ModuleVM> get _visibleModules {
    // normaliza
    final list = _modules.entries.map((e) {
      final data = Map<String, dynamic>.from(e.value ?? {});
      return _ModuleVM.fromMap(
        e.key,
        data,
        progressPercent: _progressFor(e.key),
        lessonsCount: _lessonsFor(data),
      );
    }).toList();

    // filtro por nivel + búsqueda
    final term = _searchController.text.trim().toLowerCase();
    final filtered = list.where((m) {
      final lvl = (m.level ?? 'basico').toLowerCase();
      final levelOk = _activeLevel == 'todos' || lvl == _activeLevel;
      final termOk =
          term.isEmpty || (m.title ?? m.id).toLowerCase().contains(term);
      return levelOk && termOk;
    }).toList();

    // orden por "order" y fallback por título
    filtered.sort((a, b) {
      final ao = a.order ?? double.infinity;
      final bo = b.order ?? double.infinity;
      if (ao != bo) return ao.compareTo(bo);
      return (a.title ?? '').toLowerCase().compareTo(
        (b.title ?? '').toLowerCase(),
      );
    });

    return filtered;
  }

  int _progressFor(String moduleId) {
    final p = ((_userData['progress'] ?? {}) as Map?)?['modules'] as Map? ?? {};
    final m = p[moduleId] as Map? ?? {};
    final percent = m['percent'];
    if (percent is num) return percent.clamp(0, 100).toInt();
    return 0;
  }

  int _lessonsFor(Map<String, dynamic> module) {
    if (module['lessons'] is num) return (module['lessons'] as num).toInt();
    if (module['sections'] is Map) return (module['sections'] as Map).length;
    return 0;
  }

  Future<void> _scrollToModules() async {
    // Desplaza suave hasta la grilla de módulos (equivalente a ancla #modulesGrid)
    final ctx = _modulesKey.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

  // ================= Build =================

  @override
  Widget build(BuildContext context) {
    final loading = _loadingModules || _loadingUser;
    final modules = _visibleModules;

    return AppScaffold(
      currentTab: AppTab.home,
      onNavigateToTab: (tab) async {
        switch (tab) {
          case AppTab.home:
            // Ya estás en Home
            break;
          case AppTab.modules:
            await _scrollToModules();
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
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSearchField(),
            const SizedBox(height: 10),
            _buildLevelChips(),
            const SizedBox(height: 15),

            // Sección "modules" con Key para hacer scroll desde el tab inferior
            Container(
              key: _modulesKey,
              child: loading
                  ? const _SkeletonGrid()
                  : modules.isEmpty
                  ? const _EmptyState()
                  : _buildModulesGrid(modules),
            ),

            const SizedBox(height: 24),
            _buildChallengesCard(),
          ],
        ),
      ),
    );
  }

  // ================= UI =================

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (v) {
        _debouncer?.cancel();
        _debouncer = Timer(
          const Duration(milliseconds: 250),
          () => setState(() {}),
        );
      },
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

  Widget _buildLevelChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final lvl in _levels)
          ChoiceChip(
            label: Text(lvl[0].toUpperCase() + lvl.substring(1)),
            selected: _activeLevel == lvl,
            onSelected: (_) => setState(() => _activeLevel = lvl),
          ),
      ],
    );
  }

  Widget _buildModulesGrid(List<_ModuleVM> modules) {
    return GridView.builder(
      key: const PageStorageKey('modulesGrid'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
        childAspectRatio: 0.54,
      ),
      itemCount: modules.length,
      itemBuilder: (context, index) => _ModuleCard(
        module: modules[index],
        onOpen: () => _openModule(modules[index]),
      ),
    );
  }

  Widget _buildChallengesCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Retos',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 4),
          Text(
            'Muy pronto encontrarás desafíos interactivos para reforzar tus aprendizajes.',
            style: TextStyle(color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }

  void _openModule(_ModuleVM m) {
    final title = (m.title ?? '').toLowerCase();
    if (title.contains('windows')) {
      Navigator.of(context).pushNamed(ModulePage.routeName);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Abrir módulo: ${m.title ?? m.id}')),
      );
    }
  }
}

// ================= VM + UI Cards =================

class _ModuleVM {
  final String id;
  final String? title;
  final String? description;
  final String? level; // basico|intermedio|avanzado
  final double? order; // para ordenar
  final int lessons;
  final int percent; // progreso 0..100
  final String? theme; // blue|green|orange|purple|default

  _ModuleVM({
    required this.id,
    this.title,
    this.description,
    this.level,
    this.order,
    required this.lessons,
    required this.percent,
    this.theme,
  });

  factory _ModuleVM.fromMap(
    String id,
    Map<String, dynamic> m, {
    required int progressPercent,
    required int lessonsCount,
  }) {
    return _ModuleVM(
      id: id,
      title: (m['title'] ?? id).toString(),
      description: (m['description'] ?? '').toString(),
      level: (m['level'] ?? 'basico').toString(),
      order: (m['order'] is num) ? (m['order'] as num).toDouble() : null,
      lessons: lessonsCount,
      percent: progressPercent.clamp(0, 100),
      theme: (m['theme'] ?? 'default').toString(),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module, required this.onOpen});

  final _ModuleVM module;
  final VoidCallback onOpen;

@override
Widget build(BuildContext context) {
  final themeColor = _themeColor(module.theme);
  final isWindows = (module.id.toLowerCase().contains('windows') ||
      (module.title ?? '').toLowerCase().contains('windows'));
  final percent = module.percent.clamp(0, 100);

  return Stack(
    children: [
      // Card
      Container(
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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cabecera: imagen (Windows) o bloque de color (otros)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 90,
                  child: isWindows
                      ? Image.asset(
                          'assets/images/iconos/windows.png',
                          fit: BoxFit.cover,
                        )
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                themeColor,
                                Color.lerp(themeColor, Colors.white, .28) ??
                                    themeColor
                              ],
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),

              // Título y lecciones
              Text(
                module.title ?? 'Módulo',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF1D2536),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                module.lessons == 1
                    ? '1 lección'
                    : '${module.lessons} lecciones',
                style: const TextStyle(color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 10),

              // Barra de progreso
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: percent / 100,
                  minHeight: 8,
                  color: isWindows ? Colors.blueAccent : themeColor,
                  backgroundColor: (isWindows
                          ? Colors.blue
                          : themeColor)
                      .withOpacity(0.12),
                ),
              ),
              const SizedBox(height: 12),

              // Botón
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onOpen,
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
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(percent > 0 ? 'Reanudar' : 'Ver módulo'),
                ),
              ),
            ],
          ),
        ),
      ),

      // Chip con porcentaje, arriba-derecha
      Positioned(
        top: 12,
        right: 12,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: (isWindows ? Colors.blueAccent : themeColor),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: (isWindows ? Colors.blueAccent : themeColor)
                    .withOpacity(.25),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Text(
            '$percent%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    ],
  );
}


  Color _themeColor(String? theme) {
    switch ((theme ?? '').toLowerCase()) {
      case 'blue':
        return const Color(0xFF2563EB);
      case 'green':
        return const Color(0xFF22C55E);
      case 'orange':
        return const Color(0xFFF97316);
      case 'purple':
        return const Color(0xFF7C3AED);
      default:
        return const Color(0xFF64748B);
    }
  }
}
class _CardTopHeader extends StatelessWidget {
  const _CardTopHeader({required this.module});
  final _ModuleVM module;

  @override
  Widget build(BuildContext context) {
    final percent = module.percent.clamp(0, 100);
    final isWindows = (module.id.toLowerCase().contains('windows') ||
        (module.title ?? '').toLowerCase().contains('windows'));

    // Colores por defecto si NO es Windows (tu fallback actual)
    final fallback = _themeColor(module.theme);
    final fallbackLight = Color.lerp(fallback, Colors.white, .22) ?? fallback;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Container(
        height: 132,
        decoration: BoxDecoration(
          gradient: isWindows
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [fallback, fallbackLight],
                ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Fondo con logo SOLO para Windows
            if (isWindows)
              Image.asset(
                'assets/images/iconos/windows.png',
                fit: BoxFit.cover,
              ),

            // Velo para mejorar contraste del anillo/porcentaje
            if (isWindows)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withOpacity(.10),
                      Colors.white.withOpacity(.05),
                    ],
                  ),
                ),
              ),

            // Anillo + porcentaje centrado
            Center(
              child: SizedBox(
                width: 86,
                height: 86,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Pista
                    CircularProgressIndicator(
                      value: 1,
                      strokeWidth: 10,
                      color: Colors.white.withOpacity(.28),
                      backgroundColor: Colors.transparent,
                    ),
                    // Progreso
                    CircularProgressIndicator(
                      value: percent / 100,
                      strokeWidth: 10,
                      color: isWindows
                          ? Colors.white
                          : Colors.white.withOpacity(.95),
                      backgroundColor: Colors.transparent,
                    ),
                    Text(
                      '$percent%',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Copiamos tu helper para colores de tema (mismo que en _ModuleCard)
  Color _themeColor(String? theme) {
    switch ((theme ?? '').toLowerCase()) {
      case 'blue':   return const Color(0xFF2D6AE0);
      case 'green':  return const Color(0xFF2BAA58);
      case 'orange': return const Color(0xFFE97129);
      case 'purple': return const Color(0xFF6D40D8);
      default:       return const Color(0xFF4B5B7A);
    }
  }
}


class _SkeletonGrid extends StatelessWidget {
  const _SkeletonGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
        childAspectRatio: 0.58,
      ),
      itemBuilder: (_, __) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(
          children: [
            Container(
              height: 150,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(26),
                ),
                gradient: LinearGradient(
                  colors: [Colors.grey.shade200, Colors.grey.shade100],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 5, 18, 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 16,
                      width: 120,
                      color: Colors.grey.shade200,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 12,
                      width: 80,
                      color: Colors.grey.shade100,
                    ),
                    const Spacer(),
                    Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF3FB),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60),
      alignment: Alignment.center,
      child: const Text(
        'No encontramos módulos para tu búsqueda.\nAjusta los filtros o intenta con otro término.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFF6B7280)),
      ),
    );
  }
}
