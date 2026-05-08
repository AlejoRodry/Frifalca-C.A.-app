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
  final bool isDetailed;
  final bool fullWidth;

  const PedidoCard({
    super.key,
    required this.pedido,
    required this.onTap,
    this.trailingActions,
    this.isDetailed = false,
    this.fullWidth =
        true, // Fuerzo que los pedidos sean alargados uniformemente
  });

  /// Obtiene el color de la barra lateral según el estado del pedido
  Color _getColorEstado() {
    if (pedido.sinStock && pedido.estado == 'Pendiente') {
      return AppColors.warning; // Naranja/Ambar
    }
    switch (pedido.estado) {
      case 'Despachado':
        return AppColors.success; // Verde
      case 'Pendiente':
        return AppColors.warning; // Amarillo
      case 'Cancelado':
        return AppColors.error; // Rojo
      default:
        return AppColors.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorEstado = _getColorEstado();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool esMixto = pedido.cantSaco > 0 && pedido.cantBolsa > 0;

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      child: Card(
        elevation: isDetailed ? 0 : 2,
        margin: isDetailed
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        color: isDetailed ? Colors.transparent : Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: InkWell(
          onTap: isDetailed ? null : onTap,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: isDetailed
                  ? null
                  : Border(left: BorderSide(color: colorEstado, width: 6)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cabecera: Ticket #001 (Texto reducido) + Badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Ticket #${pedido.ticket}",
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 16, // 1rem Subtitulo
                          color: isDark ? Colors.white : AppColors.primary,
                        ),
                      ),
                      buildBadgeEstado(context, pedido.estado, pedido.sinStock),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (!isDetailed) ...[
                    // VISTA RESUMIDA OPTIMIZADA (Mobile First)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Bloque informativo Izquierdo
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                esMixto ? "Mixto" : pedido.tipoHielo,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13, // 0.8rem Parrafo
                                ),
                              ),
                              Text(
                                "Sacos: ${pedido.cantSaco} | Bolsas: ${pedido.cantBolsa}",
                                style: const TextStyle(
                                  fontSize: 13, // 0.8rem Parrafo
                                  color: Colors.blueGrey,
                                ),
                              ),
                              Text(
                                pedido.fecha != null
                                    ? "${pedido.fecha!.day}/${pedido.fecha!.month} ${pedido.fecha!.hour}:${pedido.fecha!.minute.toString().padLeft(2, '0')}"
                                    : "Sin fecha",
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12, // 0.75rem aprox
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Monto destacado a la izquierda de las acciones
                        Padding(
                          padding: const EdgeInsets.only(right: 8, bottom: 4),
                          child: Text(
                            "${pedido.monto.toStringAsFixed(0)} Bs",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: isDark
                                  ? AppColors.secondary
                                  : AppColors.primary,
                            ),
                          ),
                        ),

                        // Acciones a la derecha
                        ?trailingActions,
                      ],
                    ),
                  ] else ...[
                    // VISTA DETALLADA
                    const Divider(),
                    _buildDetailRow(
                      context,
                      Icons.inventory_2_outlined,
                      "Especificación",
                      pedido.tipoHielo,
                    ),
                    _buildDetailRow(
                      context,
                      Icons.shopping_cart_checkout_outlined,
                      "Cantidades",
                      "Sacos: ${pedido.cantSaco} | Bolsas: ${pedido.cantBolsa}",
                    ),
                    _buildDetailRow(
                      context,
                      Icons.payments_outlined,
                      "Monto Total",
                      "${pedido.monto.toStringAsFixed(2)} Bs",
                    ),
                    _buildDetailRow(
                      context,
                      Icons.person_add_alt_1_outlined,
                      "Vendedor",
                      pedido.creadoPor ?? "N/A",
                    ),
                    _buildDetailRow(
                      context,
                      Icons.local_shipping_outlined,
                      "Estado Despacho",
                      pedido.despachadoPor ?? "Pendiente",
                    ),
                    _buildDetailRow(
                      context,
                      Icons.history_edu_outlined,
                      "Nº de Orden",
                      pedido.orden ?? "General",
                    ),
                    if (pedido.detalleSaco != null ||
                        pedido.detalleBolsa != null)
                      _buildDetailRow(
                        context,
                        Icons.notes_outlined,
                        "Notas Adicionales",
                        "${pedido.detalleSaco ?? ''} ${pedido.detalleBolsa ?? ''}",
                      ),
                    const SizedBox(height: 10),
                    ?trailingActions,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? Colors.blueGrey.shade300
                        : Colors.blueGrey.shade700,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
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
    final bool sinStock =
        (sacoFisico - sacoComp) <= 0 || (bolsaFisico - bolsaComp) <= 0;
    final int totalSacos = (sacoFisico - sacoComp).clamp(0, 999999);
    final int totalBolsas = (bolsaFisico - bolsaComp).clamp(0, 999999);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: sinStock
              ? [Colors.orange.shade800, Colors.red.shade700]
              : [Colors.blue.shade800, Colors.cyan.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (sinStock ? Colors.orange : Colors.cyan).withValues(
              alpha: 0.3,
            ),
            blurRadius: 15,
            offset: const Offset(0, 8),
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
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.inventory_2_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Control de Inventario",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                // Si el ancho es menor a 340px, apilamos las tarjetas en vertical
                bool stackModo = constraints.maxWidth < 340;

                final items = [
                  Expanded(
                    flex: stackModo ? 0 : 1,
                    child: _itemProducto(
                      context,
                      "Sacos de Hielo",
                      sacoFisico,
                      sacoComp,
                      "NZAtCFwTfLTwb3xiiOUk",
                    ),
                  ),
                  SizedBox(
                    width: stackModo ? 0 : 12,
                    height: stackModo ? 8 : 0,
                  ),
                  Expanded(
                    flex: stackModo ? 0 : 1,
                    child: _itemProducto(
                      context,
                      "Bolsas de Hielo",
                      bolsaFisico,
                      bolsaComp,
                      "DWDbVnRf5nqGu8uTu3KA",
                    ),
                  ),
                ];

                return stackModo
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: items
                            .map((w) => w is Expanded ? w.child : w)
                            .toList(),
                      )
                    : Row(children: items);
              },
            ),
            const SizedBox(height: 10),
            // Mensaje informativo
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.touch_app_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Toca un producto para ver el inventario con más detalle",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13, // 0.8rem Parrafo
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
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
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
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 14, // Reducido de 16
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          "Disp: $disponible",
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 12, // Reducido de 13
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 12,
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
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: IconButton(
                icon: const Icon(
                  Icons.edit_note_rounded,
                  color: Colors.white,
                  size: 22,
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
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 18,
                              color: Colors.blue,
                            ),
                            SizedBox(width: 8),
                            Text('Producción del día'),
                          ],
                        ),
                      ),
                      const DropdownMenuItem(
                        value: 'Devolución',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.sync_rounded,
                              size: 18,
                              color: Colors.blue,
                            ),
                            SizedBox(width: 8),
                            Text('Devolución'),
                          ],
                        ),
                      ),
                      const DropdownMenuItem(
                        value: 'Ajuste (+)',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add_circle_outline_rounded,
                              size: 18,
                              color: Colors.blue,
                            ),
                            SizedBox(width: 8),
                            Text('Ajuste (+)'),
                          ],
                        ),
                      ),
                      // Opciones para Salida (valores negativos)
                      const DropdownMenuItem(
                        value: 'Merma/Ruptura',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 18,
                              color: Colors.orange,
                            ),
                            SizedBox(width: 8),
                            Text('Merma/Ruptura'),
                          ],
                        ),
                      ),
                      const DropdownMenuItem(
                        value: 'Ajuste (-)',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.remove_circle_outline_rounded,
                              size: 18,
                              color: Colors.red,
                            ),
                            SizedBox(width: 8),
                            Text('Ajuste (-)'),
                          ],
                        ),
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
    this.pedidosFullWidth = false,
  });

  final bool pedidosFullWidth;

  @override
  Widget build(BuildContext context) {
    final pendientes = pedidos.where((p) => p.estado == 'Pendiente').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
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
        LayoutBuilder(
          builder: (context, gridConstraints) {
            final int crossAxisCount =
                (gridConstraints.maxWidth > 800 && !pedidosFullWidth) ? 2 : 1;

            if (crossAxisCount > 1) {
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 600,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent: 135,
                ),
                itemCount: pendientes.length,
                itemBuilder: (context, index) {
                  final pedido = pendientes[index];
                  return PedidoCard(
                    pedido: pedido,
                    onTap: () => onShowDetails(pedido),
                    fullWidth: pedidosFullWidth,
                    trailingActions: Row(
                      mainAxisSize: MainAxisSize.min,
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
              );
            } else {
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: pendientes.length,
                itemBuilder: (context, index) {
                  final pedido = pendientes[index];
                  return PedidoCard(
                    pedido: pedido,
                    onTap: () => onShowDetails(pedido),
                    fullWidth: pedidosFullWidth,
                    trailingActions: Row(
                      mainAxisSize: MainAxisSize.min,
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
              );
            }
          },
        ),
      ],
    );
  }
}
