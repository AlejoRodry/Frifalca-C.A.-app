import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'modelo_pedidos.dart';
import 'logic/inventory_manager.dart';
import 'servicios_de_notificaciones.dart'; // Importamos el servicio de notificaciones

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final InventoryManager _inventoryManager = InventoryManager();
  final NotificationService _notificationService = NotificationService(); // Instanciamos el servicio

  // Límite de stock para enviar notificaciones
  static const int _limiteStockSacos = 10;
  static const int _limiteStockBolsas = 20;

  Stream<List<Pedido>> streamPedidos({
    String? filtroTicket,
    String? filtroEstado,
    DateTime? fechaInicio,
    DateTime? fechaFin,
  }) {
    Query query = _db.collection('Pedidos').orderBy('fecha', descending: true);

    if (filtroTicket != null && filtroTicket.isNotEmpty) {
      query = query.where('N_ticket', isEqualTo: filtroTicket);
    }
    if (filtroEstado != null && filtroEstado != "Todos") {
      query = query.where('estado', isEqualTo: filtroEstado);
    }
    if (fechaInicio != null && fechaFin != null) {
      query = query.where('fecha', isGreaterThanOrEqualTo: fechaInicio).where('fecha', isLessThanOrEqualTo: fechaFin);
    }
    return query.snapshots().map((snapshot) => snapshot.docs.map((doc) => Pedido.fromFirestore(doc)).toList());
  }

  Future<void> cancelarPedido(String idDoc) async {
    await _db.collection('Pedidos').doc(idDoc).update({
      'estado': 'Cancelado',
      'fecha_cancelacion': FieldValue.serverTimestamp(),
      'cancelado_por': FirebaseAuth.instance.currentUser?.email,
    });
  }

  Future<void> despacharPedido(String idDoc, String nombreDespachador, Pedido pedido) async {
    final bool stockSuficiente = await _inventoryManager.hayStockSuficiente(pedido.cantidadSacos, pedido.cantidadBolsas);
    if (!stockSuficiente) throw Exception('No hay stock suficiente para despachar este pedido.');

    final batch = _db.batch();
    final pedidoRef = _db.collection('Pedidos').doc(idDoc);

    batch.update(pedidoRef, {
      'estado': 'Despachado',
      'despachado_por': nombreDespachador,
      'fecha_despacho': FieldValue.serverTimestamp(),
    });

    if (pedido.cantidadSacos > 0) {
      final productoRef = _db.collection('Productos').doc("NZAtCFwTfLTwb3xiiOUk");
      batch.update(productoRef, {'stock': FieldValue.increment(-pedido.cantidadSacos)});
    }
    if (pedido.cantidadBolsas > 0) {
      final productoRef = _db.collection('Productos').doc("DWDbVnRf5nqGu8uTu3KA");
      batch.update(productoRef, {'stock': FieldValue.increment(-pedido.cantidadBolsas)});
    }

    await batch.commit();

    // Después de confirmar la transacción, verificamos el stock.
    await _verificarStockYNotificar();
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

    // Después de ajustar, verificamos el stock.
    await _verificarStockYNotificar();
  }

  Future<void> crearPedido({
    required String categoriaHielo,
    required double monto,
    required String ticket,
    required String nombreCreador,
    required String orden,
    String? subTipoSaco,
    String? subTipoBolsa,
    int? cantSaco,
    int? cantBolsa,
  }) async {
    final bool stockSuficiente = await _inventoryManager.hayStockSuficiente(cantSaco ?? 0, cantBolsa ?? 0);
    if (!stockSuficiente) throw Exception('No hay stock suficiente para crear este pedido.');

    WriteBatch batch = _db.batch();
    DocumentReference nuevoPedido = _db.collection('Pedidos').doc();
    batch.set(nuevoPedido, {
      'tipo_hielo': {
        'categoria': categoriaHielo,
        'orden': orden,
        'detalle_saco': subTipoSaco,
        'detalle_bolsa': subTipoBolsa,
        'cantidad_saco': cantSaco,
        'cantidad_bolsa': cantBolsa,
      },
      'Monto_total': monto,
      'N_ticket': ticket,
      'estado': 'Pendiente',
      'fecha': FieldValue.serverTimestamp(),
      'creado_por': nombreCreador,
    });
    await batch.commit();
  }

  // --- NUEVA FUNCIÓN PRIVADA PARA VERIFICAR Y NOTIFICAR ---
  Future<void> _verificarStockYNotificar() async {
    try {
      final docSacos = await _db.collection('Productos').doc("NZAtCFwTfLTwb3xiiOUk").get();
      final stockSacos = docSacos.data()?['stock'] as int? ?? 0;

      if (stockSacos <= _limiteStockSacos) {
        await _notificationService.enviarAlertaStockBajo("Sacos de Hielo", stockSacos);
      }

      final docBolsas = await _db.collection('Productos').doc("DWDbVnRf5nqGu8uTu3KA").get();
      final stockBolsas = docBolsas.data()?['stock'] as int? ?? 0;

      if (stockBolsas <= _limiteStockBolsas) {
        await _notificationService.enviarAlertaStockBajo("Bolsas de Hielo", stockBolsas);
      }
    } catch (e) {
      // print("Error al verificar stock para notificación: $e");
      // No relanzamos la excepción para no afectar la operación principal del usuario
    }
  }
}
