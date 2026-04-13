import 'package:cloud_firestore/cloud_firestore.dart';

// Fragmento 1 de seguridad (FCM)
const String kS1 = "AAAA";

class Pedido {
  final String id;
  final String tipoHielo;
  final double monto;
  final String ticket;
  final String estado;
  final String? creadoPor;
  final String? despachadoPor;
  final DateTime? fecha;
  final bool sinStock;
  final int cantSaco;
  final int cantBolsa;

  final String? idCliente;
  final String? orden;
  final String? detalleSaco;
  final String? detalleBolsa;

  Pedido({
    required this.id,
    required this.tipoHielo,
    required this.monto,
    required this.ticket,
    required this.estado,
    this.creadoPor,
    this.despachadoPor,
    this.fecha,
    this.sinStock = false,
    this.cantSaco = 0,
    this.cantBolsa = 0,
    this.idCliente,
    this.orden,
    this.detalleSaco,
    this.detalleBolsa,
  });

  // Convierte el mapa de Firestore en un objeto Pedido de forma 100% segura
  factory Pedido.fromFirestore(DocumentSnapshot doc) {
    // 1. Extraemos data asegurando que no sea nulo
    final data = (doc.data() as Map<String, dynamic>?) ?? {};

    // 2. Implementamos el 'mapa seguro' para tipo_hielo solicitado
    final Map<String, dynamic> infoHielo =
        (data['tipo_hielo'] as Map<String, dynamic>?) ?? {};

    return Pedido(
      id: doc.id,
      // Acceso seguro a sub-campos de tipo_hielo
      tipoHielo: infoHielo['categoria']?.toString() ?? 'Sin categoría',

      // Seguridad en campos raíz usando el operador ??
      monto: (data['Monto_total'] ?? 0).toDouble(),
      ticket: data['N_ticket']?.toString() ?? 'No asignado',
      estado: data['estado'] ?? 'Pendiente',
      creadoPor: data['creado_por']?.toString(),
      despachadoPor: data['despachado_por']?.toString(),
      fecha: (data['fecha'] as Timestamp?)?.toDate(),
      sinStock: data['sin_stock'] ?? false,

      // Valores por defecto seguros para sub-campos numéricos y de texto
      cantSaco: (infoHielo['cantidad_saco'] ?? 0).toInt(),
      cantBolsa: (infoHielo['cantidad_bolsa'] ?? 0).toInt(),
      idCliente: data['id_cliente']?.toString(),
      orden:
          infoHielo['orden']?.toString() ?? 'Saco', // Valor por defecto sensato
      detalleSaco: infoHielo['detalle_saco']?.toString() ?? 'Saco Público',
      detalleBolsa: infoHielo['detalle_bolsa']?.toString() ?? 'Bolsa Público',
    );
  }
}

class Cita {
  final String id;
  final String
  nombre; // Se mantiene por compatibilidad, pero se usará nombreCliente predominantemente
  final String motivo;
  final DateTime fecha;
  final String slot; // Formato HH:mm
  final String? idPedido;
  final String? idCliente;
  final String? nombreCliente;
  final String colorEtiqueta;
  final bool estadoAgendado;

  Cita({
    required this.id,
    required this.nombre,
    required this.motivo,
    required this.fecha,
    required this.slot,
    this.idPedido,
    this.idCliente,
    this.nombreCliente,
    this.colorEtiqueta = "#FFA500", // Naranja por defecto (Por buscar)
    this.estadoAgendado = false,
  });

  factory Cita.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    DateTime fechaValidada = DateTime.now();
    try {
      final rawFecha = data['fecha'];
      if (rawFecha is Timestamp) {
        fechaValidada = rawFecha.toDate();
      } else if (rawFecha is String) {
        fechaValidada = DateTime.tryParse(rawFecha) ?? DateTime.now();
      }
    } catch (_) {
      // Fallback a DateTime.now() en caso de error
    }

    return Cita(
      id: doc.id,
      nombre: data['nombre'] ?? '',
      motivo: data['motivo'] ?? '',
      fecha: fechaValidada,
      slot: data['slot'] ?? '',
      idPedido: data['id_pedido'],
      idCliente: data['id_cliente'],
      nombreCliente: data['nombre_cliente'],
      colorEtiqueta: data['color_etiqueta'] ?? "#FFA500",
      estadoAgendado: data['estado_agendado'] ?? false,
    );
  }

  /// Verifica si la cita debe marcarse como completada basándose en el estado del pedido.
  bool debeMarcarseComoCompletada(String? estadoPedido) {
    if (idPedido == null || estadoPedido == null) return false;
    // Si el pedido está 'Despachado' y la cita no está 'Completada', debe actualizarse.
    return estadoPedido == 'Despachado' && !estadoAgendado;
  }
}
