import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ticademy/auth_service.dart';

class GoogleSignInButton extends StatefulWidget {
  const GoogleSignInButton({
    super.key,
    this.label = 'Continuar con Google',
    this.onSignedIn,
    this.onError,
  });

  final String label;
  final ValueChanged<UserCredential>? onSignedIn;
  final ValueChanged<Object>? onError;

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  bool _isLoading = false;

  Future<void> _handlePressed() async {
    if (_isLoading) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
    });

    try {
      final credential = await authService.value.signInWithGoogle();
      if (!mounted) return;
      widget.onSignedIn?.call(credential);
    } on FirebaseAuthException catch (e) {
      widget.onError?.call(e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'No se pudo iniciar sesion con Google'),
        ),
      );
    } on MissingPluginException catch (e) {
      widget.onError?.call(e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Google Sign-In no esta disponible en esta plataforma.',
          ),
        ),
      );
    } catch (error) {
      widget.onError?.call(error);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hubo un problema al conectar con Google'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handlePressed,
        style:
            ElevatedButton.styleFrom(
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              minimumSize: const Size.fromHeight(58),
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1E2445),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(29),
              ),
              shadowColor: Colors.transparent,
              side: const BorderSide(color: Color(0xFFD9DEFF), width: 1.2),
            ).copyWith(
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return const Color(0xFFE5E9FF);
                }
                return null;
              }),
            ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: _isLoading
              ? const SizedBox(
                  key: ValueKey('loading'),
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.6),
                )
              : Row(
                  key: const ValueKey('content'),
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/iconos/google_icon.png',
                      width: 28,
                      height: 28,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 16),
                    Flexible(
                      child: Text(
                        widget.label,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
