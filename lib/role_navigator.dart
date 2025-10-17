import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ticademy/app_index_page.dart';
import 'package:ticademy/auth_service.dart';
import 'package:ticademy/collaborators_page.dart';
import 'package:ticademy/presence_service.dart';
import 'package:ticademy/teachers_page.dart';

class RoleNavigator {
  const RoleNavigator._();

  static Future<void> handlePostSignIn(BuildContext context, User user) async {
    final role = await authService.value.ensureUserRole(user: user);
    await PresenceService.instance.setOnlineAndBind(user);
    if (!context.mounted) return;

    final Widget destination;
    switch (role) {
      case 'docente':
        destination = const TeachersPage();
        break;
      case 'colaborador':
        destination = const CollaboratorsPage();
        break;
      default:
        destination = const AppIndexPage();
        break;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => destination),
      (route) => false,
    );
  }
}
