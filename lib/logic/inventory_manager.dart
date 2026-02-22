import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class InventoryManager {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final _stockController = StreamController<Map<String, int>>.broadcast();
  Stream<Map<String, int>> get stockStream => _stockController.stream;

  InventoryManager() {
    _db.collection('Productos').snapshots().listen((snapshot) {
      final stock = <String, int>{};
      for (var doc in snapshot.docs) {
        stock[doc.id] = doc.data()['stock'] as int? ?? 0;
      }
      _stockController.add(stock);
    });
  }

  Future<bool> hayStockSuficiente(int sacosNecesarios, int bolsasNecesarias) async {
    final snapshot = await _db.collection('Productos').get();
    int sacosEnStock = 0;
    int bolsasEnStock = 0;

    for (var doc in snapshot.docs) {
      if (doc.id == "NZAtCFwTfLTwb3xiiOUk") {
        sacosEnStock = doc.data()['stock'] as int? ?? 0;
      } else if (doc.id == "DWDbVnRf5nqGu8uTu3KA") {
        bolsasEnStock = doc.data()['stock'] as int? ?? 0;
      }
    }

    return sacosEnStock >= sacosNecesarios && bolsasEnStock >= bolsasNecesarias;
  }

  void dispose() {
    _stockController.close();
  }
}
