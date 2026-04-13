import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'theme.dart';

class RegistroTrabajadorScreen extends StatefulWidget {
  const RegistroTrabajadorScreen({super.key});

  @override
  State<RegistroTrabajadorScreen> createState() =>
      _RegistroTrabajadorScreenState();
}

class _RegistroTrabajadorScreenState extends State<RegistroTrabajadorScreen> {
  final _nombreController = TextEditingController();
  final _apellidoController = TextEditingController();
  final _usuarioController = TextEditingController();
  final _emailController = TextEditingController();
  final _rolController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _emailValidado = false;
  bool _obscurePassword = true;

  Future<void> _validarEmail() async {
    final email = _emailController.text.toLowerCase().replaceAll(' ', '');
    if (email.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final doc = await FirebaseFirestore.instance
          .collection('PreAutorizaciones')
          .doc(email)
          .get();

      if (!doc.exists) {
        _mostrarError("Este correo no ha sido pre-autorizado.");
        setState(() => _isLoading = false);
        return;
      }

      final data = doc.data()!;
      if (data['status'] != 'pending') {
        _mostrarError(
          "Este registro ya ha sido completado o no está disponible.",
        );
        setState(() => _isLoading = false);
        return;
      }

      setState(() {
        _nombreController.text = data['nombre'] ?? '';
        _apellidoController.text = data['apellido'] ?? '';
        _rolController.text = data['rol'] ?? 'trabajador';
        _emailValidado = true;
        _isLoading = false;
      });
    } catch (e) {
      _mostrarError("Error al validar email: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _registrarTrabajador() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      _mostrarError("Las contraseñas no coinciden.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final emailNormalized = _emailController.text.trim().toLowerCase();

      // 1. Crear usuario en Auth
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: emailNormalized,
            password: _passwordController.text.trim(),
          );

      final uid = userCredential.user!.uid;

      // 2. Crear documento en Trabajadores usando UID como ID (siguiendo el patrón oficial)
      try {
        await FirebaseFirestore.instance
            .collection('Trabajadores')
            .doc(uid)
            .set({
              'nombre': _nombreController.text.trim(),
              'apellido': _apellidoController.text.trim(),
              'usuario': _usuarioController.text.trim(),
              'correo':
                  emailNormalized, // Email ya normalizado (trim y lowercase)
              'rol': _rolController.text.trim(),
              'cargo': 'Personal',
              'fecha_registro': FieldValue.serverTimestamp(),
              'completado': true,
              'uid': uid,
              'ultima_modificacion': FieldValue.serverTimestamp(),
            });
      } catch (e) {
        // ROLLBACK: Si falla la base de datos, eliminamos el usuario de Auth para evitar cuentas huérfanas
        await userCredential.user?.delete();
        debugPrint(
          "Rollback ejecutado: Usuario de Auth eliminado por error en Firestore.",
        );
        rethrow;
      }

      // 3. Actualizar status en PreAutorizaciones (opcional, si existe la colección)
      try {
        await FirebaseFirestore.instance
            .collection('PreAutorizaciones')
            .doc(emailNormalized)
            .update({'status': 'completed'});
      } catch (e) {
        // Ignorar si no existe o ya está actualizado
      }

      if (mounted) {
        // Limpiar controladores
        _nombreController.clear();
        _apellidoController.clear();
        _usuarioController.clear();
        _emailController.clear();
        _rolController.clear();
        _passwordController.clear();
        _confirmPasswordController.clear();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("¡Registro completado con éxito!"),
            backgroundColor: Colors.green,
          ),
        );

        // Resetear el estado de la aplicación y volver al login
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    } on FirebaseAuthException catch (e) {
      _mostrarError(_traducirError(e.code));
    } on FirebaseException catch (e) {
      _mostrarError("Error de Firebase: ${e.message}");
    } catch (e) {
      _mostrarError("Error inesperado: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _mostrarError(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: Colors.red),
    );
  }

