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
    int totalGeneral = totalSacos + totalBolsas;
    // Color azul celeste "hielo"
    final Color azulHielo = Colors.lightBlue[300]!;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Column(
        children: [
          ExpansionTile(
            leading: Icon(Icons.ac_unit, color: azulHielo, size: 30),
            title: Text("Inventario Actual", 
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blue[900])),
            subtitle: Text("Total unidades: $totalGeneral\nPresionar para más información",
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
            children: [
              _itemProducto(context, "Sacos de Hielo", totalSacos, "NZAtCFwTfLTwb3xiiOUk"),
              _itemProducto(context, "Bolsas de Hielo", totalBolsas, "DWDbVnRf5nqGu8uTu3KA"),
            ],
          ),
          // Aviso debajo del modal si alguno está en cero
          if (totalSacos <= 0 || totalBolsas <= 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red[50]!,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15)),
              ),
              child: Column(
                children: [
                  if (totalSacos <= 0)
                    const Text("⚠️ Trabajando sin stock en SACO", 
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  if (totalBolsas <= 0)
                    const Text("⚠️ Trabajando sin stock en BOLSA", 
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _itemProducto(BuildContext context, String nombre, int cantidad, String id) {
    bool sinStock = cantidad <= 0;
    return ListTile(
      title: Text(nombre, style: TextStyle(color: sinStock ? Colors.red : Colors.black)),
      subtitle: sinStock ? const Text("Trabajando sin stock", style: TextStyle(color: Colors.red)) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("$cantidad", 
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: sinStock ? Colors.red : Colors.black)),
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.blueGrey),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
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
  final List<Pedido> pedidos; // Recibiremos los pedidos desde el panel principal

  const ListaPedidosPendientes({super.key, required this.pedidos});

  @override
  Widget build(BuildContext context) {
    // Filtramos solo los que están en estado 'Pendiente'
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
          shrinkWrap: true, // Importante para que funcione dentro de un SingleChildScrollView
          physics: const NeverScrollableScrollPhysics(),
          itemCount: pendientes.length,
          itemBuilder: (context, index) {
            final pedido = pendientes[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.timer, color: Colors.orange),
                title: Text("Ticket: ${pedido.ticket}"),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Producto: ${pedido.tipoHielo}"),
                    Text("Creado por: ${pedido.creadoPor ?? 'No asignado'}", 
                      style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.blueGrey)),
                      if (pedido.despachadoPor != null)
                        Text("Despachado por: ${pedido.despachadoPor}", 
                          style: const TextStyle(color: Colors.green)),
                  ],
                ),
                trailing: Text("${pedido.monto} Bs", 
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            );
          },
        ),
      ],
    );
  }
}