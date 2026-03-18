import 'package:flutter/material.dart';
import 'theme.dart';
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
  final bool esInvitado;
  const PanelPrincipal({
    super.key,
    required this.onToggleTheme,
    this.esInvitado = false,
  });

  @override
  State<PanelPrincipal> createState() => _PanelPrincipalState();
}

class _PanelPrincipalState extends State<PanelPrincipal> {
  final DatabaseService _dbService = DatabaseService();
  String _filtroTicket = "";
  String _filtroEstado = "Todos";
  DateTime _selectedDate = DateTime.now();

  late Stream<QuerySnapshot> _productosStream;
  late Future<DocumentSnapshot?> _userFuture;

  // Método de obtención de datos basado exclusivamente en el correo
  Future<DocumentSnapshot?> _obtenerPerfilPorEmail(String email) async {
    try {
      // Consulta obligatoria por campo 'correo' ya que los IDs son aleatorios
      final query = await FirebaseFirestore.instance
          .collection('Trabajadores')
          .where('correo', isEqualTo: email)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) return query.docs.first;
      return null;
    } catch (e) {
      debugPrint("Error crítico en _obtenerPerfilPorEmail: $e");
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    final userAuth = FirebaseAuth.instance.currentUser;
    // Iniciamos la carga basada en email como llave única
    if (userAuth != null && userAuth.email != null) {
      _userFuture = _obtenerPerfilPorEmail(userAuth.email!);
    } else {
      _userFuture = Future.value(null);
    }

    _productosStream = FirebaseFirestore.instance
        .collection('Productos')
        .snapshots();
  }

