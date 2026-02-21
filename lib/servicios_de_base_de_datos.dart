// servicios_de_base_de_datos.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'modelo_pedidos.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<Pedido>> streamPedidos({
    String? filtroTicket,
    String? filtroEstado,
    DateTime? fechaInicio,
    DateTime? fechaFin,
  }) { Query query = _db.collection('Pedidos').orderBy('fecha', descending: true);

    if (filtroTicket != null && filtroTicket.isNotEmpty) {
      query = query.where('N_ticket', isEqualTo: filtroTicket);
    }
    
    if (filtroEstado != null && filtroEstado != "Todos") {
      query = query.where('estado', isEqualTo: filtroEstado);
    }

    // Nota: El filtrado por fecha exacto en Firestore requiere un rango
    if (fechaInicio != null && fechaFin != null) {
      query = query.where('fecha', isGreaterThanOrEqualTo: fechaInicio)
                   .where('fecha', isLessThanOrEqualTo: fechaFin);
    }

    return query.snapshots().map(
      (snapshot) => snapshot.docs.map((doc) => Pedido.fromFirestore(doc)).toList(),
    );
  }

  // Nueva lógica para cancelar pedidos
  Future<void> cancelarPedido(String idDoc) async {
    await _db.collection('Pedidos').doc(idDoc).update({
      'estado': 'Cancelado',
      'fecha_cancelacion': FieldValue.serverTimestamp(),
      'cancelado_por': FirebaseAuth.instance.currentUser?.email,
    });
  }

  Future<void> despacharPedido(String idDoc, String nombreDespachador) async {
    await _db.collection('Pedidos').doc(idDoc).update({
      'estado': 'Despachado',
      'despachado_por': nombreDespachador, // Ahora guarda "Juan Pérez" en vez de correo
      'fecha_despacho': FieldValue.serverTimestamp(),
    });
  }
  
  Future<void> ajustarStock(String idDoc, int cambio, String nombreUsuario) async {
    final batch = _db.batch();
    final productoRef = _db.collection('Productos').doc(idDoc);
    final historialRef = _db.collection('Historial_Inventario').doc();

    batch.update(productoRef, {'stock': FieldValue.increment(cambio)});
    batch.set(historialRef, {
      'producto_id': idDoc,
      'cantidad_añadida': cambio,
      'usuario': nombreUsuario,
      'fecha': FieldValue.serverTimestamp(),
      'tipo': 'Carga de Inventario',
    });
    await batch.commit();
  }

  // FUNCIÓN CORREGIDA
  Future<void> crearPedidoYDescontar({
    required String categoriaHielo,
    required double monto,
    required String ticket,
    required Map<String, int> productosYCantidades, // Mapa para mixtos
    required String nombreCreador,
  }) async {
    WriteBatch batch = _db.batch();

    // 1. Crear el pedido
    DocumentReference nuevoPedido = _db.collection('Pedidos').doc();
    batch.set(nuevoPedido, {
      'tipo_hielo': {'categoria': categoriaHielo},
      'Monto_total': monto,
      'N_ticket': ticket,
      'estado': 'Pendiente',
      'fecha': FieldValue.serverTimestamp(),
      'creado_por': nombreCreador,
    });

    // 2. Descontar stock (Modo Venta Directa: solo descuenta si hay stock)
    for (var entry in productosYCantidades.entries) {
      DocumentReference productoRef = _db.collection('Productos').doc(entry.key);
      DocumentSnapshot snap = await productoRef.get();
      int stockActual = (snap.data() as Map<String, dynamic>)['stock'] ?? 0;

      if (stockActual > 0) {
        int aDescontar = (entry.value > stockActual) ? stockActual : entry.value;
        batch.update(productoRef, {'stock': FieldValue.increment(-aDescontar)});
      }
    }
    await batch.commit();
  }
}