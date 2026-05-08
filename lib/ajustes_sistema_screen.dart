import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'servicios_de_base_de_datos.dart';
import 'servicios_de_notificaciones.dart';
import 'theme.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

class AjustesSistemaScreen extends StatefulWidget {
  const AjustesSistemaScreen({super.key});

  @override
  State<AjustesSistemaScreen> createState() => _AjustesSistemaScreenState();
}

class _AjustesSistemaScreenState extends State<AjustesSistemaScreen> {
  final DatabaseService _dbService = DatabaseService();
  final NotificationService _notifService = NotificationService();

  Future<void> _ejecutarRespaldo(
    BuildContext context, {
    bool soloLocal = false,
  }) async {
    // 1. Mostrar indicación de carga
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 2. Generar datos
      final datos = await _dbService.generarDatosRespaldo();
      final String jsonStr = jsonEncode(datos);

      if (soloLocal) {
        // --- RESPALDO LOCAL (no disponible en web) ---
        if (kIsWeb) {
          if (context.mounted) Navigator.pop(context);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'La descarga local no está disponible en el navegador. Usa "Respaldo en Google Drive".',
              ),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/respaldo_frifalca.json');
        await file.writeAsString(jsonStr);

        if (context.mounted) Navigator.pop(context); // Quitar carga
        await OpenFilex.open(file.path);
      } else {
        // --- RESPALDO EN DRIVE ---
        final exito = await _notifService.subirRespaldoDrive(datos);

        if (context.mounted) {
          Navigator.pop(context); // Quitar carga
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                exito
                    ? "¡Respaldo subido a Google Drive exitosamente!"
                    : "Error al subir a Drive. Revisa tu script puente.",
              ),
              backgroundColor: exito ? Colors.green : Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error crítico: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Ajustes del Sistema"),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _dbService.streamAjustesSistema(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};

          final bool calcularAuto = data['calcular_precios_auto'] ?? false;
          final bool stockBajo = data['notificaciones_stock_bajo'] ?? false;
          final bool updateAuto = data['actualizaciones_automaticas'] ?? false;
          final int itemsPorPagina = data['items_por_pagina'] ?? 10;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSectionHeader("Finanzas y Precios"),
              _buildSettingTileSimple(
                icon: Icons.currency_exchange_rounded,
                color: Colors.orange,
                title: "Gestión de Tasa de Cambio",
                subtitle: "Configurar valor del dólar (BCV/Manual)",
                onTap: () => _mostrarDialogoGestionTasa(context),
              ),
              const SizedBox(height: 10),
              _buildSettingTile(
                icon: Icons.calculate_rounded,
                title: "Calcular precios automáticamente",
                subtitle: "Sincronizado con la tasa oficial BCV",
                value: calcularAuto,
                onChanged: (val) {
                  _dbService.actualizarAjustesSistema(calcularPreciosAuto: val);
                },
              ),
              const Divider(height: 32),
              _buildSectionHeader("Preferencias de Visualización"),
              _buildSettingTileSimple(
                icon: Icons.list_alt_rounded,
                color: Colors.deepPurple,
                title: "Items por página",
                subtitle: "Actualmente: $itemsPorPagina elementos",
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (context) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            "Items por página",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        ...[10, 20, 50].map(
                          (val) => ListTile(
                            title: Text("$val pedidos"),
                            trailing: itemsPorPagina == val
                                ? const Icon(Icons.check, color: Colors.green)
                                : null,
                            onTap: () {
                              _dbService.actualizarAjustesSistema(
                                itemsPorPagina: val,
                              );
                              Navigator.pop(context);
                            },
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  );
                },
              ),
              const Divider(height: 32),
              _buildSectionHeader("Notificaciones"),
              _buildSettingTile(
                icon: Icons.notification_important_rounded,
                title: "Notificaciones de stock bajo",
                subtitle: "Alertas cuando los productos se agotan",
                value: stockBajo,
                onChanged: (val) {
                  _dbService.actualizarAjustesSistema(
                    notificacionesStockBajo: val,
                  );
                },
              ),
              const Divider(height: 32),
              _buildSectionHeader("Seguridad y Respaldos"),
              _buildSettingTileSimple(
                icon: Icons.cloud_upload_rounded,
                color: Colors.blue,
                title: "Respaldo en Google Drive",
                subtitle: "Subir copia de seguridad de toda la base de datos",
                onTap: () => _ejecutarRespaldo(context),
              ),
              const SizedBox(height: 10),
              _buildSettingTileSimple(
                icon: Icons.file_download_rounded,
                color: Colors.green,
                title: "Descargar Respaldo JSON",
                subtitle: "Guardar copia local en este dispositivo",
                onTap: () => _ejecutarRespaldo(context, soloLocal: true),
              ),
              const Divider(height: 32),
              _buildSettingTile(
                icon: Icons.system_update_rounded,
                title: "Habilitar actualizaciones automáticas",
                subtitle: "Descargar nuevas versiones al estar disponibles",
                value: updateAuto,
                onChanged: (val) {
                  _dbService.actualizarAjustesSistema(
                    actualizacionesAutomaticas: val,
                  );
                },
              ),
              const Divider(height: 32),
              _buildSectionHeader("Interfaz de Escritorio"),
              _buildSettingTile(
                icon: Icons.view_sidebar_rounded,
                title: "Mostrar panel lateral por defecto",
                subtitle: "Visible en pantallas grandes (Desktop)",
                value: data['mostrar_panel_lateral'] ?? true,
                onChanged: (val) {
                  _dbService.actualizarAjustesSistema(mostrarPanelLateral: val);
                },
              ),
              const SizedBox(height: 10),
              _buildSettingTile(
                icon: Icons.grid_view_rounded,
                title: "Diseño de pedidos compacto",
                subtitle: "Muestra pedidos en varias columnas (Grid)",
                value: data['diseno_compacto'] ?? false,
                onChanged: (val) {
                  _dbService.actualizarAjustesSistema(disenoCompacto: val);
                },
              ),
              const SizedBox(height: 10),
              _buildSettingTile(
                icon: Icons.view_stream_rounded,
                title: "Pedidos en ancho completo",
                subtitle: "Los pedidos ocupan todo el espacio horizontal",
                value: data['diseno_pedidos_largo'] ?? false,
                onChanged: (val) {
                  _dbService.actualizarAjustesSistema(disenoPedidosLargo: val);
                },
              ),
              const SizedBox(height: 40),
              const Center(
                child: Text(
                  "Los cambios se guardan y reflejan instantáneamente en todos los dispositivos.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _mostrarDialogoGestionTasa(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return StreamBuilder<DocumentSnapshot>(
          stream: _dbService.streamConfiguracionTasa(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();

            final data = snapshot.data!.data() as Map<String, dynamic>;
            final bool usarAuto = data['usar_automatica'] ?? false;
            final double valorManual = (data['valor_manual'] ?? 0.0).toDouble();
            final double ultimaBcv = (data['ultima_bcv'] ?? 0.0).toDouble();

            final TextEditingController manualController =
                TextEditingController(text: valorManual.toString());
            bool autoLocal = usarAuto;

            return StatefulBuilder(
              builder: (context, setStateDialog) {
                return AlertDialog(
                  title: const Text("Gestión de Tasa de Cambio"),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SwitchListTile(
                        title: const Text("Usar Tasa BCV Automática"),
                        subtitle: const Text(
                          "Se actualiza vía API de terceros",
                        ),
                        value: autoLocal,
                        onChanged: (val) {
                          setStateDialog(() => autoLocal = val);
                        },
                      ),
                      const SizedBox(height: 10),
                      if (!autoLocal)
                        TextField(
                          controller: manualController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: "Valor Manual (Bs/\$)",
                            prefixIcon: Icon(Icons.edit_note_rounded),
                          ),
                        ),
                      if (autoLocal)
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            "Última actualización BCV: $ultimaBcv Bs/\$",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Cancelar"),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        double? manualVal = double.tryParse(
                          manualController.text,
                        );
                        await _dbService.actualizarConfiguracionTasa(
                          usarAuto: autoLocal,
                          valorManual: manualVal,
                        );
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text("Guardar"),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppColors.secondary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingTileSimple({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.secondary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppColors.secondary),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        thumbColor: WidgetStateProperty.all(AppColors.secondary),
        activeTrackColor: AppColors.secondary.withAlpha(100),
      ),
    );
  }
}
