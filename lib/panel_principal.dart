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

import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'ajustes_sistema_screen.dart';
import 'servicios_de_notificaciones.dart';
import 'servicios_de_actualizacion.dart';

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
  final NotificationService _notifService = NotificationService();
  // Controladores y estados locales
  String _filtroTicket = "";
  String _filtroEstado = "Todos";
  DateTime _selectedDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );

  late Stream<QuerySnapshot> _productosStream;
  late Stream<List<Cita>> _citasStream;
  late Stream<DocumentSnapshot> _tasaStream;
  late Stream<DocumentSnapshot> _ajustesStream;
  late Future<DocumentSnapshot?> _userFuture;

  double _tasaVigente = 1.0;
  bool _usarTasaAutomatica = false;

  double _valorManualTasa = 1.0;

  // Claves para validación de formularios
  final _formKeyPedido = GlobalKey<FormState>();
  final _formKeyCliente = GlobalKey<FormState>();
  final _formKeyTrabajador = GlobalKey<FormState>();

  DateTime? _ultimaVezVistoNotificaciones;
  late AnimationController _notifAnimationController;

  bool _mostrarTasaEnPedidos = false;
  Pedido? _pedidoSeleccionado;
  bool _mostrarPanelLateral = true;
  bool _disenoCompacto = false;
  bool _disenoPedidosLargo = false;

  // Variables de Paginación y Filtros Avanzados
  int _itemsPorPagina = 10;
  int _paginaActual = 1;
  String _filtroRangoTiempo =
      "Hoy"; // Hoy, Semana, Mes, Año, Todo, Personalizado
  DateTimeRange? _customDateRange;

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

    // --- ACTIVACIÓN DE NOTIFICACIONES ---
    _notifAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _cargarUltimaVistaNotificaciones();

    if (!widget.esInvitado) {
      _notifService.initNotifications();
      _notifService.saveTokenForCurrentUser();
    }

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
    _tasaStream = _dbService.streamConfiguracionTasa();
    _ajustesStream = _dbService.streamAjustesSistema();

    // Listener para la tasa
    _tasaStream.listen((snap) {
      if (snap.exists && mounted) {
        final data = snap.data() as Map<String, dynamic>;
        setState(() {
          _usarTasaAutomatica = data['usar_automatica'] ?? false;
          _valorManualTasa = (data['valor_manual'] ?? 1.0).toDouble();

          if (_usarTasaAutomatica) {
            final double bcv = (data['ultima_bcv'] ?? 0.0).toDouble();
            // Refuerzo de seguridad: Si el valor automático es inválido (nulo o 0),
            // usamos el valor manual como fallback inmediato.
            _tasaVigente = (bcv > 0) ? bcv : _valorManualTasa;
          } else {
            _tasaVigente = _valorManualTasa;
          }
        });
      }
    });

    // Listener para ajustes del sistema (Visibilidad de Tasa)
    _ajustesStream.listen((snap) {
      if (snap.exists && mounted) {
        final data = snap.data() as Map<String, dynamic>;
        setState(() {
          _mostrarTasaEnPedidos = data['calcular_precios_auto'] ?? false;
          _itemsPorPagina = data['items_por_pagina'] ?? 10;
          _mostrarPanelLateral = data['mostrar_panel_lateral'] ?? true;
          _disenoCompacto = data['diseno_compacto'] ?? false;
          _disenoPedidosLargo = data['diseno_pedidos_largo'] ?? false;
        });
      }
    });

    // Actualizar tasa al iniciar si está en automático
    _dbService.obtenerTasaVigente();

    // Verificación de actualización remota (OTA)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.checkUpdate(context);
    });
  }

  @override
  void dispose() {
    _notifAnimationController.dispose();
    super.dispose();
  }

  Future<void> _cargarUltimaVistaNotificaciones() async {
    final prefs = await SharedPreferences.getInstance();
    final int? timestamp = prefs.getInt('ultima_visto_notif');
    if (timestamp != null) {
      if (mounted) {
        setState(() {
          _ultimaVezVistoNotificaciones = DateTime.fromMillisecondsSinceEpoch(
            timestamp,
          );
        });
      }
    } else {
      // Si es la primera vez, marcamos como visto "ahora" para no mostrar puntos rojos por notificaciones viejas
      final ahora = DateTime.now();
      await prefs.setInt('ultima_visto_notif', ahora.millisecondsSinceEpoch);
      if (mounted) {
        setState(() {
          _ultimaVezVistoNotificaciones = ahora;
        });
      }
    }
  }

  Future<void> _marcarNotificacionesComoLeidas() async {
    final prefs = await SharedPreferences.getInstance();
    final ahora = DateTime.now();
    await prefs.setInt('ultima_visto_notif', ahora.millisecondsSinceEpoch);
    if (mounted) {
      setState(() {
        _ultimaVezVistoNotificaciones = ahora;
      });
    }
  }

  // setEstaEditando y seleccionarPedido removidos.

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

        // --- VERIFICACIÓN DE BLOQUEO ---
        if (userData['bloqueado'] == true) {
          return Scaffold(
            backgroundColor: AppColors.primary,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.block_rounded,
                        color: Colors.red,
                        size: 80,
                      ),
                    ),
                    const SizedBox(height: 30),
                    const Text(
                      "ACCESO RESTRINGIDO",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      "Tu cuenta ha sido suspendida por el administrador del sistema.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "Si crees que se trata de un error, por favor contacta al soporte técnico de Frifalca.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                    const SizedBox(height: 40),
                    ElevatedButton.icon(
                      onPressed: () => FirebaseAuth.instance.signOut(),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text("Cerrar Sesión"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 30,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

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
        final bool isDesktop = constraints.maxWidth >= 600;
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

    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        if (showHeader)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        "Frifalca C.A.",
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: AppColors.secondary,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(width: 20),
                      _buildHeaderGreeting(nombreCompleto),
                    ],
                  ),
                  Row(
                    children: [
                      _buildNotificationBellButton(),
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
        SliverPersistentHeader(
          pinned: true,
          delegate: _DynamicInventoryHeaderDelegate(
            sacoFisico: sacoFisico,
            sacoComp: sacoComp,
            bolsaFisico: bolsaFisico,
            bolsaComp: bolsaComp,
            esInvitado: widget.esInvitado,
            nombreCompleto: nombreCompleto,
            rolActual: rolActual,
            onAjustar: (context, id, cant, motivo) => _procesarAjusteInventario(
              context,
              id,
              cant,
              nombreCompleto,
              motivo,
            ),
          ),
        ),
      ],
      body: TabBarView(
        children: widget.esInvitado
            ? [
                CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    _buildInventarioSliver(
                      sacoDisp,
                      bolsaDisp,
                      nombreCompleto,
                      rolActual,
                      sacoFisico,
                      sacoComp,
                      bolsaFisico,
                      bolsaComp,
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ],
                ),
              ]
            : [
                // TAB 0: PANEL
                CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    _buildInventarioSliver(
                      sacoDisp,
                      bolsaDisp,
                      nombreCompleto,
                      rolActual,
                      sacoFisico,
                      sacoComp,
                      bolsaFisico,
                      bolsaComp,
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ],
                ),
                // TAB 1: PEDIDOS
                CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    _buildPedidosSliver(
                      rolActual,
                      nombreCompleto,
                      sacoFisico,
                      sacoComp,
                      bolsaFisico,
                      bolsaComp,
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ],
                ),
                // TAB 2: CITAS
                CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    _buildCitasSliver(
                      rolActual,
                      nombreCompleto,
                      sacoFisico,
                      sacoComp,
                      bolsaFisico,
                      bolsaComp,
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ],
                ),
                // TAB 3: CONFIG
                CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    _buildConfiguracionesSliver(rolActual, userData),
                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ],
                ),
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
    final isDark = Theme.of(railContext).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: (isDark ? Colors.white : Colors.black).withValues(
              alpha: 0.1,
            ),
            width: 0.5,
          ),
        ),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: NavigationRail(
            selectedIndex: controller.index,
            onDestinationSelected: (int index) {
              setState(() {
                controller.animateTo(index);
              });
            },
            leading: Column(
              children: [
                const SizedBox(height: 20),
                Image.asset(
                  'assets/icon_web.png',
                  height: 45,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 25),
                FloatingActionButton(
                  mini: true,
                  onPressed: () => _mostrarDialogoNuevoPedido(
                    context,
                    nombreCompleto,
                    sacoFisico,
                    sacoComp,
                    bolsaFisico,
                    bolsaComp,
                  ),
                  backgroundColor: Colors.cyanAccent.shade700,
                  elevation: 4,
                  child: const Icon(Icons.add, color: Colors.white),
                ),
                const SizedBox(height: 10),
              ],
            ),
            backgroundColor: (isDark ? Colors.black : Colors.white).withValues(
              alpha: 0.85,
            ),
            indicatorColor: AppColors.secondary.withValues(alpha: 0.2),
            selectedIconTheme: IconThemeData(
              color: isDark ? AppColors.secondary : AppColors.primary,
            ),
            unselectedIconTheme: IconThemeData(
              color: isDark ? Colors.blueGrey : Colors.black45,
            ),
            selectedLabelTextStyle: GoogleFonts.outfit(
              color: isDark ? AppColors.secondary : AppColors.primary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
            unselectedLabelTextStyle: GoogleFonts.outfit(
              color: isDark ? Colors.blueGrey : Colors.black87,
              fontSize: 11,
            ),
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
          ),
        ),
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

  Widget _buildNotificationBellButton() {
    return StreamBuilder<List<QueryDocumentSnapshot>>(
      stream: _dbService.streamNotificaciones(limite: 1),
      builder: (context, snapshot) {
        bool hayNuevas = false;
        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          final data = snapshot.data!.first.data() as Map<String, dynamic>;
          final fecha = (data['fecha'] as Timestamp?)?.toDate();
          if (fecha != null &&
              (_ultimaVezVistoNotificaciones == null ||
                  fecha.isAfter(_ultimaVezVistoNotificaciones!))) {
            hayNuevas = true;
          }
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            _buildHeaderButton(
              icon: hayNuevas
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              color: AppColors.secondary,
              onPressed: () => _mostrarCentroNotificaciones(context),
            ),
            if (hayNuevas)
              Positioned(
                top: 10,
                right: 10,
                child: FadeTransition(
                  opacity: _notifAnimationController,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent,
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Nuevo widget para el saludo compacto en el encabezado
  Widget _buildHeaderGreeting(String nombre) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color:
              (Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black)
                  .withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: AppColors.secondary.withValues(alpha: 0.2),
            child: const Icon(
              Icons.person_rounded,
              color: AppColors.secondary,
              size: 14,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "¡Buen día!",
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
              Text(
                nombre,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    final controller = DefaultTabController.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(
                height: 65,
                decoration: BoxDecoration(
                  color: (isDark ? Colors.black : Colors.white).withValues(
                    alpha: 0.85,
                  ),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: (isDark ? Colors.white : Colors.black).withValues(
                      alpha: 0.1,
                    ),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
              ),
            ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = isDark ? AppColors.secondary : AppColors.primary;
    final inactiveColor = isDark ? Colors.blueGrey : Colors.black87;

    return Expanded(
      child: InkWell(
        onTap: () {
          DefaultTabController.of(context).animateTo(index);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: selected ? activeColor : inactiveColor, size: 24),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: selected ? activeColor : inactiveColor,
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
    // Cálculo de fechas según filtro
    DateTime? start;
    DateTime? end;
    final now = DateTime.now();

    switch (_filtroRangoTiempo) {
      case "Hoy":
        start = DateTime(now.year, now.month, now.day);
        end = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case "Esta Semana":
        start = now.subtract(Duration(days: now.weekday - 1));
        start = DateTime(start.year, start.month, start.day);
        end = now.add(Duration(days: 7 - now.weekday));
        end = DateTime(end.year, end.month, end.day, 23, 59, 59);
        break;
      case "Este Mes":
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        break;
      case "Este Año":
        start = DateTime(now.year, 1, 1);
        end = DateTime(now.year, 12, 31, 23, 59, 59);
        break;
      case "Personalizado":
        start = _customDateRange?.start;
        end = _customDateRange?.end;
        break;
      default:
        start = null;
        end = null;
    }

    return SliverToBoxAdapter(
      child: Column(
        children: [
          const SizedBox(height: 12), // Espacio estándar MD3
          // --- BARRA DE BÚSQUEDA ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 45, // Reducción de altura
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                onChanged: (val) => setState(() {
                  _filtroTicket = val;
                  _paginaActual = 1;
                }),
                textAlignVertical: TextAlignVertical.center,
                decoration: const InputDecoration(
                  hintText: "Buscar ticket...",
                  hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: AppColors.secondary,
                    size: 20,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),

          // --- FILTROS DE TIEMPO (Compactos e integrados) ---
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                ...["Hoy", "Esta Semana", "Este Mes"].map((r) {
                  final isSelected = _filtroRangoTiempo == r;
                  final isDark =
                      Theme.of(context).brightness == Brightness.dark;

                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(r),
                      selected: isSelected,
                      onSelected: (val) {
                        setState(() {
                          if (val) {
                            _filtroRangoTiempo = r;
                          } else {
                            _filtroRangoTiempo = "Todo";
                          }
                          _paginaActual = 1;
                        });
                      },
                      selectedColor: Colors.cyan.withValues(alpha: 0.15),
                      backgroundColor: Colors.transparent,
                      checkmarkColor: isDark
                          ? Colors.cyanAccent
                          : Colors.cyan.shade800,
                      labelStyle: TextStyle(
                        fontSize: 11,
                        color: isSelected
                            ? (isDark
                                  ? Colors.cyanAccent
                                  : Colors.cyan.shade800)
                            : (isDark ? Colors.white70 : Colors.blueGrey),
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      shape: StadiumBorder(
                        side: BorderSide(
                          color: isSelected
                              ? Colors.cyan.withValues(alpha: 0.5)
                              : (isDark ? Colors.white12 : Colors.black12),
                        ),
                      ),
                    ),
                  );
                }),

                // Chip de Calendario (Con botón de limpiar)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ChoiceChip(
                        avatar: Icon(
                          Icons.date_range_rounded,
                          size: 14,
                          color: _filtroRangoTiempo == "Personalizado"
                              ? (Theme.of(context).brightness == Brightness.dark
                                    ? Colors.cyanAccent
                                    : Colors.cyan.shade800)
                              : Colors.blueGrey,
                        ),
                        label: Text(
                          _filtroRangoTiempo == "Personalizado" &&
                                  _customDateRange != null
                              ? "${_customDateRange!.start.day}/${_customDateRange!.start.month} - ${_customDateRange!.end.day}/${_customDateRange!.end.month}"
                              : "Filtro",
                        ),
                        selected: _filtroRangoTiempo == "Personalizado",
                        onSelected: (val) async {
                          if (!val) {
                            setState(() {
                              _filtroRangoTiempo = "Todo";
                              _customDateRange = null;
                              _paginaActual = 1;
                            });
                            return;
                          }
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2023),
                            lastDate: DateTime.now().add(
                              const Duration(days: 1),
                            ),
                            initialDateRange: _customDateRange,
                          );
                          if (picked != null) {
                            setState(() {
                              _customDateRange = picked;
                              _filtroRangoTiempo = "Personalizado";
                              _paginaActual = 1;
                            });
                          }
                        },
                        selectedColor: Colors.cyan.withValues(alpha: 0.15),
                        backgroundColor: Colors.transparent,
                        checkmarkColor:
                            Theme.of(context).brightness == Brightness.dark
                            ? Colors.cyanAccent
                            : Colors.cyan.shade800,
                        labelStyle: TextStyle(
                          fontSize: 11,
                          color: _filtroRangoTiempo == "Personalizado"
                              ? (Theme.of(context).brightness == Brightness.dark
                                    ? Colors.cyanAccent
                                    : Colors.cyan.shade800)
                              : (Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white70
                                    : Colors.blueGrey),
                          fontWeight: _filtroRangoTiempo == "Personalizado"
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        shape: StadiumBorder(
                          side: BorderSide(
                            color: _filtroRangoTiempo == "Personalizado"
                                ? Colors.cyan.withValues(alpha: 0.5)
                                : (Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white12
                                      : Colors.black12),
                          ),
                        ),
                      ),
                      if (_filtroRangoTiempo == "Personalizado" &&
                          _customDateRange != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _customDateRange = null;
                                _filtroRangoTiempo = "Hoy";
                                _paginaActual = 1;
                              });
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                size: 14,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // --- FILTROS DE ESTADO ---
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
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
              fechaInicio: start,
              fechaFin: end,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _buildErrorState(snapshot.error.toString());
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final allPedidos = snapshot.data ?? [];
              if (allPedidos.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: Text("Sin resultados")),
                );
              }

              // Paginación Manual (Client Side)
              final startIndex = (_paginaActual - 1) * _itemsPorPagina;
              final paginatedPedidos = allPedidos
                  .skip(startIndex)
                  .take(_itemsPorPagina)
                  .toList();
              final totalPaginas = (allPedidos.length / _itemsPorPagina).ceil();

              return Column(
                children: [
                  LayoutBuilder(
                    builder: (context, gridConstraints) {
                      final bool isWide = gridConstraints.maxWidth > 800;
                      if (isWide && _disenoCompacto) {
                        return GridView.builder(
                          key: const PageStorageKey("pedidos_grid_view"),
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(15),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 600,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                mainAxisExtent: 155,
                              ),
                          itemCount: paginatedPedidos.length,
                          itemBuilder: (context, index) {
                            final pedido = paginatedPedidos[index];
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
                              fullWidth: _disenoPedidosLargo,
                              trailingActions: pedido.estado == 'Pendiente'
                                  ? _buildPedidoAcciones(
                                      pedido,
                                      rolActual,
                                      nombreCompleto,
                                    )
                                  : null,
                            );
                          },
                        );
                      } else {
                        // DISEÑO ANCHO (Por defecto o si es móvil)
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 10,
                          ),
                          child: Column(
                            children: paginatedPedidos.map((pedido) {
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
                                fullWidth: _disenoPedidosLargo,
                                trailingActions: pedido.estado == 'Pendiente'
                                    ? _buildPedidoAcciones(
                                        pedido,
                                        rolActual,
                                        nombreCompleto,
                                      )
                                    : null,
                              );
                            }).toList(),
                          ),
                        );
                      }
                    },
                  ),

                  if (totalPaginas > 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left_rounded),
                            onPressed: _paginaActual > 1
                                ? () => setState(() => _paginaActual--)
                                : null,
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              "Página $_paginaActual de $totalPaginas",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right_rounded),
                            onPressed: _paginaActual < totalPaginas
                                ? () => setState(() => _paginaActual++)
                                : null,
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: Colors.orange),
            const SizedBox(height: 10),
            Text(
              "Error: $error",
              style: const TextStyle(color: Colors.orange, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPedidoAcciones(
    Pedido pedido,
    String rolActual,
    String nombreCompleto,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildActionButton(Icons.cancel_outlined, Colors.red, () async {
          final conf = await _mostrarDialogoConfirmacion(
            context,
            "¿CANCELAR pedido?",
            "No se puede deshacer.",
            Colors.red,
          );
          if (conf == true) {
            await _dbService.cancelarPedido(
              pedido.id,
              cantSaco: pedido.cantSaco,
              cantBolsa: pedido.cantBolsa,
            );
            _notificarExito("Pedido cancelado");
          }
        }),
        const SizedBox(width: 8),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            elevation: 0,
          ),
          onPressed: () async {
            final conf = await _mostrarDialogoConfirmacion(
              context,
              "¿DESPACHAR pedido?",
              "Se descontará del inventario.",
              Colors.green,
            );
            if (conf == true) {
              await _dbService.despacharPedido(
                pedido.id,
                nombreCompleto,
                rolActual,
                cantSaco: pedido.cantSaco,
                cantBolsa: pedido.cantBolsa,
              );
              _notificarExito("Pedido despachado");
            }
          },
          child: const Text(
            "Despachar",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ],
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
            pedidosFullWidth:
                true, // Forzamos full width para optimizar espacio como en la imagen
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
                    rolActual,
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
            padding: const EdgeInsets.fromLTRB(20, 15, 20, 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Agenda de hoy",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (_selectedDate.day != DateTime.now().day ||
                        _selectedDate.month != DateTime.now().month ||
                        _selectedDate.year != DateTime.now().year)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedDate = DateTime(
                              DateTime.now().year,
                              DateTime.now().month,
                              DateTime.now().day,
                            );
                            _citasStream = _dbService.streamCitasDelDia(
                              _selectedDate,
                            );
                          });
                        },
                        child: const Text("Hoy"),
                      ),
                    IconButton(
                      icon: const Icon(Icons.calendar_month_rounded),
                      color: AppColors.secondary,
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
              ],
            ),
          ),
          StreamBuilder<List<Cita>>(
            stream: _citasStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(height: 10),
                      Text(
                        "Error en la agenda: ${snapshot.error}",
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                      if (snapshot.error.toString().contains("index"))
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            "Falta crear el índice compuesto en Firebase.",
                            style: TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }

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
        onTap: () {
          _mostrarDialogoCita(
            slotTime,
            cita,
            rolActual: rolActual,
            nombreCompleto: nombreCompleto,
            sF: sF,
            sC: sC,
            bF: bF,
            bC: bC,
          );
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
          onPressed: () => _mostrarDialogoCita(
            slotTime,
            cita,
            rolActual: rolActual,
            nombreCompleto: nombreCompleto,
            sF: sF,
            sC: sC,
            bF: bF,
            bC: bC,
          ),
        ),
      ),
    );
  }

  void _mostrarDialogoCita(
    String slot,
    Cita cita, {
    String rolActual = 'Empleado',
    String nombreCompleto = '',
    int sF = 0,
    int sC = 0,
    int bF = 0,
    int bC = 0,
  }) {
    // ─── CITA EXISTENTE ───
    if (cita.id.isNotEmpty) {
      final bool puedeGestionar =
          rolActual == 'admin' || rolActual == 'supervisor';

      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(Icons.event_available, color: AppColors.secondary),
              const SizedBox(width: 10),
              Text(
                "Cita – $slot",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow(
                Icons.person,
                "Cliente",
                cita.nombreCliente ?? cita.nombre,
              ),
              _buildInfoRow(Icons.notes, "Nota", cita.motivo),
              _buildInfoRow(
                Icons.flag,
                "Estado",
                cita.estadoAgendado ? '✅ Retirado' : '⏳ Pendiente de retiro',
              ),
              if (cita.idPedido != null)
                _buildInfoRow(
                  Icons.link,
                  "Pedido",
                  "Ticket vinculado (#${cita.idPedido!.substring(0, 6)}…)",
                ),
            ],
          ),
          actions: [
            // ── Cancelar cita (solo admin/supervisor) ──
            if (puedeGestionar)
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text(
                  "Cancelar Cita",
                  style: TextStyle(color: Colors.red),
                ),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: dialogCtx,
                    builder: (c) => AlertDialog(
                      title: const Text("¿Cancelar esta cita?"),
                      content: const Text(
                        "Esto eliminará la cita de la agenda. El pedido asociado NO se cancelará automáticamente.",
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text("No"),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(c, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          child: const Text(
                            "Sí, cancelar",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    try {
                      await _dbService.cancelarCita(
                        cita.id,
                        motivo: 'Cancelada por $nombreCompleto',
                      );
                      if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Cita cancelada"),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("Error: $e"),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  }
                },
              ),

            // ── Reagendar cita (solo admin/supervisor) ──
            if (puedeGestionar)
              TextButton.icon(
                icon: const Icon(Icons.edit_calendar, color: Colors.orange),
                label: const Text(
                  "Reagendar",
                  style: TextStyle(color: Colors.orange),
                ),
                onPressed: () async {
                  Navigator.pop(dialogCtx);
                  _mostrarDialogoReagendar(cita);
                },
              ),

            // ── Marcar como Retirado ──
            if (!cita.estadoAgendado)
              ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline),
                label: const Text("Marcar como Retirado"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  // Si tiene pedido vinculado, obtenemos cantidades para despachar
                  int cantS = 0, cantB = 0;
                  if (cita.idPedido != null) {
                    final p = await _dbService.getPedidoById(cita.idPedido!);
                    if (p != null) {
                      cantS = p.cantSaco;
                      cantB = p.cantBolsa;
                    }
                  }
                  try {
                    await _dbService.marcarCitaComoRetirada(
                      idCita: cita.id,
                      idPedido: cita.idPedido,
                      despachadorNombre: nombreCompleto,
                      despachadorRol: rolActual,
                      cantSaco: cantS,
                      cantBolsa: cantB,
                    );
                    if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "✅ Cita marcada como retirada y pedido despachado",
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Error: $e"),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text("Cerrar"),
            ),
          ],
        ),
      );
      return;
    }

    // ─── FORMULARIO PARA AGENDAR ───
    String? idPedidoSel;
    String? idClienteSel;
    String? nombreClienteSel;
    final motivoCtrl = TextEditingController(); // vacío, sin texto predefinido

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (stfContext, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(Icons.event_note, color: AppColors.secondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Agendar Retiro ($slot)",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
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
                  builder: (streamCtx, snapshot) {
                    if (!snapshot.hasData) {
                      return const LinearProgressIndicator();
                    }
                    final pedidos = snapshot.data!.docs;

                    if (pedidos.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          "No hay pedidos pendientes para agendar retiro.",
                          style: TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }

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
                // ── FIX: placeholder correcto, campo vacío ──
                TextField(
                  controller: motivoCtrl,
                  decoration: const InputDecoration(
                    labelText: "Nota opcional",
                    hintText: "Ej: Retiro de pedido",
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: idPedidoSel == null
                  ? null
                  : () async {
                      try {
                        final nuevaCita = Cita(
                          id: '',
                          nombre: nombreClienteSel ?? "Cliente",
                          motivo: motivoCtrl.text.isEmpty
                              ? "Retiro de pedido"
                              : motivoCtrl.text,
                          fecha: DateTime(
                            _selectedDate.year,
                            _selectedDate.month,
                            _selectedDate.day,
                          ),
                          slot: slot,
                          idPedido: idPedidoSel,
                          idCliente: idClienteSel,
                          nombreCliente: nombreClienteSel,
                        );

                        await _dbService.agendarCita(nuevaCita);

                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("✅ Cita agendada con éxito"),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        _dbService.registrarErrorSistema(
                          contexto: "Agendar Cita ($slot)",
                          error: e.toString(),
                        );
                        if (mounted) {
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

  /// Widget helper para mostrar filas de información en el diálogo de cita
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.blueGrey),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  TextSpan(
                    text: "$label: ",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  TextSpan(text: value, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Diálogo para reagendar una cita existente a otra fecha y hora
  void _mostrarDialogoReagendar(Cita cita) async {
    DateTime nuevaFecha = cita.fecha;
    String nuevoSlot = cita.slot;

    // Posibles slots disponibles (08:00 a 15:50, cada 10 min)
    final List<String> slots = List.generate(48, (i) {
      final total = 8 * 60 + i * 10;
      final h = (total ~/ 60).toString().padLeft(2, '0');
      final m = (total % 60).toString().padLeft(2, '0');
      return "$h:$m";
    });

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.edit_calendar, color: Colors.orange),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Reagendar Cita",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.calendar_today,
                  color: AppColors.secondary,
                ),
                title: Text(
                  "${nuevaFecha.day}/${nuevaFecha.month}/${nuevaFecha.year}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text("Toca para cambiar la fecha"),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: nuevaFecha,
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setModalState(() => nuevaFecha = picked);
                  }
                },
              ),
              const Divider(),
              DropdownButtonFormField<String>(
                initialValue: nuevoSlot,
                decoration: const InputDecoration(
                  labelText: "Nuevo horario",
                  border: OutlineInputBorder(),
                ),
                items: slots
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setModalState(() => nuevoSlot = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                try {
                  await _dbService.reagendarCita(
                    cita.id,
                    nuevaFecha,
                    nuevoSlot,
                  );
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  if (mounted) {
                    setState(() {
                      _selectedDate = nuevaFecha;
                      _citasStream = _dbService.streamCitasDelDia(nuevaFecha);
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("📅 Cita reagendada con éxito"),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Error al reagendar: $e"),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text("Confirmar Reagendado"),
            ),
          ],
        ),
      ),
    );
  }

  // DIALOGO LOGOUT
  void _mostrarCentroNotificaciones(BuildContext context) {
    _marcarNotificacionesComoLeidas();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          children: [
            // Barra superior del modal
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.blueGrey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Notificaciones",
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: StreamBuilder<List<QueryDocumentSnapshot>>(
                stream: _dbService.streamNotificaciones(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.notifications_off_outlined,
                            size: 60,
                            color: Colors.blueGrey.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 15),
                          const Text(
                            "No hay notificaciones recientes",
                            style: TextStyle(color: Colors.blueGrey),
                          ),
                        ],
                      ),
                    );
                  }

                  final logs = snapshot.data!;
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                    itemCount: logs.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final data = logs[index].data() as Map<String, dynamic>;
                      final String accion = data['accion'] ?? 'EVENTO';
                      final String detalle = data['detalle'] ?? '';
                      final DateTime fecha =
                          (data['fecha'] as Timestamp?)?.toDate() ??
                          DateTime.now();

                      // Lógica de iconos temáticos
                      IconData icon = Icons.info_outline_rounded;
                      Color color = AppColors.secondary;

                      if (accion.contains('PEDIDO')) {
                        icon = Icons.receipt_long_rounded;
                        color = Colors.orange;
                      } else if (accion.contains('INVENTARIO') ||
                          accion.contains('STOCK')) {
                        icon = Icons.inventory_2_outlined;
                        color = Colors.blue;
                      } else if (accion.contains('TASA')) {
                        icon = Icons.currency_exchange_rounded;
                        color = Colors.green;
                      } else if (accion.contains('USUARIO')) {
                        icon = Icons.person_outline_rounded;
                        color = Colors.purple;
                      } else if (accion.contains('CLIENTE')) {
                        icon = Icons.person_add_alt_1_outlined;
                        color = Colors.teal;
                      }

                      return Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: color.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(icon, color: color, size: 20),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        accion.replaceAll('_', ' '),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: color,
                                        ),
                                      ),
                                      Text(
                                        "${fecha.hour}:${fecha.minute.toString().padLeft(2, '0')}",
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.blueGrey,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    detalle,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      height: 1.3,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "${fecha.day}/${fecha.month}/${fecha.year}",
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Configuraciones",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
              icon: Icons.people_outline_rounded,
              color: Colors.blue,
              title: "Gestión de Clientes",
              subtitle: "Ver, buscar y añadir clientes a la base de datos",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => _GestionClientesScreen(
                      dbService: _dbService,
                      onNuevoCliente: () => _mostrarFormularioCliente(context),
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
            if (rolActual == "admin" || rolActual == "supervisor") ...[
              const SizedBox(height: 10),
              _buildSettingsTile(
                icon: Icons.admin_panel_settings_outlined,
                color: Colors.redAccent,
                title: rolActual == "admin"
                    ? "Panel de Control Admin"
                    : "Panel de Gestión Supervisor",
                subtitle: rolActual == "admin"
                    ? "Gestión avanzada de usuarios y datos"
                    : "Acceso a reportes e inventario",
                onTap: () => _mostrarPanelAdmin(context, rolActual),
              ),
            ],
            const SizedBox(height: 10),
            _buildSettingsTile(
              icon: Icons.settings_applications_rounded,
              color: AppColors.secondary,
              title: "Ajustes del Sistema",
              subtitle:
                  "Control central de automatización, tasa y visualización",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AjustesSistemaScreen(),
                  ),
                );
              },
            ),
            Padding(
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
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        'Versión 1.0.0A',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0x999E9E9E),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
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
              // --- SECCIÓN GESTIÓN USUARIOS ---
              _buildAdminActionTile(
                icon: Icons.people_alt_rounded,
                color: Colors.blueAccent,
                title: "Panel de Personal",
                subtitle: "Ver, buscar, bloquear o pre-autorizar personal",
                onTap: () {
                  Navigator.pop(context); // Cierra el modal de admin
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => _GestionPersonalScreen(
                        dbService: _dbService,
                        onPreAutorizar: () =>
                            _mostrarFormularioTrabajador(context),
                      ),
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
              // --- SECCIÓN MONITOR ERRORES ---
              _buildAdminActionTile(
                icon: Icons.bug_report_rounded,
                color: Colors.red,
                title: "Monitor de Errores",
                subtitle: "Ver fallos técnicos reportados",
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MonitorErroresScreen(),
                    ),
                  );
                },
              ),
            ],
            if (rolActual == "admin") ...[
              const SizedBox(height: 15),
              // --- SECCIÓN PRUEBA FCM (Temporal) ---
              _buildAdminActionTile(
                icon: Icons.notification_add_rounded,
                color: Colors.redAccent,
                title: "Probar Notificación Global",
                subtitle: "Verificar conexión FCM V1",
                onTap: () async {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Enviando prueba vía GAS...")),
                  );
                  await _notifService.enviarNotificacionGAS(
                    topic: "stock_alerts",
                    titulo: "¡Conexión Exitosa!",
                    cuerpo:
                        "El puente de notificaciones GAS ahora está activo.",
                    prioridad: NotifPriority.alta,
                  );
                },
              ),
              const SizedBox(height: 15),
              // --- SECCIÓN ELIMINAR BASE DE DATOS ---
              _buildAdminActionTile(
                icon: Icons.delete_forever_rounded,
                color: Colors.red,
                title: "Eliminar Base de Datos",
                subtitle: "Borrado crítico de registros (Solo Admin)",
                onTap: () async {
                  final confirmar = await _mostrarDialogoConfirmacion(
                    context,
                    "¡ACCIÓN CRÍTICA!",
                    "¿Está ABSOLUTAMENTE seguro de eliminar los registros locales? Esta acción es irreversible y solo permitida para el Administrador principal.",
                    Colors.red,
                  );
                  if (confirmar == true) {
                    // Aquí iría la lógica de borrado si existiera en el service
                    _mostrarMensaje(
                      "Función restringida por seguridad superior",
                      esError: true,
                    );
                  }
                },
              ),
            ],

            const SizedBox(height: 40),
            const Text(
              "Nota de Seguridad",
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

  void _mostrarDialogoGestionTasa(BuildContext context) {
    final TextEditingController manualController = TextEditingController(
      text: _valorManualTasa.toString(),
    );
    bool autoLocal = _usarTasaAutomatica;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text("Gestión de Tasa de Cambio"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text("Usar Tasa BCV Automática"),
                subtitle: const Text("Se actualiza vía API de terceros"),
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
                  decoration: InputDecoration(
                    labelText: "Valor Manual (Bs/\$)",
                    prefixIcon: const Icon(Icons.edit_note_rounded),
                  ),
                ),
              if (autoLocal)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    "Tasa actual BCV: $_tasaVigente Bs/\$",
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
                double? manualVal = double.tryParse(manualController.text);
                await _dbService.actualizarConfiguracionTasa(
                  usarAuto: autoLocal,
                  valorManual: manualVal,
                );
                if (context.mounted) Navigator.pop(context);
                _notificarExito("Configuración de tasa actualizada");
              },
              child: const Text("Guardar"),
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
                      items: ["Empleado", "supervisor", "admin"]
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
            constraints: const BoxConstraints(maxWidth: 1000),
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
                    // --- PRECIO DEL DÓLAR (BCV/MANUAL) ---
                    if (_mostrarTasaEnPedidos) ...[
                      InkWell(
                        onTap: () => _mostrarDialogoGestionTasa(context),
                        borderRadius: BorderRadius.circular(15),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.orange.withValues(alpha: 0.15),
                                Colors.amber.withValues(alpha: 0.05),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.monetization_on_rounded,
                                  color: Colors.orange,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _usarTasaAutomatica
                                          ? "Tasa Oficial BCV"
                                          : "Tasa Manual",
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: _usarTasaAutomatica
                                            ? Colors.orange
                                            : Colors.blueGrey,
                                      ),
                                    ),
                                    Text(
                                      "1 USD = ${_tasaVigente.toStringAsFixed(2)} Bs.",
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.edit_note_rounded,
                                color: Colors.orange,
                                size: 22,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
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
                    if (_tasaVigente > 1.0) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Tasa del día: $_tasaVigente Bs/\$",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey.withValues(alpha: 0.7),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextFormField(
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: "Calcular desde USD (\$)",
                          prefixText: "\$ ",
                          hintText: "0.00",
                          helperText:
                              "Se multiplicará por la tasa para obtener el total en Bs.",
                        ),
                        onChanged: (val) {
                          double? usd = double.tryParse(
                            val.replaceAll(',', '.'),
                          );
                          if (usd != null) {
                            montoController.text = (usd * _tasaVigente)
                                .toStringAsFixed(2);
                          }
                        },
                      ),
                    ],
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
                      tasaAplicada: _tasaVigente,
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
                      tasaAplicada: _tasaVigente,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label ?? valor),
        selected: seleccionado,
        onSelected: (bool selected) {
          setState(() {
            if (selected) {
              _filtroEstado = valor;
            } else {
              _filtroEstado = "Todos";
            }
            _paginaActual = 1;
          });
        },
        selectedColor: Colors.cyan.withValues(alpha: 0.15),
        backgroundColor: Colors.transparent,
        labelStyle: TextStyle(
          color: seleccionado
              ? (isDark ? Colors.cyanAccent : Colors.cyan.shade800)
              : (isDark ? Colors.white70 : Colors.blueGrey),
          fontWeight: seleccionado ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
        checkmarkColor: isDark ? Colors.cyanAccent : Colors.cyan.shade800,
        showCheckmark: true,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: StadiumBorder(
          side: BorderSide(
            color: seleccionado
                ? Colors.cyan.withValues(alpha: 0.5)
                : (isDark ? Colors.white12 : Colors.black12),
          ),
        ),
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
    // Si el panel lateral está habilitado y hay espacio (Desktop), lo seleccionamos
    if (_mostrarPanelLateral && MediaQuery.of(context).size.width > 1100) {
      setState(() {
        _pedidoSeleccionado = pedido;
      });
      return;
    }

    // De lo contrario, usamos el modal tradicional
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),
              comp.PedidoCard(
                pedido: pedido,
                isDetailed: true,
                onTap: () {},
                trailingActions:
                    (rolActual == "admin" || rolActual == "supervisor")
                    ? Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.edit_rounded),
                            label: const Text("Editar Pedido"),
                            onPressed: () {
                              Navigator.pop(context);
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
                      )
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidePanel(
    BuildContext context,
    Pedido pedido,
    String rolActual,
    String nombreCompleto,
    int sF,
    int sC,
    int bF,
    int bC,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 450,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          left: BorderSide(
            color: isDark ? Colors.white10 : Colors.black12,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          AppBar(
            title: const Text("Detalles del Pedido"),
            backgroundColor: Colors.transparent,
            foregroundColor: isDark ? Colors.white : AppColors.primary,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() => _pedidoSeleccionado = null),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: comp.PedidoCard(
                pedido: pedido,
                isDetailed: true,
                onTap: () {},
                trailingActions:
                    (rolActual == "admin" || rolActual == "supervisor")
                    ? Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.edit_rounded),
                            label: const Text("Editar Pedido"),
                            onPressed: () {
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
                      )
                    : null,
              ),
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
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  Future<void> _seleccionarFecha(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customStartDate != null && _customEndDate != null
          ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppColors.primary,
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: Theme.of(context).scaffoldBackgroundColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _customStartDate = picked.start;
        _customEndDate = picked.end;
        _filtroEstadisticas = "Personalizado";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Dashboard de Ventas",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<List<Pedido>>(
        stream: widget.dbService.streamVentasFiltradas(
          _filtroEstadisticas,
          fechaInicio: _customStartDate,
          fechaFin: _customEndDate,
        ),
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
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: 'Día',
                          label: Text('Hoy', style: TextStyle(fontSize: 12)),
                        ),
                        ButtonSegment(
                          value: 'Semana',
                          label: Text('Sem', style: TextStyle(fontSize: 12)),
                        ),
                        ButtonSegment(
                          value: 'Mes',
                          label: Text('Mes', style: TextStyle(fontSize: 12)),
                        ),
                        ButtonSegment(
                          value: 'Año',
                          label: Text('Año', style: TextStyle(fontSize: 12)),
                        ),
                        ButtonSegment(
                          value: 'Personalizado',
                          label: Icon(Icons.calendar_month_rounded, size: 18),
                        ),
                      ],
                      selected: {_filtroEstadisticas},
                      onSelectionChanged: (Set<String> newSelection) {
                        if (newSelection.first == 'Personalizado') {
                          _seleccionarFecha(context);
                        } else {
                          setState(() {
                            _filtroEstadisticas = newSelection.first;
                            _customStartDate = null;
                            _customEndDate = null;
                          });
                        }
                      },
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: AppColors.secondary,
                        selectedForegroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],
              ),
              if (_filtroEstadisticas == 'Personalizado' &&
                  _customStartDate != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Center(
                    child: Chip(
                      label: Text(
                        "${_customStartDate!.day}/${_customStartDate!.month} - ${_customEndDate!.day}/${_customEndDate!.month}",
                        style: const TextStyle(fontSize: 12),
                      ),
                      onDeleted: () {
                        setState(() {
                          _filtroEstadisticas = "Semana";
                          _customStartDate = null;
                          _customEndDate = null;
                        });
                      },
                    ),
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
                height: 350,
                padding: const EdgeInsets.only(top: 25, bottom: 10),
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
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: SizedBox(
                    width: (labels.length * 50.0).clamp(
                      MediaQuery.of(context).size.width - 40,
                      5000,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 20),
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
                                reservedSize: 40,
                                getTitlesWidget: (val, meta) {
                                  final int index = val.toInt();
                                  if (index < labels.length) {
                                    return SideTitleWidget(
                                      meta: meta,
                                      space: 10,
                                      child: Text(
                                        labels[index],
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary.withValues(
                                            alpha: 0.7,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ),
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
    } else if (filtro == 'Mes' || filtro == 'Personalizado') {
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
    } else if (filtro == 'Mes' || filtro == 'Personalizado') {
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
  String _tipoFiltro = 'Ninguno'; // Ninguno, Nombre, Correo, Acción, Fecha
  DateTime? _fechaInicioBitacora;
  DateTime? _fechaFinBitacora;

  Future<void> _seleccionarRangoFecha(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        _fechaInicioBitacora = picked.start;
        _fechaFinBitacora = picked.end;
        _tipoFiltro = 'Fecha';
      });
    }
  }

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
                        items:
                            ['Ninguno', 'Nombre', 'Correo', 'Acción', 'Fecha']
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t),
                                  ),
                                )
                                .toList(),
                        onChanged: (val) {
                          if (val == 'Fecha') {
                            _seleccionarRangoFecha(context);
                          } else {
                            setState(() {
                              _tipoFiltro = val!;
                              _filtroNombre = null;
                              _filtroCorreo = null;
                              _filtroAccion = null;
                              _fechaInicioBitacora = null;
                              _fechaFinBitacora = null;
                              _searchController.clear();
                            });
                          }
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
                if (_tipoFiltro == 'Fecha' && _fechaInicioBitacora != null) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _seleccionarRangoFecha(context),
                    child: Chip(
                      avatar: const Icon(Icons.date_range, size: 16),
                      label: Text(
                        "Desde: ${_fechaInicioBitacora!.day}/${_fechaInicioBitacora!.month} - Hasta: ${_fechaFinBitacora!.day}/${_fechaFinBitacora!.month}",
                      ),
                      onDeleted: () {
                        setState(() {
                          _tipoFiltro = 'Ninguno';
                          _fechaInicioBitacora = null;
                          _fechaFinBitacora = null;
                        });
                      },
                    ),
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
                fechaInicio: _fechaInicioBitacora,
                fechaFin: _fechaFinBitacora,
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
          // Contenido Principal: Ocupa todo el ancho restante
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
          if (parent._mostrarPanelLateral && parent._pedidoSeleccionado != null)
            parent._buildSidePanel(
              context,
              parent._pedidoSeleccionado!,
              rolActual,
              nombreCompleto,
              sacoFisico,
              sacoComp,
              bolsaFisico,
              bolsaComp,
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
      extendBody: true,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.primary,
        elevation: 0,
        title: Text(
          'Frifalca',
          style: GoogleFonts.montserrat(
            color: AppColors.secondary,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        actions: [
          parent._buildNotificationBellButton(),
          IconButton(
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
              color: Colors.white,
            ),
            onPressed: onToggleTheme,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
            onPressed: () => parent._mostrarConfirmacionLogout(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
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
  final String rolActual;
  final Function(BuildContext context, String id, int cantidad, String motivo)
  onAjustar;
  final double maxExtentValue;

  _DynamicInventoryHeaderDelegate({
    required this.sacoFisico,
    required this.sacoComp,
    required this.bolsaFisico,
    required this.bolsaComp,
    required this.esInvitado,
    required this.nombreCompleto,
    required this.rolActual,
    required this.onAjustar,
    // ignore: unused_element_parameter
    this.maxExtentValue =
        185.0, // Base reducida para que se ajuste a la tarjeta al desaparecer la alerta
  });

  /// Calcula si hay alerta de sin stock activa
  bool get _haySinStock =>
      (sacoFisico - sacoComp) <= 0 || (bolsaFisico - bolsaComp) <= 0;

  /// El maxExtent se estira y se contrae de forma agresiva según el estado
  @override
  double get maxExtent => maxExtentValue + (_haySinStock ? 75.0 : 0.0);

  @override
  double get minExtent => 60.0; // Cambiado a un mínimo mayor para evitar solapes al reducir maxExtent

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

    // Si el scroll ha avanzado lo suficiente, mostramos el componente resumido
    if (percent > 0.8) {
      return ResumenInventarioHeader(
        sacos: sacoFisico - sacoComp,
        bolsas: bolsaFisico - bolsaComp,
      );
    }

    // Si no, mostramos el diseño expandido sin el contenedor gris de fondo
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
          child: Padding(
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 2,
              ), // Align 20px
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Cálculo de alerta dentro del delegado
                  if (_haySinStock) ...[
                    _buildAlertaBadge("TRABAJANDO SIN STOCK"),
                    const SizedBox(height: 8),
                  ],
                  comp.InventarioResumenCard(
                    sacoFisico: sacoFisico,
                    sacoComp: sacoComp,
                    bolsaFisico: bolsaFisico,
                    bolsaComp: bolsaComp,
                    readOnly:
                        esInvitado ||
                        (rolActual != "admin" && rolActual != "supervisor"),
                    onAjustar: onAjustar,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _DynamicInventoryHeaderDelegate oldDelegate) =>
      maxExtentValue != oldDelegate.maxExtentValue ||
      sacoFisico != oldDelegate.sacoFisico ||
      sacoComp != oldDelegate.sacoComp ||
      bolsaFisico != oldDelegate.bolsaFisico ||
      bolsaComp != oldDelegate.bolsaComp ||
      esInvitado != oldDelegate.esInvitado ||
      nombreCompleto != oldDelegate.nombreCompleto ||
      rolActual != oldDelegate.rolActual;
}

// Nuevo widget independiente para el estado "encogido" o resumido
class ResumenInventarioHeader extends StatelessWidget {
  final int sacos;
  final int bolsas;

  const ResumenInventarioHeader({
    super.key,
    required this.sacos,
    required this.bolsas,
  });

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

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool hayAlerta = sacos <= 0 || bolsas <= 0;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.9),
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.05),
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (hayAlerta) ...[
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
              _buildMiniInfo("Sacos", sacos, AppColors.secondary),
              const SizedBox(width: 20),
              Container(
                width: 1,
                height: 20,
                color: isDark ? Colors.white24 : Colors.black12,
              ),
              const SizedBox(width: 20),
              _buildMiniInfo("Bolsas", bolsas, AppColors.secondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _GestionPersonalScreen extends StatefulWidget {
  final DatabaseService dbService;
  final VoidCallback onPreAutorizar;
  const _GestionPersonalScreen({
    required this.dbService,
    required this.onPreAutorizar,
  });

  @override
  State<_GestionPersonalScreen> createState() => _GestionPersonalScreenState();
}

class _GestionPersonalScreenState extends State<_GestionPersonalScreen> {
  String _filtro = "";

  void _mostrarDetallesUsuario(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("${data['nombre'] ?? ''} ${data['apellido'] ?? ''}"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: data.entries.map((e) {
              if (e.value == null) return const SizedBox.shrink();
              String valor = e.value.toString();
              if (e.value is Timestamp) {
                valor = (e.value as Timestamp).toDate().toString();
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black,
                    ),
                    children: [
                      TextSpan(
                        text: "${e.key}: ",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: valor),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cerrar"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Panel de Personal"),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_rounded),
            tooltip: "Pre-autorizar Trabajador",
            onPressed: widget.onPreAutorizar,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(15),
            child: TextField(
              decoration: InputDecoration(
                hintText: "Buscar por nombre...",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                filled: true,
                fillColor: Theme.of(context).cardColor,
              ),
              onChanged: (v) => setState(() => _filtro = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<QueryDocumentSnapshot>>(
              stream: widget.dbService.streamTrabajadores(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final allUsers = snapshot.data ?? [];
                final usuarios = allUsers.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final nombre =
                      "${data['nombre'] ?? ''} ${data['apellido'] ?? ''}"
                          .toLowerCase();
                  return nombre.contains(_filtro);
                }).toList();

                if (usuarios.isEmpty) {
                  return const Center(
                    child: Text("No hay trabajadores registrados"),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(15),
                  itemCount: usuarios.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final data = usuarios[index].data() as Map<String, dynamic>;
                    final String uid = usuarios[index].id;
                    final String nombre =
                        "${data['nombre'] ?? ''} ${data['apellido'] ?? ''}";
                    final String correo = data['correo'] ?? 'Sin correo';
                    final String rol = data['rol'] ?? 'Empleado';
                    final bool bloqueado = data['bloqueado'] ?? false;

                    return ListTile(
                      onTap: () => _mostrarDetallesUsuario(data),
                      leading: CircleAvatar(
                        backgroundColor: bloqueado
                            ? Colors.red.withValues(alpha: 0.1)
                            : Colors.blue.withValues(alpha: 0.1),
                        child: Icon(
                          bloqueado
                              ? Icons.person_off_rounded
                              : Icons.person_rounded,
                          color: bloqueado ? Colors.red : Colors.blue,
                        ),
                      ),
                      title: Text(
                        nombre,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          decoration: bloqueado
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      subtitle: Text("$correo\nRol: $rol"),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              bloqueado
                                  ? Icons.lock_open_rounded
                                  : Icons.lock_outline_rounded,
                              color: bloqueado ? Colors.green : Colors.orange,
                            ),
                            tooltip: bloqueado ? "Desbloquear" : "Bloquear",
                            onPressed: () =>
                                _confirmarCambioEstado(uid, !bloqueado, nombre),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.red,
                            ),
                            tooltip: "Eliminar",
                            onPressed: () => _confirmarEliminacion(uid, nombre),
                          ),
                        ],
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

  void _confirmarCambioEstado(String uid, bool nuevoEstado, String nombre) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(nuevoEstado ? "Bloquear Usuario" : "Desbloquear Usuario"),
        content: Text(
          "¿Deseas ${nuevoEstado ? 'bloquear' : 'desbloquear'} a $nombre?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await widget.dbService.actualizarEstadoTrabajador(
                uid,
                nuevoEstado,
              );
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    "Usuario ${nuevoEstado ? 'bloqueado' : 'desbloqueado'}",
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: nuevoEstado ? Colors.orange : Colors.green,
            ),
            child: Text(nuevoEstado ? "Bloquear" : "Desbloquear"),
          ),
        ],
      ),
    );
  }

  void _confirmarEliminacion(String uid, String nombre) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Eliminar Trabajador"),
        content: Text("¿Estás seguro de eliminar permanentemente a $nombre?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await widget.dbService.eliminarTrabajador(uid);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Trabajador eliminado")),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Eliminar"),
          ),
        ],
      ),
    );
  }
}