  // Ya no usamos variables de estado para el nombre y el rol,
  // sino que los obtenemos directamente del StreamBuilder en el build.

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot?>(
      future: _userFuture,
      builder: (context, userSnap) {
        if (widget.esInvitado) {
          final Map<String, dynamic> guestData = {
            'nombre': 'Invitado',
            'apellido': '',
            'rol': 'Invitado',
            'usuario': 'invitado',
            'correo': 'public@frifalca.com',
          };
          return _buildAdaptiveLayout("Invitado", "Invitado", guestData);
        }

        if (userSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (userSnap.hasError || !userSnap.hasData || userSnap.data == null) {
          return const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(30.0),
                child: Text(
                  "El correo no tiene un perfil asociado en la base de datos.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          );
        }

        final userData = userSnap.data!.data() as Map<String, dynamic>;
        final String nombreCompleto =
            "${userData['nombre'] ?? 'Sin nombre'} ${userData['apellido'] ?? ''}"
                .trim();
        final String rolActual = userData['rol'] ?? "Empleado";

        return _buildAdaptiveLayout(nombreCompleto, rolActual, userData);
      },
    );
  }

  Widget _buildAdaptiveLayout(
    String nombreCompleto,
    String rolActual,
    Map<String, dynamic> userData,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 800;
        return DefaultTabController(
          length: widget.esInvitado ? 1 : 4,
          child: StreamBuilder<QuerySnapshot>(
            stream: _productosStream,
            builder: (context, prodSnap) {
              // --- Cálculo de Stocks ---
              int sacoFisico = 0, sacoComp = 0, bolsaFisico = 0, bolsaComp = 0;
              if (prodSnap.hasData) {
                for (var doc in prodSnap.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (doc.id == "NZAtCFwTfLTwb3xiiOUk") {
                    sacoFisico = (data['stock_fisico'] as num? ?? 0).toInt();
                    sacoComp = (data['stock_comprometido'] as num? ?? 0)
                        .toInt();
                  }
                  if (doc.id == "DWDbVnRf5nqGu8uTu3KA") {
                    bolsaFisico = (data['stock_fisico'] as num? ?? 0).toInt();
                    bolsaComp = (data['stock_comprometido'] as num? ?? 0)
                        .toInt();
                  }
                }
              }

              // --- AUDITORÍA DE STOCK ---
              if (prodSnap.hasData) {
                debugPrint("--- AUDITORÍA DE INVENTARIO (PanelPrincipal) ---");
                debugPrint(
                  "DEBUG: Estado del Stream Productos: ${prodSnap.connectionState}",
                );
                debugPrint(
                  "DEBUG: Cantidad de documentos recibidos: ${prodSnap.data?.docs.length ?? 0}",
                );

                if (prodSnap.data!.docs.isNotEmpty) {
                  debugPrint(
                    "DEBUG: Ejemplo de primer doc (Productos): ${prodSnap.data?.docs.first.data()}",
                  );
                  for (var doc in prodSnap.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final String nombreProd = doc.id == "NZAtCFwTfLTwb3xiiOUk"
                        ? "SACO"
                        : "BOLSA";
                    final int fisico = (data['stock_fisico'] as num? ?? 0)
                        .toInt();
                    final int compField =
                        (data['stock_comprometido'] as num? ?? 0).toInt();
                    debugPrint(
                      "Producto: $nombreProd | Físico Firebase: $fisico | Comprometido Firebase: $compField | Disponible Calc: ${fisico - compField}",
                    );
                  }
                } else {
                  debugPrint(
                    "DEBUG: No se encontraron documentos en la colección 'Productos'",
                  );
                }
                debugPrint("-----------------------------------------------");
              } else if (prodSnap.hasError) {
                debugPrint(
                  "DEBUG: Error en Stream Productos: ${prodSnap.error}",
                );
              } else {
                debugPrint(
                  "DEBUG: Esperando datos de Productos (Estado: ${prodSnap.connectionState})",
                );
              }

              if (isDesktop) {
                return _EscritorioView(
                  nombreCompleto: nombreCompleto,
                  rolActual: rolActual,
                  userData: userData,
                  sacoFisico: sacoFisico,
                  sacoComp: sacoComp,
                  bolsaFisico: bolsaFisico,
                  bolsaComp: bolsaComp,
                  esInvitado: widget.esInvitado,
                  onToggleTheme: widget.onToggleTheme,
                  parent: this,
                );
              } else {
                return _MovilView(
                  nombreCompleto: nombreCompleto,
                  rolActual: rolActual,
                  userData: userData,
                  sacoFisico: sacoFisico,
                  sacoComp: sacoComp,
                  bolsaFisico: bolsaFisico,
                  bolsaComp: bolsaComp,
                  esInvitado: widget.esInvitado,
                  onToggleTheme: widget.onToggleTheme,
                  parent: this,
                );
              }
            },
          ),
        );
      },
    );
  }

  // --- WIDGETS DE NIVEL DE VISTA ---

  Widget _buildMainContent({
    required String nombreCompleto,
    required String rolActual,
    required int sacoFisico,
    required int sacoComp,
    required int bolsaFisico,
    required int bolsaComp,
    required Map<String, dynamic> userData,
    bool showHeader = true,
  }) {
    final int sacoDisp = (sacoFisico - sacoComp).clamp(0, 999999);
    final int bolsaDisp = (bolsaFisico - bolsaComp).clamp(0, 999999);
    bool hayAlertaProd = (sacoDisp <= 0 && bolsaDisp <= 0);
    bool hayAlertaStock = (sacoDisp <= 0 || bolsaDisp <= 0);
    double totalHeight =
        (hayAlertaStock ? 320 : 260) + (hayAlertaProd ? 80 : 0);

    return Scrollbar(
      thumbVisibility: true,
      trackVisibility: true,
      child: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            if (showHeader) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 25, 20, 15),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Image.asset('assets/frifalca6.png', height: 40),
                      Text(
                        "Frifalca C.A.",
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: AppColors.secondary,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Row(
                        children: [
                          _buildHeaderButton(
                            icon:
                                Theme.of(context).brightness == Brightness.dark
                                ? Icons.light_mode
                                : Icons.dark_mode,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.yellow
                                : AppColors.primary,
                            onPressed: widget.onToggleTheme,
                          ),
                          _buildHeaderButton(
                            icon: Icons.logout_rounded,
                            color: AppColors.error,
                            onPressed: () =>
                                _mostrarConfirmacionLogout(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildGreetingCard(nombreCompleto),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 25)),
            ],
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverAppBarDelegate(
                minHeight: totalHeight,
                maxHeight: totalHeight,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Column(
                    children: [
                      if (hayAlertaProd) _buildAlertaProduccion(),
                      comp.InventarioResumenCard(
                        sacoFisico: sacoFisico,
                        sacoComp: sacoComp,
                        bolsaFisico: bolsaFisico,
                        bolsaComp: bolsaComp,
                        readOnly: widget.esInvitado,
                        onAjustar: (id, cantidad) => _procesarAjusteInventario(
                          id,
                          cantidad,
                          nombreCompleto,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ];
        },
        body: TabBarView(
          physics: widget.esInvitado
              ? const NeverScrollableScrollPhysics()
              : null,
          children: [
            _buildInventarioTabContent(
              sacoDisp,
              bolsaDisp,
              nombreCompleto,
              rolActual,
            ),
            if (!widget.esInvitado) ...[
              _buildPedidosTab(rolActual, nombreCompleto),
              _buildCitasTab(),
              _buildConfiguracionesTab(rolActual, userData),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _procesarAjusteInventario(
    String id,
    int cantidad,
    String autor,
  ) async {
    try {
      await _dbService.ajustarStock(id, cantidad, autor);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Inventario actualizado por $autor"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildNavigationRail(BuildContext railContext, String nombreCompleto) {
    final controller = DefaultTabController.of(railContext);
    return NavigationRail(
      selectedIndex: controller.index,
      onDestinationSelected: (int index) {
        setState(() {
          controller.animateTo(index);
        });
      },
      leading: Column(
        children: [
          const SizedBox(height: 20),
          Image.asset('assets/frifalca6.png', height: 40),
          const SizedBox(height: 30),
          FloatingActionButton(
            mini: true,
            elevation: 0,
            backgroundColor: AppColors.secondary,
            onPressed: () =>
                _mostrarDialogoNuevoPedido(context, nombreCompleto),
            child: const Icon(Icons.add, color: Colors.white),
          ),
          const SizedBox(height: 10),
        ],
      ),
      backgroundColor: AppColors.primary,
      indicatorColor: AppColors.secondary.withValues(alpha: 0.2),
      selectedIconTheme: const IconThemeData(color: AppColors.secondary),
      unselectedIconTheme: const IconThemeData(color: Colors.white54),
      selectedLabelTextStyle: const TextStyle(color: AppColors.secondary),
      unselectedLabelTextStyle: const TextStyle(color: Colors.white54),
      labelType: NavigationRailLabelType.all,
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.grid_view_rounded),
          label: Text("Panel"),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.receipt_long_rounded),
          label: Text("Pedidos"),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.calendar_month_rounded),
          label: Text("Citas"),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.settings_suggest_rounded),
          label: Text("Config"),
        ),
      ],
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

  Widget _buildDrawer(
    BuildContext context,
    String nombreCompleto,
    String rolActual,
  ) {
    return Drawer(
      backgroundColor: AppColors.primary,
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: AppColors.primary),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/frifalca6.png', height: 60),
                const SizedBox(height: 10),
                const Text(
                  "Frifalca C.A.",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          _buildDrawerItem(
            context,
            icon: Icons.grid_view_rounded,
            label: "Panel Principal",
            index: 0,
          ),
          _buildDrawerItem(
            context,
            icon: Icons.receipt_long_rounded,
            label: "Pedidos",
            index: 1,
          ),
          _buildDrawerItem(
            context,
            icon: Icons.calendar_month_rounded,
            label: "Citas",
            index: 2,
          ),
          _buildDrawerItem(
            context,
            icon: Icons.settings_rounded,
            label: "Configuración",
            index: 3,
          ),
          const Divider(color: Colors.white24, indent: 20, endIndent: 20),
          ListTile(
            leading: const Icon(
              Icons.add_circle_outline,
              color: AppColors.secondary,
            ),
            title: const Text(
              "Añadir Pedido",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            onTap: () {
              Navigator.pop(context); // Cierra drawer
              _mostrarDialogoNuevoPedido(context, nombreCompleto);
            },
          ),
          const Spacer(),
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.error),
            title: const Text(
              "Cerrar Sesión",
              style: TextStyle(color: Colors.white),
            ),
            onTap: () => _mostrarConfirmacionLogout(context),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int index,
  }) {
    final controller = DefaultTabController.of(context);
    bool selected = controller.index == index;
    return ListTile(
      leading: Icon(
        icon,
        color: selected ? AppColors.secondary : Colors.white70,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? AppColors.secondary : Colors.white70,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      onTap: () {
        controller.animateTo(index);
        Navigator.pop(context);
      },
    );
  }

  Widget _buildGreetingCard(String nombre) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      // ... resto del widget sin cambios significativos en UI
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
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[400]
                  : Colors.grey[600],
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            "¡Buen día, ${nombre.split(' ')[0]}!",
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
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
      margin: const EdgeInsets.only(bottom: 20),
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

  Widget _buildBottomNav(BuildContext context) {
    final controller = DefaultTabController.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return BottomAppBar(
          shape: const CircularNotchedRectangle(),
          notchMargin: 8.0,
          color: Theme.of(context).cardColor,
          elevation: 10,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMobileNavItem(
                context,
                index: 0,
                icon: Icons.grid_view_rounded,
                label: "Panel",
                selected: controller.index == 0,
              ),
              _buildMobileNavItem(
                context,
                index: 1,
                icon: Icons.receipt_long_rounded,
                label: "Pedidos",
                selected: controller.index == 1,
              ),
              const SizedBox(width: 40), // Espacio para el FAB central
              _buildMobileNavItem(
                context,
                index: 2,
                icon: Icons.calendar_month_rounded,
                label: "Citas",
                selected: controller.index == 2,
              ),
              _buildMobileNavItem(
                context,
                index: 3,
                icon: Icons.settings_rounded,
                label: "Config",
                selected: controller.index == 3,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMobileNavItem(
    BuildContext context, {
    required int index,
    required IconData icon,
    required String label,
    required bool selected,
  }) {
    return Expanded(
      child: InkWell(
        onTap: () {
          DefaultTabController.of(context).animateTo(index);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: selected ? AppColors.secondary : Colors.blueGrey,
              size: 24,
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: selected ? AppColors.secondary : Colors.blueGrey,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPedidosTab(String rolActual, String nombreCompleto) {
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
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: AppColors.secondary,
                ),
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
              debugPrint(
                "DEBUG: Stream Pedidos - Estado: ${snapshot.connectionState}",
              );
              debugPrint(
                "DEBUG: Stream Pedidos - Cantidad: ${snapshot.data?.length ?? 0}",
              );
              debugPrint(
                "DEBUG: Filtros actuales - Estado: $_filtroEstado, Ticket: $_filtroTicket",
              );

              if (snapshot.hasError) {
                debugPrint("DEBUG: Erro en Stream Pedidos: ${snapshot.error}");
                return Center(child: Text("Error: ${snapshot.error}"));
              }

              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final pedidos = snapshot.data!;
              if (pedidos.isEmpty) {
                return const Center(
                  child: Text(
                    "No se encontraron pedidos con estos filtros.",
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }

              return Scrollbar(
                thumbVisibility: true,
                controller: ScrollController(),
                child: ListView.builder(
                  padding: const EdgeInsets.all(15),
                  itemCount: pedidos.length,
                  shrinkWrap: true,
                  physics:
                      const ClampingScrollPhysics(), // Cambiado para mejor integración
                  itemBuilder: (context, index) {
                    final pedido = pedidos[index];
                    return comp.PedidoCard(
                      pedido: pedido,
                      onTap: () => _mostrarDetalleCompleto(
                        context,
                        pedido,
                        rolActual,
                        nombreCompleto,
                      ),
                      trailingActions: pedido.estado == 'Pendiente'
                          ? Row(
                              children: [
                                if (rolActual == "admin")
                                  IconButton(
                                    icon: const Icon(
                                      Icons.cancel_outlined,
                                      color: Colors.red,
                                    ),
                                    onPressed: () => _confirmarAccion(
                                      context: context,
                                      titulo: "Cancelar Pedido",
                                      mensaje:
                                          "¿Seguro que quieres cancelar el ticket ${pedido.ticket}?",
                                      colorBoton: Colors.red,
                                      textoBoton: "Sí, cancelar",
                                      onConfirm: () async {
                                        await _dbService.cancelarPedido(
                                          pedido.id,
                                          cantSaco: pedido.cantSaco,
                                          cantBolsa: pedido.cantBolsa,
                                        );
                                        _notificarExito(
                                          "Pedido #${pedido.ticket} cancelado",
                                        );
                                      },
                                    ),
                                  ),
                                const SizedBox(width: 4),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green[50],
                                    foregroundColor: Colors.green,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    minimumSize: const Size(0, 32),
                                  ),
                                  onPressed: () => _confirmarAccion(
                                    context: context,
                                    titulo: "Despachar Pedido",
                                    mensaje:
                                        "¿Confirmas el despacho del ticket ${pedido.ticket}?",
                                    colorBoton: Colors.green,
                                    textoBoton: "Confirmar Despacho",
                                    onConfirm: () async {
                                      await _dbService.despacharPedido(
                                        pedido.id,
                                        nombreCompleto,
                                        cantSaco: pedido.cantSaco,
                                        cantBolsa: pedido.cantBolsa,
                                      );
                                      _notificarExito(
                                        "Pedido #${pedido.ticket} despachado con éxito",
                                      );
                                    },
                                  ),
                                  child: const Text(
                                    "Despachar",
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            )
                          : null,
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Dentro de _PanelPrincipalState en panel_principal.dart
  Widget _buildInventarioTabContent(
    int sacoDisp,
    int bolsaDisp,
    String nombreCompleto,
    String rolActual,
  ) {
    return StreamBuilder<List<Pedido>>(
      stream: _dbService.streamPedidos(filtroEstado: "Pendiente"),
      builder: (context, pedidoSnap) {
        if (pedidoSnap.hasError) {
          return const Center(child: Text("Error de conexión"));
        }
        if (!pedidoSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final bool isDesktop = MediaQuery.of(context).size.width > 800;
        return Scrollbar(
          thumbVisibility: true,
          controller:
              ScrollController(), // Evita conflictos con el Scrollbar principal
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, isDesktop ? 10 : 20, 20, 20),
            children: [
              if (!isDesktop) const Divider(),
              comp.ListaPedidosPendientes(
                pedidos: pedidoSnap.data ?? [],
                stockSacoDisp: sacoDisp,
                stockBolsaDisp: bolsaDisp,
                onDespachar: (pedido) {
                  _confirmarAccion(
                    context: context,
                    titulo: "Despachar Ahora",
                    mensaje:
                        "¿Confirmas el despacho rápido del ticket ${pedido.ticket}?",
                    colorBoton: Colors.green,
                    textoBoton: "Sí, despachar",
                    onConfirm: () async {
                      await _dbService.despacharPedido(
                        pedido.id,
                        nombreCompleto,
                        cantSaco: pedido.cantSaco,
                        cantBolsa: pedido.cantBolsa,
                      );
                      _notificarExito("Pedido #${pedido.ticket} despachado!");
                    },
                  );
                },
                onShowDetails: (pedido) => _mostrarDetalleCompleto(
                  context,
                  pedido,
                  rolActual,
                  nombreCompleto,
                ),
              ),
            ],
          ),
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
              return Scrollbar(
                thumbVisibility: true,
                child: ListView.builder(
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
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSlotCard(String slotTime, Cita cita) {
    bool ocupado = cita.id.isNotEmpty;

    // Parseo seguro de color hex
    Color colorEtiqueta = Colors.green; // Por defecto disponible
    if (ocupado) {
      try {
        colorEtiqueta = Color(
          int.parse(cita.colorEtiqueta.replaceAll('#', '0xff')),
        );
      } catch (e) {
        colorEtiqueta = Colors.orange;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        leading: Container(
          width: 60,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: colorEtiqueta.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorEtiqueta.withValues(alpha: 0.5)),
          ),
          child: Text(
            slotTime,
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, color: colorEtiqueta),
          ),
        ),
        title: Text(
          ocupado ? (cita.nombreCliente ?? cita.nombre) : "Disponible",
          style: TextStyle(
            fontWeight: ocupado ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: ocupado ? Text(cita.motivo) : const Text("Espacio libre"),
        trailing: IconButton(
          icon: Icon(
            ocupado
                ? (cita.estadoAgendado
                      ? Icons.check_circle
                      : Icons.pending_actions)
                : Icons.add_circle_outline,
          ),
          color: ocupado ? colorEtiqueta : Colors.cyan,
          onPressed: () => _mostrarDialogoCita(slotTime, cita),
        ),
      ),
    );
  }

  void _mostrarDialogoCita(String slot, Cita cita) {
    if (cita.id.isNotEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text("Pedido Agendado - $slot"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Cliente: ${cita.nombreCliente ?? cita.nombre}",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              Text("Nota: ${cita.motivo}"),
              const SizedBox(height: 5),
              Text(
                "Estado: ${cita.estadoAgendado ? 'Completado (Buscado)' : 'Pendiente (Por buscar)'}",
              ),
            ],
          ),
          actions: [
            if (!cita.estadoAgendado)
              ElevatedButton(
                onPressed: () async {
                  await _dbService.actualizarEstadoAgendado(cita.id, true);
                  if (context.mounted) Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text(
                  "Marcar como Buscado",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cerrar"),
            ),
          ],
        ),
      );
      return;
    }

    // --- FORMULARIO PARA AGENDAR ---
    String? idPedidoSel;
    String? idClienteSel;
    String? nombreClienteSel;
    final motivoCtrl = TextEditingController(text: "Retiro de pedido");

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text("Agendar Retiro ($slot)"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Selecciona un pedido pendiente:",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('Pedidos')
                    .where('estado', isEqualTo: 'Pendiente')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const LinearProgressIndicator();
                  final pedidos = snapshot.data!.docs;
                  return DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: idPedidoSel,
                    hint: const Text("Elegir Pedido"),
                    items: pedidos.map((p) {
                      final d = p.data() as Map<String, dynamic>;
                      return DropdownMenuItem(
                        value: p.id,
                        child: Text(
                          "Ticket: ${d['N_ticket']} (${d['tipo_hielo']?['categoria']})",
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) async {
                      final pDoc = pedidos.firstWhere((p) => p.id == val);
                      final pData = pDoc.data() as Map<String, dynamic>;
                      final String? idC = pData['id_cliente'];

                      String nC = "Cliente Genérico";
                      if (idC != null) {
                        final cDoc = await FirebaseFirestore.instance
                            .collection('Clientes')
                            .doc(idC)
                            .get();
                        if (cDoc.exists) {
                          final cData = cDoc.data()!;
                          nC = "${cData['Nombre']} ${cData['Apellido']}";
                        }
                      }

                      setModalState(() {
                        idPedidoSel = val;
                        idClienteSel = idC;
                        nombreClienteSel = nC;
                      });
                    },
                  );
                },
              ),
              if (nombreClienteSel != null) ...[
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person, color: Colors.green, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Cliente: $nombreClienteSel",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 15),
              TextField(
                controller: motivoCtrl,
                decoration: const InputDecoration(labelText: "Nota opcional"),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: idPedidoSel == null
                  ? null
                  : () async {
                      await _dbService.crearCita(
                        nombre: nombreClienteSel ?? "Cliente",
                        motivo: motivoCtrl.text,
                        fecha: _selectedDate,
                        slot: slot,
                        idPedido: idPedidoSel,
                        idCliente: idClienteSel,
                        nombreCliente: nombreClienteSel,
                      );
                      if (context.mounted) Navigator.pop(context);
                    },
              child: const Text("Confirmar Agenda"),
            ),
          ],
        ),
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

  Widget _buildConfiguracionesTab(
    String rolActual,
    Map<String, dynamic> userData,
  ) {
    return Scrollbar(
      thumbVisibility: true,
      child: ListView(
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
                    body: _buildPerfilWidget(userData),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          if (rolActual == "admin") ...[
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
                  MaterialPageRoute(
                    builder: (context) => const BitacoraScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(
                Icons.admin_panel_settings,
                color: Colors.red,
              ),
              title: const Text("Panel Admin"),
              subtitle: const Text("Gestión de usuarios y sistema"),
              tileColor: Theme.of(context).cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              onTap: () => _mostrarPanelAdmin(context, rolActual),
            ),
          ],
        ],
      ),
    );
  }

  void _mostrarPanelAdmin(BuildContext context, String rolActual) {
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

            if (rolActual == "admin") ...[
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
            ],

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

  Widget _buildPerfilWidget(Map<String, dynamic> data) {
    final User? userAuth = FirebaseAuth.instance.currentUser;
    if (userAuth == null) {
      return const Center(child: Text("No hay sesión activa"));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Icon(Icons.account_circle, size: 100, color: Colors.blueGrey),
          const SizedBox(height: 20),
          _infoCard("Usuario", data['usuario'] ?? 'No disponible'),
          _infoCard("Nombre", data['nombre'] ?? 'No disponible'),
          _infoCard("Apellido", data['apellido'] ?? 'No disponible'),
          _infoCard("Rol", data['rol'] ?? 'No disponible'),
          _infoCard("Correo", data['correo'] ?? 'No disponible'),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: () async {
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              try {
                await FirebaseAuth.instance.sendPasswordResetEmail(
                  email: userAuth.email!,
                );
                if (mounted) {
                  navigator.pop();
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content: Text("Correo de restablecimiento enviado"),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  scaffoldMessenger.showSnackBar(
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
              backgroundColor: AppColors.secondary,
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

  void _mostrarDialogoNuevoPedido(
    BuildContext context,
    String nombreCompleto, [
    Pedido? pedido,
  ]) {
    final TextEditingController ticketController = TextEditingController(
      text: pedido?.ticket ?? "",
    );
    final TextEditingController montoController = TextEditingController(
      text: pedido?.monto.toString() ?? "",
    );

    // Controladores de cantidad (comportamiento bancario/numérico)
    final TextEditingController cantSacoCont = TextEditingController(
      text: pedido != null ? pedido.cantSaco.toString() : "1",
    );
    final TextEditingController cantBolsaCont = TextEditingController(
      text: pedido != null ? pedido.cantBolsa.toString() : "1",
    );

    String ordenSeleccionada = pedido?.orden ?? "Saco"; // Saco, Bolsa, Mixto
    String? subTipoSaco = pedido?.detalleSaco ?? "Saco Público";
    String? subTipoBolsa = pedido?.detalleBolsa ?? "Bolsa Público";
    String? idClienteSeleccionado = pedido?.idCliente;
    String nombreClienteLabel = idClienteSeleccionado != null
        ? "Cargando cliente..."
        : "Seleccionar Cliente (Opcional)";

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
                              value: idClienteSeleccionado,
                              hint: const Text(
                                "Elegir cliente",
                                style: TextStyle(fontSize: 12),
                              ),
                              underline: const SizedBox(),
                              items: clientes.map((c) {
                                final d = c.data() as Map<String, dynamic>;
                                if (c.id == idClienteSeleccionado &&
                                    nombreClienteLabel ==
                                        "Cargando cliente...") {
                                  // Actualizamos la etiqueta del cliente si ya está cargado
                                  // Nota: Esto ocurre durante el build, pero setState disparará otro build seguro.
                                  Future.microtask(() {
                                    if (context.mounted) {
                                      setState(() {
                                        nombreClienteLabel =
                                            "Cliente: ${d['Nombre']} ${d['Apellido']}";
                                      });
                                    }
                                  });
                                }
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

                if (pedido == null) {
                  await _dbService.crearPedidoYDescontar(
                    categoriaHielo: categoriaFinal,
                    monto: monto,
                    ticket: ticketController.text,
                    productosYCantidades: mapaDescuento,
                    nombreCreador: nombreCompleto,
                    idCliente: idClienteSeleccionado,
                  );
                } else {
                  await _dbService.actualizarPedido(
                    id: pedido.id,
                    categoriaHielo: categoriaFinal,
                    monto: monto,
                    ticket: ticketController.text,
                    productosYCantidades: mapaDescuento,
                    nombreCreador: nombreCompleto,
                    idCliente: idClienteSeleccionado,
                    cantPrevia: {
                      "NZAtCFwTfLTwb3xiiOUk": pedido.cantSaco,
                      "DWDbVnRf5nqGu8uTu3KA": pedido.cantBolsa,
                    },
                  );
                }

                if (context.mounted) {
                  Navigator.pop(context);
                  _notificarExito(
                    "Pedido #${ticketController.text} guardado correctamente",
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
        selectedColor: AppColors.secondary,
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

  // MÉTODO PARA NOTIFICACIONES FLOTANTES EN LA PARTE SUPERIOR
  void _notificarExito(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                mensaje,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 3),
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 140,
          left: 20,
          right: 20,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        elevation: 8,
      ),
    );
  }

  void _confirmarAccion({
    required BuildContext context,
    required String titulo,
    required String mensaje,
    required Color colorBoton,
    required String textoBoton,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo, style: const TextStyle(color: AppColors.primary)),
        content: Text(mensaje),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Atrás"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colorBoton,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              textoBoton,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarDetalleCompleto(
    BuildContext context,
    Pedido pedido,
    String rolActual,
    String nombreCompleto,
  ) {
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
                if (rolActual == "admin")
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
                          nombreCompleto,
                          pedido,
                        );
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
              color: AppColors.secondary,
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
                          color: AppColors.secondary,
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

class BitacoraScreen extends StatefulWidget {
  const BitacoraScreen({super.key});

  @override
  State<BitacoraScreen> createState() => _BitacoraScreenState();
}

class _BitacoraScreenState extends State<BitacoraScreen> {
  final DatabaseService _dbService = DatabaseService();
  String? _filtroNombre;
  String? _filtroCorreo;
  String? _filtroAccion;

  final TextEditingController _searchController = TextEditingController();
  String _tipoFiltro = 'Ninguno'; // Ninguno, Nombre, Correo, Acción

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Bitácora del Sistema"),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // --- BARRA DE FILTROS ---
          Container(
            padding: const EdgeInsets.all(12),
            color: AppColors.primary.withValues(alpha: 0.05),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.filter_list,
                      size: 20,
                      color: AppColors.secondary,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      "Filtrar por:",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _tipoFiltro,
                        items: ['Ninguno', 'Nombre', 'Correo', 'Acción']
                            .map(
                              (t) => DropdownMenuItem(value: t, child: Text(t)),
                            )
                            .toList(),
                        onChanged: (val) {
                          setState(() {
                            _tipoFiltro = val!;
                            _filtroNombre = null;
                            _filtroCorreo = null;
                            _filtroAccion = null;
                            _searchController.clear();
                          });
                        },
                      ),
                    ),
                  ],
                ),
                if (_tipoFiltro != 'Ninguno') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Escribe el ${_tipoFiltro.toLowerCase()}...",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.check_circle),
                        onPressed: () {
                          setState(() {
                            if (_tipoFiltro == 'Nombre') {
                              _filtroNombre = _searchController.text.trim();
                            } else if (_tipoFiltro == 'Correo') {
                              _filtroCorreo = _searchController.text.trim();
                            } else if (_tipoFiltro == 'Acción') {
                              _filtroAccion = _searchController.text.trim();
                            }
                          });
                        },
                      ),
                    ),
                    onSubmitted: (val) {
                      setState(() {
                        if (_tipoFiltro == 'Nombre') _filtroNombre = val.trim();
                        if (_tipoFiltro == 'Correo') _filtroCorreo = val.trim();
                        if (_tipoFiltro == 'Acción') _filtroAccion = val.trim();
                      });
                    },
                  ),
                ],
              ],
            ),
          ),

          // --- LISTADO DE EVENTOS ---
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _dbService.streamBitacora(
                filtroNombre: _filtroNombre,
                filtroCorreo: _filtroCorreo,
                filtroAccion: _filtroAccion,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 40,
                        ),
                        const SizedBox(height: 10),
                        const Text("Error al cargar la bitácora"),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            snapshot.error.toString(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        if (snapshot.error.toString().contains('index'))
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text(
                              "Nota: Asegúrate de que los índices compuestos estén habilitados en Firestore Console.",
                              style: TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final eventos = snapshot.data?.docs ?? [];

                if (eventos.isEmpty) {
                  return const Center(
                    child: Text("No hay registros que coincidan"),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(10),
                  itemCount: eventos.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final data = eventos[index].data() as Map<String, dynamic>;
                    final DateTime? fecha = (data['fecha'] as Timestamp?)
                        ?.toDate();

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.purple.withValues(alpha: 0.1),
                        child: const Icon(
                          Icons.history_edu,
                          color: Colors.purple,
                        ),
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
                            "Por: ${data['nombre_usuario'] ?? 'Usuario'} (${data['usuario'] ?? 'Email'})",
                            style: TextStyle(
                              fontSize: 11,
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
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                      isThreeLine: true,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- WIDGETS DE VISTA PRIVADOS ---

class _EscritorioView extends StatelessWidget {
  final String nombreCompleto;
  final String rolActual;
  final Map<String, dynamic> userData;
  final int sacoFisico;
  final int sacoComp;
  final int bolsaFisico;
  final int bolsaComp;
  final bool esInvitado;
  final VoidCallback onToggleTheme;
  final _PanelPrincipalState parent;

  const _EscritorioView({
    required this.nombreCompleto,
    required this.rolActual,
    required this.userData,
    required this.sacoFisico,
    required this.sacoComp,
    required this.bolsaFisico,
    required this.bolsaComp,
    required this.esInvitado,
    required this.onToggleTheme,
    required this.parent,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          if (!esInvitado) parent._buildNavigationRail(context, nombreCompleto),
          Expanded(
            child: parent._buildMainContent(
              nombreCompleto: nombreCompleto,
              rolActual: rolActual,
              sacoFisico: sacoFisico,
              sacoComp: sacoComp,
              bolsaFisico: bolsaFisico,
              bolsaComp: bolsaComp,
              userData: userData,
              showHeader: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _MovilView extends StatelessWidget {
  final String nombreCompleto;
  final String rolActual;
  final Map<String, dynamic> userData;
  final int sacoFisico;
  final int sacoComp;
  final int bolsaFisico;
  final int bolsaComp;
  final bool esInvitado;
  final VoidCallback onToggleTheme;
  final _PanelPrincipalState parent;

  const _MovilView({
    required this.nombreCompleto,
    required this.rolActual,
    required this.userData,
    required this.sacoFisico,
    required this.sacoComp,
    required this.bolsaFisico,
    required this.bolsaComp,
    required this.esInvitado,
    required this.onToggleTheme,
    required this.parent,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Image.asset('assets/frifalca6.png', height: 35),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
            onPressed: onToggleTheme,
          ),
        ],
      ),
      drawer: esInvitado
          ? null
          : parent._buildDrawer(context, nombreCompleto, rolActual),
      body: parent._buildMainContent(
        nombreCompleto: nombreCompleto,
        rolActual: rolActual,
        sacoFisico: sacoFisico,
        sacoComp: sacoComp,
        bolsaFisico: bolsaFisico,
        bolsaComp: bolsaComp,
        userData: userData,
        showHeader:
            false, // El AppBar móvil reemplaza la cabecera del contenido
      ),
      floatingActionButton: esInvitado
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.pop(context),
              label: const Text("Login"),
              icon: const Icon(Icons.login),
              backgroundColor: AppColors.secondary,
            )
          : FloatingActionButton(
              onPressed: () =>
                  parent._mostrarDialogoNuevoPedido(context, nombreCompleto),
              backgroundColor: AppColors.secondary,
              elevation: 4,
              shape: const CircleBorder(),
              child: const Icon(Icons.add, color: Colors.white, size: 30),
            ),
      floatingActionButtonLocation: esInvitado
          ? FloatingActionButtonLocation.centerFloat
          : FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: esInvitado ? null : parent._buildBottomNav(context),
    );
  }
}
