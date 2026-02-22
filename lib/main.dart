import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'panel_principal.dart';
import 'servicios_de_notificaciones.dart'; // Importar el servicio

final LocalAuthentication auth = LocalAuthentication();
final NotificationService _notificationService = NotificationService(); // Instancia del servicio

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await _notificationService.initNotifications(); // Inicializar notificaciones
  runApp(const InicialSesion());
}

class InicialSesion extends StatelessWidget {
  const InicialSesion({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frifalca',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      initialRoute: '/',
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return const PanelPrincipal();
          }
          return const Login(title: 'Iniciar Sesión');
        },
      ),
    );
  }
}

class Login extends StatefulWidget {
  final String title;

  const Login({super.key, required this.title});

  @override
  State<Login> createState() => _Login();
}

class _Login extends State<Login> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final NotificationService _notificationService = NotificationService();
  bool _mantenerSesion = false;
  bool _oscurecerPassword = true;
  String? _usuarioRecordado;
  String? _correoRecordado;
  String? _passwordRecordado;
  String _mensajeError = "";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cargarUsuarioRecordado();
    });
  }

  Future<void> _cargarUsuarioRecordado() async {
    final prefs = await SharedPreferences.getInstance();
    final nombreGuardado = prefs.getString('user_name');
    final correoGuardado = prefs.getString('correo_recordado');
    _passwordRecordado = prefs.getString('user_password');

    if (!mounted) return;

    if (nombreGuardado != null || correoGuardado != null) {
      setState(() {
        _usuarioRecordado = nombreGuardado ?? correoGuardado;
        _correoRecordado = correoGuardado;
        _emailController.text = correoGuardado ?? "";
      });
    }
  }

  Future<void> _autenticarConHuella() async {
    try {
      bool puedeAutenticar =
        await auth.canCheckBiometrics || await auth.isDeviceSupported();
      if (!puedeAutenticar) return;

      bool autenticado = await auth.authenticate(
        localizedReason: 'Usa tu huella para entrar a Frifalca',
      );

      if (!mounted) return;

      if (autenticado && _correoRecordado != null && _passwordRecordado != null) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _correoRecordado!,
          password: _passwordRecordado!,
        );
        // Guardar token después de la autenticación con huella
        await _notificationService.saveTokenForCurrentUser();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mensajeError = "Error de huella: $e";
      });
    }
  }

  Future<void> _procesarLogin() async {
    final messenger = ScaffoldMessenger.of(context);
    String input = _emailController.text.trim();
    String password = _passwordController.text.trim();

    if (input.isEmpty || password.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Rellena todos los campos")),
      );
      return;
    }

    try {
      String emailFinal = input;
      String nombreDeUsuarioParaGuardar = input; 

      var query = await FirebaseFirestore.instance
        .collection('Trabajadores')
        .where(input.contains('@') ? 'correo' : 'usuario', isEqualTo: input)
        .get();

      if (query.docs.isNotEmpty) {
        var datos = query.docs.first.data();
        emailFinal = datos['correo'];
        nombreDeUsuarioParaGuardar = datos['usuario'];
      } else if (!input.contains('@')) {
        messenger.showSnackBar(const SnackBar(content: Text("Usuario no encontrado")));
        return;
      }

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailFinal,
        password: password,
      );

      // Guardar token después del login
      await _notificationService.saveTokenForCurrentUser();
      
      final prefs = await SharedPreferences.getInstance();
      if (_mantenerSesion || _usuarioRecordado != null) {
        await prefs.setString('correo_recordado', emailFinal);
        await prefs.setString('user_name', nombreDeUsuarioParaGuardar); 
        await prefs.setString('user_password', password);
      } else {
        await prefs.clear();
      }
    } on FirebaseAuthException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(_traducirError(e.code)), backgroundColor: Colors.red),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Error inesperado: $e")));
    }
  }

  String _traducirError(String code) {
    switch (code) {
      case 'user-not-found':
        return "El usuario no existe.";
      case 'wrong-password':
        return "Contraseña incorrecta.";
      case 'network-request-failed':
        return "Error de conexión a internet.";
      default:
        return "Error al intentar entrar. Revisa tus datos.";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Frifalca"), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          children: [
            Image.asset(
              'assets/frifalca6.png',
              height: 120,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 10),
            Text(
              _usuarioRecordado != null
                  ? "¡Hola, $_usuarioRecordado!"
                  : "Iniciar Sesión",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            if (_usuarioRecordado == null) ...[
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: "Usuario o Correo",
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            
            const SizedBox(height: 20),
            TextField(
              controller: _passwordController,
              obscureText: _oscurecerPassword,
              decoration: InputDecoration(
                labelText: "Contraseña",
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _oscurecerPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _oscurecerPassword = !_oscurecerPassword),
                ),
              ),
            ),
            const SizedBox(height: 20),

            if (_usuarioRecordado == null)
              CheckboxListTile (
                title: const Text("Mantener sesión activa"),
                value: _mantenerSesion,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                onChanged: (val) => setState(() => _mantenerSesion = val!),
              ), 

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: _procesarLogin,
              child: const Text("Entrar"),
            ),

            if (_mensajeError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(_mensajeError, style: const TextStyle(color: Colors.red)),
              ),

            if (_usuarioRecordado != null) ...[
              const SizedBox(height: 20),
              const Divider(),
              IconButton(
                icon: const Icon(Icons.fingerprint, size: 60, color: Colors.blue),
                onPressed: _autenticarConHuella,
              ),
              const Text("Ingresar con huella"),
              TextButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.clear();
                  setState(() {
                    _usuarioRecordado = null;
                    _correoRecordado = null;
                    _mantenerSesion = false;
                    _emailController.clear();
                    _passwordController.clear();
                  });
                },
                child: const Text("Usar otra cuenta"),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
