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
  });

  // Convierte el mapa de Firestore en un objeto Pedido
  factory Pedido.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Pedido(
      id: doc.id,
      tipoHielo: data['tipo_hielo']?['categoria'] ?? 'Sin categoría',
      // Usamos .toDouble() sobre el valor numérico de forma segura
      monto: (data['Monto_total'] ?? 0).toDouble(),
      ticket: data['N_ticket'] ?? 'No asignado',
      estado: data['estado'] ?? 'Pendiente',
      creadoPor: data['creado_por'],
      despachadoPor: data['despachado_por'],
      fecha: (data['fecha'] as Timestamp?)?.toDate(),
      sinStock: data['sin_stock'] ?? false,
      cantSaco: data['tipo_hielo']?['cantidad_saco'] ?? 0,
      cantBolsa: data['tipo_hielo']?['cantidad_bolsa'] ?? 0,
      idCliente: data['id_cliente'],
    );
  }
}

class Cita {
  final String id;
  final String nombre;
  final String motivo;
  final DateTime fecha;
  final String slot; // Formato HH:mm

  Cita({
    required this.id,
    required this.nombre,
    required this.motivo,
    required this.fecha,
    required this.slot,
  });

  factory Cita.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Cita(
      id: doc.id,
      nombre: data['nombre'] ?? '',
      motivo: data['motivo'] ?? '',
      fecha: (data['fecha'] as Timestamp?)?.toDate() ?? DateTime.now(),
      slot: data['slot'] ?? '',
    );
  }
}