class _GestionClientesScreen extends StatefulWidget {
  final DatabaseService dbService;
  final VoidCallback onNuevoCliente;
  const _GestionClientesScreen({
    required this.dbService,
    required this.onNuevoCliente,
  });

  @override
  State<_GestionClientesScreen> createState() => _GestionClientesScreenState();
}

class _GestionClientesScreenState extends State<_GestionClientesScreen> {
  String _filtro = "";

  void _mostrarDetallesCliente(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("${data['Nombre'] ?? ''} ${data['Apellido'] ?? ''}"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: data.entries.map((e) {
              if (e.value == null) return const SizedBox.shrink();
              String valor = e.value.toString();
              if (e.value is Timestamp) {
                valor = (e.value as Timestamp).toDate().toString();
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black,
                    ),
                    children: [
                      TextSpan(
                        text: "${e.key}: ",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: valor),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cerrar"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Gestión de Clientes"),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_rounded),
            tooltip: "Nuevo Cliente",
            onPressed: widget.onNuevoCliente,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(15),
            child: TextField(
              decoration: InputDecoration(
                hintText: "Buscar cliente...",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                filled: true,
                fillColor: Theme.of(context).cardColor,
              ),
              onChanged: (v) => setState(() => _filtro = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<QueryDocumentSnapshot>>(
              stream: widget.dbService.streamClientes(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final allClients = snapshot.data ?? [];
                final clientes = allClients.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final nombre =
                      "${data['Nombre'] ?? ''} ${data['Apellido'] ?? ''}"
                          .toLowerCase();
                  return nombre.contains(_filtro);
                }).toList();

                if (clientes.isEmpty) {
                  return const Center(
                    child: Text("No hay clientes registrados"),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(15),
                  itemCount: clientes.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final data = clientes[index].data() as Map<String, dynamic>;
                    final String cid = clientes[index].id;
                    final String nombre =
                        "${data['Nombre'] ?? ''} ${data['Apellido'] ?? ''}";
                    final String cedula = data['Cedula'] ?? 'S/C';

                    return ListTile(
                      onTap: () => _mostrarDetallesCliente(data),
                      leading: CircleAvatar(
                        backgroundColor: Colors.green.withValues(alpha: 0.1),
                        child: const Icon(
                          Icons.person_rounded,
                          color: Colors.green,
                        ),
                      ),
                      title: Text(
                        nombre,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text("Cédula: V-$cedula"),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.red,
                        ),
                        tooltip: "Eliminar Cliente",
                        onPressed: () => _confirmarEliminacion(cid, nombre),
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

  void _confirmarEliminacion(String id, String nombre) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Eliminar Cliente"),
        content: Text("¿Estás seguro de eliminar permanentemente a $nombre?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await widget.dbService.eliminarCliente(id, nombre);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Cliente eliminado")),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Eliminar"),
          ),
        ],
      ),
    );
  }
}

// --- Monitor de Errores ---
class MonitorErroresScreen extends StatelessWidget {
  const MonitorErroresScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = DatabaseService();
    return Scaffold(
      appBar: AppBar(
        title: const Text("Monitor de Errores"),
        backgroundColor: Colors.redAccent,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: db.streamErroresSistema(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text("No se han reportado errores técnicos."),
            );
          }

          final logs = snapshot.data!.docs;
          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final data = logs[index].data() as Map<String, dynamic>;
              final DateTime fecha =
                  (data['fecha'] as Timestamp?)?.toDate() ?? DateTime.now();

              return Card(
                margin: const EdgeInsets.only(bottom: 15),
                child: ExpansionTile(
                  leading: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red,
                  ),
                  title: Text(
                    data['contexto'] ?? "Error desconocido",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    "${fecha.day}/${fecha.month} ${fecha.hour}:${fecha.minute} - ${data['usuario']}",
                    style: const TextStyle(fontSize: 12),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Mensaje de Error:",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                          const SizedBox(height: 5),
                          SelectableText(
                            data['error'] ?? "Sin mensaje",
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                          ),
                          const Divider(),
                          Text("Dispositivo: ${data['dispositivo']}"),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
