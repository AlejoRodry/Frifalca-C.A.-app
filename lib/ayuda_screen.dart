import 'dart:ui';
import 'package:flutter/material.dart';
import 'theme.dart';

class AyudaScreen extends StatelessWidget {
  const AyudaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Centro de Ayuda"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : Colors.blueGrey[900],
        ),
        titleTextStyle: TextStyle(
          color: isDark ? Colors.white : Colors.blueGrey[900],
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF030B14), AppColors.primary]
                : [const Color(0xFFE3F2FD), Colors.white],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            children: [
              _buildHelpHeader(context),
              const SizedBox(height: 30),
              _buildHelpCard(
                context,
                icon: Icons.inventory_2_rounded,
                title: "Gestión de Inventario",
                description:
                    "El sistema gestiona tres tipos de stock:\n\n"
                    "• Físico: Cantidad real de hielo en cava.\n"
                    "• Comprometido: Hielo reservado por pedidos pendientes.\n"
                    "• Disponible: Stock real listo para la venta.\n\n"
                    "Al despachar un pedido, el sistema descuenta automáticamente las unidades del stock físico.",
              ),
              const SizedBox(height: 20),
              _buildHelpCard(
                context,
                icon: Icons.fingerprint_rounded,
                title: "Acceso con Huella Dactilar",
                description:
                    "Para mayor seguridad y rapidez, puedes configurar el acceso biométrico. "
                    "Esto vincula tu perfil de trabajador con el lector de huellas de tu dispositivo, "
                    "permitiendo iniciar sesión sin necesidad de ingresar tu contraseña manualmente en cada acceso.",
              ),
              const SizedBox(height: 20),
              _buildHelpCard(
                context,
                icon: Icons.notifications_active_rounded,
                title: "Sistema de Notificaciones FCM V1",
                description:
                    "Implementamos el protocolo HTTP v1 de Firebase Cloud Messaging para garantizar que "
                    "todas las alertas críticas lleguen al instante. Recibirás avisos sobre:\n\n"
                    "• Niveles de stock críticos.\n"
                    "• Paradas programadas de producción.\n"
                    "• Actualizaciones importantes del sistema.",
              ),
              const SizedBox(height: 40),
              Center(
                child: Text(
                  "Frigorífico Falcón C.A. - v1.0.0\nPNF Informática UPTAG",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.white38 : Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHelpHeader(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.secondary.withValues(alpha: 0.2),
            ),
          ),
          child: const Icon(
            Icons.help_outline_rounded,
            color: AppColors.secondary,
            size: 40,
          ),
        ),
        const SizedBox(height: 15),
        const Text(
          "¿Cómo podemos ayudarte?",
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 5),
        const Text(
          "Guía rápida de funciones del sistema Frifalca",
          style: TextStyle(color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildHelpCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withAlpha(15)
                : Colors.white.withAlpha(180),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.secondary.withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.secondary.withValues(alpha: 0.05),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: AppColors.secondary, size: 28),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Text(
                description,
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
