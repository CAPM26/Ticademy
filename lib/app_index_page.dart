import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ticademy/auth_service.dart';
import 'package:ticademy/welcome_page.dart';

class AppIndexPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // La función popPage() no es necesaria, la eliminamos.

    void _logout() async {
      try {
        await authService.value?.signOut();
        // Redirecciona a WelcomePage y elimina todas las rutas anteriores de la pila
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => WelcomePage()),
          (Route<dynamic> route) => false, // Elimina todas las rutas anteriores
        );
      } on FirebaseAuthException catch (e) {
        print(e.message);
      }
    }

    return Scaffold(
      backgroundColor: Color(0xFFF5F7FA), // Fondo claro
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.blue,
                      child: Icon(Icons.check, color: Colors.white),
                    ),
                    SizedBox(width: 8),
                    Text(
                      "Ticademy",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                // Botón de Cerrar Sesión
                IconButton(
                  icon: Icon(Icons.logout, color: Colors.blue.shade700),
                  onPressed: _logout, // Llama directamente a la función _logout
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade700,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.local_fire_department,
                        color: Colors.white,
                        size: 18,
                      ),
                      SizedBox(width: 4),
                      Text(
                        "3",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            // ...el resto de tu código
          ],
        ),
      ),
    );
  }

  // ... las demás funciones y widgets de apoyo
}