import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import 'dart:convert';

enum NotifPriority { alta, media, baja }

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Configuración de GAS (Google Apps Script)
  // Reemplazar con la URL de la Web App desplegada y tu propia API Key
  static const String _gasWebAppUrl =
      "https://script.google.com/macros/s/AKfycbwdvAxcqffTVqn8_4faDftfGOnjUOayASdR6WU1wN1ey1BofXbkdKIWjulRnbxOjluH/exec";
  static const String _notifApiKey = "Frifalca.1978#";

  Future<void> initNotifications() async {
    await _firebaseMessaging.requestPermission();
    await subscribeToStockAlerts();
    await _initLocalNotifications();

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification != null && (Platform.isAndroid || Platform.isIOS)) {
        _flutterLocalNotificationsPlugin.show(
          id: notification.hashCode,
          title: notification.title,
          body: notification.body,
          notificationDetails: const NotificationDetails(
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

  /// Envía una notificación a través del puente Google Apps Script (GAS)
  Future<void> enviarNotificacionGAS({
    String? token,
    String? topic,
    required String titulo,
    required String cuerpo,
    required NotifPriority prioridad,
  }) async {
    try {
      // Si la prioridad es ALTA, se dispara de inmediato sin esperar (Fire and Forget opcional o await rápido)
      final bool esUrgente = prioridad == NotifPriority.alta;

      final Map<String, dynamic> payload = {
        "api_key": _notifApiKey,
        "token": token,
        "topic": topic,
        "title": titulo,
        "body": cuerpo,
        "priority": prioridad.name,
      };

      debugPrint("Enviando notificación GAS (${prioridad.name}): $titulo");

      // Usamos un timeout corto para que la app no se cuelgue si el GAS tarda en responder
      final response = await http
          .post(
            Uri.parse(_gasWebAppUrl),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(payload),
          )
          .timeout(Duration(seconds: esUrgente ? 5 : 10));

      if (response.statusCode != 200) {
        debugPrint(
          "Error en respuesta GAS: ${response.statusCode} - ${response.body}",
        );
      }
    } catch (e) {
      debugPrint("Error al enviar notificación vía GAS: $e");
      // El error se silencia para que la app continúe su flujo normal
    }
  }

  // Métodos auxiliares para disparadores comunes
  Future<void> notificarNuevoPedido(String ticket, double monto) async {
    await enviarNotificacionGAS(
      topic: "stock_alerts",
      titulo: "¡Nuevo Pedido Registrado!",
      cuerpo: "Ticket: $ticket por un monto de $monto Bs.",
      prioridad: NotifPriority.alta,
    );
  }

  Future<void> notificarStockBajo(String producto, int cantidad) async {
    await enviarNotificacionGAS(
      topic: "stock_alerts",
      titulo: "⚠️ Alerta de Stock Bajo",
      cuerpo:
          "El producto $producto tiene solo $cantidad unidades disponibles.",
      prioridad: NotifPriority.alta,
    );
  }

  Future<void> notificarCitaAgendada(String cliente, String fecha) async {
    await enviarNotificacionGAS(
      topic: "stock_alerts",
      titulo: "📅 Nueva Cita Agendada",
      cuerpo: "Cliente: $cliente para el día $fecha.",
      prioridad: NotifPriority.media,
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
      // Silenciar errores de guardado de token
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
    await _flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
    );
  }

  /// Envía el respaldo completo a Google Drive a través del puente GAS
  Future<bool> subirRespaldoDrive(Map<String, dynamic> datosJson) async {
    try {
      final Map<String, dynamic> payload = {
        "api_key": _notifApiKey,
        "action": "BACKUP",
        "file_name":
            "Respaldo_Frifalca_${DateTime.now().day}_${DateTime.now().month}.json",
        "content": datosJson,
      };

      final response = await http
          .post(
            Uri.parse(_gasWebAppUrl),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(payload),
          )
          .timeout(
            const Duration(seconds: 30),
          ); // Damos tiempo para procesar el archivo

      // GAS puede responder 200 o 302 (redirección post-ejecución), ambos son éxito
      final exito = response.statusCode >= 200 && response.statusCode < 400;
      if (!exito) {
        debugPrint(
          "Error GAS Drive: código ${response.statusCode} - ${response.body}",
        );
      }
      return exito;
    } catch (e) {
      debugPrint("Error al subir respaldo a Drive: $e");
      return false;
    }
  }
}
