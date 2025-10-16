import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:ticademy/app_index_page.dart';
import 'package:ticademy/auth_service.dart';
import 'package:ticademy/presence_service.dart'; // usamos tu servicio

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 🔐 Limpieza defensiva del estado del SDK de Google para evitar
      // reautenticación automática con la cuenta previa.
      try {
        final g = GoogleSignIn();
        if (await g.isSignedIn()) {
          await g.disconnect().catchError((_) {});
          await g.signOut().catchError((_) {});
        }
      } catch (_) {}

      // Precarga de imágenes
      precacheImage(
        const AssetImage('assets/images/logos/Ticademy_Logo.png'),
        context,
      );
      precacheImage(
        const AssetImage('assets/images/iconos/google_icon.png'),
        context,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goToRegister() {
    Navigator.pushNamed(context, '/register');
  }

  void _goToLogin() {
    Navigator.pushNamed(context, '/login');
  }

  Widget _buildTicademyLogo() {
    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(44),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(44),
        child: Image.asset(
          'assets/images/logos/Ticademy_Logo.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const _TicademyGlyph(),
        ),
      ),
    );
  }

  Widget _buildGoogleButton() {
    return _GoogleSignInButton(
      onSignedIn: (_) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AppIndexPage()),
          (route) => false,
        );
      },
    );
  }

  Widget _buildEmailButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _goToLogin,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(58),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(29),
          ),
          side: const BorderSide(color: Color(0xFFB8C3FF), width: 1.3),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        child: const Text('Iniciar con Email'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF7387FF), Color(0xFF5F74F9), Color(0xFF3F5FEA)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildTicademyLogo(),
                    const SizedBox(height: 36),
                    const Text(
                      'Ticademy',
                      style: TextStyle(
                        fontSize: 46,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Aprende TIC jugando',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFFE9ECFF),
                      ),
                    ),
                    const SizedBox(height: 44),
                    _buildGoogleButton(),
                    const SizedBox(height: 18),
                    _buildEmailButton(),
                    const SizedBox(height: 32),
                    TextButton(
                      onPressed: _goToRegister,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFE9ECFF),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      child: const Text('Crear una cuenta'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TicademyGlyph extends StatelessWidget {
  const _TicademyGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(44)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7C80FF), Color(0xFF5C5BF2)],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 34,
            left: 36,
            right: 36,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0CD6F7), Color(0xFF0992C5)],
                ),
              ),
            ),
          ),
          Positioned(
            top: 84,
            left: 72,
            right: 72,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0CD6F7), Color(0xFF0992C5)],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 52,
            left: 56,
            child: Transform.rotate(
              angle: -0.55,
              child: Container(
                width: 28,
                height: 10,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  color: const Color(0xFF1CD6A0),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            right: 44,
            child: Transform.rotate(
              angle: 0.65,
              child: Container(
                width: 66,
                height: 10,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  color: const Color(0xFF1CD6A0),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 78,
            left: 66,
            child: Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF1CD6A0),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Botón local para iniciar sesión con Google usando tu AuthService.
/// Elimina la dependencia a `widgets/google_sign_in_button.dart`.
class _GoogleSignInButton extends StatefulWidget {
  const _GoogleSignInButton({required this.onSignedIn});
  final void Function(Object /*UserCredential*/ cred) onSignedIn;

  @override
  State<_GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<_GoogleSignInButton> {
  bool _loading = false;

  Future<void> _handleGoogle() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      // Asegura que no se reusa sesión previa (ya lo hace el servicio también)
      // dentro de _handleGoogle()
      final cred = await authService.value.signInWithGoogle();
      // Marca online inmediatamente
      await PresenceService.instance.setOnlineAndBind();
      if (!mounted) return;
      widget.onSignedIn(cred);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _loading ? null : _handleGoogle,
        icon: _loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Image.asset(
                'assets/images/iconos/google_icon.png',
                width: 32,
                height: 32,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.login, color: Colors.white, size: 20),
              ),
        label: Text(_loading ? 'Conectando...' : 'Ingresar con Google'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFFFFFF),
          foregroundColor: Colors.black,
          minimumSize: const Size.fromHeight(58),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(29),
          ),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          elevation: 0,
        ),
      ),
    );
  }
}
