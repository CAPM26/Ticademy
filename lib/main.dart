import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:ticademy/collaborators_page.dart';
import 'package:ticademy/friends_page.dart';
import 'package:ticademy/presence_service.dart';
import 'package:ticademy/teachers_page.dart';
import 'firebase_options.dart';
import './app_index_page.dart';
import './login_page.dart';
import './register_page.dart';
import './welcome_page.dart';
import 'module_page.dart';
import 'user_profile_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await PresenceService.instance.start();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ticademy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5564F2)),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        UserProfilePage.routeName: (context) => const UserProfilePage(),
        '/': (context) => const WelcomePage(),
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterPage(),
        '/app': (context) => const AppIndexPage(),
        '/friends': (context) => const FriendsPage(),
        '/module': (context) => const ModulePage(),
        CollaboratorsPage.routeName: (_) => const CollaboratorsPage(),
        TeachersPage.routeName: (_) => const TeachersPage(),
      },
    );
  }
}

