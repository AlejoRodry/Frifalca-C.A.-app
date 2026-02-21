import 'package:flutter/material.dart';
import 'servicios_de_base_de_datos.dart'; // Aquí está tu DatabaseService original
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'componentes_de_inventario.dart' as comp; // Usamos alias para evitar conflictos
import 'modelo_pedidos.dart';

class PanelPrincipal extends StatefulWidget {
  const PanelPrincipal({super.key});

  @override
  State<PanelPrincipal> createState() => _PanelPrincipalState();
}

class _PanelPrincipalState extends State<PanelPrincipal> {
  final DatabaseService _dbService = DatabaseService();
  String _filtroTicket = "";
  String _rolActual = "Empleado";
  String _filtroEstado = "Todos";

  late Stream<List<Pedido>> _pedidosStream;
  late Stream<QuerySnapshot> _productosStream;

  @override
  void initState() {
    super.initState();
    _cargarDatosUsuario();
    _pedidosStream = _dbService.streamPedidos(filtroEstado: "Pendiente");
    _productosStream = FirebaseFirestore.instance
        .collection('Productos')
        .snapshots();
  }

  String _nombreCompleto = "Usuario"; // Añade esta variable

  Future<void> _cargarDatosUsuario() async {
    final userAuth = FirebaseAuth.instance.currentUser;
    if (userAuth != null && userAuth.email != null) {
      final query = await FirebaseFirestore.instance
          .collection('Trabajadores')
          .where('correo', isEqualTo: userAuth.email)
          .get();

      if (query.docs.isNotEmpty && mounted) {
        final data = query.docs.first.data();
        setState(() {
          _rolActual = query.docs.first.data()['rol'] ?? "Empleado";
          _nombreCompleto = "${data['nombre']} ${data['apellido']}";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Frifalca"),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async => await FirebaseAuth.instance.signOut(),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.inventory), text: "Inventario"),
              Tab(icon: Icon(Icons.list_alt), text: "Pedidos"),
              Tab(icon: Icon(Icons.person), text: "Perfil"),
            ],
          ),
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
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: "Buscar ticket...",
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) => setState(() => _filtroTicket = val),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: _filtroEstado,
                items: ["Todos", "Pendiente", "Despachado", "Cancelado"]
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (val) => setState(() => _filtroEstado = val!),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Pedido>>(
            stream: _dbService.streamPedidos(
              filtroEstado: _filtroEstado,
              filtroTicket: _filtroTicket,
            ),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final pedidos = snapshot.data!;
              return ListView.builder(
                itemCount: pedidos.length,
                itemBuilder: (context, index) {
                  final pedido = pedidos[index];
                  final fechaFormateada = pedido.fecha != null 
                    ? "${pedido.fecha!.day}/${pedido.fecha!.month}/${pedido.fecha!.year}" 
                    : "Sin fecha";
                  return Card(
                    elevation: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: InkWell(
                      onTap: () => _mostrarDetalleCompleto(context, pedido), // Abre el modal inferior
                      borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text("Ticket: ${pedido.ticket}", 
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  _buildBadgeEstado(pedido.estado),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("Tipo: ${pedido.tipoHielo}", style: TextStyle(color: Colors.grey[700])),
                                        Text("Fecha: $fechaFormateada", style: TextStyle(color: Colors.grey[700])),
                                      ],
                                    ),
                                  ),
                                if (pedido.estado == 'Pendiente')
                                  Row(
                                    children: [
                                      if (_rolActual == "admin")
                                      IconButton(
                                        icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                                        onPressed: () => _dbService.cancelarPedido(pedido.id),
                                      ),
                                      const SizedBox(width: 4),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green[50], foregroundColor: Colors.green),
                                        onPressed: () => _dbService.despacharPedido(pedido.id, _nombreCompleto),
                                        child: const Text("Despachar"),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
              );
            },
          ) 
        ),          
      ],
    );
  }
  // Dentro de _PanelPrincipalState en panel_principal.dart
  Widget _buildInventarioTab() {
    return StreamBuilder<List<Pedido>>(
      stream: _pedidosStream,
      builder: (context, pedidoSnap) {
        // Renombrado a pedidoSnap
        return StreamBuilder<QuerySnapshot>(
          stream: _productosStream,
          builder: (context, prodSnap) {
            // Renombrado a prodSnap
            if (pedidoSnap.hasError || prodSnap.hasError) {
              return const Center(child: Text("Error de conexión"));
            }
            if (!pedidoSnap.hasData || !prodSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            int sacos = 0;
            int bolsas = 0;

            for (var doc in prodSnap.data!.docs) {
              if (doc.id == "NZAtCFwTfLTwb3xiiOUk") sacos = doc['stock'] ?? 0;
              if (doc.id == "DWDbVnRf5nqGu8uTu3KA") bolsas = doc['stock'] ?? 0;
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(15),
              child: Column(
                children: [
                  comp.InventarioResumenCard(
                    totalSacos: sacos,
                    totalBolsas: bolsas,
                    onAjustar: (id, cantidad) {
                      // Llama a tu servicio existente para sumar o restar
                      _dbService.ajustarStock(id, cantidad, _rolActual);
                    },
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  comp.ListaPedidosPendientes(pedidos: pedidoSnap.data ?? []),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPerfilTab() {
    final User? userAuth = FirebaseAuth.instance.currentUser;
    if (userAuth == null) {
      return const Center(child: Text("No hay sesión activa"));
    }
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('Trabajadores')
          .where('correo', isEqualTo: userAuth.email)
          .get()
          .then((value) => value.docs.first),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text("Error al obtener datos"));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!.data() as Map<String, dynamic>;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(
                Icons.account_circle,
                size: 100,
                color: Colors.blueGrey,
              ),
              const SizedBox(height: 20),
              _infoCard("Usuario", data['usuario'] ?? 'No disponible'),
              _infoCard("Nombre", data['nombre'] ?? 'No disponible'),
              _infoCard("Apellido", data['apellido'] ?? 'No disponible'),
              _infoCard("Rol", data['rol'] ?? 'No disponible'),
              _infoCard("Correo", data['correo'] ?? 'No disponible'),
              const SizedBox(height: 20),
              Text(
                "ID: ${userAuth.uid}",
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoCard(String titulo, String valor) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ListTile(
        title: Text(
          titulo,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        subtitle: Text(
          valor,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // El [Pedido? pedido] significa que es opcional (sirve para Crear y para Editar)
  void _mostrarDialogoNuevoPedido(BuildContext context, [Pedido? pedido]) {
    final TextEditingController ticketController = TextEditingController(text: pedido?.ticket ?? "");
    final TextEditingController montoController = TextEditingController(text: pedido?.monto.toString() ?? "");
    
    // Controladores de cantidad (comportamiento bancario/numérico)
    final TextEditingController cantSacoCont = TextEditingController(text: "1");
    final TextEditingController cantBolsaCont = TextEditingController(text: "1");

    String ordenSeleccionada = "Saco"; // Saco, Bolsa, Mixto
    String? subTipoSaco = "Saco Público"; 
    String? subTipoBolsa = "Bolsa Público";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder( // Para actualizar el diálogo internamente
        builder: (context, setState) => AlertDialog(
          title: Text(pedido == null ? "Nuevo Pedido" : "Editar Pedido"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ticketController,
                  decoration: const InputDecoration(labelText: "N° Ticket (Referencia)"),
                ),
                const SizedBox(height: 10),
                // --- SELECCIÓN DE ORDEN ---
                DropdownButtonFormField<String>(
                  initialValue: ordenSeleccionada,
                  decoration: const InputDecoration(labelText: "Orden"),
                  items: ["Saco", "Bolsa", "Mixto"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (val) => setState(() => ordenSeleccionada = val!),
                ),

                // --- SECCIÓN DINÁMICA: SACO ---
                if (ordenSeleccionada == "Saco" || ordenSeleccionada == "Mixto") ...[
                  const Divider(),
                  DropdownButtonFormField<String>(
                    initialValue: subTipoSaco,
                    decoration: const InputDecoration(labelText: "Tipo de Hielo (Saco)"),
                    items: ["Saco Pescador", "Saco Público", "Donación"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (val) => setState(() => subTipoSaco = val),
                  ),
                  TextField(
                    controller: cantSacoCont,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Cantidad de Sacos"),
                  ),
                ],

                // --- SECCIÓN DINÁMICA: BOLSA ---
                if (ordenSeleccionada == "Bolsa" || ordenSeleccionada == "Mixto") ...[
                  const Divider(),
                  DropdownButtonFormField<String>(
                    initialValue: subTipoBolsa,
                    decoration: const InputDecoration(labelText: "Tipo de Hielo (Bolsa)"),
                    items: ["Bolsa Público", "Bolsa a Mayor", "Donación"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (val) => setState(() => subTipoBolsa = val),
                  ),
                  TextField(
                    controller: cantBolsaCont,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Cantidad de Bolsas"),
                  ),
                ],

                const Divider(),
                TextField(
                  controller: montoController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: "Monto Total (Bs)", prefixText: "Bs. "),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: () async {
                final double monto = double.tryParse(montoController.text) ?? 0.0;
                final int cantSaco = int.tryParse(cantSacoCont.text) ?? 0;
                final int cantBolsa = int.tryParse(cantBolsaCont.text) ?? 0;

                String categoriaFinal = "";
                Map<String, int> mapaDescuento = {};

                if (ordenSeleccionada == "Mixto") {
                  categoriaFinal = "Mixto: $subTipoSaco + $subTipoBolsa";
                  mapaDescuento = {
                    "NZAtCFwTfLTwb3xiiOUk": cantSaco, 
                    "DWDbVnRf5nqGu8uTu3KA": cantBolsa 
                  };
                } else if (ordenSeleccionada == "Saco") {
                    categoriaFinal = subTipoSaco!;
                    mapaDescuento = {"NZAtCFwTfLTwb3xiiOUk": cantSaco};
                } else {
                    categoriaFinal = subTipoBolsa!;
                    mapaDescuento = {"DWDbVnRf5nqGu8uTu3KA": cantBolsa};
                }

                // Definimos el mapa (Esto es lo que tenías y causaba el warning)
                final Map<String, dynamic> dataPedido = {
                  'Monto_total': monto,
                  'N_ticket': ticketController.text,
                  'creado_por': _nombreCompleto,
                  'despachado_por': "",
                  'estado': "Pendiente",
                  'fecha': FieldValue.serverTimestamp(),
                  'fecha_despacho': null,
                  'tipo_hielo': {
                    'categoria': categoriaFinal,
                    'orden': ordenSeleccionada,
                    'detalle_saco': ordenSeleccionada != "Bolsa" ? subTipoSaco : null,
                    'detalle_bolsa': ordenSeleccionada != "Saco" ? subTipoBolsa : null,
                    'cantidad_saco': cantSaco,
                    'cantidad_bolsa': cantBolsa,
                  },
                };

                // REPARACIÓN: Usamos los datos de 'dataPedido' para llamar al servicio
                await _dbService.crearPedidoYDescontar(
                  categoriaHielo: dataPedido['tipo_hielo']['categoria'], // Usando la variable
                  monto: dataPedido['Monto_total'],                     // Usando la variable
                  ticket: dataPedido['N_ticket'],                       // Usando la variable
                  productosYCantidades: mapaDescuento,
                  nombreCreador: dataPedido['creado_por'],              // Usando la variable
                );

                  if (context.mounted) Navigator.pop(context);
                },
              child: const Text("Guardar Pedido"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgeEstado(String estado) {
  Color color;
  switch (estado) {
      case 'Pendiente': color = Colors.orange; break;
      case 'Despachado': color = Colors.green; break;
      case 'Cancelado': color = Colors.red; break;
      default: color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration( color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: color)),
      child: Text(estado, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  void _mostrarDetalleCompleto(BuildContext context, Pedido pedido) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                ),
                const SizedBox(height: 20),
                Text("Información Completa", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue[900])),
                const Divider(),
                _filaDetalle(Icons.confirmation_number, "N° Ticket", pedido.ticket),
                _filaDetalle(Icons.ac_unit, "Tipo de Hielo", pedido.tipoHielo),
                _filaDetalle(Icons.attach_money, "Monto Total", "${pedido.monto} Bs"),
                _filaDetalle(Icons.info, "Estado Actual", pedido.estado),
                _filaDetalle(Icons.person_add, "Creado por", pedido.creadoPor ?? "N/A"),
                _filaDetalle(Icons.local_shipping, "Despachado por", pedido.despachadoPor ?? "Pendiente"),
                _filaDetalle(Icons.calendar_today, "Fecha y Hora", pedido.fecha?.toString() ?? "N/A"),
                const SizedBox(height: 20),
                // Botón de edición solo para el Admin
                if (_rolActual == "admin")
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.edit),
                      label: const Text("Editar Pedido"),
                      onPressed: () {
                        Navigator.pop(context);
                        // Cierra el modal de detalles
                        _mostrarDialogoNuevoPedido(context, pedido); // <--- ESTO ES LO QUE FALTA
                        // Aquí llamarías a tu diálogo de edición
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Widget auxiliar para las filas del modal
  Widget _filaDetalle(IconData icono, String titulo, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icono, color: Colors.blueGrey, size: 20),
          const SizedBox(width: 10),
          Text("$titulo: ", style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(valor, style: const TextStyle(color: Colors.black87))),
        ],
      ),
    );
  } 
} 