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
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // Credenciales de la cuenta de servicio (reemplazadas por el usuario)
  final Map<String, dynamic> _credentials = {
    "type": "service_account",
    "project_id": "frifalca-db",
    "private_key_id": "dd237893386916e62d60e83191581b65d0352897",
    "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDOiQAw5OAfTupJ\nTgNDLrFX7cPny27qNuyyxAuYg/y9BFZHd0GVhxo08bFdLP0k5IAz80VMhMgFmSZC\n29O3FOQtQbhbVBIWPQZ++1hvPwhEsJe9UqO3RAIae2FHE27k7+b3kDbEitq/3Kr/\nwfCja/M+FYzO4t6hcNdRrI74AXgv20uLuXT8NbHQNzrtfQ4BrFahO1flc9JePwTD\nKeM1V5KdPs6fiSqCFysJeSpLfU9v/A+LlDjV+YQGRaIkOEYYu42eiiph8IsY97dn\njumCbpmrpXhw6RbXd2C5H5SY1Grhgw3O9vwaUXCknGPMzyiaU7r+/MDrjN7LWpAP\nbeKMSdsJAgMBAAECggEAHACEJ5zobCZBapXqqFGs1ryUWpmA3L18oxIkdlWyzxfG\n8OKQ4EqUeYgpYXYnjjhyz1hU1XaNPgERKHBwiHqLIz2tVqiT2TMF7fJ6/34+yz1c\nHV2Wd9L/LAL9YesXFnAWUwtY+ZXP6cJr5sgvLaEFti2qzSQCRkYr01V/fs2IM4ic\nGTmT5E5UmpJJlcXA9DB7QUSLxcPyZ0iDh8ng+Z0pS2tVUgKAN33Gs/ZK5+qqZMAp\nHADF3rSMdpgEh7KBfTS5y5yUI5YBGFyCeH35QMw1xZ97vq0MR1fZZYp3lU1xwCn7\nFT01G1cwV/ijBLCli+VGL9mlsSIFfy4oeDR0h3rdrwKBgQDstrxZy/qVs2nJgqMC\nmMrnAqQXGOHjk8lB7c2Hbh/IA6U+U29yt84ZCzhftceMUJzdqX8w0HL1o2N5dqu2\nguGvaNPNOFY6ndDxnIDGBT/l3DeOMv4s5YCZTkNXCx12vTKpS4hKR20NkbFnsdJq\nLeKTB6e8SewIwq0bsUMWbBw7lwKBgQDfXNAg/0ZONAb9DFApv9HScsoadQWEgCFK\n6dVmd5+oWxc68wH07WROM4ZUmQkeKuxqekPhtB9dY5qwjwmF7XWE8ZP4hWBE+ZXf\nZEYNvkgrVmMV/JvuChqZOOCO+uShyFQLZQr4R5jPfCo9VqZrWI2edk6QLwbD/g5m\nMmBsGb3yXwKBgB0qityZmH+XgqJUmVc5kk6Scbty0mpjDDo2XcuhEwNnB5Y9W48L\n/LXzPvf0AulUCW/6cXSHSpLfleMibxfm2n3tcaNonJ9OUK9kdC1x+iSNVL8No2nO\nwWCiVwPDl9bIixR2/Q0B7frtB6naLC3vB2rMV6uIhC+0JPYziiuaGIRzAoGBAIrB\n9MXa78kbRxAiexZEhMuQ5f6jnebfVk9cjmaWf8ettvO3DQskAoEWPygE3gYwsie/\nhrYLGMUCYJG4ejkJ+Ey7aqoj6VdQGYvqlh5pjBnoE6wP/qpU+osfK1mHgUsD0To2\n7iapC8QxpWfvkXj0TR4Y7ttha3mMNVPFjeL55udPAoGBAMybmjhTFL9HB5G1plYj\nRXLe70nAc+gFFlwCA9RiokZNnBTkXqgnuKAwdaJn2hPwKyvzIf+G0PicZdI/KlQi\nzeGWWZHhhO97VtHThwwtUxgeOxesWSDXPxi6cY77OtOpcO74j+PTPNozCFt8nfF5\niZ2V8ZklbIMQV5FROk3Z7rfk\n-----END PRIVATE KEY-----\n",
    "client_email": "firebase-adminsdk-fbsvc@frifalca-db.iam.gserviceaccount.com",
    "client_id": "115675586180457717106",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token",
    "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
    "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/firebase-adminsdk-fbsvc%40frifalca-db.iam.gserviceaccount.com",
    "universe_domain": "googleapis.com"
  };

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
              channelDescription: 'Notificaciones sobre el estado del inventario.',
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
      // print("Suscrito al tema 'stock_alerts' correctamente.");
    } catch (e) {
      // print("Error al suscribirse al tema: $e");
    }
  }

  Future<void> enviarAlertaStockBajo(String producto, int cantidad) async {
    final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

    try {
      final client = await auth.clientViaServiceAccount(
        auth.ServiceAccountCredentials.fromJson(_credentials),
        scopes,
      );

      final projectId = _credentials['project_id'];
      
      final url = 'https://fcm.googleapis.com/v1/projects/$projectId/messages:send';

      /* final response = */ await client.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': {
            'topic': 'stock_alerts',
            'notification': {
              'title': '⚠️ Alerta de Inventario',
              'body': 'El producto "$producto" tiene solo $cantidad unidades restantes.',
            },
            'android': {
              'priority': 'high',
              'notification': {'channel_id': 'stock_alerts_channel'},
            },
            'data': {
               'click_action': 'FLUTTER_NOTIFICATION_CLICK',
               'tipo': 'stock_bajo',
            }
          }
        }),
      );

      // print('Respuesta de Firebase (API v1): ${response.statusCode} - ${response.body}');

      client.close();

    } catch (e) {
      // print("Excepción al enviar notificación con API v1: $e");
    }
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
      });
    } catch (e) {
      // print("Error al guardar token: $e");
    }
  }

  Future<void> _initLocalNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings();
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );
    await _flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }
}
