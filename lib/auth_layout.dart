import 'package:flutter/material.dart';
import 'package:ticademy/app_index_page.dart';
import 'package:ticademy/app_loading_page.dart';
import 'package:ticademy/auth_service.dart';
import 'package:ticademy/welcome_page.dart';

class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    this.pageIfNotConnected,
  });

  final Widget? pageIfNotConnected;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: authService,
      builder: (context, authService, child) {
        return StreamBuilder(
          stream: authService?.authStateChanges,
          builder: (context, snapshot) {
            Widget widget;
            print('AuthLayout: connectionState=${snapshot.connectionState}, hasData=${snapshot.hasData}, data=${snapshot.data}');
            if (snapshot.connectionState == ConnectionState.waiting) {
              widget = AppLoadingPage();
            }
            else if (snapshot.hasData) {
              widget =  AppIndexPage();
            } else {
              widget = pageIfNotConnected ?? const WelcomePage();
            }
            return widget;
          },
        );
      },
    );
  }
}
