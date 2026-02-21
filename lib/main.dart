import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // <--- ESTA ES LA QUE FALTA
import 'dart:async'; // <--- PARA EVITAR ERRORES DE FUTURE
import 'panel_principal.dart';

final LocalAuthentication auth = LocalAuthentication();
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const InicialSesion());
}

class InicialSesion extends StatelessWidget {
  const InicialSesion({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frifalca',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      initialRoute: '/',
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // Si el snapshot tiene datos, el usuario ya está logueado
          if (snapshot.hasData) {
            return const PanelPrincipal();
          }
          // Si no, mostrar login
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
  bool _mantenerSesion = false;
  bool _oscurecerPassword = true;
  String? _usuarioRecordado;
  String? _correoRecordado;
  String? _passwordRecordado;
  String _mensajeError = ""; // Para capturar errores sin romper la app

  @override
  void initState() {
    super.initState();
    // Usamos addPostFrameCallback para esperar a que el widget esté construido
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cargarUsuarioRecordado();
    });
  }

  Future<void> _cargarUsuarioRecordado() async {
    final prefs = await SharedPreferences.getInstance();
    final nombreGuardado = prefs.getString('user_name');
    final correoGuardado = prefs.getString('correo_recordado');
    _passwordRecordado = prefs.getString('user_password');

    // Siempre verificar mounted después de un await de SharedPreferences
    if (!mounted) return;

    if (nombreGuardado != null || correoGuardado != null) {
      setState(() {
        // Priorizamos el nombre de usuario para el saludo, si no, el correo
        _usuarioRecordado = nombreGuardado ?? correoGuardado;
        _correoRecordado = correoGuardado;
        // Autocompletamos el campo de texto con lo que el usuario usó la última vez
        _emailController.text = correoGuardado ?? "";
      });
    }
  }

  Future<void> _autenticarConHuella() async {
    try {
      // 1. Verificamos disponibilidad
      bool puedeAutenticar =
        await auth.canCheckBiometrics || await auth.isDeviceSupported();
      if (!puedeAutenticar) return;

      // 2. Autenticamos (Sintaxis corregida sin 'options')
      bool autenticado = await auth.authenticate(
        localizedReason: 'Usa tu huella para entrar a Frifalca',
      );

      // 3. CONTROL CRÍTICO DE MONTAJE (Evita el error de dispose)
      if (!mounted) return;

      if (autenticado &&
          _correoRecordado != null &&
          _passwordRecordado != null) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _correoRecordado!,
          password: _passwordRecordado!,
        );
      }
    } catch (e) {
      if (!mounted) return; // Protección ante errores asíncronos
      setState(() {
        _mensajeError = "Error de huella: $e";
      });
    }
  }

  Future<void> _procesarLogin() async {
    debugPrint("Botón presionado. Usuario: ${_emailController.text}");
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
        nombreDeUsuarioParaGuardar = datos['usuario']; // <--- ESTO ASEGURA QUE SIEMPRE SEA EL NICKNAME
      } else if (!input.contains('@')) {
        // Si no hay '@' y no se encontró en Firestore
        messenger.showSnackBar(const SnackBar(content: Text("Usuario no encontrado")));
        return;
      }

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailFinal,
        password: password,
      );
      
      // 2. Guardar el nombre para mostrar el "¡Hola, Usuario!" y habilitar huella
      final prefs = await SharedPreferences.getInstance();
      if (_mantenerSesion || _usuarioRecordado != null) {
        await prefs.setString('correo_recordado', emailFinal);
        // Guardamos el 'usuario' extraído de Firestore, no el correo que escribió
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

  // Traducción de errores DENTRO de la clase
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
              'assets/frifalca6.png', // Reemplaza con la ruta de tu imagen
              height: 120,       // Ajusta el tamaño según necesites
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 10),
            // 1. Saludo
            Text(
              _usuarioRecordado != null
                  ? "¡Hola, $_usuarioRecordado!"
                  : "Iniciar Sesión",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // 2. Correo y Checkbox (Solo si es login nuevo)
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
            // 3. Contraseña (Siempre visible)
            TextField(
              controller: _passwordController,
              obscureText: _oscurecerPassword,
              decoration: InputDecoration(
                labelText: "Contraseña",
                border: OutlineInputBorder(),
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

            // 4. Botón Entrar (Uno solo y después de los campos)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: _procesarLogin,
              child: const Text("Entrar"),
            ),

            // 5. Error y Biometría
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