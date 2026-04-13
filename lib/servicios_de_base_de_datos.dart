import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'modelo_pedidos.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // --- NOTIFICACIONES ---
  // IMPORTANTE: La lógica de envío de notificaciones directas (FCM V1) ha sido eliminada por seguridad.
  // Estas operaciones deben realizarse desde un servidor seguro o Firebase Functions.

  Future<void> guardarTokenDispositivo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _db.collection('TokensNotificacion').doc(user.uid).set({
          'token': token,
          'email': user.email,
          'ultima_actualizacion': FieldValue.serverTimestamp(),
          'ultima_modificacion': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint("Error al guardar token: $e");
    }
  }

  Future<void> enviarNotificacionGlobal(String titulo, String cuerpo) async {
    // Funcionalidad desactivada en el cliente para proteger credenciales.
    debugPrint("Simulación de notificación (Backend requerido): $titulo");
  }

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

  // --- BITÁCORA (Lectura Protegida) ---
  Stream<List<QueryDocumentSnapshot>> streamBitacora({
    String? filtroNombre,
    String? filtroCorreo,
    String? filtroAccion,
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
          // El filtrado de texto se hará localmente para permitir case-insensitive (toLowerCase)
          // y evitar errores de 'indices compuestos' en NoSQL si no están creados.
          return _db
              .collection('Bitacora')
              .orderBy('fecha', descending: true)
              .snapshots();
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
    Query query = _db.collection('Pedidos').orderBy('fecha', descending: true);

    if (filtroTicket != null && filtroTicket.isNotEmpty) {
      query = query
          .where('N_ticket', isGreaterThanOrEqualTo: filtroTicket)
          .where('N_ticket', isLessThanOrEqualTo: '$filtroTicket\uf8ff');
    }

    if (filtroEstado != null && filtroEstado != "Todos") {
      query = query.where('estado', isEqualTo: filtroEstado);
    }

    // Nota: El filtrado por fecha exacto en Firestore requiere un rango
    if (fechaInicio != null && fechaFin != null) {
      query = query
          .where('fecha', isGreaterThanOrEqualTo: fechaInicio)
          .where('fecha', isLessThanOrEqualTo: fechaFin);
    }

    return query.snapshots().map(
      (snapshot) =>
          snapshot.docs.map((doc) => Pedido.fromFirestore(doc)).toList(),
    );
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

  Future<void> despacharPedido(
    String idDoc,
    String nombreDespachador, {
    int? cantSaco,
    int? cantBolsa,
  }) async {
    try {
      // VALIDACIÓN DE STOCK: Verificar stock suficiente antes de despachar
      if (cantSaco != null && cantSaco > 0) {
        const idProdSaco = "NZAtCFwTfLTwb3xiiOUk";
        final snapSaco = await _db.collection('Productos').doc(idProdSaco).get();
        if (snapSaco.exists) {
          final data = snapSaco.data() as Map?;
          int stockFisico = (data?['stock_fisico'] as num? ?? 0).toInt();
          if (stockFisico < cantSaco) {
            throw Exception("Stock insuficiente para realizar la operación. Stock disponible de sacos: $stockFisico");
          }
        }
      }

      if (cantBolsa != null && cantBolsa > 0) {
        const idProdBolsa = "DWDbVnRf5nqGu8uTu3KA";
        final snapBolsa = await _db.collection('Productos').doc(idProdBolsa).get();
        if (snapBolsa.exists) {
          final data = snapBolsa.data() as Map?;
          int stockFisico = (data?['stock_fisico'] as num? ?? 0).toInt();
          if (stockFisico < cantBolsa) {
            throw Exception("Stock insuficiente para realizar la operación. Stock disponible de bolsas: $stockFisico");
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
          throw Exception("Stock insuficiente para realizar la operación. Stock disponible: $stockFisico");
        }
      }

      // 1. Actualizar el stock físico (Usando .set con merge para robustez en Web)
      debugPrint("Intentando escribir en Productos ($idDoc)...");
      await _db.collection('Productos').doc(idDoc).set({
        'stock_fisico': FieldValue.increment(cambio),
        'ultima_modificacion': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint("¡Éxito en la actualización de stock!");

      // Determinar tipo de movimiento y nombre del producto
      String tipoMovimiento = cambio >= 0 ? 'ENTRADA' : 'SALIDA';
      String nombreProducto = idDoc == "NZAtCFwTfLTwb3xiiOUk" ? "SACO" : "BOLSA";
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

      // 4. Notificación Automática (Fuera del batch pero reactivo)
      enviarNotificacionGlobal(
        "¡Nuevo Pedido Registrado!",
        "Ticket: $ticket - Monto: $monto Bs. por $nombreCreador",
      );

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

    return _db
        .collection('Citas')
        .where('fecha', isGreaterThanOrEqualTo: inicio)
        .where('fecha', isLessThan: fin)
        .orderBy('fecha')
        .orderBy('slot')
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) => Cita.fromFirestore(doc)).toList(),
        );
  }

  Future<void> agendarCita(Cita cita) async {
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
    });
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

  Future<void> cancelarCita(String idCita) async {
    await _db.collection('Citas').doc(idCita).delete();
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

  Stream<List<Pedido>> streamVentasFiltradas(String filtro) {
    DateTime now = DateTime.now();
    DateTime inicio;

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
      default:
        inicio = now.subtract(const Duration(days: 7));
    }

    return _db
        .collection('Pedidos')
        .where('estado', isEqualTo: 'Despachado')
        .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
        .orderBy('fecha', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => Pedido.fromFirestore(doc)).toList(),
        );
  }
}
