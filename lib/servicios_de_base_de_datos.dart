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
        });
      }
    } catch (e) {
      debugPrint("Error al guardar token: $e");
    }
  }

  Future<void> enviarNotificacionGlobal(String titulo, String cuerpo) async {
    // Funcionalidad desactivada en el cliente para proteger credenciales.
    debugPrint("Simulación de notificación (Backend requerido): $titulo");
  }

  // --- BITÁCORA (Privada) ---
  Future<void> _registrarEvento({
    required String accion,
    required String detalle,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      await _db.collection('Bitacora').add({
        'accion': accion,
        'detalle': detalle,
        'fecha': FieldValue.serverTimestamp(),
        'usuario': user?.email ?? 'Desconocido',
      });
    } catch (e) {
      debugPrint("Error al registrar en bitácora: $e");
    }
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
      await _db
          .collection('PreAutorizaciones')
          .doc(correo.toLowerCase().trim())
          .set({
            'correo': correo.toLowerCase().trim(),
            'nombre': nombre,
            'apellido': apellido,
            'rol': rol,
            'fecha_preautorizacion': FieldValue.serverTimestamp(),
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

  // Nueva lógica para cancelar pedidos
  Future<void> cancelarPedido(
    String idDoc, {
    int? cantSaco,
    int? cantBolsa,
  }) async {
    final batch = _db.batch();
    batch.update(_db.collection('Pedidos').doc(idDoc), {
      'estado': 'Cancelado',
      'fecha_cancelacion': FieldValue.serverTimestamp(),
      'cancelado_por': FirebaseAuth.instance.currentUser?.email,
    });

    // Liberar stock comprometido
    if (cantSaco != null && cantSaco > 0) {
      batch.update(_db.collection('Productos').doc("NZAtCFwTfLTwb3xiiOUk"), {
        'stock_comprometido': FieldValue.increment(-cantSaco),
      });
    }
    if (cantBolsa != null && cantBolsa > 0) {
      batch.update(_db.collection('Productos').doc("DWDbVnRf5nqGu8uTu3KA"), {
        'stock_comprometido': FieldValue.increment(-cantBolsa),
      });
    }
    await batch.commit();

    await _registrarEvento(
      accion: 'PEDIDO_CANCELADO',
      detalle: 'Pedido ID: $idDoc marcado como Cancelado.',
    );
  }

  Future<void> despacharPedido(
    String idDoc,
    String nombreDespachador, {
    int? cantSaco,
    int? cantBolsa,
  }) async {
    final batch = _db.batch();
    batch.update(_db.collection('Pedidos').doc(idDoc), {
      'estado': 'Despachado',
      'despachado_por': nombreDespachador,
      'fecha_despacho': FieldValue.serverTimestamp(),
    });

    // Restar de físico y liberar compromiso
    if (cantSaco != null && cantSaco > 0) {
      final ref = _db.collection('Productos').doc("NZAtCFwTfLTwb3xiiOUk");
      batch.update(ref, {
        'stock_fisico': FieldValue.increment(-cantSaco),
        'stock_comprometido': FieldValue.increment(-cantSaco),
      });
    }
    if (cantBolsa != null && cantBolsa > 0) {
      final ref = _db.collection('Productos').doc("DWDbVnRf5nqGu8uTu3KA");
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
  }

  Future<void> ajustarStock(
    String idDoc,
    int cambio,
    String nombreUsuario,
  ) async {
    final FirebaseFirestore db = FirebaseFirestore.instance;

    // 1. Actualizar el stock físico
    await db.collection('Productos').doc(idDoc).update({
      'stock_fisico': FieldValue.increment(cambio),
    });

    // 2. Registrar en historial
    await db.collection('Historial_Inventario').add({
      'producto_id': idDoc,
      'cantidad_añadida': cambio,
      'usuario': nombreUsuario,
      'fecha': FieldValue.serverTimestamp(),
      'tipo': 'Carga de Inventario',
    });

    // 3. RE-ESCANEO REACTIVO (Trigger): Buscar pedidos "Naranja"
    final pedidosNaranja = await db
        .collection('Pedidos')
        .where('estado', isEqualTo: 'Pendiente')
        .where('sin_stock', isEqualTo: true)
        .get();

    if (pedidosNaranja.docs.isNotEmpty) {
      // Obtenemos los stocks actuales actualizados
      final prodDocs = await db.collection('Productos').get();
      Map<String, int> stocksDisponibles = {};

      for (var d in prodDocs.docs) {
        final data = d.data();
        int fisico = data['stock_fisico'] ?? 0;
        int comp = data['stock_comprometido'] ?? 0;
        stocksDisponibles[d.id] = fisico - comp;
      }

      WriteBatch batch = db.batch();
      bool huboCambios = false;

      for (var pedidoDoc in pedidosNaranja.docs) {
        final data = pedidoDoc.data();
        int reqSaco = data['tipo_hielo']?['cantidad_saco'] ?? 0;
        int reqBolsa = data['tipo_hielo']?['cantidad_bolsa'] ?? 0;

        int dispSaco = stocksDisponibles["NZAtCFwTfLTwb3xiiOUk"] ?? 0;
        int dispBolsa = stocksDisponibles["DWDbVnRf5nqGu8uTu3KA"] ?? 0;

        // Si ahora hay stock suficiente, pasa a Normal (sin_stock: false)
        if (dispSaco >= reqSaco && dispBolsa >= reqBolsa) {
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
    String? idCliente,
  }) async {
    WriteBatch batch = _db.batch();

    // 1. Verificar si falta stock para marcar el pedido (PCA Logic)
    bool faltaStock = false;
    for (var entry in productosYCantidades.entries) {
      DocumentSnapshot snap = await _db
          .collection('Productos')
          .doc(entry.key)
          .get();
      final data = snap.data() as Map<String, dynamic>?;
      int fisico = data?['stock_fisico'] ?? 0;
      int comprometido = data?['stock_comprometido'] ?? 0;
      int disponible = fisico - comprometido;

      if (disponible < entry.value) {
        faltaStock = true;
        break;
      }
    }

    // 2. Crear el pedido
    DocumentReference nuevoPedido = _db.collection('Pedidos').doc();
    batch.set(nuevoPedido, {
      'tipo_hielo': {
        'categoria': categoriaHielo,
        'cantidad_saco': productosYCantidades["NZAtCFwTfLTwb3xiiOUk"] ?? 0,
        'cantidad_bolsa': productosYCantidades["DWDbVnRf5nqGu8uTu3KA"] ?? 0,
      },
      'Monto_total': monto,
      'N_ticket': ticket,
      'estado': 'Pendiente',
      'fecha': FieldValue.serverTimestamp(),
      'creado_por': nombreCreador,
      'sin_stock': faltaStock,
      'id_cliente': idCliente,
    });

    // 3. Aumentar stock comprometido (PCA Logic)
    for (var entry in productosYCantidades.entries) {
      DocumentReference productoRef = _db
          .collection('Productos')
          .doc(entry.key);
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
  }

  Stream<List<Cita>> streamCitas(DateTime fecha) {
    // Filtrar por el día seleccionado (comienzo a fin)
    final inicio = DateTime(fecha.year, fecha.month, fecha.day);
    final fin = inicio.add(const Duration(days: 1));

    return _db
        .collection('Citas')
        .where('fecha', isGreaterThanOrEqualTo: inicio)
        .where('fecha', isLessThan: fin)
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) => Cita.fromFirestore(doc)).toList(),
        );
  }

  Future<void> crearCita({
    required String nombre,
    required String motivo,
    required DateTime fecha,
    required String slot,
  }) async {
    await _db.collection('Citas').add({
      'nombre': nombre,
      'motivo': motivo,
      'fecha': Timestamp.fromDate(fecha),
      'slot': slot,
      'creado_en': FieldValue.serverTimestamp(),
    });
  }
}
