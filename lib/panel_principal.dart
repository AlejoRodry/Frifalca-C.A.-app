import 'package:flutter/material.dart';
import 'servicios_de_base_de_datos.dart'; 
import 'componentes_de_inventario.dart' as comp;
import 'modelo_pedidos.dart';
import 'logic/inventory_manager.dart'; 
import 'package:firebase_auth/firebase_auth.dart';

class PanelPrincipal extends StatefulWidget {
  const PanelPrincipal({super.key});

  @override
  State<PanelPrincipal> createState() => _PanelPrincipalState();
}

class _PanelPrincipalState extends State<PanelPrincipal> {
  final DatabaseService _dbService = DatabaseService();
  final InventoryManager _inventoryManager = InventoryManager();
  String _filtroTicket = "";
  final String _rolActual = "Empleado";
  final String _filtroEstado = "Todos";
  String _nombreCompleto = "Usuario";

  @override
  void initState() {
    super.initState();
    _cargarDatosUsuario();
  }

  Future<void> _cargarDatosUsuario() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.email != null) {
      setState(() {
        _nombreCompleto = user.email!;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Frifalca"),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.inventory), text: "Inventario"),
              Tab(icon: Icon(Icons.list_alt), text: "Pedidos"),
              Tab(icon: Icon(Icons.person), text: "Perfil"),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => FirebaseAuth.instance.signOut(),
            )
          ],
        ),
        body: TabBarView(
          children: [
            _buildInventarioTab(),
            _buildPedidosTab(),
            _buildPerfilTab(),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _mostrarDialogoNuevoPedido(context),
          child: const Icon(Icons.add_shopping_cart),
        ),
      ),
    );
  }

  Widget _buildPedidosTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            onChanged: (value) => setState(() => _filtroTicket = value),
            decoration: const InputDecoration(
              labelText: "Buscar por Ticket",
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Pedido>>(
            stream: _dbService.streamPedidos(filtroEstado: _filtroEstado, filtroTicket: _filtroTicket),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              
              final pedidos = snapshot.data!;
              
              return StreamBuilder<Map<String, int>>(
                stream: _inventoryManager.stockStream,
                builder: (context, stockSnapshot) {
                  final stock = stockSnapshot.data ?? {};
                  final int sacosEnStock = stock['NZAtCFwTfLTwb3xiiOUk'] ?? 0;
                  final int bolsasEnStock = stock['DWDbVnRf5nqGu8uTu3KA'] ?? 0;

                  return ListView.builder(
                    itemCount: pedidos.length,
                    itemBuilder: (context, index) {
                      final pedido = pedidos[index];
                      
                      Color cardColor = Colors.white;
                      if (pedido.estado == 'Pendiente') {
                        bool stockSuficiente = true;
                        if (pedido.cantidadSacos > 0 && pedido.cantidadSacos > sacosEnStock) {
                          stockSuficiente = false;
                        }
                        if (pedido.cantidadBolsas > 0 && pedido.cantidadBolsas > bolsasEnStock) {
                          stockSuficiente = false;
                        }
                        
                        if (!stockSuficiente) {
                          cardColor = Colors.red[100]!;
                        }
                      }

                      return Card(
                        color: cardColor,
                        elevation: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: ListTile(
                          title: Text("Ticket: ${pedido.ticket}"),
                          subtitle: Text("Estado: ${pedido.estado}"),
                           trailing: pedido.estado == 'Pendiente'
                              ? ElevatedButton(
                                  child: const Text('Despachar'),
                                  onPressed: () {
                                    _dbService.despacharPedido(pedido.id, _nombreCompleto, pedido);
                                  },
                                )
                              : null,
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildInventarioTab() {
    return StreamBuilder<Map<String, int>>(
      stream: _inventoryManager.stockStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text("Error de conexión"));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final stock = snapshot.data!;
        final sacos = stock['NZAtCFwTfLTwb3xiiOUk'] ?? 0;
        final bolsas = stock['DWDbVnRf5nqGu8uTu3KA'] ?? 0;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(15),
          child: Column(
            children: [
              comp.InventarioResumenCard(
                totalSacos: sacos,
                totalBolsas: bolsas,
                onAjustar: (id, cantidad) {
                  _dbService.ajustarStock(id, cantidad, _rolActual);
                },
              ),
              const SizedBox(height: 20),
              const Divider(),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildPerfilTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Usuario: $_nombreCompleto', style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 20),
          ElevatedButton(
            child: const Text('Cerrar Sesión'),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          )
        ],
      ),
    );
  }

  void _mostrarDialogoNuevoPedido(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        final ticketController = TextEditingController();
        final montoController = TextEditingController();
        String categoriaHielo = 'Saco';

        return AlertDialog(
          title: const Text('Crear Nuevo Pedido'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ticketController,
                decoration: const InputDecoration(labelText: 'Ticket'),
              ),
              TextField(
                controller: montoController,
                decoration: const InputDecoration(labelText: 'Monto'),
                keyboardType: TextInputType.number,
              ),
              DropdownButton<String>(
                value: categoriaHielo,
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    // setState en el dialogo
                  }
                },
                items: <String>['Saco', 'Bolsa']
                    .map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: const Text('Crear'),
              onPressed: () {
                final ticket = ticketController.text;
                final monto = double.tryParse(montoController.text) ?? 0.0;
                
                _dbService.crearPedido(
                  categoriaHielo: categoriaHielo,
                  monto: monto,
                  ticket: ticket,
                  nombreCreador: _nombreCompleto,
                  orden: "N/A"
                );
                
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}