  String _traducirError(String code) {
    switch (code) {
      case 'weak-password':
        return "La contraseña es muy débil.";
      case 'email-already-in-use':
        return "Este correo ya está registrado.";
      default:
        return "Error en el registro. Intenta de nuevo.";
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Registro de Trabajador"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
        titleTextStyle: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [const Color(0xFF05121F), AppColors.primary]
                : [const Color(0xFFE3F2FD), Colors.white],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.of(context).size.width > 600 ? 30 : 16,
                vertical: 30,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withAlpha(25)
                            : Colors.white.withAlpha(230),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withAlpha(50)
                              : Colors.blueGrey.withAlpha(20),
                        ),
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.badge_outlined,
                              color: AppColors.secondary,
                              size: 50,
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _emailValidado
                                  ? "Completa tu perfil"
                                  : "Verificación",
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _emailValidado
                                  ? "Asigna una contraseña para tu cuenta"
                                  : "Ingresa el correo con el que fuiste autorizado",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.black54,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 30),

                            // --- PASO 1: VALIDACIÓN DE EMAIL ---
                            if (!_emailValidado) ...[
                              _buildTextField(
                                controller: _usuarioController,
                                label: "Nombre de Usuario",
                                icon: Icons.person_pin_rounded,
                                isDark: isDark,
                                validator: (val) {
                                  if (val == null || val.isEmpty) {
                                    return "El usuario es obligatorio";
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),
                              _buildTextField(
                                controller: _emailController,
                                label: "Correo Autorizado",
                                icon: Icons.email_outlined,
                                keyboard: TextInputType.emailAddress,
                                isDark: isDark,
                              ),
                              const SizedBox(height: 30),
                              _buildButton(
                                text: _isLoading
                                    ? "Verificando..."
                                    : "Verificar Autorización",
                                onPressed: _isLoading ? null : _validarEmail,
                                isDark: isDark,
                              ),
                            ],

                            // --- PASO 2 Y 3: CARGA DE DATOS Y PASSWORD ---
                            if (_emailValidado) ...[
                              _buildTextField(
                                controller: _nombreController,
                                label: "Nombre",
                                icon: Icons.person_outline,
                                isDark: isDark,
                                validator: (val) {
                                  if (val == null || val.isEmpty) {
                                    return "Este campo es obligatorio";
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),
                              _buildTextField(
                                controller: _apellidoController,
                                label: "Apellido",
                                icon: Icons.person_outline,
                                isDark: isDark,
                                validator: (val) {
                                  if (val == null || val.isEmpty) {
                                    return "Este campo es obligatorio";
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),
                              _buildTextField(
                                controller: _rolController,
                                label: "Rol asignado",
                                icon: Icons.work_outline,
                                readOnly: true,
                                isDark: isDark,
                                validator: (val) {
                                  if (val == null || val.isEmpty) {
                                    return "Este campo es obligatorio";
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),
                              _buildTextField(
                                controller: _passwordController,
                                label: "Nueva Contraseña",
                                icon: _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                obscure: _obscurePassword,
                                isDark: isDark,
                                onIconPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                validator: (val) {
                                  if (val == null || val.length < 6) {
                                    return "Mínimo 6 caracteres";
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),
                              _buildTextField(
                                controller: _confirmPasswordController,
                                label: "Confirmar Contraseña",
                                icon: Icons.lock_outline,
                                obscure: _obscurePassword,
                                isDark: isDark,
                                validator: (val) {
                                  if (val != _passwordController.text) {
                                    return "Las contraseñas no coinciden";
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 30),
                              _buildButton(
                                text: _isLoading
                                    ? "Registrando..."
                                    : "Finalizar Registro",
                                onPressed: _isLoading
                                    ? null
                                    : _registrarTrabajador,
                                isDark: isDark,
                              ),
                              const SizedBox(height: 15),
                              TextButton(
                                onPressed: () =>
                                    setState(() => _emailValidado = false),
                                child: Text(
                                  "Usar otro correo",
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black54,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    VoidCallback? onIconPressed,
    TextInputType keyboard = TextInputType.text,
    String? Function(String?)? validator,
    bool readOnly = false,
    bool isDark = true,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      validator: validator,
      readOnly: readOnly,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
        prefixIcon: Icon(icon, color: AppColors.secondary, size: 20),
        suffixIcon: onIconPressed != null
            ? IconButton(
                icon: Icon(
                  obscure ? Icons.visibility_off : Icons.visibility,
                  color: isDark ? Colors.white38 : Colors.black26,
                ),
                onPressed: onIconPressed,
              )
            : null,
        filled: true,
        fillColor: isDark
            ? Colors.white.withAlpha(20)
            : Colors.black.withAlpha(10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildButton({
    required String text,
    required VoidCallback? onPressed,
    bool isDark = true,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.secondary,
          foregroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          elevation: 0,
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
