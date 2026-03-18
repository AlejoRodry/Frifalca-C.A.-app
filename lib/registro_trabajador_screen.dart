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
  final _cedulaController = TextEditingController();
  final _emailController = TextEditingController();
  final _rolController = TextEditingController();
  final _statusController = TextEditingController();
  final _passwordController = TextEditingController();
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
        _cedulaController.text = data['cedula'] ?? '';
        _statusController.text = 'active'; // Status por defecto al registrarse
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

      // 2. Crear documento en pre_autorizacion_usuarios con email como ID
      await FirebaseFirestore.instance
          .collection('pre_autorizacion_usuarios')
          .doc(emailNormalized)
          .set({
            'nombre': _nombreController.text.trim(),
            'apellido': _apellidoController.text.trim(),
            'cedula': _cedulaController.text.trim(),
            'email': emailNormalized,
            'rol': _rolController.text.trim(),
            'status': _statusController.text.trim(),
            'uid': uid,
            'ingresado': FieldValue.serverTimestamp(),
            'ultima_modificacion': FieldValue.serverTimestamp(),
          });

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
        _cedulaController.clear();
        _emailController.clear();
        _rolController.clear();
        _statusController.clear();
        _passwordController.clear();

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
                : [AppColors.primary, const Color(0xFF0E3D6B)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(30),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(25),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white.withAlpha(50)),
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
                              style: const TextStyle(
                                color: Colors.white,
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
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 30),

                            // --- PASO 1: VALIDACIÓN DE EMAIL ---
                            if (!_emailValidado) ...[
                              _buildTextField(
                                controller: _emailController,
                                label: "Correo Autorizado",
                                icon: Icons.email_outlined,
                                keyboard: TextInputType.emailAddress,
                              ),
                              const SizedBox(height: 30),
                              _buildButton(
                                text: _isLoading
                                    ? "Verificando..."
                                    : "Verificar Autorización",
                                onPressed: _isLoading ? null : _validarEmail,
                              ),
                            ],

                            // --- PASO 2 Y 3: CARGA DE DATOS Y PASSWORD ---
                            if (_emailValidado) ...[
                              _buildTextField(
                                controller: _nombreController,
                                label: "Nombre",
                                icon: Icons.person_outline,
                              ),
                              const SizedBox(height: 15),
                              _buildTextField(
                                controller: _apellidoController,
                                label: "Apellido",
                                icon: Icons.person_outline,
                              ),
                              const SizedBox(height: 15),
                              _buildTextField(
                                controller: _cedulaController,
                                label: "Cédula",
                                icon: Icons.badge_outlined,
                                keyboard: TextInputType.number,
                              ),
                              const SizedBox(height: 15),
                              _buildTextField(
                                controller: _rolController,
                                label: "Rol asignado",
                                icon: Icons.work_outline,
                              ),
                              const SizedBox(height: 15),
                              _buildTextField(
                                controller: _statusController,
                                label: "Estado",
                                icon: Icons.info_outline,
                              ),
                              _buildTextField(
                                controller: _passwordController,
                                label: "Nueva Contraseña",
                                icon: _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                obscure: _obscurePassword,
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
                              const SizedBox(height: 30),
                              _buildButton(
                                text: _isLoading
                                    ? "Registrando..."
                                    : "Finalizar Registro",
                                onPressed: _isLoading
                                    ? null
                                    : _registrarTrabajador,
                              ),
                              const SizedBox(height: 15),
                              TextButton(
                                onPressed: () =>
                                    setState(() => _emailValidado = false),
                                child: const Text(
                                  "Usar otro correo",
                                  style: TextStyle(color: Colors.white70),
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
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      validator: validator,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: AppColors.secondary, size: 20),
        suffixIcon: onIconPressed != null
            ? IconButton(
                icon: Icon(icon, color: Colors.white38),
                onPressed: onIconPressed,
              )
            : null,
        filled: true,
        fillColor: Colors.white.withAlpha(20),
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
