import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme.dart';
import 'servicios_de_base_de_datos.dart'; // Aquí está tu DatabaseService original
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'componentes_de_inventario.dart'
    as comp; // Usamos alias para evitar conflictos
import 'modelo_pedidos.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';
import 'ayuda_screen.dart';
import 'dart:ui';

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

class _PanelPrincipalState extends State<PanelPrincipal>
    with TickerProviderStateMixin {
  final DatabaseService _dbService = DatabaseService();
  final ScrollController _scrollController = ScrollController();
  String _filtroTicket = "";
  String _filtroEstado = "Todos";
  DateTime _selectedDate = DateTime.now();

  late Stream<QuerySnapshot> _productosStream;
  late Stream<List<Cita>> _citasStream;
  late Future<DocumentSnapshot?> _userFuture;

  // Claves para validación de formularios
  final _formKeyPedido = GlobalKey<FormState>();
  final _formKeyCliente = GlobalKey<FormState>();
  final _formKeyTrabajador = GlobalKey<FormState>();

  // Método de obtención de datos basado exclusivamente en el correo
  Future<DocumentSnapshot?> _obtenerPerfilPorEmail(String email) async {
    try {
      final cleanEmail = email.trim().toLowerCase();
      // Consulta obligatoria por campo 'correo' ya que los IDs son aleatorios
      final query = await FirebaseFirestore.instance
          .collection('Trabajadores')
          .where('correo', isEqualTo: cleanEmail)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) return query.docs.first;
      return null;
    } catch (e) {
      debugPrint("Error crítico en _obtenerPerfilPorEmail: $email - $e");
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    final userAuth = FirebaseAuth.instance.currentUser;
    // Iniciamos la carga basada en email como llave única
    if (userAuth != null && userAuth.email != null) {
      final String safeEmail = userAuth.email!.trim().toLowerCase();
      _userFuture = _obtenerPerfilPorEmail(safeEmail);
    } else {
      _userFuture = Future.value(null);
    }

    _productosStream = FirebaseFirestore.instance
        .collection('Productos')
        .snapshots();
    _citasStream = _dbService.streamCitasDelDia(_selectedDate);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
        return Builder(
          builder: (context) {
            final int tabLength = widget.esInvitado ? 1 : 4;
            if (!mounted) return const SizedBox.shrink();
            // Inicializar controlador si no existe o cambió el tamaño
            if (!mounted) return const SizedBox.shrink();

            return DefaultTabController(
              length: tabLength,
              child: StreamBuilder<QuerySnapshot>(
                stream: _productosStream,
                builder: (context, prodSnap) {
                  // --- Cálculo de Stocks ---
                  int sacoFisico = 0,
                      sacoComp = 0,
                      bolsaFisico = 0,
                      bolsaComp = 0;
                  if (prodSnap.hasData) {
                    for (var doc in prodSnap.data!.docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      if (doc.id == "NZAtCFwTfLTwb3xiiOUk") {
                        sacoFisico = (data['stock_fisico'] as num? ?? 0)
                            .toInt();
                        sacoComp = (data['stock_comprometido'] as num? ?? 0)
                            .toInt();
                      }
                      if (doc.id == "DWDbVnRf5nqGu8uTu3KA") {
                        bolsaFisico = (data['stock_fisico'] as num? ?? 0)
                            .toInt();
                        bolsaComp = (data['stock_comprometido'] as num? ?? 0)
                            .toInt();
                      }
                    }
                  }

                  // --- AUDITORÍA DE STOCK ---
                  if (prodSnap.hasData) {
                    debugPrint(
                      "--- AUDITORÍA DE INVENTARIO (PanelPrincipal) ---",
                    );
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
                        final String nombreProd =
                            doc.id == "NZAtCFwTfLTwb3xiiOUk" ? "SACO" : "BOLSA";
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
                    debugPrint(
                      "-----------------------------------------------",
                    );
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

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      trackVisibility: true,
      thickness: 8.0,
      radius: const Radius.circular(10),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        slivers: [
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
                          icon: Theme.of(context).brightness == Brightness.dark
                              ? Icons.light_mode
                              : Icons.dark_mode,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.yellow
                              : AppColors.primary,
                          onPressed: widget.onToggleTheme,
                        ),
                        _buildHeaderButton(
                          icon: Icons.logout_rounded,
                          color: AppColors.error,
                          onPressed: () => _mostrarConfirmacionLogout(context),
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
          ],

          SliverPersistentHeader(
            pinned: true,
            delegate: _DynamicInventoryHeaderDelegate(
              sacoFisico: sacoFisico,
              sacoComp: sacoComp,
              bolsaFisico: bolsaFisico,
              bolsaComp: bolsaComp,
              esInvitado: widget.esInvitado,
              nombreCompleto: nombreCompleto,
              onAjustar: (context, id, cant, motivo) =>
                  _procesarAjusteInventario(
                    context,
                    id,
                    cant,
                    nombreCompleto,
                    motivo,
                  ),
            ),
          ),

          Builder(
            builder: (context) {
              final tabController = DefaultTabController.of(context);
              return AnimatedBuilder(
                animation: tabController,
                builder: (context, _) {
                  final index = tabController.index;
                  if (widget.esInvitado) {
                    return _buildInventarioSliver(
                      sacoDisp,
                      bolsaDisp,
                      nombreCompleto,
                      rolActual,
                      sacoFisico,
                      sacoComp,
                      bolsaFisico,
                      bolsaComp,
                    );
                  }

                  switch (index) {
                    case 0:
                      return _buildInventarioSliver(
                        sacoDisp,
                        bolsaDisp,
                        nombreCompleto,
                        rolActual,
                        sacoFisico,
                        sacoComp,
                        bolsaFisico,
                        bolsaComp,
                      );
                    case 1:
                      return _buildPedidosSliver(
                        rolActual,
                        nombreCompleto,
                        sacoFisico,
                        sacoComp,
                        bolsaFisico,
                        bolsaComp,
                      );
                    case 2:
                      return _buildCitasSliver(
                        rolActual,
                        nombreCompleto,
                        sacoFisico,
                        sacoComp,
                        bolsaFisico,
                        bolsaComp,
                      );
                    case 3:
                      return _buildConfiguracionesSliver(rolActual, userData);
                    default:
                      return const SliverToBoxAdapter(child: SizedBox());
                  }
                },
              );
            },
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Future<void> _procesarAjusteInventario(
    BuildContext context,
    String id,
    int cantidad,
    String autor,
    String motivo,
  ) async {
    try {
      await _dbService.ajustarStock(id, cantidad, autor, motivo: motivo);
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text("Inventario actualizado por $autor | Motivo: $motivo"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildNavigationRail(
    BuildContext railContext,
    String nombreCompleto,
    int sacoFisico,
    int sacoComp,
    int bolsaFisico,
    int bolsaComp,
  ) {
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
            onPressed: () => _mostrarDialogoNuevoPedido(
              context,
              nombreCompleto,
              sacoFisico,
              sacoComp,
              bolsaFisico,
              bolsaComp,
            ),
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
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
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

  Widget _buildPedidosSliver(
    String rolActual,
    String nombreCompleto,
    int sF,
    int sC,
    int bF,
    int bC,
  ) {
    return SliverToBoxAdapter(
      child: Column(
        children: [
          // --- BARRA DE BÚSQUEDA Y FILTROS ---
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
              ), // Reducido de 15
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(
                  15,
                ), // Reducido de 20 para ser más profesional
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
                  hintText: "Buscar por ticket...",
                  hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: AppColors.secondary,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    vertical: 12,
                  ), // Ajuste interno
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

          StreamBuilder<List<Pedido>>(
            stream: _dbService.streamPedidos(
              filtroEstado: _filtroEstado,
              filtroTicket: _filtroTicket,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final pedidos = snapshot.data ?? [];
              if (pedidos.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: Text("Sin resultados")),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(15),
                itemCount: pedidos.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  final pedido = pedidos[index];
                  return comp.PedidoCard(
                    pedido: pedido,
                    onTap: () => _mostrarDetalleCompleto(
                      context,
                      pedido,
                      rolActual,
                      nombreCompleto,
                      sF,
                      sC,
                      bF,
                      bC,
                    ),
                    trailingActions: pedido.estado == 'Pendiente'
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildActionButton(
                                Icons.cancel_outlined,
                                Colors.red,
                                () async {
                                  final confirmar =
                                      await _mostrarDialogoConfirmacion(
                                        context,
                                        "¿Está seguro de que desea CANCELAR este pedido?",
                                        "Esta acción no se puede deshacer.",
                                        Colors.red,
                                      );
                                  if (confirmar == true) {
                                    try {
                                      await _dbService.cancelarPedido(
                                        pedido.id,
                                        cantSaco: pedido.cantSaco,
                                        cantBolsa: pedido.cantBolsa,
                                      );
                                      if (!context.mounted) return;
                                      _notificarExito(
                                        "Pedido #${pedido.ticket} cancelado",
                                      );
                                    } catch (e) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            "Error al cancelar: ${e.toString().replaceAll('Exception: ', '')}",
                                          ),
                                          backgroundColor: Colors.red,
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              15,
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  elevation: 0,
                                ),
                                onPressed: () async {
                                  final confirmar =
                                      await _mostrarDialogoConfirmacion(
                                        context,
                                        "¿Está seguro de que desea DESPACHAR este pedido?",
                                        "Se descontará del inventario físico.",
                                        Colors.green,
                                      );
                                  if (confirmar == true) {
                                    try {
                                      await _dbService.despacharPedido(
                                        pedido.id,
                                        nombreCompleto,
                                        cantSaco: pedido.cantSaco,
                                        cantBolsa: pedido.cantBolsa,
                                      );
                                      if (!context.mounted) return;
                                      _notificarExito(
                                        "Pedido #${pedido.ticket} despachado con éxito",
                                      );
                                    } catch (e) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            e.toString().replaceAll(
                                              'Exception: ',
                                              '',
                                            ),
                                          ),
                                          backgroundColor: Colors.red,
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              15,
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                  } else {
                                    if (!context.mounted) return;
                                    _mostrarMensaje(
                                      "Acción cancelada",
                                      esError: true,
                                    );
                                  }
                                },
                                child: const Text(
                                  "Despachar",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : null,
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: 20),
        onPressed: onPressed,
      ),
    );
  }

  // Dentro de _PanelPrincipalState en panel_principal.dart
  Widget _buildInventarioSliver(
    int sacoDisp,
    int bolsaDisp,
    String nombreCompleto,
    String rolActual,
    int sF,
    int sC,
    int bF,
    int bC,
  ) {
    return SliverToBoxAdapter(
      child: StreamBuilder<List<Pedido>>(
        stream: _dbService.streamPedidos(filtroEstado: "Pendiente"),
        builder: (context, pedidoSnap) {
          if (!pedidoSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return comp.ListaPedidosPendientes(
            pedidos: pedidoSnap.data ?? [],
            stockSacoDisp: sacoDisp,
            stockBolsaDisp: bolsaDisp,
            onDespachar: (pedido) async {
              final confirmar = await _mostrarDialogoConfirmacion(
                context,
                "¿Está seguro de que desea DESPACHAR este pedido?",
                "Se descontará del inventario físico.",
                Colors.green,
              );
              if (confirmar == true) {
                try {
                  await _dbService.despacharPedido(
                    pedido.id,
                    nombreCompleto,
                    cantSaco: pedido.cantSaco,
                    cantBolsa: pedido.cantBolsa,
                  );
                  if (!context.mounted) return;
                  _notificarExito("Pedido despachado exitosamente");
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.toString().replaceAll('Exception: ', '')),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  );
                }
              } else {
                if (!context.mounted) return;
                _mostrarMensaje("Acción cancelada", esError: true);
              }
            },
            onShowDetails: (pedido) => _mostrarDetalleCompleto(
              context,
              pedido,
              rolActual,
              nombreCompleto,
              sF,
              sC,
              bF,
              bC,
            ),
          );
        },
      ),
    );
  }

  Widget _buildCitasSliver(
    String rolActual,
    String nombreCompleto,
    int sF,
    int sC,
    int bF,
    int bC,
  ) {
    return SliverToBoxAdapter(
      child: Column(
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
                      setState(() {
                        _selectedDate = picked;
                        _citasStream = _dbService.streamCitasDelDia(
                          _selectedDate,
                        );
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          StreamBuilder<List<Cita>>(
            stream: _citasStream,
            builder: (context, snapshot) {
              final citas = snapshot.data ?? [];

              // Lógica de sincronización automática (Validación de pedidos)
              for (var c in citas) {
                if (c.idPedido != null && !c.estadoAgendado) {
                  _verificarSincronizacionCita(c);
                }
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                itemCount: 48,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
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
                  return _buildSlotCard(
                    slotTime,
                    citaEnSlot,
                    rolActual,
                    nombreCompleto,
                    sF,
                    sC,
                    bF,
                    bC,
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  void _verificarSincronizacionCita(Cita cita) async {
    if (cita.idPedido == null) return;
    final pedido = await _dbService.getPedidoById(cita.idPedido!);
    if (pedido != null && cita.debeMarcarseComoCompletada(pedido.estado)) {
      await _dbService.actualizarEstadoAgendado(cita.id, true);
    }
  }

  Widget _buildSlotCard(
    String slotTime,
    Cita cita,
    String rolActual,
    String nombreCompleto,
    int sF,
    int sC,
    int bF,
    int bC,
  ) {
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
        onTap: () async {
          if (cita.idPedido != null && cita.idPedido!.isNotEmpty) {
            final p = await _dbService.getPedidoById(cita.idPedido!);
            if (p != null && mounted) {
              _mostrarDetalleCompleto(
                context,
                p,
                rolActual,
                nombreCompleto,
                sF,
                sC,
                bF,
                bC,
              );
            }
          } else {
            _mostrarDialogoCita(slotTime, cita);
          }
        },
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
        subtitle: ocupado
            ? Row(
                children: [
                  if (cita.idPedido != null)
                    const Icon(Icons.link, size: 14, color: Colors.grey),
                  if (cita.idPedido != null) const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      cita.motivo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : const Text("Espacio libre"),
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
                  try {
                    await _dbService.actualizarEstadoAgendado(cita.id, true);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Cita marcada como buscada"),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Error al actualizar cita: $e"),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
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
                      try {
                        final nuevaCita = Cita(
                          id: '', // Firestore genera el ID
                          nombre: nombreClienteSel ?? "Cliente",
                          motivo: motivoCtrl.text,
                          fecha: _selectedDate,
                          slot: slot,
                          idPedido: idPedidoSel,
                          idCliente: idClienteSel,
                          nombreCliente: nombreClienteSel,
                        );

                        await _dbService.agendarCita(nuevaCita);

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Cita agendada con éxito"),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("Error al agendar cita: $e"),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
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

  Widget _buildConfiguracionesSliver(
    String rolActual,
    Map<String, dynamic> userData,
  ) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Configuraciones",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            _buildSettingsTile(
              icon: Icons.person_outline_rounded,
              color: Colors.cyan,
              title: "Mi Perfil",
              subtitle: "Gestión de cuenta y seguridad",
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
            _buildSettingsTile(
              icon: Icons.help_outline_rounded,
              color: AppColors.secondary,
              title: "Centro de Ayuda",
              subtitle: "Tutoriales y soporte técnico",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AyudaScreen()),
                );
              },
            ),
            if (rolActual == "admin") ...[
              const SizedBox(height: 10),
              _buildSettingsTile(
                icon: Icons.admin_panel_settings_outlined,
                color: Colors.redAccent,
                title: "Panel de Control Admin",
                subtitle: "Gestión avanzada de usuarios y datos",
                onTap: () => _mostrarPanelAdmin(context, rolActual),
              ),
            ],
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    SizedBox(height: 20),
                    Text(
                      '© 2026 Todos los Derechos Reservados',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(
                          0x999E9E9E,
                        ), // Colors.grey.withValues(alpha: 0.6)
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      'Desarrollado por Aldayr García',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0x999E9E9E), fontSize: 12),
                    ),
                    Text(
                      'Bajo la tutoría del Ing. Andrik Arguello',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0x999E9E9E),
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
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
  }

  Widget _buildSettingsTile({
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
      tileColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: onTap,
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
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Form(
            key: _formKeyCliente,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nomCtrl,
                  decoration: const InputDecoration(labelText: "Nombre"),
                  validator: (v) =>
                      v == null || v.isEmpty ? "Campo obligatorio" : null,
                ),
                const SizedBox(height: 30),
                TextFormField(
                  controller: apeCtrl,
                  decoration: const InputDecoration(labelText: "Apellido"),
                  validator: (v) =>
                      v == null || v.isEmpty ? "Campo obligatorio" : null,
                ),
                const SizedBox(height: 30),
                TextFormField(
                  controller: cedCtrl,
                  decoration: const InputDecoration(
                    labelText: "Cédula",
                    prefixText: "V-",
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) =>
                      v == null || v.isEmpty ? "Campo obligatorio" : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_formKeyCliente.currentState?.validate() ?? false) {
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
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Form(
              key: _formKeyTrabajador,
              child: SingleChildScrollView(
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
                    const SizedBox(height: 30),
                    TextFormField(
                      controller: correoCtrl,
                      decoration: const InputDecoration(
                        labelText: "Correo Electrónico",
                      ),
                      validator: (v) => v == null || !v.contains('@')
                          ? "Correo inválido"
                          : null,
                    ),
                    const SizedBox(height: 30),
                    TextFormField(
                      controller: nomCtrl,
                      decoration: const InputDecoration(labelText: "Nombre"),
                      validator: (v) =>
                          v == null || v.isEmpty ? "Campo obligatorio" : null,
                    ),
                    const SizedBox(height: 30),
                    TextFormField(
                      controller: apeCtrl,
                      decoration: const InputDecoration(labelText: "Apellido"),
                      validator: (v) =>
                          v == null || v.isEmpty ? "Campo obligatorio" : null,
                    ),
                    const SizedBox(height: 30),
                    DropdownButtonFormField<String>(
                      initialValue: rolSel,
                      items: ["Empleado", "admin"]
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => rolSel = v!),
                      decoration: const InputDecoration(
                        labelText: "Rol asignado",
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: () async {
                if (_formKeyTrabajador.currentState?.validate() ?? false) {
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
    String nombreCompleto,
    int sF,
    int sC,
    int bF,
    int bC, [
    Pedido? pedido,
  ]) {
    final int sDisp = (sF - sC).clamp(0, 999999);
    final int bDisp = (bF - bC).clamp(0, 999999);
    final bool sinStock = sDisp <= 0 || bDisp <= 0;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

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
          backgroundColor: sinStock
              ? (isDark ? const Color(0xFF3D2C10) : Colors.orange.shade50)
              : null,
          title: Text(pedido == null ? "Nuevo Pedido" : "Editar Pedido"),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Form(
              key: _formKeyPedido,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (sinStock) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.5),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.orange,
                              size: 20,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "TRABAJANDO SIN STOCK",
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
                    ],
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
                          const SizedBox(height: 15),
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
                                        clienteDoc.data()
                                            as Map<String, dynamic>;
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
                    const SizedBox(height: 30),
                    TextFormField(
                      controller: ticketController,
                      decoration: const InputDecoration(
                        labelText: "N° Ticket (Opcional)",
                      ),
                    ),
                    const SizedBox(height: 30),
                    // --- SELECCIÓN DE ORDEN ---
                    DropdownButtonFormField<String>(
                      key: ValueKey("orden_$ordenSeleccionada"),
                      initialValue: ordenSeleccionada,
                      decoration: const InputDecoration(labelText: "Orden"),
                      items: ["Saco", "Bolsa", "Mixto"]
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => ordenSeleccionada = val);
                        }
                      },
                    ),

                    // --- SECCIÓN DINÁMICA: SACO ---
                    if (ordenSeleccionada == "Saco" ||
                        ordenSeleccionada == "Mixto") ...[
                      const SizedBox(height: 30),
                      const Divider(),
                      const SizedBox(height: 15),
                      DropdownButtonFormField<String>(
                        key: ValueKey("sub_saco_$subTipoSaco"),
                        initialValue: subTipoSaco,
                        decoration: const InputDecoration(
                          labelText: "Tipo de Hielo (Saco)",
                        ),
                        items: ["Saco Pescador", "Saco Público", "Donación"]
                            .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => subTipoSaco = val);
                          }
                        },
                      ),
                      const SizedBox(height: 30),
                      TextFormField(
                        controller: cantSacoCont,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: "Cantidad de Sacos",
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return "Campo obligatorio";
                          }
                          final int? valor = int.tryParse(v);
                          if (valor == null) {
                            return "Debe ser un número entero";
                          }
                          if (valor <= 0) {
                            return "La cantidad debe ser mayor a cero";
                          }
                          return null;
                        },
                      ),
                    ],

                    // --- SECCIÓN DINÁMICA: BOLSA ---
                    if (ordenSeleccionada == "Bolsa" ||
                        ordenSeleccionada == "Mixto") ...[
                      const SizedBox(height: 30),
                      const Divider(),
                      const SizedBox(height: 15),
                      DropdownButtonFormField<String>(
                        key: ValueKey("sub_bolsa_$subTipoBolsa"),
                        initialValue: subTipoBolsa,
                        decoration: const InputDecoration(
                          labelText: "Tipo de Hielo (Bolsa)",
                        ),
                        items: ["Bolsa Público", "Bolsa a Mayor", "Donación"]
                            .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => subTipoBolsa = val);
                          }
                        },
                      ),
                      const SizedBox(height: 30),
                      TextFormField(
                        controller: cantBolsaCont,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: "Cantidad de Bolsas",
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return "Campo obligatorio";
                          }
                          final int? valor = int.tryParse(v);
                          if (valor == null) {
                            return "Debe ser un número entero";
                          }
                          if (valor <= 0) {
                            return "La cantidad debe ser mayor a cero";
                          }
                          return null;
                        },
                      ),
                    ],

                    const SizedBox(height: 30),
                    const Divider(),
                    const SizedBox(height: 15),
                    TextFormField(
                      controller: montoController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}'),
                        ),
                      ],
                      decoration: const InputDecoration(
                        labelText: "Monto Total (Bs - Opcional)",
                        prefixText: "Bs. ",
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return null; // Opcional, permitido vacío
                        }
                        // Reemplazamos coma por punto para el parsing si es necesario
                        final v = value.replaceAll(',', '.');
                        final double? parsed = double.tryParse(v);
                        if (parsed == null || parsed < 0) {
                          return 'Debe ser un número positivo (Ej: 15.50)';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: () async {
                if (_formKeyPedido.currentState?.validate() ?? false) {
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
                      orden: ordenSeleccionada,
                      detalleSaco: subTipoSaco,
                      detalleBolsa: subTipoBolsa,
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
                      orden: ordenSeleccionada,
                      detalleSaco: subTipoSaco,
                      detalleBolsa: subTipoBolsa,
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
    _mostrarMensaje(mensaje, esError: false);
  }

  void _mostrarMensaje(String mensaje, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              esError ? Icons.cancel : Icons.check_circle,
              color: Colors.white,
              size: 20,
            ),
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
        backgroundColor: esError ? Colors.red : AppColors.primary,
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

  void _mostrarDetalleCompleto(
    BuildContext context,
    Pedido pedido,
    String rolActual,
    String nombreCompleto,
    int sF,
    int sC,
    int bF,
    int bC,
  ) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

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
                      color: isDark ? Colors.grey[700] : Colors.grey[300],
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
                    color: isDark ? Colors.white : Colors.blue[900],
                  ),
                ),
                const Divider(),
                _filaDetalle(
                  context,
                  Icons.confirmation_number,
                  "N° Ticket",
                  pedido.ticket,
                ),
                _filaDetalle(
                  context,
                  Icons.ac_unit,
                  "Tipo de Hielo",
                  pedido.tipoHielo,
                ),
                _filaDetalle(
                  context,
                  Icons.attach_money,
                  "Monto Total",
                  "${pedido.monto} Bs",
                ),
                _filaDetalle(
                  context,
                  Icons.info,
                  "Estado Actual",
                  pedido.estado,
                ),
                _filaDetalle(
                  context,
                  Icons.person_add,
                  "Creado por",
                  pedido.creadoPor ?? "N/A",
                ),
                _filaDetalle(
                  context,
                  Icons.local_shipping,
                  "Despachado por",
                  pedido.despachadoPor ?? "Pendiente",
                ),
                _filaDetalle(
                  context,
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
                          sF,
                          sC,
                          bF,
                          bC,
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
  Widget _filaDetalle(
    BuildContext context,
    IconData icono,
    String titulo,
    String valor,
  ) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icono,
            color: isDark ? Colors.blueGrey[200] : Colors.blueGrey,
            size: 20,
          ),
          const SizedBox(width: 10),
          Text(
            "$titulo: ",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _mostrarDialogoConfirmacion(
    BuildContext context,
    String titulo,
    String mensaje,
    Color colorPrimario,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              titulo,
              style: TextStyle(
                color: colorPrimario,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              mensaje,
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  "Volver",
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.grey,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text("Confirmar"),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EstadisticasScreen extends StatefulWidget {
  final DatabaseService dbService;
  const _EstadisticasScreen({required this.dbService});

  @override
  State<_EstadisticasScreen> createState() => _EstadisticasScreenState();
}

class _EstadisticasScreenState extends State<_EstadisticasScreen> {
  String _filtroEstadisticas = "Semana";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Dashboard de Ventas")),
      body: StreamBuilder<List<Pedido>>(
        stream: widget.dbService.streamVentasFiltradas(_filtroEstadisticas),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final pedidos = snapshot.data ?? [];
          double totalMonto = 0;
          final Map<String, int> volumenVentas = {};

          for (var p in pedidos) {
            totalMonto += p.monto;
            final fecha = p.fecha ?? DateTime.now();
            String key = _getLabelPorFiltro(fecha, _filtroEstadisticas);
            volumenVentas[key] = (volumenVentas[key] ?? 0) + 1;
          }

          final List<String> labels = _getLabelsOrdenados(_filtroEstadisticas);
          final List<BarChartGroupData> barGroups = [];
          int maxVolumen = 0;
          for (int i = 0; i < labels.length; i++) {
            final count = volumenVentas[labels[i]] ?? 0;
            if (count > maxVolumen) maxVolumen = count;
            barGroups.add(
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: count.toDouble(),
                    color: AppColors.secondary,
                    width: 16,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Día', label: Text('Hoy')),
                  ButtonSegment(value: 'Semana', label: Text('Sem')),
                  ButtonSegment(value: 'Mes', label: Text('Mes')),
                  ButtonSegment(value: 'Año', label: Text('Año')),
                ],
                selected: {_filtroEstadisticas},
                onSelectionChanged: (Set<String> newSelection) {
                  setState(() {
                    _filtroEstadisticas = newSelection.first;
                  });
                },
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: AppColors.secondary,
                  selectedForegroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 30),
              _buildGananciasCard(totalMonto, _filtroEstadisticas),
              const SizedBox(height: 30),
              const Text(
                "Volumen de Pedidos",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                height: 300,
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
                    alignment: BarChartAlignment.spaceAround,
                    maxY: (maxVolumen + 2).toDouble(),
                    barGroups: barGroups,
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (val, meta) => Text(
                            val.toInt() < labels.length
                                ? labels[val.toInt()]
                                : '',
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- MÉTODOS AUXILIARES MOVIDOS ---
  Widget _buildGananciasCard(double monto, String filtro) {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF1A3A5A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet,
                color: Colors.cyanAccent,
              ),
              const SizedBox(width: 10),
              Text(
                "Ganancias ($filtro)",
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            "${monto.toStringAsFixed(2)} Bs.",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _getLabelPorFiltro(DateTime fecha, String filtro) {
    if (filtro == 'Día') {
      return "${fecha.hour}h";
    } else if (filtro == 'Semana') {
      return _getDiaNombreTab(0, customDate: fecha);
    } else if (filtro == 'Mes') {
      return "Dia ${fecha.day}";
    } else {
      switch (fecha.month) {
        case 1:
          return "Ene";
        case 2:
          return "Feb";
        case 3:
          return "Mar";
        case 4:
          return "Abr";
        case 5:
          return "May";
        case 6:
          return "Jun";
        case 7:
          return "Jul";
        case 8:
          return "Ago";
        case 9:
          return "Sep";
        case 10:
          return "Oct";
        case 11:
          return "Nov";
        case 12:
          return "Dic";
        default:
          return "";
      }
    }
  }

  List<String> _getLabelsOrdenados(String filtro) {
    if (filtro == 'Día') {
      return List.generate(24, (i) => "${i}h");
    } else if (filtro == 'Semana') {
      return ["Lun", "Mar", "Mie", "Jue", "Vie", "Sab", "Dom"];
    } else if (filtro == 'Mes') {
      return List.generate(31, (i) => "Dia ${i + 1}");
    } else {
      return [
        "Ene",
        "Feb",
        "Mar",
        "Abr",
        "May",
        "Jun",
        "Jul",
        "Ago",
        "Sep",
        "Oct",
        "Nov",
        "Dic",
      ];
    }
  }

  String _getDiaNombreTab(int index, {DateTime? customDate}) {
    final ahora = DateTime.now();
    final dia = customDate ?? ahora.subtract(Duration(days: 6 - index));
    switch (dia.weekday) {
      case 1:
        return "Lun";
      case 2:
        return "Mar";
      case 3:
        return "Mie";
      case 4:
        return "Jue";
      case 5:
        return "Vie";
      case 6:
        return "Sab";
      case 7:
        return "Dom";
      default:
        return "";
    }
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
            child: StreamBuilder<List<QueryDocumentSnapshot>>(
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

                final eventos = snapshot.data ?? [];

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
                    final String motivo = data['motivo'] ?? 'No especificado';
                    final String? tipoMovimiento = data['tipo_movimiento'];

                    // Determinar color del chip según tipo de movimiento
                    Color chipColor;
                    if (tipoMovimiento == 'ENTRADA') {
                      chipColor = Colors.green;
                    } else if (tipoMovimiento == 'SALIDA') {
                      chipColor = Colors.orange;
                    } else {
                      chipColor = Colors.grey;
                    }

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
                          const SizedBox(height: 6),
                          // Chip del motivo
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: chipColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: chipColor.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  tipoMovimiento == 'ENTRADA'
                                      ? Icons.arrow_downward
                                      : tipoMovimiento == 'SALIDA'
                                      ? Icons.arrow_upward
                                      : Icons.info_outline,
                                  size: 12,
                                  color: chipColor,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    'Motivo: $motivo',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: chipColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
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
          if (!esInvitado)
            parent._buildNavigationRail(
              context,
              nombreCompleto,
              sacoFisico,
              sacoComp,
              bolsaFisico,
              bolsaComp,
            ),
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
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () => parent._mostrarConfirmacionLogout(context),
          ),
        ],
      ),
      drawer: null,
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
              onPressed: () => parent._mostrarDialogoNuevoPedido(
                context,
                nombreCompleto,
                sacoFisico,
                sacoComp,
                bolsaFisico,
                bolsaComp,
              ),
              backgroundColor: AppColors.secondary,
              elevation: 4,
              shape: const CircleBorder(),
              child: const Icon(Icons.add, color: Colors.white, size: 30),
            ),
      floatingActionButtonLocation: esInvitado
          ? FloatingActionButtonLocation.centerFloat
          : FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: esInvitado ? null : parent._buildBottomNav(context),
    );
  }
}

class _DynamicInventoryHeaderDelegate extends SliverPersistentHeaderDelegate {
  final int sacoFisico, sacoComp, bolsaFisico, bolsaComp;
  final bool esInvitado;
  final String nombreCompleto;
  final Function(BuildContext context, String id, int cantidad, String motivo)
  onAjustar;

  _DynamicInventoryHeaderDelegate({
    required this.sacoFisico,
    required this.sacoComp,
    required this.bolsaFisico,
    required this.bolsaComp,
    required this.esInvitado,
    required this.nombreCompleto,
    required this.onAjustar,
  });

  @override
  double get maxExtent => 320.0; // Reducido aún más para eliminar "aire" innecesario

  Widget _buildMiniInfo(String label, int val, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "$label: ",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        Text(
          val.toString(),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _buildAlertaBadge(String mensaje) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red[900]?.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.report_problem, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              mensaje,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final double percent = (shrinkOffset / maxExtent).clamp(0.0, 1.0);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: percent > 0.5 ? 0.05 : 0.02)
                : Colors.white.withValues(alpha: percent > 0.5 ? 0.9 : 0.7),
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.05),
              ),
            ),
          ),
          child: Stack(
            children: [
              // --- ESTADO EXPANDIDO (Con alertas integradas) ---
              Positioned.fill(
                child: Opacity(
                  opacity: (1.0 - percent * 2.5).clamp(0.0, 1.0),
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Cálculo de alerta dentro del delegado
                        if ((sacoFisico - sacoComp) <= 0 ||
                            (bolsaFisico - bolsaComp) <= 0) ...[
                          _buildAlertaBadge("TRABAJANDO SIN STOCK"),
                          const SizedBox(height: 8),
                        ],
                        comp.InventarioResumenCard(
                          sacoFisico: sacoFisico,
                          sacoComp: sacoComp,
                          bolsaFisico: bolsaFisico,
                          bolsaComp: bolsaComp,
                          readOnly: esInvitado,
                          onAjustar: onAjustar,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // --- ESTADO COLAPSADO (Dot indicador de alerta) ---
              Opacity(
                opacity: (percent * 2.0 - 1.0).clamp(0.0, 1.0),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Indicador minimalista de alerta en modo colapsado
                      if ((sacoFisico - sacoComp) <= 0 ||
                          (bolsaFisico - bolsaComp) <= 0) ...[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      _buildMiniInfo(
                        "S",
                        sacoFisico - sacoComp,
                        AppColors.secondary,
                      ),
                      const SizedBox(width: 25),
                      Container(
                        width: 1,
                        height: 20,
                        color: isDark ? Colors.white24 : Colors.black12,
                      ),
                      const SizedBox(width: 25),
                      _buildMiniInfo(
                        "B",
                        bolsaFisico - bolsaComp,
                        AppColors.secondary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  double get minExtent => 60.0;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      true;
}
