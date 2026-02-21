import 'package:cloud_firestore/cloud_firestore.dart';

class Pedido {
  final String id;
  final String tipoHielo;
  final double monto;
  final String ticket;
  final String estado;
  final String? creadoPor;
  final String? despachadoPor;
  final DateTime? fecha;

  Pedido({
    required this.id,
    required this.tipoHielo,
    required this.monto,
    required this.ticket,
    required this.estado,
    this.creadoPor,
    this.despachadoPor,
    this.fecha,
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
    );
  }
}
