import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io' show Platform;
import 'dart:convert';

// Imports para la nueva API v1
import 'package:googleapis_auth/auth_io.dart' as auth;
// a importación http ya no es necesaria con la API v1
// import 'package:http/http.dart' as http;

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Las credenciales de cuenta de servicio han sido eliminadas por seguridad.
  // El envío de mensajes debe realizarse desde un entorno seguro (Cloud Functions o Backend).

  Future<void> initNotifications() async {
    await _firebaseMessaging.requestPermission();
    await subscribeToStockAlerts();
    await _initLocalNotifications();
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification != null && (Platform.isAndroid || Platform.isIOS)) {
        _flutterLocalNotificationsPlugin.show(
          notification.hashCode,
          notification.title,
          notification.body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'stock_alerts_channel',
              'Alertas de Stock',
              channelDescription:
                  'Notificaciones sobre el estado del inventario.',
              icon: '@mipmap/launcher_icon',
              importance: Importance.max,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
        );
      }
    });
  }

  Future<void> subscribeToStockAlerts() async {
    try {
      await _firebaseMessaging.subscribeToTopic("stock_alerts");
    } catch (e) {
      debugPrint("Error al suscribirse al tema: $e");
    }
  }

  Future<void> enviarAlertaStockBajo(String producto, int cantidad) async {
    // El envío de notificaciones directas desde el cliente ha sido desactivado.
    // Implementar lógica en Firebase Functions que reaccione a cambios en el inventario.
    debugPrint(
      "SIMULACIÓN: Alerta de stock bajo para $producto ($cantidad unidades).",
    );
  }

  Future<void> saveTokenForCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await _firebaseMessaging.getToken();
    if (user == null || user.email == null || token == null) return;

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('Trabajadores')
          .where('correo', isEqualTo: user.email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) return;
      final workerDocId = querySnapshot.docs.first.id;
      await FirebaseFirestore.instance
          .collection('Trabajadores')
          .doc(workerDocId)
          .collection('tokens')
          .doc(token)
          .set({
            'token': token,
            'createdAt': FieldValue.serverTimestamp(),
            'platform': Platform.operatingSystem,
            'ultima_modificacion': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (e) {
      // print("Error al guardar token: $e");
    }
  }

  Future<void> _initLocalNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings();
    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );
    await _flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }
}
