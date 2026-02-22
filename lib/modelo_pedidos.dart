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
  final int cantidadSacos;
  final int cantidadBolsas;

  Pedido({
    required this.id,
    required this.tipoHielo,
    required this.monto,
    required this.ticket,
    required this.estado,
    this.creadoPor,
    this.despachadoPor,
    this.fecha,
    required this.cantidadSacos,
    required this.cantidadBolsas,
  });

  factory Pedido.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final tipoHieloData = data['tipo_hielo'] as Map<String, dynamic>? ?? {};

    return Pedido(
      id: doc.id,
      tipoHielo: tipoHieloData['categoria'] ?? 'Sin categoría',
      monto: (data['Monto_total'] ?? 0).toDouble(),
      ticket: data['N_ticket'] ?? 'No asignado',
      estado: data['estado'] ?? 'Pendiente',
      creadoPor: data['creado_por'],
      despachadoPor: data['despachado_por'],
      fecha: (data['fecha'] as Timestamp?)?.toDate(),
      cantidadSacos: tipoHieloData['cantidad_saco'] ?? 0,
      cantidadBolsas: tipoHieloData['cantidad_bolsa'] ?? 0,
    );
  }
}
