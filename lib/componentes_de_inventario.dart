// componentes_de_inventario.dart
import 'package:flutter/material.dart';
import 'modelo_pedidos.dart';

class InventarioResumenCard extends StatelessWidget {
  final int totalSacos;
  final int totalBolsas;
  final Function(String id, int cantidad) onAjustar;

  const InventarioResumenCard({
    super.key,
    required this.totalSacos,
    required this.totalBolsas,
    required this.onAjustar,
  });

  @override
  Widget build(BuildContext context) {
    bool stockCritico = totalSacos <= 0 || totalBolsas <= 0;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: stockCritico
              ? [const Color(0xFFF2994A), const Color(0xFFF2C94C)] // Naranja
              : [const Color(0xFF4FACFE), const Color(0xFF00F2FE)], // Azul
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color:
                (stockCritico
                        ? const Color(0xFFF2994A)
                        : const Color(0xFF4FACFE))
                    .withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.inventory_2_rounded, color: Colors.white, size: 28),
                SizedBox(width: 12),
                Text(
                  "Control de Inventario",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _itemProducto(
              context,
              "Sacos de Hielo",
              totalSacos,
              "NZAtCFwTfLTwb3xiiOUk",
            ),
            const SizedBox(height: 10),
            _itemProducto(
              context,
              "Bolsas de Hielo",
              totalBolsas,
              "DWDbVnRf5nqGu8uTu3KA",
            ),
            // Aviso compacto debajo si alguno está en cero
            if (totalSacos <= 0 || totalBolsas <= 0) ...[
              const SizedBox(height: 15),
              Container(
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
            ],
          ],
        ),
      ),
    );
  }

  Widget _itemProducto(
    BuildContext context,
    String nombre,
    int cantidad,
    String id,
  ) {
    bool sinStock = cantidad <= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nombre,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
              Text(
                sinStock ? "Sin unidades" : "Disponibles: $cantidad",
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.edit_note_rounded, color: Colors.white),
            onPressed: () => _mostrarDialogoAjuste(context, nombre, id),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoAjuste(BuildContext context, String nombre, String id) {
    final TextEditingController cantidadCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Ajustar Stock - $nombre"),
        content: TextField(
          controller: cantidadCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: "Ej: 100 o -50",
            helperText: "Usa números negativos para restar",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () {
              int? valor = int.tryParse(cantidadCtrl.text);
              if (valor != null) {
                onAjustar(id, valor);
                Navigator.pop(context);
              }
            },
            child: const Text("Aplicar"),
          ),
        ],
      ),
    );
  }
}

class ListaPedidosPendientes extends StatelessWidget {
  final List<Pedido> pedidos;
  final int stockSacoDisp;
  final int stockBolsaDisp;

  const ListaPedidosPendientes({
    super.key,
    required this.pedidos,
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
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Text(
            "Pedidos en Proceso",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        if (pendientes.isEmpty)
          const Center(child: Text("No hay pedidos pendientes")),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: pendientes.length,
          itemBuilder: (context, index) {
            final pedido = pendientes[index];

            // 2. Lógica de Colores Reactiva (Basada en el campo sinStock de Firestore)
            final bool requiereProduccion = pedido.sinStock;

            final Color colorEnfoque = requiereProduccion
                ? const Color(0xFFFFC107)
                : const Color(0xFF4CAF50); // Naranja Ambar / Verde
            final String statusTexto = requiereProduccion
                ? "PROCESANDO"
                : "COMPLETADO";
            final Color badgeBg = colorEnfoque.withValues(alpha: 0.12);

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: colorEnfoque.withValues(alpha: 0.08),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // --- ACERTO LATERAL DE COLOR ---
                    Container(
                      width: 8,
                      decoration: BoxDecoration(
                        color: colorEnfoque,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(25),
                          bottomLeft: Radius.circular(25),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "PEDIDO #${pedido.ticket}",
                                  style: TextStyle(
                                    color: Colors.blueGrey[300],
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: badgeBg,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    statusTexto,
                                    style: TextStyle(
                                      color: colorEnfoque,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(
                                  Icons.shopping_bag_rounded,
                                  color: Colors.cyan[400],
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  "${pedido.cantSaco > 0 ? '${pedido.cantSaco} sacos' : ''}${pedido.cantSaco > 0 && pedido.cantBolsa > 0 ? ' + ' : ''}${pedido.cantBolsa > 0 ? '${pedido.cantBolsa} bolsas' : ''}",
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2C3E50),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: "Tipo: ",
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 13,
                                    ),
                                  ),
                                  TextSpan(
                                    text: pedido.tipoHielo,
                                    style: const TextStyle(
                                      color: Color(0xFF2C3E50),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              "Total: ${pedido.monto.toStringAsFixed(0)} bs",
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
