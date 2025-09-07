import 'package:flutter/material.dart';
import 'package:ticademy/app_index_page.dart';
import 'package:ticademy/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  String errorMessage = '';

Future<void> _login() async {
  // Validación manual para mostrar alerta si los campos están vacíos
  if (_emailController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Por favor, completa el correo y la contraseña'),
      ),
    );
    return; // Detenemos la ejecución si falta información
  }

  if (!_formKey.currentState!.validate()) return;

  setState(() {
    _isLoading = true;
  });

  try {
    await authService.value?.signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
    );
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => AppIndexPage()),
      (Route<dynamic> route) => false,
    );
  } on FirebaseAuthException catch (e) {
    setState(() {
      errorMessage = e.message ?? 'Error desconocido';
    });
  } finally {
    setState(() {
      _isLoading = false;
    });
  }
}

void _forgotPassword() async {
  final email = _emailController.text.trim();

  if (email.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Por favor, ingresa tu correo electrónico para enviar el correo de recuperación'),
      ),
    );
    return;
  }

  try {
    await FirebaseAuth.instance.sendPasswordResetEmail(email : email);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Correo de recuperación enviado. Revisa tu bandeja.'),
      ),
    );
  } on FirebaseAuthException catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error: ${e.message}'),
      ),
    );
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Iniciar Sesión')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Ingresa un correo';
                  }
                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                    return 'Correo inválido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Contraseña'),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Ingresa tu contraseña';
                  }
                  if (value.length < 8) {
                    return 'Debe tener al menos 8 caracteres';
                  }
                  if (!RegExp(r'[A-Z]').hasMatch(value)) {
                    return 'Debe contener al menos una letra mayúscula';
                  }
                  if (!RegExp(r'[a-z]').hasMatch(value)) {
                    return 'Debe contener al menos una letra minúscula';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Text(errorMessage, style: TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _forgotPassword,
                  child: const Text('Olvidé mi contraseña'),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _login,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Iniciar Sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
