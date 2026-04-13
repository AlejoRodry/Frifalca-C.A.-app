import 'package:flutter/material.dart';
import 'theme.dart';
import 'modelo_pedidos.dart';

Widget buildBadgeEstado(
  BuildContext context,
  String estado, [
  bool sinStock = false,
]) {
  Color color;
  String texto = estado;

  if (sinStock && estado == 'Pendiente') {
    color = AppColors.warning;
    texto = "EN PROCESO";
  } else {
    switch (estado) {
      case 'Pendiente':
        color = AppColors.warning;
        texto = "EN PROCESO";
        break;
      case 'Despachado':
        color = AppColors.success;
        break;
      case 'Cancelado':
        color = AppColors.error;
        break;
      default:
        color = AppColors.textSecondaryLight;
    }
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.5)),
    ),
    child: Text(
      texto,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

class PedidoCard extends StatelessWidget {
  final Pedido pedido;
  final VoidCallback onTap;
  final Widget? trailingActions;

  const PedidoCard({
    super.key,
    required this.pedido,
    required this.onTap,
    this.trailingActions,
  });

  /// Obtiene el color de la barra lateral según el estado del pedido
  Color _getColorEstado() {
    if (pedido.sinStock && pedido.estado == 'Pendiente') {
      return AppColors.pedidoSinStock; // Naranja
    }
    switch (pedido.estado) {
      case 'Despachado':
        return AppColors.pedidoDespachado; // Verde
      case 'Pendiente':
        return AppColors.pedidoEnProceso; // Amarillo
      case 'Cancelado':
        return AppColors.pedidoCancelado; // Rojo
      default:
        return AppColors.secondary; // Color por defecto
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = trailingActions;
    final fechaFormateada = pedido.fecha != null
        ? "${pedido.fecha!.day}/${pedido.fecha!.month}/${pedido.fecha!.year}"
        : "Sin fecha";

    final colorEstado = _getColorEstado();

    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: colorEstado, width: 5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Ticket: ${pedido.ticket}",
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    buildBadgeEstado(context, pedido.estado, pedido.sinStock),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Tipo: ${pedido.tipoHielo}",
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          Text(
                            "Fecha: $fechaFormateada",
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    actions ?? const SizedBox.shrink(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class InventarioResumenCard extends StatelessWidget {
  final int sacoFisico;
  final int sacoComp;
  final int bolsaFisico;
  final int bolsaComp;
  final Function(BuildContext context, String id, int cantidad, String motivo)
  onAjustar;
  final bool readOnly;

  const InventarioResumenCard({
    super.key,
    required this.sacoFisico,
    required this.sacoComp,
    required this.bolsaFisico,
    required this.bolsaComp,
    required this.onAjustar,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final int totalSacos = (sacoFisico - sacoComp).clamp(0, 999999);
    final int totalBolsas = (bolsaFisico - bolsaComp).clamp(0, 999999);
    bool stockCritico = totalSacos <= 0 || totalBolsas <= 0;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: stockCritico
              ? [
                  const Color(0xFFF2994A), // Naranja suave
                  const Color(0xFFF2C94C), // Amarillo sutil
                ]
              : [AppColors.primary, AppColors.primary.withValues(alpha: 0.9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (stockCritico ? AppColors.error : AppColors.primary)
                .withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.inventory_2_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                SizedBox(width: 12),
                Text(
                  "Control de Inventario",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 35), // Increased from 25 for better spacing
            // Fila con Sacos y Bolsas en la misma línea
            Row(
              children: [
                Expanded(
                  child: _itemProducto(
                    context,
                    "Sacos de Hielo",
                    sacoFisico,
                    sacoComp,
                    "NZAtCFwTfLTwb3xiiOUk",
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _itemProducto(
                    context,
                    "Bolsas de Hielo",
                    bolsaFisico,
                    bolsaComp,
                    "DWDbVnRf5nqGu8uTu3KA",
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            // Mensaje informativo
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.touch_app_rounded,
                    color: Colors.white70,
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Toca un producto para ver el inventario con más detalle",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Aviso compacto debajo si alguno está en cero - con AnimatedSize para expansión suave
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: (totalSacos <= 0 || totalBolsas <= 0)
                  ? Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            if (totalSacos <= 0)
                              const Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    "Sin stock en SACO",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            if (totalSacos <= 0 && totalBolsas <= 0)
                              const SizedBox(height: 4),
                            if (totalBolsas <= 0)
                              const Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    "Sin stock en BOLSA",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemProducto(
    BuildContext context,
    String nombre,
    int fisico,
    int comp,
    String id,
  ) {
    final int disponible = (fisico - comp).clamp(0, 999999);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _mostrarDesglose(context, nombre, fisico, comp),
              borderRadius: BorderRadius.circular(15),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          "Disp: $disponible",
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 10,
                              ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 10,
                          color: Colors.white70,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!readOnly)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: IconButton(
                icon: const Icon(
                  Icons.edit_note_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () => _mostrarDialogoAjuste(context, nombre, id),
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(),
              ),
            ),
        ],
      ),
    );
  }

  void _mostrarDesglose(
    BuildContext context,
    String nombre,
    int fisico,
    int comp,
  ) {
    final int disponible = (fisico - comp).clamp(0, 999999);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(25, 25, 25, 15),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Desglose: $nombre",
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            _filaDesglose(
              context,
              "Stock Físico (En cava)",
              fisico,
              Colors.blue,
            ),
            const Divider(),
            _filaDesglose(
              context,
              "Stock Comprometido (Pedidos)",
              comp,
              Colors.orange,
            ),
            const Divider(),
            _filaDesglose(
              context,
              "Stock Disponible (Venta)",
              disponible,
              disponible <= 0 ? Colors.red : Colors.green,
              esResultado: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _filaDesglose(
    BuildContext context,
    String label,
    int valor,
    Color color, {
    bool esResultado = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: esResultado ? FontWeight.bold : FontWeight.normal,
              fontSize: esResultado ? 16 : 14,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              valor.toString(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: esResultado ? 18 : 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoAjuste(BuildContext context, String nombre, String id) {
    final TextEditingController cantidadCtrl = TextEditingController();
    String? motivoSeleccionado;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text("Ajustar Stock - $nombre"),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: cantidadCtrl,
                    keyboardType: TextInputType.numberWithOptions(signed: true),
                    decoration: const InputDecoration(
                      hintText: "Ej: 100 o -50",
                      helperText: "Usa números negativos para restar",
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return "Campo obligatorio";
                      }
                      final valor = int.tryParse(v.replaceAll('-', ''));
                      if (valor == null) {
                        return "Debe ser un número válido";
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: "Motivo del ajuste",
                      prefixIcon: Icon(Icons.assignment_outlined),
                      helperText: "Selecciona el motivo correspondiente",
                    ),
                    initialValue: motivoSeleccionado,
                    hint: const Text("Selecciona un motivo"),
                    items: [
                      // Opciones para Entrada (valores positivos)
                      const DropdownMenuItem(
                        value: 'Producción del día',
                        child: Text('📦 Producción del día'),
                      ),
                      const DropdownMenuItem(
                        value: 'Devolución',
                        child: Text('🔄 Devolución'),
                      ),
                      const DropdownMenuItem(
                        value: 'Ajuste (+)',
                        child: Text('➕ Ajuste (+)'),
                      ),
                      // Opciones para Salida (valores negativos)
                      const DropdownMenuItem(
                        value: 'Merma/Ruptura',
                        child: Text('⚠️ Merma/Ruptura'),
                      ),
                      const DropdownMenuItem(
                        value: 'Ajuste (-)',
                        child: Text('➖ Ajuste (-)'),
                      ),
                    ],
                    onChanged: (valor) {
                      setDialogState(() {
                        motivoSeleccionado = valor;
                      });
                    },
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return "Debe seleccionar un motivo";
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: () {
                // Validar formulario
                if (!formKey.currentState!.validate()) {
                  return;
                }

                final text = cantidadCtrl.text.trim();
                if (text.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text("Por favor ingresa una cantidad"),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                int? valor = int.tryParse(text);
                if (valor == null) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text("solo numeros no texto"),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                if (motivoSeleccionado == null) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text("Debe seleccionar un motivo"),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                // Pasar el motivo al callback
                onAjustar(dialogContext, id, valor, motivoSeleccionado!);
                Navigator.pop(dialogContext);
              },
              child: const Text("Aplicar"),
            ),
          ],
        ),
      ),
    );
  }
}

class ListaPedidosPendientes extends StatelessWidget {
  final List<Pedido> pedidos;
  final int stockSacoDisp;
  final int stockBolsaDisp;
  final Function(Pedido pedido) onDespachar;
  final Function(Pedido pedido) onShowDetails;

  const ListaPedidosPendientes({
    super.key,
    required this.pedidos,
    required this.onDespachar,
    required this.onShowDetails,
    this.stockSacoDisp = 0,
    this.stockBolsaDisp = 0,
  });

  @override
  Widget build(BuildContext context) {
    final pendientes = pedidos.where((p) => p.estado == 'Pendiente').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Text(
            "Pedidos en Proceso",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        if (pendientes.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20.0),
            child: Center(child: Text("No hay pedidos pendientes")),
          ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: pendientes.length,
          itemBuilder: (context, index) {
            final pedido = pendientes[index];

            return PedidoCard(
              pedido: pedido,
              onTap: () => onShowDetails(pedido),
              trailingActions: Row(
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, 36),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () => onDespachar(pedido),
                    child: const Text(
                      "Despachar",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
