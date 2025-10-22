// lib/ui/app_scaffold.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:ticademy/auth_service.dart';
import 'package:ticademy/welcome_page.dart';
import 'package:ticademy/collaborators_page.dart';

enum AppTab { home, achievements, friends, profile }

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.body,
    required this.currentTab,
    this.title,
    this.showTopBar = true,
    this.actions,
    this.onNavigateToTab,
  });

  final Widget body;
  final AppTab currentTab;
  final String? title;                  // si quieres sobreescribir
  final bool showTopBar;
  final List<Widget>? actions;          // acciones extra
  final void Function(AppTab tab)? onNavigateToTab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: showTopBar
          ? _AppTopBar(
              title: title,
              extraActions: actions,
            )
          : null,
      body: SafeArea(child: body),
      bottomNavigationBar: _AppBottomNav(
        currentTab: currentTab,
        onTap: (tab) {
          if (onNavigateToTab != null) {
            onNavigateToTab!(tab);
          } else {
            _defaultNav(context, tab);
          }
        },
      ),
    );
  }

  void _defaultNav(BuildContext context, AppTab tab) {
    switch (tab) {
      case AppTab.home:
        Navigator.pushReplacementNamed(context, '/app');
        break;
      case AppTab.achievements:
        Navigator.pushReplacementNamed(context, '/achievements');
        break;
      case AppTab.friends:
        Navigator.pushReplacementNamed(context, '/friends');
        break;
      case AppTab.profile:
        Navigator.pushReplacementNamed(context, '/profile');
        break;
    }
  }
}

class _AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _AppTopBar({this.title, this.extraActions});

  final String? title;
  final List<Widget>? extraActions;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      elevation: 0,
      backgroundColor: const Color(0xFFF6F8FC),
      centerTitle: false,
      titleSpacing: 0,
      title: Row(
        children: [
          const SizedBox(width: 16),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color.fromARGB(255, 212, 214, 216).withValues(alpha: 0.12),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/images/logos/Ticademy_Logo.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title ?? 'Ticademy',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0B1726),
            ),
          ),
        ],
      ),
      actions: [
        if (extraActions != null) ...extraActions!,
        const SizedBox(width: 4),
        _TopMenuButton(),
        const SizedBox(width: 12),
      ],
    );
  }
}

class _TopMenuButton extends StatelessWidget {
  const _TopMenuButton();

  Future<bool> _isCollaborator() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    // Lee solo el rol string
    final snap = await FirebaseDatabase.instance
        .ref('users/${user.uid}/profile/role')
        .get();

    final role = (snap.value ?? '').toString().trim().toLowerCase();
    return role == 'colaborador' || role == 'colaboradora';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isCollaborator(),
      builder: (context, snapshot) {
        final canSeeCollab = snapshot.data == true;

        return PopupMenuButton<String>(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onSelected: (value) async {
            switch (value) {
              case 'collab':
                // Abre la vista de colaboradores
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CollaboratorsPage()),
                );
                break;
              case 'help':
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Centro de ayuda en construcción')),
                );
                break;
              case 'logout':
                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (uid != null) {
                  // si usas PresenceService:
                  // await PresenceService.instance.setOffline();
                }
                await authService.value.signOut();
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const WelcomePage()),
                  (_) => false,
                );
                break;
            }
          },
          itemBuilder: (context) => [
            if (canSeeCollab)
              const PopupMenuItem(value: 'collab', child: Text('Colaboradores')),
            if (canSeeCollab) const PopupMenuDivider(),
            const PopupMenuItem(value: 'help', child: Text('Ayuda')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'logout', child: Text('Cerrar sesión')),
          ],
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF0B1726),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.more_horiz, color: Colors.white),
          ),
        );
      },
    );
  }
}


class _BasicTopMenu extends StatelessWidget {
  const _BasicTopMenu({
    required this.isCollab,
    required this.onHelp,
    required this.onLogout,
  });

  final bool isCollab;
  final VoidCallback onHelp;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (value) async {
        switch (value) {
          case 'collab':
            Navigator.of(context).pushNamed(CollaboratorsPage.routeName);
            break;
          case 'help':
            onHelp();
            break;
          case 'logout':
            onLogout();
            break;
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        if (isCollab)
          const PopupMenuItem<String>(
            value: 'collab',
            child: ListTile(
              leading: Icon(Icons.group_work_outlined),
              title: Text('Colaboradores'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        const PopupMenuItem<String>(
          value: 'help',
          child: ListTile(
            leading: Icon(Icons.help_outline),
            title: Text('Ayuda'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'logout',
          child: ListTile(
            leading: Icon(Icons.logout),
            title: Text('Cerrar sesión'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF0B1726),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.more_horiz, color: Colors.white),
      ),
    );
  }
}


class _AppBottomNav extends StatelessWidget {
  const _AppBottomNav({
    required this.currentTab,
    required this.onTap,
  });

  final AppTab currentTab;
  final void Function(AppTab) onTap;

  int get _index {
    switch (currentTab) {
      case AppTab.home:
        return 0;
      case AppTab.achievements:
        return 1;
      case AppTab.friends:
        return 2;
      case AppTab.profile:
        return 3;
    }
  }

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (i) => onTap(AppTab.values[i]),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.emoji_events_outlined),
          selectedIcon: Icon(Icons.emoji_events),
          label: 'Logros',
        ),
        NavigationDestination(
          icon: Icon(Icons.group_outlined),
          selectedIcon: Icon(Icons.group),
          label: 'Amigos',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Perfil',
        ),
      ],
      // estilo opcional
      elevation: 1,
      backgroundColor: Colors.white,
      indicatorColor: const Color(0xFFEFF3FB),
      height: 64,
    );
  }
}
