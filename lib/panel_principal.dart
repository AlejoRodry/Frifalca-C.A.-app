import 'package:flutter/material.dart';
import 'servicios_de_base_de_datos.dart'; // Aquí está tu DatabaseService original
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'componentes_de_inventario.dart'
    as comp; // Usamos alias para evitar conflictos
import 'modelo_pedidos.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';

class PanelPrincipal extends StatefulWidget {
  final VoidCallback onToggleTheme;
  const PanelPrincipal({super.key, required this.onToggleTheme});

  @override
  State<PanelPrincipal> createState() => _PanelPrincipalState();
}

class _PanelPrincipalState extends State<PanelPrincipal> {
  final DatabaseService _dbService = DatabaseService();
  String _filtroTicket = "";
  String _rolActual = "Empleado";
  String _filtroEstado = "Todos";
  DateTime _selectedDate = DateTime.now();

  late Stream<QuerySnapshot> _productosStream;

  @override
  void initState() {
    super.initState();
    _cargarDatosUsuario();
    _productosStream = FirebaseFirestore.instance
        .collection('Productos')
        .snapshots();
  }

  String _nombreCompleto = "Usuario"; // Añade esta variable

  Future<void> _cargarDatosUsuario() async {
    final userAuth = FirebaseAuth.instance.currentUser;
    if (userAuth != null) {
      if (!mounted) return;
      try {
        debugPrint("DEBUG: Buscando trabajador con UID: ${userAuth.uid}");

        final doc = await FirebaseFirestore.instance
            .collection('Trabajadores')
            .doc(userAuth.uid)
            .get();

        if (!mounted) return;

        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          setState(() {
            _nombreCompleto =
                "${data['nombre'] ?? 'Sin Nombre'} ${data['apellido'] ?? ''}";
            _rolActual = data['rol'] ?? "Empleado";
          });
          debugPrint("DEBUG: Éxito! Datos encontrados: $_nombreCompleto");
        } else {
          debugPrint(
            "DEBUG: ERROR - El documento NO existe en la colección Trabajadores.",
          );
          setState(() => _nombreCompleto = "Error: Doc no encontrado");
        }
      } catch (e) {
        debugPrint("DEBUG: ERROR EXCEPCIÓN - $e");
        if (!mounted) return;
        setState(() => _nombreCompleto = "Error: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        body: SafeArea(
          child: StreamBuilder<QuerySnapshot>(
            stream: _productosStream,
            builder: (context, prodSnap) {
              int sacoFisico = 0, sacoComp = 0;
              int bolsaFisico = 0, bolsaComp = 0;

              if (prodSnap.hasData) {
                for (var doc in prodSnap.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (doc.id == "NZAtCFwTfLTwb3xiiOUk") {
                    sacoFisico = data['stock_fisico'] ?? 0;
                    sacoComp = data['stock_comprometido'] ?? 0;
                  }
                  if (doc.id == "DWDbVnRf5nqGu8uTu3KA") {
                    bolsaFisico = data['stock_fisico'] ?? 0;
                    bolsaComp = data['stock_comprometido'] ?? 0;
                  }
                }
              }

              int sacoDisp = sacoFisico - sacoComp;
              int bolsaDisp = bolsaFisico - bolsaComp;
              bool hayAlerta = (sacoDisp <= 0 && bolsaDisp <= 0);
              double headerHeight = hayAlerta ? 310 : 250;

              return NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) {
                  return [
                    // --- LOGO Y LOGOUT (Scrollable) ---
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 15,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Image.asset(
                              'assets/frifalca6.png',
                              height: 40,
                              fit: BoxFit.contain,
                            ),
                            Text(
                              "Frifalca C.A.",
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.cyan[600],
                                letterSpacing: -0.5,
                              ),
                            ),
                            Row(
                              children: [
                                _buildHeaderButton(
                                  icon:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Icons.light_mode
                                      : Icons.dark_mode,
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.yellow
                                      : const Color(0xFF2C3E50),
                                  onPressed: widget.onToggleTheme,
                                ),
                                _buildHeaderButton(
                                  icon: Icons.logout_rounded,
                                  color: const Color(0xFFE74C3C),
                                  onPressed: () =>
                                      _mostrarConfirmacionLogout(context),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // --- BIENVENIDA (Scrollable) ---
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _buildGreetingCard(),
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 15)),

                    // --- CONTROL DE INVENTARIO (Sticky/Pinned) ---
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _SliverAppBarDelegate(
                        minHeight: headerHeight,
                        maxHeight: headerHeight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: Column(
                            children: [
                              if (hayAlerta) _buildAlertaProduccion(),
                              comp.InventarioResumenCard(
                                totalSacos: sacoDisp,
                                totalBolsas: bolsaDisp,
                                onAjustar: (id, cantidad) => _dbService
                                    .ajustarStock(id, cantidad, _rolActual),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ];
                },
                body: TabBarView(
                  children: [
                    _buildInventarioTabContent(sacoDisp, bolsaDisp),
                    _buildPedidosTab(),
                    _buildCitasTab(),
                    _buildConfiguracionesTab(),
                  ],
                ),
              );
            },
          ),
        ),
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SizedBox(
            height: 60,
            width: 60,
            child: FloatingActionButton(
              onPressed: () => _mostrarDialogoNuevoPedido(context),
              backgroundColor: Colors.cyan,
              elevation: 4,
              shape: const CircleBorder(),
              child: const Icon(Icons.add, color: Colors.white, size: 30),
            ),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  Widget _buildHeaderButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
            ),
          ],
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      onPressed: onPressed,
    );
  }

  Widget _buildGreetingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: Colors.cyan.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            "Panel Central",
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
          const SizedBox(height: 5),
          Text(
            "¡Buen día, ${_nombreCompleto.split(' ')[0]}!",
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C3E50),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertaProduccion() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.red[900],
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        children: [
          Icon(Icons.report_problem, color: Colors.white, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              "⚠️ ALERTA: Producción detenida.",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      height: 80,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(35),
        boxShadow: [
          BoxShadow(
            color: Colors.cyan.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(35),
        child: const TabBar(
          labelColor: Colors.cyan,
          unselectedLabelColor: Colors.blueGrey,
          labelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
          unselectedLabelStyle: TextStyle(fontSize: 10),
          indicator: UnderlineTabIndicator(
            borderSide: BorderSide(width: 3, color: Colors.cyan),
            insets: EdgeInsets.symmetric(horizontal: 45),
          ),
          indicatorPadding: EdgeInsets.only(bottom: 8),
          tabs: [
            Tab(icon: Icon(Icons.grid_view_rounded, size: 22), text: "Panel"),
            Tab(
              icon: Icon(Icons.receipt_long_rounded, size: 22),
              text: "Pedidos",
            ),
            Tab(
              icon: Icon(Icons.calendar_month_rounded, size: 22),
              text: "Citas",
            ),
            Tab(
              icon: Icon(Icons.settings_rounded, size: 22),
              text: "Configuraciones",
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPedidosTab() {
    return Column(
      children: [
        // --- BARRA DE BÚSQUEDA Y FILTROS ---
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 5),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              onChanged: (val) => setState(() => _filtroTicket = val),
              decoration: const InputDecoration(
                hintText: "Buscar por número de ticket...",
                hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                prefixIcon: Icon(Icons.search_rounded, color: Colors.cyan),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
        ),

        // --- FILTROS HORIZONTALES ---
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          child: Row(
            children: [
              _buildFilterChip("Todos"),
              _buildFilterChip("Pendiente", label: "En espera"),
              _buildFilterChip("Despachado"),
              _buildFilterChip("Cancelado"),
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
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      onTap: () => _mostrarDetalleCompleto(
                        context,
                        pedido,
                      ), // Abre el modal inferior
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Ticket: ${pedido.ticket}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                _buildBadgeEstado(
                                  pedido.estado,
                                  pedido.sinStock,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Tipo: ${pedido.tipoHielo}",
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                      Text(
                                        "Fecha: $fechaFormateada",
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (pedido.estado == 'Pendiente')
                                  Row(
                                    children: [
                                      if (_rolActual == "admin")
                                        IconButton(
                                          icon: const Icon(
                                            Icons.cancel_outlined,
                                            color: Colors.red,
                                          ),
                                          onPressed: () =>
                                              _dbService.cancelarPedido(
                                                pedido.id,
                                                cantSaco: pedido.cantSaco,
                                                cantBolsa: pedido.cantBolsa,
                                              ),
                                        ),
                                      const SizedBox(width: 4),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green[50],
                                          foregroundColor: Colors.green,
                                        ),
                                        onPressed: () async {
                                          await _dbService.despacharPedido(
                                            pedido.id,
                                            _nombreCompleto,
                                            cantSaco: pedido.cantSaco,
                                            cantBolsa: pedido.cantBolsa,
                                          );
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  "Se ha despachado correctamente",
                                                ),
                                                backgroundColor: Colors.green,
                                              ),
                                            );
                                          }
                                        },
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
          ),
        ),
      ],
    );
  }

  // Dentro de _PanelPrincipalState en panel_principal.dart
  Widget _buildInventarioTabContent(int sacoDisp, int bolsaDisp) {
    return StreamBuilder<List<Pedido>>(
      stream: _dbService.streamPedidos(filtroEstado: "Pendiente"),
      builder: (context, pedidoSnap) {
        if (pedidoSnap.hasError) {
          return const Center(child: Text("Error de conexión"));
        }
        if (!pedidoSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            const Divider(),
            comp.ListaPedidosPendientes(
              pedidos: pedidoSnap.data ?? [],
              stockSacoDisp: sacoDisp,
              stockBolsaDisp: bolsaDisp,
            ),
          ],
        );
      },
    );
  }

  Widget _buildCitasTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Agenda de hoy",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.calendar_today),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setState(() => _selectedDate = picked);
                  }
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Cita>>(
            stream: _dbService.streamCitas(_selectedDate),
            builder: (context, snapshot) {
              final citas = snapshot.data ?? [];
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                itemCount: 48, // De 08:00 a 16:00 son 8 horas * 6 slots = 48
                itemBuilder: (context, index) {
                  // Generar slots de 10 min desde 08:00
                  final totalMinutes = 8 * 60 + (index * 10);
                  final hour = totalMinutes ~/ 60;
                  final min = totalMinutes % 60;
                  final slotTime =
                      "${hour.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}";

                  final citaEnSlot = citas.firstWhere(
                    (c) => c.slot == slotTime,
                    orElse: () => Cita(
                      id: '',
                      nombre: '',
                      motivo: '',
                      fecha: DateTime.now(),
                      slot: '',
                    ),
                  );

                  return _buildSlotCard(slotTime, citaEnSlot);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSlotCard(String slotTime, Cita cita) {
    bool ocupado = cita.id.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        leading: Text(
          slotTime,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: ocupado ? Colors.red : Colors.green,
          ),
        ),
        title: Text(ocupado ? cita.nombre : "Disponible"),
        subtitle: ocupado ? Text(cita.motivo) : null,
        trailing: IconButton(
          icon: Icon(ocupado ? Icons.info_outline : Icons.add_circle_outline),
          color: ocupado ? Colors.cyan : Colors.cyan,
          onPressed: () => _mostrarDialogoCita(slotTime, cita),
        ),
      ),
    );
  }

  void _mostrarDialogoCita(String slot, Cita cita) {
    if (cita.id.isNotEmpty) {
      // Mostrar info si ya está ocupado
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text("Cita a las $slot"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Nombre: ${cita.nombre}"),
              const SizedBox(height: 5),
              Text("Motivo: ${cita.motivo}"),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cerrar"),
            ),
          ],
        ),
      );
      return;
    }

    // Si está libre, permitir crear una
    final nameCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Agendar en slot $slot"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: "Nombre"),
            ),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: "Motivo"),
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
              if (nameCtrl.text.isNotEmpty) {
                await _dbService.crearCita(
                  nombre: nameCtrl.text,
                  motivo: reasonCtrl.text,
                  fecha: _selectedDate,
                  slot: slot,
                );
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text("Guardar"),
          ),
        ],
      ),
    );
  }

  // DIALOGO LOGOUT
  void _mostrarConfirmacionLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cerrar Sesión"),
        content: const Text("¿Estás seguro de cerrar la sesión?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              FirebaseAuth.instance.signOut();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              "Sí, cerrar",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfiguracionesTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          "Configuraciones",
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        ListTile(
          leading: const Icon(Icons.person, color: Colors.cyan),
          title: const Text("Perfil"),
          subtitle: const Text("Ver tus datos y cambiar contraseña"),
          tileColor: Theme.of(context).cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => Scaffold(
                  appBar: AppBar(title: const Text("Perfil")),
                  body: _buildPerfilWidget(),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        if (_rolActual == "admin") ...[
          ListTile(
            leading: const Icon(Icons.history_edu, color: Colors.purple),
            title: const Text("Bitácora"),
            subtitle: const Text("Historial de auditoría del sistema"),
            tileColor: Theme.of(context).cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const BitacoraScreen()),
              );
            },
          ),
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.admin_panel_settings, color: Colors.red),
            title: const Text("Panel Admin"),
            subtitle: const Text("Gestión de usuarios y sistema"),
            tileColor: Theme.of(context).cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            onTap: () => _mostrarPanelAdmin(context),
          ),
        ],
      ],
    );
  }

  void _mostrarPanelAdmin(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(25),
          children: [
            const Center(
              child: Text(
                "Panel de Administración",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 40),

            // --- SECCIÓN CLIENTES ---
            _buildAdminActionTile(
              icon: Icons.person_add_alt_1_rounded,
              color: Colors.blue,
              title: "Registrar Nuevo Cliente",
              subtitle: "Añadir a la base de datos de estadísticas",
              onTap: () => _mostrarFormularioCliente(context),
            ),

            // --- SECCIÓN TRABAJADORES ---
            const SizedBox(height: 15),
            _buildAdminActionTile(
              icon: Icons.badge_rounded,
              color: Colors.orange,
              title: "Pre-autorizar Trabajador",
              subtitle: "Permitir registro de nuevos empleados",
              onTap: () => _mostrarFormularioTrabajador(context),
            ),

            const SizedBox(height: 15),
            // --- SECCIÓN ESTADÍSTICAS ---
            _buildAdminActionTile(
              icon: Icons.bar_chart_rounded,
              color: Colors.green,
              title: "Estadísticas de Ventas",
              subtitle: "Ver ingresos y clientes frecuentes",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        _EstadisticasScreen(dbService: _dbService),
                  ),
                );
              },
            ),

            const SizedBox(height: 15),
            // --- SECCIÓN BITÁCORA ---
            _buildAdminActionTile(
              icon: Icons.history_edu_rounded,
              color: Colors.purple,
              title: "Ver Bitácora de Eventos",
              subtitle: "Historial de acciones y auditoría",
              onTap: () {
                Navigator.pop(context); // Cierra el modal de admin
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BitacoraScreen(),
                  ),
                );
              },
            ),

            const SizedBox(height: 15),
            // --- SECCIÓN PRUEBA FCM (Temporal) ---
            _buildAdminActionTile(
              icon: Icons.notification_add_rounded,
              color: Colors.redAccent,
              title: "Probar Notificación Global",
              subtitle: "Verificar conexión FCM V1",
              onTap: () async {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Enviando prueba V1...")),
                );
                await _dbService.enviarNotificacionGlobal(
                  "¡Conexión Exitosa!",
                  "El sistema de notificaciones V1 está activo",
                );
              },
            ),

            const SizedBox(height: 40),
            const Text(
              "⚠️ Nota de Seguridad",
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const Text(
              "Las acciones realizadas aquí son registradas automáticamente en la bitácora del sistema para auditoría.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminActionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
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
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  void _mostrarFormularioCliente(BuildContext context) {
    final nomCtrl = TextEditingController();
    final apeCtrl = TextEditingController();
    final cedCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Nuevo Cliente"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nomCtrl,
              decoration: const InputDecoration(labelText: "Nombre"),
            ),
            TextField(
              controller: apeCtrl,
              decoration: const InputDecoration(labelText: "Apellido"),
            ),
            TextField(
              controller: cedCtrl,
              decoration: const InputDecoration(
                labelText: "Cédula",
                prefixText: "V-",
              ),
              keyboardType: TextInputType.number,
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
              if (nomCtrl.text.isNotEmpty &&
                  apeCtrl.text.isNotEmpty &&
                  cedCtrl.text.isNotEmpty) {
                await _dbService.registrarCliente(
                  nombre: nomCtrl.text.trim(),
                  apellido: apeCtrl.text.trim(),
                  cedula: cedCtrl.text.trim(),
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Cliente registrado con éxito"),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              }
            },
            child: const Text("Registrar"),
          ),
        ],
      ),
    );
  }

  void _mostrarFormularioTrabajador(BuildContext context) {
    final correoCtrl = TextEditingController();
    final nomCtrl = TextEditingController();
    final apeCtrl = TextEditingController();
    String rolSel = "Empleado";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text("Pre-autorizar Trabajador"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Instrucción: El empleado deberá completar su registro desde su propio dispositivo usando este correo.",
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: correoCtrl,
                  decoration: const InputDecoration(
                    labelText: "Correo Electrónico",
                  ),
                ),
                TextField(
                  controller: nomCtrl,
                  decoration: const InputDecoration(labelText: "Nombre"),
                ),
                TextField(
                  controller: apeCtrl,
                  decoration: const InputDecoration(labelText: "Apellido"),
                ),
                DropdownButtonFormField<String>(
                  initialValue: rolSel,
                  items: ["Empleado", "admin"]
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setState(() => rolSel = v!),
                  decoration: const InputDecoration(labelText: "Rol asignado"),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: () async {
                if (correoCtrl.text.contains('@')) {
                  await _dbService.preAutorizarTrabajador(
                    correo: correoCtrl.text.trim(),
                    nombre: nomCtrl.text.trim(),
                    apellido: apeCtrl.text.trim(),
                    rol: rolSel,
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Correo pre-autorizado. Listo para registro.",
                        ),
                        backgroundColor: Colors.blue,
                      ),
                    );
                  }
                }
              },
              child: const Text("Autorizar"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerfilWidget() {
    final User? userAuth = FirebaseAuth.instance.currentUser;
    if (userAuth == null) {
      return const Center(child: Text("No hay sesión activa"));
    }
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('Trabajadores')
          .doc(userAuth.uid)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text("Error: ${snapshot.error}"));
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(
            child: Text("No se encontraron tus datos en la base."),
          );
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
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: () async {
                  try {
                    await FirebaseAuth.instance.sendPasswordResetEmail(
                      email: userAuth.email!,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Correo de restablecimiento enviado"),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Error: $e"),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.lock_reset_rounded),
                label: const Text("Cambiar Contraseña"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan[600],
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
              const SizedBox(height: 30),
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
    final TextEditingController ticketController = TextEditingController(
      text: pedido?.ticket ?? "",
    );
    final TextEditingController montoController = TextEditingController(
      text: pedido?.monto.toString() ?? "",
    );

    // Controladores de cantidad (comportamiento bancario/numérico)
    final TextEditingController cantSacoCont = TextEditingController(text: "1");
    final TextEditingController cantBolsaCont = TextEditingController(
      text: "1",
    );

    String ordenSeleccionada = "Saco"; // Saco, Bolsa, Mixto
    String? subTipoSaco = "Saco Público";
    String? subTipoBolsa = "Bolsa Público";
    String? idClienteSeleccionado;
    String nombreClienteLabel = "Seleccionar Cliente (Opcional)";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        // Para actualizar el diálogo internamente
        builder: (context, setState) => AlertDialog(
          title: Text(pedido == null ? "Nuevo Pedido" : "Editar Pedido"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // --- SELECCIÓN DE CLIENTE ---
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.cyan.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.cyan.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.person_search,
                            color: Colors.cyan,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              nombreClienteLabel,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 40,
                        child: StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('Clientes')
                              .snapshots(),
                          builder: (context, snap) {
                            if (!snap.hasData) {
                              return const LinearProgressIndicator();
                            }
                            final clientes = snap.data!.docs;
                            return DropdownButton<String>(
                              isExpanded: true,
                              hint: const Text(
                                "Elegir cliente",
                                style: TextStyle(fontSize: 12),
                              ),
                              underline: const SizedBox(),
                              items: clientes.map((c) {
                                final d = c.data() as Map<String, dynamic>;
                                return DropdownMenuItem(
                                  value: c.id,
                                  child: Text(
                                    "${d['Nombre']} ${d['Apellido']}",
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                final clienteDoc = clientes.firstWhere(
                                  (c) => c.id == val,
                                );
                                final d =
                                    clienteDoc.data() as Map<String, dynamic>;
                                setState(() {
                                  idClienteSeleccionado = val;
                                  nombreClienteLabel =
                                      "Cliente: ${d['Nombre']} ${d['Apellido']}";
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: ticketController,
                  decoration: const InputDecoration(
                    labelText: "N° Ticket (Referencia)",
                  ),
                ),
                const SizedBox(height: 10),
                // --- SELECCIÓN DE ORDEN ---
                DropdownButtonFormField<String>(
                  initialValue: ordenSeleccionada,
                  decoration: const InputDecoration(labelText: "Orden"),
                  items: ["Saco", "Bolsa", "Mixto"]
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (val) => setState(() => ordenSeleccionada = val!),
                ),

                // --- SECCIÓN DINÁMICA: SACO ---
                if (ordenSeleccionada == "Saco" ||
                    ordenSeleccionada == "Mixto") ...[
                  const Divider(),
                  DropdownButtonFormField<String>(
                    initialValue: subTipoSaco,
                    decoration: const InputDecoration(
                      labelText: "Tipo de Hielo (Saco)",
                    ),
                    items: ["Saco Pescador", "Saco Público", "Donación"]
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (val) => setState(() => subTipoSaco = val),
                  ),
                  TextField(
                    controller: cantSacoCont,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Cantidad de Sacos",
                    ),
                  ),
                ],

                // --- SECCIÓN DINÁMICA: BOLSA ---
                if (ordenSeleccionada == "Bolsa" ||
                    ordenSeleccionada == "Mixto") ...[
                  const Divider(),
                  DropdownButtonFormField<String>(
                    initialValue: subTipoBolsa,
                    decoration: const InputDecoration(
                      labelText: "Tipo de Hielo (Bolsa)",
                    ),
                    items: ["Bolsa Público", "Bolsa a Mayor", "Donación"]
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (val) => setState(() => subTipoBolsa = val),
                  ),
                  TextField(
                    controller: cantBolsaCont,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Cantidad de Bolsas",
                    ),
                  ),
                ],

                const Divider(),
                TextField(
                  controller: montoController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: "Monto Total (Bs)",
                    prefixText: "Bs. ",
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: () async {
                final double monto =
                    double.tryParse(montoController.text) ?? 0.0;
                final int cantSaco = int.tryParse(cantSacoCont.text) ?? 0;
                final int cantBolsa = int.tryParse(cantBolsaCont.text) ?? 0;

                String categoriaFinal = "";
                Map<String, int> mapaDescuento = {};

                if (ordenSeleccionada == "Mixto") {
                  categoriaFinal = "Mixto: $subTipoSaco + $subTipoBolsa";
                  mapaDescuento = {
                    "NZAtCFwTfLTwb3xiiOUk": cantSaco,
                    "DWDbVnRf5nqGu8uTu3KA": cantBolsa,
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
                    'detalle_saco': ordenSeleccionada != "Bolsa"
                        ? subTipoSaco
                        : null,
                    'detalle_bolsa': ordenSeleccionada != "Saco"
                        ? subTipoBolsa
                        : null,
                    'cantidad_saco': cantSaco,
                    'cantidad_bolsa': cantBolsa,
                  },
                };

                await _dbService.crearPedidoYDescontar(
                  categoriaHielo:
                      dataPedido['tipo_hielo']['categoria'], // Usando la variable
                  monto: dataPedido['Monto_total'], // Usando la variable
                  ticket: dataPedido['N_ticket'], // Usando la variable
                  productosYCantidades: mapaDescuento,
                  nombreCreador: dataPedido['creado_por'], // Usando la variable
                  idCliente: idClienteSeleccionado,
                );

                // Como DatabaseService aún no tiene idCliente en la firma de crearPedidoYDescontar (la actualizo ahora)
                // Usaré un update manual por ahora o actualizaremos el servicio. Mejor actualizo el servicio en el siguiente paso.

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Se ha registrado correctamente"),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              child: const Text("Guardar Pedido"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String valor, {String? label}) {
    final bool seleccionado = _filtroEstado == valor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: ChoiceChip(
        label: Text(label ?? valor),
        selected: seleccionado,
        onSelected: (bool selected) {
          if (selected) setState(() => _filtroEstado = valor);
        },
        selectedColor: Colors.cyan,
        backgroundColor: Colors.white,
        labelStyle: TextStyle(
          color: seleccionado ? Colors.white : Colors.blueGrey,
          fontWeight: seleccionado ? FontWeight.bold : FontWeight.normal,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: BorderSide(
            color: seleccionado
                ? Colors.cyan
                : Colors.blueGrey.withValues(alpha: 0.2),
          ),
        ),
        showCheckmark: false,
        elevation: seleccionado ? 4 : 0,
      ),
    );
  }

  Widget _buildBadgeEstado(String estado, [bool sinStock = false]) {
    Color color;
    String texto = estado;

    if (sinStock && estado == 'Pendiente') {
      color = Colors.deepOrange;
      texto = "SIN STOCK";
    } else {
      switch (estado) {
        case 'Pendiente':
          color = Colors.orange;
          break;
        case 'Despachado':
          color = Colors.green;
          break;
        case 'Cancelado':
          color = Colors.red;
          break;
        default:
          color = Colors.grey;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
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
                  child: Container(
                    width: 50,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "Información Completa",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[900],
                  ),
                ),
                const Divider(),
                _filaDetalle(
                  Icons.confirmation_number,
                  "N° Ticket",
                  pedido.ticket,
                ),
                _filaDetalle(Icons.ac_unit, "Tipo de Hielo", pedido.tipoHielo),
                _filaDetalle(
                  Icons.attach_money,
                  "Monto Total",
                  "${pedido.monto} Bs",
                ),
                _filaDetalle(Icons.info, "Estado Actual", pedido.estado),
                _filaDetalle(
                  Icons.person_add,
                  "Creado por",
                  pedido.creadoPor ?? "N/A",
                ),
                _filaDetalle(
                  Icons.local_shipping,
                  "Despachado por",
                  pedido.despachadoPor ?? "Pendiente",
                ),
                _filaDetalle(
                  Icons.calendar_today,
                  "Fecha y Hora",
                  pedido.fecha?.toString() ?? "N/A",
                ),
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
                        _mostrarDialogoNuevoPedido(
                          context,
                          pedido,
                        ); // <--- ESTO ES LO QUE FALTA
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
          Text(
            "$titulo: ",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: Text(valor, style: const TextStyle(color: Colors.black87)),
          ),
        ],
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
  });
  final double minHeight;
  final double maxHeight;
  final Widget child;

  @override
  double get minExtent => minHeight;
  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return maxHeight != oldDelegate.maxHeight ||
        minHeight != oldDelegate.minHeight ||
        child != oldDelegate.child;
  }
}

class _EstadisticasScreen extends StatefulWidget {
  final DatabaseService dbService;
  const _EstadisticasScreen({required this.dbService});

  @override
  State<_EstadisticasScreen> createState() => _EstadisticasScreenState();
}

class _EstadisticasScreenState extends State<_EstadisticasScreen> {
  double _ventasDia = 0;
  double _ventasMes = 0;
  List<BarChartGroupData> _barGroups = [];
  List<Map<String, dynamic>> _topClientes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _cargarEstadisticas();
  }

  Future<void> _cargarEstadisticas() async {
    setState(() => _isLoading = true);
    final ahora = DateTime.now();

    // 1. Ventas del Día
    final inicioDia = DateTime(ahora.year, ahora.month, ahora.day);
    final snapDia = await FirebaseFirestore.instance
        .collection('Pedidos')
        .where('estado', whereIn: ['Despachado', 'Entregado'])
        .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(inicioDia))
        .get();

    double totalDia = 0;
    for (var doc in snapDia.docs) {
      totalDia += (doc.data()['Monto_total'] ?? 0).toDouble();
    }

    // 2. Ventas del Mes
    final inicioMes = DateTime(ahora.year, ahora.month, 1);
    final snapMes = await FirebaseFirestore.instance
        .collection('Pedidos')
        .where('estado', whereIn: ['Despachado', 'Entregado'])
        .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(inicioMes))
        .get();

    double totalMes = 0;
    for (var doc in snapMes.docs) {
      totalMes += (doc.data()['Monto_total'] ?? 0).toDouble();
    }

    // 3. Gráfica 7 días
    List<BarChartGroupData> groups = [];
    for (int i = 6; i >= 0; i--) {
      final diaBusqueda = ahora.subtract(Duration(days: i));
      final inicio = DateTime(
        diaBusqueda.year,
        diaBusqueda.month,
        diaBusqueda.day,
      );
      final fin = inicio.add(const Duration(days: 1));

      final snap = await FirebaseFirestore.instance
          .collection('Pedidos')
          .where('estado', whereIn: ['Despachado', 'Entregado'])
          .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
          .where('fecha', isLessThan: Timestamp.fromDate(fin))
          .get();

      double sumaDia = 0;
      for (var doc in snap.docs) {
        sumaDia += (doc.data()['Monto_total'] ?? 0).toDouble();
      }

      groups.add(
        BarChartGroupData(
          x: 6 - i,
          barRods: [
            BarChartRodData(
              toY: sumaDia,
              color: Colors.cyan,
              width: 15,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
    }

    // 4. Top Clientes (Usando snapMes para una muestra relevante)
    Map<String, int> conteoClientes = {};
    for (var doc in snapMes.docs) {
      final idC = doc.data()['id_cliente'];
      if (idC != null) {
        conteoClientes[idC] = (conteoClientes[idC] ?? 0) + 1;
      }
    }

    List<Map<String, dynamic>> topList = [];
    var sortedEntries = conteoClientes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (var entry in sortedEntries.take(5)) {
      final clientDoc = await FirebaseFirestore.instance
          .collection('Clientes')
          .doc(entry.key)
          .get();
      if (clientDoc.exists) {
        final d = clientDoc.data()!;
        topList.add({
          'nombre': "${d['Nombre']} ${d['Apellido']}",
          'compras': entry.value,
        });
      }
    }

    if (mounted) {
      setState(() {
        _ventasDia = totalDia;
        _ventasMes = totalMes;
        _barGroups = groups;
        _topClientes = topList;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Dashboard de Ventas"),
        actions: [
          IconButton(
            onPressed: _cargarEstadisticas,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        "Hoy",
                        "${_ventasDia.toStringAsFixed(2)} Bs",
                        Colors.green,
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: _buildStatCard(
                        "Mes",
                        "${_ventasMes.toStringAsFixed(2)} Bs",
                        Colors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 25),
                const Text(
                  "Ventas Úitimos 7 Días",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                Container(
                  height: 250,
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: BarChart(
                    BarChartData(
                      barGroups: _barGroups,
                      borderData: FlBorderData(show: false),
                      titlesData: const FlTitlesData(
                        show: true,
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                const Text(
                  "Top 5 Clientes (Mes)",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 15),
                ..._topClientes.map(
                  (c) => Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(c['nombre']),
                      trailing: Text(
                        "${c['compras']} compras",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.cyan,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class BitacoraScreen extends StatelessWidget {
  const BitacoraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Bitácora del Sistema"),
        backgroundColor: Colors.cyan[600],
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('Bitacora')
            .orderBy('fecha', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text("Error al cargar la bitácora"));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final eventos = snapshot.data!.docs;

          if (eventos.isEmpty) {
            return const Center(child: Text("No hay registros en la bitácora"));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(10),
            itemCount: eventos.length,
            separatorBuilder: (context, index) => const Divider(),
            itemBuilder: (context, index) {
              final data = eventos[index].data() as Map<String, dynamic>;
              final DateTime? fecha = (data['fecha'] as Timestamp?)?.toDate();

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.purple.withValues(alpha: 0.1),
                  child: const Icon(Icons.history_edu, color: Colors.purple),
                ),
                title: Text(
                  data['accion'] ?? 'Sin acción',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data['detalle'] ?? 'Sin detalle'),
                    const SizedBox(height: 4),
                    Text(
                      "Usuario: ${data['usuario'] ?? 'Sistema'}",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
                trailing: Text(
                  fecha != null
                      ? "${fecha.day}/${fecha.month}/${fecha.year}\n${fecha.hour}:${fecha.minute.toString().padLeft(2, '0')}"
                      : '--:--',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                isThreeLine: true,
              );
            },
          );
        },
      ),
    );
  }
}
