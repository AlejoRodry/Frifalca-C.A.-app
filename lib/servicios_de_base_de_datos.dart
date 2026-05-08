import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'modelo_pedidos.dart';
import 'servicios_de_notificaciones.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();

  // --- BITÁCORA (Privada para escritura) ---
  Future<void> _registrarEvento({
    required String accion,
    required String detalle,
    String? motivo,
    String? tipoMovimiento,
    String? productoId,
    int? cantidad,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      await _db.collection('Bitacora').add({
        'accion': accion,
        'usuario': user?.email ?? 'Desconocido',
        'nombre_usuario': user?.displayName ?? 'Usuario',
        'fecha': FieldValue.serverTimestamp(),
        'detalle': detalle,
        'motivo': motivo ?? 'No especificado',
        'tipo_movimiento': tipoMovimiento,
        'producto_id': productoId,
        'cantidad': cantidad,
        'ultima_modificacion': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Error al registrar en bitácora: $e");
    }
  }

  // --- LOG DE ERRORES (Público para reporte) ---
  Future<void> registrarErrorSistema({
    required String contexto,
    required String error,
    String? stackTrace,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      await _db.collection('LogsErrores').add({
        'contexto': contexto,
        'error': error.toString(),
        'stackTrace': stackTrace?.toString(),
        'usuario': user?.email ?? 'Desconocido',
        'fecha': FieldValue.serverTimestamp(),
        'dispositivo': kIsWeb ? 'Navegador Web' : 'Dispositivo Móvil',
      });
    } catch (e) {
      debugPrint("Falla crítica al registrar error de sistema: $e");
    }
  }

  Stream<QuerySnapshot> streamErroresSistema() {
    return _db
        .collection('LogsErrores')
        .orderBy('fecha', descending: true)
        .limit(50)
        .snapshots();
  }

  // --- BITÁCORA (Lectura Protegida) ---
  Stream<List<QueryDocumentSnapshot>> streamBitacora({
    String? filtroNombre,
    String? filtroCorreo,
    String? filtroAccion,
    DateTime? fechaInicio,
    DateTime? fechaFin,
  }) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      debugPrint(
        "ADVERTENCIA: Intento de lectura de bitácora sin sesión activa.",
      );
      return const Stream.empty();
    }

    // Validamos el rol de admin consultando Firestore antes de exponer el stream de Bitacora
    return _db
        .collection('Trabajadores')
        .where('correo', isEqualTo: user.email)
        .limit(1)
        .snapshots()
        .asyncExpand((userSnap) {
          if (userSnap.docs.isEmpty) {
            debugPrint("ADVERTENCIA: No se encontró perfil para ${user.email}");
            return const Stream.empty();
          }

          final data = userSnap.docs.first.data();
          final String rol = data['rol'] ?? 'Empleado';

          if (rol != 'admin') {
            debugPrint(
              "SEGURIDAD: Acceso denegado a Bitácora para el usuario: ${user.email} con rol: $rol",
            );
            return const Stream.empty();
          }

          // Consulta base optimizada por fecha.
          Query query = _db
              .collection('Bitacora')
              .orderBy('fecha', descending: true);

          if (fechaInicio != null) {
            query = query.where(
              'fecha',
              isGreaterThanOrEqualTo: Timestamp.fromDate(fechaInicio),
            );
          }
          if (fechaFin != null) {
            query = query.where(
              'fecha',
              isLessThanOrEqualTo: Timestamp.fromDate(fechaFin),
            );
          }

          return query.snapshots();
        })
        .map((snapshot) {
          List<QueryDocumentSnapshot> docs = snapshot.docs;

          if (filtroNombre != null && filtroNombre.isNotEmpty) {
            final f = filtroNombre.toLowerCase();
            docs = docs.where((doc) {
              final val =
                  (doc.data() as Map)['nombre_usuario']
                      ?.toString()
                      .toLowerCase() ??
                  '';
              return val.contains(f);
            }).toList();
          }

          if (filtroCorreo != null && filtroCorreo.isNotEmpty) {
            final f = filtroCorreo.toLowerCase();
            docs = docs.where((doc) {
              final val =
                  (doc.data() as Map)['usuario']?.toString().toLowerCase() ??
                  '';
              return val.contains(f);
            }).toList();
          }

          if (filtroAccion != null && filtroAccion.isNotEmpty) {
            final f = filtroAccion.toLowerCase();
            docs = docs.where((doc) {
              final val =
                  (doc.data() as Map)['accion']?.toString().toLowerCase() ?? '';
              return val.contains(f);
            }).toList();
          }

          return docs;
        });
  }

  /// Streaming simplificado de la Bitácora para el "Centro de Notificaciones"
  /// Accesible para todos los trabajadores registrados
  Stream<List<QueryDocumentSnapshot>> streamNotificaciones({int limite = 20}) {
    return _db
        .collection('Bitacora')
        .orderBy('fecha', descending: true)
        .limit(limite)
        .snapshots()
        .map((snapshot) => snapshot.docs);
  }

  // --- GESTIÓN DE CLIENTES ---
  Future<void> registrarCliente({
    required String nombre,
    required String apellido,
    required String cedula,
  }) async {
    try {
      await _db.collection('Clientes').add({
        'Nombre': nombre,
        'Apellido': apellido,
        'Cedula': cedula,
        'fecha_registro': FieldValue.serverTimestamp(),
        'numero_visitas': 0,
        'llave_busqueda': "${nombre.toLowerCase()} ${apellido.toLowerCase()}",
        'ultima_modificacion': FieldValue.serverTimestamp(),
      });
      await _registrarEvento(
        accion: 'CLIENTE_REGISTRADO',
        detalle: 'Se registró al cliente: $nombre $apellido (V-$cedula)',
      );
    } catch (e) {
      throw Exception("Error al registrar cliente: $e");
    }
  }

  Future<void> eliminarCliente(String id, String nombre) async {
    try {
      await _db.collection('Clientes').doc(id).delete();
      await _registrarEvento(
        accion: 'CLIENTE_ELIMINADO',
        detalle: 'Se eliminó al cliente: $nombre',
      );
    } catch (e) {
      throw Exception("Error al eliminar cliente: $e");
    }
  }

  // --- GESTIÓN DE USUARIOS (UID-based Security) ---
  Future<void> preAutorizarTrabajador({
    required String correo,
    required String nombre,
    required String apellido,
    required String rol,
  }) async {
    try {
      // Usamos el correo como ID del documento temporal para facilitar la búsqueda al registrarse
      final String emailId = correo.toLowerCase().replaceAll(' ', '');
      await _db.collection('PreAutorizaciones').doc(emailId).set({
        'email': emailId,
        'nombre': nombre,
        'apellido': apellido,
        'rol': rol,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'ultima_modificacion': FieldValue.serverTimestamp(),
      });

      await _registrarEvento(
        accion: 'USUARIO_PREAUTORIZADO',
        detalle: 'Se pre-autorizó el correo: $correo con rol: $rol',
      );
    } catch (e) {
      throw Exception("Error al pre-autorizar trabajador: $e");
    }
  }

  /// Vincula los datos de pre-autorización con el UID real del usuario al iniciar sesión.
  /// También asegura que el documento exista en la colección Trabajadores.
  Future<void> vincularTrabajadorAlRegistrarse() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) return;

      final String email = user.email!.toLowerCase().trim();
      final String uid = user.uid;

      // 1. Verificar si ya existe el perfil por UID
      final docReal = await _db.collection('Trabajadores').doc(uid).get();
      if (docReal.exists) return; // Ya está vinculado y configurado

      // 2. Buscar si hay una pre-autorización pendiente para este correo
      final preAuthDoc = await _db
          .collection('PreAutorizaciones')
          .doc(email)
          .get();

      if (preAuthDoc.exists) {
        final data = preAuthDoc.data()!;
        // Mover datos a la colección oficial usando UID como ID
        await _db.collection('Trabajadores').doc(uid).set({
          'uid': uid,
          'nombre': data['nombre'],
          'apellido': data['apellido'],
          'correo': email,
          'rol': data['rol'],
          'cargo': 'Personal', // Campo sugerido por el usuario
          'fecha_registro': FieldValue.serverTimestamp(),
          'completado': true,
          'ultima_modificacion': FieldValue.serverTimestamp(),
        });

        // Eliminar pre-autorización ya usada
        await _db.collection('PreAutorizaciones').doc(email).delete();

        await _registrarEvento(
          accion: 'USUARIO_VINCULADO',
          detalle: 'Perfil creado exitosamente para $email con UID: $uid',
        );
      } else {
        // 3. Si no hay pre-autorización, crear un perfil base para evitar bloqueos de seguridad
        // (Esto ocurre si el admin no lo pre-autorizó pero el usuario logró registrarse)
        await _db.collection('Trabajadores').doc(uid).set({
          'uid': uid,
          'nombre': user.displayName ?? 'Usuario',
          'apellido': '',
          'correo': email,
          'rol': 'Empleado', // Rol por defecto
          'cargo': 'Sin asignar',
          'fecha_registro': FieldValue.serverTimestamp(),
          'completado': false,
          'ultima_modificacion': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint("Error al vincular trabajador: $e");
    }
  }

  Stream<List<Pedido>> streamPedidos({
    String? filtroTicket,
    String? filtroEstado,
    DateTime? fechaInicio,
    DateTime? fechaFin,
  }) {
    try {
      // Consulta ultra-flexible: Sin ordenamiento en el servidor para evitar exclusiones
      Query query = _db.collection('Pedidos');

      if (filtroEstado != null && filtroEstado != "Todos") {
        query = query.where('estado', isEqualTo: filtroEstado);
      }

      if (fechaInicio != null && fechaFin != null) {
        query = query
            .where('fecha', isGreaterThanOrEqualTo: fechaInicio)
            .where('fecha', isLessThanOrEqualTo: fechaFin);
      }

      return query
          .snapshots()
          .map((snapshot) {
            // 1. Convertir y filtrar por Ticket manualmente
            List<Pedido> pedidos = snapshot.docs.map((doc) {
              return Pedido.fromFirestore(doc);
            }).toList();

            if (filtroTicket != null && filtroTicket.trim().isNotEmpty) {
              final String queryNormalizada = filtroTicket.trim().toLowerCase();
              pedidos = pedidos.where((p) {
                // Normalización y limpieza de espacios en blanco
                final String ticketNormalizado = p.ticket.trim().toLowerCase();
                return ticketNormalizado.contains(queryNormalizada);
              }).toList();
            }

            // 2. Ordenar manualmente (Descendente: los nuevos arriba)
            pedidos.sort((a, b) {
              final dateA = a.fecha ?? DateTime(2000);
              final dateB = b.fecha ?? DateTime(2000);
              return dateB.compareTo(dateA);
            });

            return pedidos;
          })
          .handleError((error) {
            debugPrint("-------------------------------------------");
            debugPrint("ERROR EN STREAM_PEDIDOS:");
            debugPrint("Detalle: $error");
            if (error.toString().contains("composite index")) {
              debugPrint(
                "NECESITAS UN ÍNDICE COMPUESTO. Revisa la consola de Firebase.",
              );
            }
            debugPrint("-------------------------------------------");

            // Reportar el error al log persistente
            registrarErrorSistema(
              contexto: "DatabaseService.streamPedidos",
              error: error.toString(),
            );
          });
    } catch (e) {
      debugPrint("Error al inicializar query en streamPedidos: $e");
      return const Stream.empty();
    }
  }

  Future<Pedido?> getPedidoById(String id) async {
    final doc = await _db.collection('Pedidos').doc(id).get();
    if (doc.exists) {
      return Pedido.fromFirestore(doc);
    }
    return null;
  }

  // Nueva lógica para cancelar pedidos
  Future<void> cancelarPedido(
    String idDoc, {
    int? cantSaco,
    int? cantBolsa,
  }) async {
    try {
      final batch = _db.batch();
      debugPrint("DEBUG: Intentando cancelar pedido $idDoc");

      batch.update(_db.collection('Pedidos').doc(idDoc), {
        'estado': 'Cancelado',
        'fecha_cancelacion': FieldValue.serverTimestamp(),
        'cancelado_por': FirebaseAuth.instance.currentUser?.email,
        'ultima_modificacion': FieldValue.serverTimestamp(),
      });

      // Liberar stock comprometido
      if (cantSaco != null && cantSaco > 0) {
        const idProdSaco = "NZAtCFwTfLTwb3xiiOUk";
        debugPrint(
          "DEBUG: Incrementando stock_comprometido en $idProdSaco por ${-cantSaco}",
        );

        // Verificación de consistencia: ¿Existe el campo?
        final snap = await _db.collection('Productos').doc(idProdSaco).get();
        if (!snap.exists ||
            !(snap.data() as Map).containsKey('stock_comprometido')) {
          debugPrint(
            "ADVERTENCIA: El campo 'stock_comprometido' no existe en $idProdSaco. Inicializando...",
          );
          batch.update(snap.reference, {'stock_comprometido': 0});
        }

        batch.update(_db.collection('Productos').doc(idProdSaco), {
          'stock_comprometido': FieldValue.increment(-cantSaco),
        });
      }

      if (cantBolsa != null && cantBolsa > 0) {
        const idProdBolsa = "DWDbVnRf5nqGu8uTu3KA";
        debugPrint(
          "DEBUG: Incrementando stock_comprometido en $idProdBolsa por ${-cantBolsa}",
        );

        final snap = await _db.collection('Productos').doc(idProdBolsa).get();
        if (!snap.exists ||
            !(snap.data() as Map).containsKey('stock_comprometido')) {
          debugPrint(
            "ADVERTENCIA: El campo 'stock_comprometido' no existe en $idProdBolsa. Inicializando...",
          );
          batch.update(snap.reference, {'stock_comprometido': 0});
        }

        batch.update(_db.collection('Productos').doc(idProdBolsa), {
          'stock_comprometido': FieldValue.increment(-cantBolsa),
        });
      }

      await batch.commit();

      await _registrarEvento(
        accion: 'PEDIDO_CANCELADO',
        detalle: 'Pedido ID: $idDoc marcado como Cancelado.',
      );
    } catch (e, stack) {
      debugPrint("ERROR CRÍTICO en cancelarPedido: $e");
      debugPrint("STACKTRACE: $stack");
      rethrow;
    }
  }

  // --- GESTIÓN DE TASA DE CAMBIO ---
  Stream<DocumentSnapshot> streamConfiguracionTasa() {
    return _db.collection('Configuraciones').doc('tasa_cambio').snapshots();
  }

  Future<double> obtenerTasaVigente() async {
    try {
      final doc = await _db
          .collection('Configuraciones')
          .doc('tasa_cambio')
          .get();
      if (!doc.exists) {
        // Inicializar si no existe
        await _db.collection('Configuraciones').doc('tasa_cambio').set({
          'usar_automatica': false,
          'valor_manual': 1.0,
          'ultima_bcv': 1.0,
          'fecha_actualizacion': FieldValue.serverTimestamp(),
        });
        return 1.0;
      }

      final data = doc.data() as Map<String, dynamic>;
      bool usarAuto = data['usar_automatica'] ?? false;
      double valorManual = (data['valor_manual'] ?? 0.0).toDouble();

      if (usarAuto) {
        try {
          // Uso de Proxy AllOrigins para evitar bloqueos de CORS en Flutter Web
          // La URL original se codifica para ser enviada como parámetro al proxy
          final String apiUrl = 'https://ve.dolarapi.com/v1/dolares/oficial';
          final response = await http.get(
            Uri.parse(
              'https://api.allorigins.win/get?url=${Uri.encodeComponent(apiUrl)}',
            ),
          );

          if (response.statusCode == 200) {
            // PRIMER jsonDecode: Desenvuelve el wrapper de AllOrigins
            // AllOrigins devuelve un objeto con la forma: {"contents": "string_con_el_json_real", ...}
            final wrapper = jsonDecode(response.body);
            final String contents = wrapper['contents'];

            // SEGUNDO jsonDecode: Decodifica el JSON real de la tasa contenido en 'contents'
            final json = jsonDecode(contents);

            // ve.dolarapi.com usa 'promedio' o 'price' para el valor oficial
            double bcvPrice = (json['promedio'] ?? json['price'] ?? 0.0)
                .toDouble();

            if (bcvPrice > 0) {
              await _db
                  .collection('Configuraciones')
                  .doc('tasa_cambio')
                  .update({
                    'ultima_bcv': bcvPrice,
                    'fecha_actualizacion': FieldValue.serverTimestamp(),
                  });
              return bcvPrice;
            }
          }
        } catch (apiError) {
          // Si el proxy falla o hay error de red, silenciamos y retornamos el valor manual configurado
          debugPrint(
            "Error crítico consultando Proxy AllOrigins/API: $apiError",
          );
        }
        return valorManual;
      } else {
        return valorManual;
      }
    } catch (e) {
      debugPrint("Error en obtenerTasaVigente: $e");
      return 1.0;
    }
  }

  Future<void> actualizarConfiguracionTasa({
    bool? usarAuto,
    double? valorManual,
  }) async {
    final Map<String, dynamic> data = {};
    if (usarAuto != null) {
      data['usar_automatica'] = usarAuto;
    }
    if (valorManual != null) {
      data['valor_manual'] = valorManual;
    }
    data['ultima_modificacion'] = FieldValue.serverTimestamp();

    await _db.collection('Configuraciones').doc('tasa_cambio').update(data);
    await _registrarEvento(
      accion: 'CONFIG_TASA_ACTUALIZADA',
      detalle: 'Se actualizó la configuración de la tasa de cambio.',
    );
  }

  // --- AJUSTES DEL SISTEMA ---
  Future<void> actualizarAjustesSistema({
    bool? notificacionesStockBajo,
    bool? actualizacionesAutomaticas,
    bool? calcularPreciosAuto,
    bool? mostrarPanelLateral,
    int? itemsPorPagina,
    bool? disenoCompacto,
    bool? disenoPedidosLargo,
  }) async {
    final Map<String, dynamic> data = {};
    if (notificacionesStockBajo != null) {
      data['notificaciones_stock_bajo'] = notificacionesStockBajo;
    }
    if (actualizacionesAutomaticas != null) {
      data['actualizaciones_automaticas'] = actualizacionesAutomaticas;
    }
    if (calcularPreciosAuto != null) {
      data['calcular_precios_auto'] = calcularPreciosAuto;
    }
    if (mostrarPanelLateral != null) {
      data['mostrar_panel_lateral'] = mostrarPanelLateral;
    }
    if (itemsPorPagina != null) {
      data['items_por_pagina'] = itemsPorPagina;
    }
    if (disenoCompacto != null) {
      data['diseno_compacto'] = disenoCompacto;
    }
    if (disenoPedidosLargo != null) {
      data['diseno_pedidos_largo'] = disenoPedidosLargo;
    }
    data['ultima_modificacion'] = FieldValue.serverTimestamp();

    await _db
        .collection('Configuraciones')
        .doc('ajustes_sistema')
        .set(data, SetOptions(merge: true));

    // Si calcularPreciosAuto cambió, sincronizamos con tasa_cambio por consistencia
    if (calcularPreciosAuto != null) {
      await _db.collection('Configuraciones').doc('tasa_cambio').update({
        'usar_automatica': calcularPreciosAuto,
        'ultima_modificacion': FieldValue.serverTimestamp(),
      });
    }

    await _registrarEvento(
      accion: 'AJUSTES_SISTEMA_ACTUALIZADOS',
      detalle: 'Se actualizaron los ajustes generales del sistema.',
    );
  }

  Stream<DocumentSnapshot> streamAjustesSistema() {
    return _db.collection('Configuraciones').doc('ajustes_sistema').snapshots();
  }

  Future<void> despacharPedido(
    String idDoc,
    String nombreDespachador,
    String rolDespachador, {
    int? cantSaco,
    int? cantBolsa,
  }) async {
    try {
      // VALIDACIÓN DE STOCK: Verificar stock suficiente antes de despachar
      // Los roles Admin y Supervisor pueden saltar esta validación (autorización especial)
      bool esAutorizado =
          rolDespachador == "admin" || rolDespachador == "supervisor";

      if (!esAutorizado) {
        if (cantSaco != null && cantSaco > 0) {
          const idProdSaco = "NZAtCFwTfLTwb3xiiOUk";
          final snapSaco = await _db
              .collection('Productos')
              .doc(idProdSaco)
              .get();
          if (snapSaco.exists) {
            final data = snapSaco.data() as Map?;
            int stockFisico = (data?['stock_fisico'] as num? ?? 0).toInt();
            if (stockFisico < cantSaco) {
              throw Exception(
                "Stock insuficiente. Se requiere autorización de un Supervisor o Admin para despachar sin stock físico.",
              );
            }
          }
        }

        if (cantBolsa != null && cantBolsa > 0) {
          const idProdBolsa = "DWDbVnRf5nqGu8uTu3KA";
          final snapBolsa = await _db
              .collection('Productos')
              .doc(idProdBolsa)
              .get();
          if (snapBolsa.exists) {
            final data = snapBolsa.data() as Map?;
            int stockFisico = (data?['stock_fisico'] as num? ?? 0).toInt();
            if (stockFisico < cantBolsa) {
              throw Exception(
                "Stock insuficiente. Se requiere autorización de un Supervisor o Admin para despachar sin stock físico.",
              );
            }
          }
        }
      }

      final batch = _db.batch();
      debugPrint(
        "DEBUG: Intentando despachar pedido $idDoc por $nombreDespachador",
      );

      batch.update(_db.collection('Pedidos').doc(idDoc), {
        'estado': 'Despachado',
        'despachado_por': nombreDespachador,
        'fecha_despacho': FieldValue.serverTimestamp(),
        'ultima_modificacion': FieldValue.serverTimestamp(),
      });

      // Restar de físico y liberar compromiso
      if (cantSaco != null && cantSaco > 0) {
        const idProdSaco = "NZAtCFwTfLTwb3xiiOUk";
        debugPrint("DEBUG: Despachando Saco ($idProdSaco): cantidad $cantSaco");

        final ref = _db.collection('Productos').doc(idProdSaco);
        final snap = await ref.get();

        if (!snap.exists) {
          debugPrint("ERROR: El producto $idProdSaco no existe.");
        } else {
          final data = snap.data() as Map?;
          Map<String, dynamic> initData = {};
          if (!data!.containsKey('stock_fisico')) {
            debugPrint(
              "ADVERTENCIA: 'stock_fisico' no existe en $idProdSaco. Inicializando...",
            );
            initData['stock_fisico'] = 0;
          }
          if (!data.containsKey('stock_comprometido')) {
            debugPrint(
              "ADVERTENCIA: 'stock_comprometido' no existe en $idProdSaco. Inicializando...",
            );
            initData['stock_comprometido'] = 0;
          }
          if (initData.isNotEmpty) batch.update(ref, initData);
        }

        // Escritura segura: Ambos campos en una sola operación
        batch.update(ref, {
          'stock_fisico': FieldValue.increment(-cantSaco),
          'stock_comprometido': FieldValue.increment(-cantSaco),
        });

        // --- DISPARADOR DE NOTIFICACIÓN DE STOCK BAJO ---
        try {
          final data = snap.data() as Map?;
          final int stockPrevio = (data?['stock_fisico'] as num? ?? 0).toInt();
          final int stockNuevo = stockPrevio - cantSaco;
          if (stockNuevo < 15) {
            _notificationService.notificarStockBajo("SACO", stockNuevo);
          }
        } catch (e) {
          debugPrint("Error en trigger de stock bajo (Saco): $e");
        }
      }

      if (cantBolsa != null && cantBolsa > 0) {
        const idProdBolsa = "DWDbVnRf5nqGu8uTu3KA";
        debugPrint(
          "DEBUG: Despachando Bolsa ($idProdBolsa): cantidad $cantBolsa",
        );

        final ref = _db.collection('Productos').doc(idProdBolsa);
        final snap = await ref.get();

        if (!snap.exists) {
          debugPrint("ERROR: El producto $idProdBolsa no existe.");
        } else {
          final data = snap.data() as Map?;
          Map<String, dynamic> initData = {};
          if (!data!.containsKey('stock_fisico')) {
            debugPrint(
              "ADVERTENCIA: 'stock_fisico' no existe en $idProdBolsa. Inicializando...",
            );
            initData['stock_fisico'] = 0;
          }
          if (!data.containsKey('stock_comprometido')) {
            debugPrint(
              "ADVERTENCIA: 'stock_comprometido' no existe en $idProdBolsa. Inicializando...",
            );
            initData['stock_comprometido'] = 0;
          }
          if (initData.isNotEmpty) batch.update(ref, initData);
        }

        batch.update(ref, {
          'stock_fisico': FieldValue.increment(-cantBolsa),
          'stock_comprometido': FieldValue.increment(-cantBolsa),
        });

        // --- DISPARADOR DE NOTIFICACIÓN DE STOCK BAJO ---
        try {
          final data = snap.data() as Map?;
          final int stockPrevio = (data?['stock_fisico'] as num? ?? 0).toInt();
          final int stockNuevo = stockPrevio - cantBolsa;
          if (stockNuevo < 15) {
            _notificationService.notificarStockBajo("BOLSA", stockNuevo);
          }
        } catch (e) {
          debugPrint("Error en trigger de stock bajo (Bolsa): $e");
        }
      }

      await batch.commit();

      await _registrarEvento(
        accion: 'PEDIDO_DESPACHADO',
        detalle: 'Pedido ID: $idDoc despachado por $nombreDespachador.',
      );
    } catch (e, stack) {
      debugPrint("ERROR CRÍTICO en despacharPedido: $e");
      debugPrint("STACKTRACE: $stack");
      rethrow;
    }
  }

  Future<void> ajustarStock(
    String idDoc,
    int cambio,
    String nombreUsuario, {
    String motivo = 'No especificado',
  }) async {
    try {
      debugPrint(
        "DEBUG: Ajustando stock de $idDoc con cambio: $cambio por $nombreUsuario | Motivo: $motivo",
      );

      // Verificación previa e inicialización
      final snap = await _db.collection('Productos').doc(idDoc).get();
      if (!snap.exists) {
        debugPrint(
          "ERROR: El producto $idDoc no existe al intentar ajustar stock.",
        );
      } else if (!(snap.data() as Map).containsKey('stock_fisico')) {
        debugPrint(
          "ADVERTENCIA: 'stock_fisico' no existe en $idDoc. Inicializando en 0...",
        );
        await _db.collection('Productos').doc(idDoc).update({
          'stock_fisico': 0,
        });
      }

      // VALIDACIÓN DE STOCK: Si el cambio es negativo, verificar que haya stock suficiente
      if (cambio < 0) {
        final data = snap.data() as Map?;
        int stockFisico = (data?['stock_fisico'] as num? ?? 0).toInt();
        if (stockFisico < -cambio) {
          throw Exception(
            "Stock insuficiente para realizar la operación. Stock disponible: $stockFisico",
          );
        }
      }

      // 1. Actualizar el stock físico (Usando .set con merge para robustez en Web)
      debugPrint("Intentando escribir en Productos ($idDoc)...");
      await _db.collection('Productos').doc(idDoc).set({
        'stock_fisico': FieldValue.increment(cambio),
        'ultima_modificacion': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint("¡Éxito en la actualización de stock!");

      // Determinar nombre del producto y tipo de movimiento
      String nombreProducto = idDoc == "NZAtCFwTfLTwb3xiiOUk"
          ? "SACO"
          : "BOLSA";
      String tipoMovimiento = cambio >= 0 ? 'ENTRADA' : 'SALIDA';

      // --- DISPARADOR DE NOTIFICACIÓN DE STOCK BAJO ---
      try {
        final int stockPrevio = (snap.data() as Map?)?['stock_fisico'] ?? 0;
        final int stockNuevo = stockPrevio + cambio;

        // Umbral de ejemplo: 15 unidades. Podría leerse de ajustes_sistema.
        if (stockNuevo < 15 && cambio < 0) {
          _notificationService.notificarStockBajo(nombreProducto, stockNuevo);
        }
      } catch (e) {
        debugPrint("Error en trigger de stock bajo: $e");
      }

      int cantidadAbsoluta = cambio.abs();

      // 2. Registrar en Bitácora con motivo
      await _registrarEvento(
        accion: 'AJUSTE_INVENTARIO',
        detalle:
            'Se ${cambio >= 0 ? "sumaron" : "restaron"} $cantidadAbsoluta $nombreProducto por [Motivo: $motivo] por el usuario $nombreUsuario',
        motivo: motivo,
        tipoMovimiento: tipoMovimiento,
        productoId: idDoc,
        cantidad: cambio,
      );

      // 3. Registrar en Historial_Inventario con motivo
      await _db.collection('Historial_Inventario').add({
        'producto_id': idDoc,
        'cantidad_añadida': cambio,
        'usuario': nombreUsuario,
        'fecha': FieldValue.serverTimestamp(),
        'tipo': 'Carga de Inventario',
        'motivo': motivo,
        'tipo_movimiento': tipoMovimiento,
        'ultima_modificacion': FieldValue.serverTimestamp(),
      });
    } catch (e, stack) {
      debugPrint("ERROR CRÍTICO en ajustarStock: $e");
      debugPrint("STACKTRACE: $stack");
      rethrow;
    }

    // 3. RE-ESCANEO REACTIVO (Trigger): Buscar pedidos "Naranja"
    final pedidosNaranja = await _db
        .collection('Pedidos')
        .where('estado', isEqualTo: 'Pendiente')
        .where('sin_stock', isEqualTo: true)
        .get();

    if (pedidosNaranja.docs.isNotEmpty) {
      // Obtenemos los stocks actuales actualizados
      final prodDocs = await _db.collection('Productos').get();
      Map<String, int> stocksDisponibles = {};

      for (var d in prodDocs.docs) {
        final data = d.data();
        int fisico = (data['stock_fisico'] as num? ?? 0).toInt();
        int comp = (data['stock_comprometido'] as num? ?? 0).toInt();
        stocksDisponibles[d.id] = fisico - comp;
      }

      WriteBatch batch = _db.batch();
      bool huboCambios = false;

      for (var pedidoDoc in pedidosNaranja.docs) {
        final data = pedidoDoc.data();
        int reqSaco = (data['tipo_hielo']?['cantidad_saco'] as num? ?? 0)
            .toInt();
        int reqBolsa = (data['tipo_hielo']?['cantidad_bolsa'] as num? ?? 0)
            .toInt();

        int dispSaco = stocksDisponibles["NZAtCFwTfLTwb3xiiOUk"] ?? 0;
        int dispBolsa = stocksDisponibles["DWDbVnRf5nqGu8uTu3KA"] ?? 0;

        // Un pedido deja de estar "Sin Stock" si para cada producto que requiere,
        // el stock físico es suficiente para cubrir el stock comprometido total.
        bool sacoOk = (reqSaco == 0 || dispSaco >= 0);
        bool bolsaOk = (reqBolsa == 0 || dispBolsa >= 0);

        if (sacoOk && bolsaOk) {
          batch.update(pedidoDoc.reference, {'sin_stock': false});
          huboCambios = true;
        }
      }

      if (huboCambios) await batch.commit();
    }
  }

  // FUNCIÓN CORREGIDA
  Future<void> crearPedidoYDescontar({
    required String categoriaHielo,
    required double monto,
    required String ticket,
    required Map<String, int> productosYCantidades, // Mapa para mixtos
    required String nombreCreador,
    String? orden,
    String? detalleSaco,
    String? detalleBolsa,
    String? idCliente,
    double? tasaAplicada,
  }) async {
    try {
      WriteBatch batch = _db.batch();
      debugPrint(
        "DEBUG: Iniciando creación de pedido. Ticket: $ticket, Creador: $nombreCreador",
      );

      // 1. Verificar si falta stock para marcar el pedido (PCA Logic)
      bool faltaStock = false;
      for (var entry in productosYCantidades.entries) {
        debugPrint(
          "DEBUG: Validando stock para producto ${entry.key} | Cantidad pedida: ${entry.value}",
        );

        DocumentSnapshot snap = await _db
            .collection('Productos')
            .doc(entry.key)
            .get();

        if (!snap.exists) {
          debugPrint("ERROR: El producto ${entry.key} NO EXISTE en Firestore.");
          continue;
        }

        final data = snap.data() as Map<String, dynamic>?;
        int fisico = data?['stock_fisico'] ?? 0;
        int comprometido = data?['stock_comprometido'] ?? 0;
        int disponible = fisico - comprometido;

        if (!data!.containsKey('stock_comprometido')) {
          debugPrint(
            "ADVERTENCIA: 'stock_comprometido' no existe en ${entry.key}.",
          );
        }

        if (disponible < entry.value) {
          faltaStock = true;
          debugPrint(
            "DEBUG: Insuficiente stock para ${entry.key}. Disponible: $disponible",
          );
        }
      }

      // 2. Crear el pedido
      DocumentReference nuevoPedido = _db.collection('Pedidos').doc();
      batch.set(nuevoPedido, {
        'tipo_hielo': {
          'categoria': categoriaHielo,
          'cantidad_saco': productosYCantidades["NZAtCFwTfLTwb3xiiOUk"] ?? 0,
          'cantidad_bolsa': productosYCantidades["DWDbVnRf5nqGu8uTu3KA"] ?? 0,
          'orden': orden,
          'detalle_saco': detalleSaco,
          'detalle_bolsa': detalleBolsa,
        },
        'Monto_total': monto,
        'N_ticket': ticket,
        'estado': 'Pendiente',
        'fecha': FieldValue.serverTimestamp(),
        'creado_por': nombreCreador,
        'sin_stock': faltaStock,
        'id_cliente': idCliente,
        'tasa_aplicada': tasaAplicada ?? 0.0,
        'ultima_modificacion': FieldValue.serverTimestamp(),
      });

      // 3. Aumentar stock comprometido (PCA Logic)
      for (var entry in productosYCantidades.entries) {
        debugPrint(
          "DEBUG: Incrementando stock_comprometido de ${entry.key} en +${entry.value}",
        );
        DocumentReference productoRef = _db
            .collection('Productos')
            .doc(entry.key);

        // Verificación de existencia del campo antes de incrementar
        final snap = await productoRef.get();
        if (snap.exists &&
            !(snap.data() as Map).containsKey('stock_comprometido')) {
          debugPrint(
            "ADVERTENCIA: 'stock_comprometido' no existe en ${entry.key}. Inicializando...",
          );
          batch.update(productoRef, {'stock_comprometido': 0});
        }

        batch.update(productoRef, {
          'stock_comprometido': FieldValue.increment(entry.value),
        });
      }
      await batch.commit();

      // 4. Notificación Automática (Prioridad ALTA vía GAS)
      _notificationService.notificarNuevoPedido(ticket, monto);

      await _registrarEvento(
        accion: 'PEDIDO_CREADO',
        detalle:
            'Ticket: $ticket | Categoría: $categoriaHielo | Monto: $monto Bs.',
      );
    } catch (e, stack) {
      debugPrint("ERROR CRÍTICO en crearPedidoYDescontar: $e");
      debugPrint("STACKTRACE: $stack");
      rethrow;
    }
  }

  Stream<List<Cita>> obtenerCitas() {
    return _db
        .collection('Citas')
        .orderBy('fecha', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => Cita.fromFirestore(doc)).toList(),
        );
  }

  Stream<List<Cita>> streamCitas(DateTime fecha) {
    return streamCitasDelDia(fecha);
  }

  Stream<List<Cita>> streamCitasDelDia(DateTime fecha) {
    // Filtrar por el día seleccionado (comienzo a fin)
    final inicio = DateTime(fecha.year, fecha.month, fecha.day);
    final fin = inicio.add(const Duration(days: 1));

    // Hemos simplificado la consulta eliminando el orderBy('slot')
    // para evitar la necesidad de crear un índice compuesto manual.
    // El ordenamiento se maneja automáticamente en la UI al asignar slots.
    return _db
        .collection('Citas')
        .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
        .where('fecha', isLessThan: Timestamp.fromDate(fin))
        .orderBy('fecha')
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) => Cita.fromFirestore(doc)).toList(),
        );
  }

  Future<void> agendarCita(Cita cita) async {
    try {
      await _db.collection('Citas').add({
        'nombre': cita.nombre,
        'motivo': cita.motivo,
        'fecha': Timestamp.fromDate(cita.fecha),
        'slot': cita.slot,
        'id_pedido': cita.idPedido,
        'id_cliente': cita.idCliente,
        'nombre_cliente': cita.nombreCliente,
        'color_etiqueta': cita.colorEtiqueta,
        'estado_agendado': cita.estadoAgendado,
        'creado_en': FieldValue.serverTimestamp(),
        'ultima_modificacion': FieldValue.serverTimestamp(),
        'creado_por': FirebaseAuth.instance.currentUser?.email,
      });

      await _registrarEvento(
        accion: 'CITA_AGENDADA',
        detalle:
            'Cita agendada para ${cita.nombreCliente ?? cita.nombre} en el slot ${cita.slot} para el día ${cita.fecha.day}/${cita.fecha.month}',
      );

      // --- DISPARADOR DE NOTIFICACIÓN DE CITA ---
      _notificationService.notificarCitaAgendada(
        cita.nombreCliente ?? cita.nombre,
        "${cita.fecha.day}/${cita.fecha.month}",
      );
    } catch (e) {
      debugPrint("Error en agendarCita: $e");
      rethrow;
    }
  }

  Future<void> crearCita({
    required String nombre,
    required String motivo,
    required DateTime fecha,
    required String slot,
    String? idPedido,
    String? idCliente,
    String? nombreCliente,
    String colorEtiqueta = "#FFA500",
    bool estadoAgendado = false,
  }) async {
    await agendarCita(
      Cita(
        id: '',
        nombre: nombre,
        motivo: motivo,
        fecha: fecha,
        slot: slot,
        idPedido: idPedido,
        idCliente: idCliente,
        nombreCliente: nombreCliente,
        colorEtiqueta: colorEtiqueta,
        estadoAgendado: estadoAgendado,
      ),
    );
  }

  /// Cancela una cita y la elimina de la agenda, registrando en bitácora.
  Future<void> cancelarCita(String idCita, {String? motivo}) async {
    // Leemos la cita antes de eliminarla para dejar registro
    final doc = await _db.collection('Citas').doc(idCita).get();
    String detalle = 'Cita ID: $idCita eliminada.';
    if (doc.exists) {
      final d = doc.data() as Map<String, dynamic>;
      detalle =
          'Cita cancelada para ${d['nombre_cliente'] ?? d['nombre']} slot ${d['slot']}. Motivo: ${motivo ?? 'No especificado'}';
    }
    await _db.collection('Citas').doc(idCita).delete();
    await _registrarEvento(accion: 'CITA_CANCELADA', detalle: detalle);
  }

  /// Reagenda una cita a una nueva fecha y slot de hora.
  Future<void> reagendarCita(
    String idCita,
    DateTime nuevaFecha,
    String nuevoSlot,
  ) async {
    await _db.collection('Citas').doc(idCita).update({
      'fecha': Timestamp.fromDate(nuevaFecha),
      'slot': nuevoSlot,
      'estado_agendado': false,
      'color_etiqueta': '#FFA500',
      'ultima_modificacion': FieldValue.serverTimestamp(),
    });
    await _registrarEvento(
      accion: 'CITA_REAGENDADA',
      detalle:
          'Cita ID: $idCita reagendada al ${nuevaFecha.day}/${nuevaFecha.month}/${nuevaFecha.year} a las $nuevoSlot.',
    );
  }

  /// Marca la cita como completada (retirada). Si tiene un pedido asociado, lo despacha también.
  Future<void> marcarCitaComoRetirada({
    required String idCita,
    required String? idPedido,
    required String despachadorNombre,
    required String despachadorRol,
    int cantSaco = 0,
    int cantBolsa = 0,
  }) async {
    // 1. Marcar la cita como completada
    await _db.collection('Citas').doc(idCita).update({
      'estado_agendado': true,
      'color_etiqueta': '#4CAF50',
      'ultima_modificacion': FieldValue.serverTimestamp(),
    });

    // 2. Si hay pedido asociado, despacharlo automáticamente
    if (idPedido != null && idPedido.isNotEmpty) {
      try {
        final pedidoDoc = await _db.collection('Pedidos').doc(idPedido).get();
        if (pedidoDoc.exists) {
          final pedidoData = pedidoDoc.data() as Map<String, dynamic>;
          final String estadoActual = pedidoData['estado'] ?? 'Pendiente';
          // Solo despachar si aún está Pendiente (evitar doble despacho)
          if (estadoActual == 'Pendiente') {
            await despacharPedido(
              idPedido,
              despachadorNombre,
              despachadorRol,
              cantSaco: cantSaco,
              cantBolsa: cantBolsa,
            );
          }
        }
      } catch (e) {
        debugPrint('Error al despachar pedido asociado a cita: $e');
      }
    }
  }

  Future<void> actualizarEstadoAgendado(String idCita, bool completado) async {
    await _db.collection('Citas').doc(idCita).update({
      'estado_agendado': completado,
      'color_etiqueta': completado ? "#4CAF50" : "#FFA500", // Verde vs Naranja
      'ultima_modificacion': FieldValue.serverTimestamp(),
    });
  }

  // --- FUNCIÓN DE AUDITORÍA ---
  Future<Map<String, int>> verificarStockReal(String productoId) async {
    try {
      final doc = await _db.collection('Productos').doc(productoId).get();
      if (!doc.exists) return {'fisico': 0, 'comprometido': 0};

      final data = doc.data() as Map<String, dynamic>;
      return {
        'fisico': (data['stock_fisico'] as num? ?? 0).toInt(),
        'comprometido': (data['stock_comprometido'] as num? ?? 0).toInt(),
      };
    } catch (e) {
      debugPrint("Error en auditoría verificarStockReal: $e");
      return {'fisico': 0, 'comprometido': 0};
    }
  }

  Future<void> actualizarPedido({
    required String id,
    required String categoriaHielo,
    required double monto,
    required String ticket,
    required Map<String, int> productosYCantidades,
    required String nombreCreador,
    required Map<String, int> cantPrevia, // Para ajustar stockComprometido
    String? orden,
    String? detalleSaco,
    String? detalleBolsa,
    String? idCliente,
    double? tasaAplicada,
  }) async {
    try {
      WriteBatch batch = _db.batch();

      // 1. Ajustar stock comprometido (Revertir previo, aplicar nuevo)
      for (var entry in productosYCantidades.entries) {
        final idProd = entry.key;
        final nuevaCant = entry.value;
        final viejaCant = cantPrevia[idProd] ?? 0;
        final delta = nuevaCant - viejaCant;

        if (delta != 0) {
          batch.update(_db.collection('Productos').doc(idProd), {
            'stock_comprometido': FieldValue.increment(delta),
          });
        }
      }

      // 2. Actualizar el pedido
      batch.update(_db.collection('Pedidos').doc(id), {
        'tipo_hielo.categoria': categoriaHielo,
        'tipo_hielo.cantidad_saco':
            productosYCantidades["NZAtCFwTfLTwb3xiiOUk"] ?? 0,
        'tipo_hielo.cantidad_bolsa':
            productosYCantidades["DWDbVnRf5nqGu8uTu3KA"] ?? 0,
        'tipo_hielo.orden': orden,
        'tipo_hielo.detalle_saco': detalleSaco,
        'tipo_hielo.detalle_bolsa': detalleBolsa,
        'Monto_total': monto,
        'N_ticket': ticket,
        'creado_por': nombreCreador,
        'id_cliente': idCliente,
        'tasa_aplicada': tasaAplicada,
        'ultima_modificacion': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      await _registrarEvento(
        accion: 'PEDIDO_ACTUALIZADO',
        detalle: 'Ticket: $ticket | ID: $id actualizado por $nombreCreador',
      );
    } catch (e) {
      debugPrint("Error al actualizar pedido: $e");
      rethrow;
    }
  }

  Stream<List<Pedido>> getVentasSemanales() {
    final DateTime sieteDiasAtras = DateTime.now().subtract(
      const Duration(days: 7),
    );
    return _db
        .collection('Pedidos')
        .where('estado', isEqualTo: 'Despachado')
        .where(
          'fecha',
          isGreaterThanOrEqualTo: Timestamp.fromDate(sieteDiasAtras),
        )
        .orderBy('fecha', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => Pedido.fromFirestore(doc)).toList(),
        );
  }

  Stream<List<Pedido>> streamVentasFiltradas(
    String filtro, {
    DateTime? fechaInicio,
    DateTime? fechaFin,
  }) {
    DateTime now = DateTime.now();
    DateTime inicio;
    DateTime? fin;

    switch (filtro) {
      case 'Día':
        inicio = DateTime(now.year, now.month, now.day);
        break;
      case 'Semana':
        inicio = now.subtract(Duration(days: now.weekday - 1));
        inicio = DateTime(inicio.year, inicio.month, inicio.day);
        break;
      case 'Mes':
        inicio = DateTime(now.year, now.month, 1);
        break;
      case 'Año':
        inicio = DateTime(now.year, 1, 1);
        break;
      case 'Personalizado':
        if (fechaInicio != null) {
          inicio = fechaInicio;
          fin = fechaFin;
        } else {
          inicio = now.subtract(const Duration(days: 7));
        }
        break;
      default:
        inicio = now.subtract(const Duration(days: 7));
    }

    Query query = _db
        .collection('Pedidos')
        .where('estado', isEqualTo: 'Despachado')
        .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio));

    if (fin != null) {
      query = query.where(
        'fecha',
        isLessThanOrEqualTo: Timestamp.fromDate(fin),
      );
    }

    return query
        .orderBy('fecha', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => Pedido.fromFirestore(doc)).toList(),
        );
  }

  // --- GESTIÓN DE TRABAJADORES (ADMIN) ---
  Stream<List<QueryDocumentSnapshot>> streamTrabajadores() {
    return _db.collection('Trabajadores').snapshots().map((snap) => snap.docs);
  }

  Stream<List<QueryDocumentSnapshot>> streamClientes() {
    return _db.collection('Clientes').snapshots().map((snap) => snap.docs);
  }

  Future<void> actualizarEstadoTrabajador(String uid, bool bloqueado) async {
    await _db.collection('Trabajadores').doc(uid).update({
      'bloqueado': bloqueado,
      'ultima_modificacion': FieldValue.serverTimestamp(),
    });

    await _registrarEvento(
      accion: bloqueado ? 'USUARIO_BLOQUEADO' : 'USUARIO_DESBLOQUEADO',
      detalle:
          'Se ${bloqueado ? "bloqueó" : "desbloqueó"} al usuario con UID: $uid',
    );
  }

  Future<void> eliminarTrabajador(String uid) async {
    final doc = await _db.collection('Trabajadores').doc(uid).get();
    final data = doc.data();
    final email = data?['correo'] ?? 'Desconocido';

    await _db.collection('Trabajadores').doc(uid).delete();

    await _registrarEvento(
      accion: 'USUARIO_ELIMINADO',
      detalle: 'Se eliminaró al usuario: $email con UID: $uid',
    );
  }

  dynamic _sanitizeFirestoreData(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toIso8601String();
    } else if (value is GeoPoint) {
      return {'lat': value.latitude, 'lng': value.longitude};
    } else if (value is DocumentReference) {
      return value.path;
    } else if (value is Map) {
      final Map<String, dynamic> newMap = {};
      value.forEach((k, v) {
        newMap[k as String] = _sanitizeFirestoreData(v);
      });
      return newMap;
    } else if (value is List) {
      return value.map((v) => _sanitizeFirestoreData(v)).toList();
    }
    return value;
  }

  // --- SISTEMA DE RESPALDO (BACKUP) ---
  /// Recolecta todos los datos de las colecciones principales para generar un backup.
  Future<Map<String, dynamic>> generarDatosRespaldo() async {
    final Map<String, dynamic> backup = {
      'fecha_creacion': DateTime.now().toIso8601String(),
      'app': 'Frifalca C.A.',
      'datos': {},
    };

    final colecciones = [
      'Productos',
      'Pedidos',
      'Clientes',
      'Trabajadores',
      'Citas',
      'Bitacora',
      'Configuraciones',
    ];

    for (String col in colecciones) {
      final snap = await _db.collection(col).get();
      backup['datos'][col] = snap.docs.map((doc) {
        final data = doc.data();
        data['id_documento'] = doc.id; // Preservar el ID original
        return _sanitizeFirestoreData(data);
      }).toList();
    }

    return backup;
  }
}
