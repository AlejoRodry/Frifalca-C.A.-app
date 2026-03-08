import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'panel_principal.dart';

// La biometría se maneja dinámicamente en los métodos correspondientes para evitar fallos en Web.

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Flag para evitar múltiples ejecuciones de runApp si el timeout salta junto con el éxito/error
  bool appStarted = false;

  void startApp(Widget app) {
    if (!appStarted) {
      appStarted = true;
      runApp(app);
    }
  }

  // Prueba de vida: Si en 6 segundos no ha cargado Firebase, forzamos error
  Timer(const Duration(seconds: 6), () {
    if (!appStarted) {
      startApp(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.timer_off_outlined,
                      color: Colors.orange,
                      size: 60,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "Timeout de Inicialización",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "Los servicios de Firebase están tardando demasiado en responder. Revisa tu conexión.",
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 30),
                    ElevatedButton(
                      onPressed: () => main(),
                      child: const Text("Reintentar arranque"),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
  });

  try {
    debugPrint("Iniciando Firebase (Web: $kIsWeb)...");

    // Inicialización de Firebase con un timeout interno de seguridad
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 5));

    startApp(const ThemeWrapper());
  } catch (e) {
    debugPrint("Error crítico en main(): $e");
    startApp(
      MaterialApp(
        theme: ThemeData.light(),
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 80),
                  const SizedBox(height: 20),
                  const Text(
                    "Error de Inicialización",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 15),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      e.toString(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[400],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 25,
                        vertical: 15,
                      ),
                    ),
                    onPressed: () => main(),
                    icon: const Icon(Icons.refresh),
                    label: const Text("Intentar de nuevo"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ThemeWrapper extends StatefulWidget {
  const ThemeWrapper({super.key});

  @override
  State<ThemeWrapper> createState() => _ThemeWrapperState();
}

class _ThemeWrapperState extends State<ThemeWrapper> {
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDarkMode') ?? false;

    if (!mounted) return;

    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  Future<void> _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _themeMode = _themeMode == ThemeMode.light
          ? ThemeMode.dark
          : ThemeMode.light;
      prefs.setBool('isDarkMode', _themeMode == ThemeMode.dark);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frifalca',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00BCD4),
          primary: const Color(0xFF00BCD4),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF0F9FA),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          color: Colors.white,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          brightness: Brightness.dark,
          seedColor: const Color(0xFF00BCD4),
          primary: const Color(0xFF00BCD4),
          surface: const Color(0xFF1E1E1E),
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          color: const Color(0xFF2C2C2C),
        ),
      ),
      initialRoute: '/',
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return PanelPrincipal(onToggleTheme: _toggleTheme);
          }
          return Login(title: 'Iniciar Sesión', onToggleTheme: _toggleTheme);
        },
      ),
    );
  }
}

class Login extends StatefulWidget {
  final String title;
  final VoidCallback onToggleTheme;

  const Login({super.key, required this.title, required this.onToggleTheme});

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

    if (!mounted) return;

    setState(() {
      if (nombreGuardado != null || correoGuardado != null) {
        _usuarioRecordado = nombreGuardado ?? correoGuardado;
        _correoRecordado = correoGuardado;
        _emailController.text = correoGuardado ?? "";
      }
    });
  }

  Future<void> _autenticarConHuella() async {
    if (kIsWeb) {
      debugPrint("La huella no está disponible en Web");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "La autenticación biométrica no está disponible en navegador.",
          ),
        ),
      );
      return;
    }

    try {
      // 1. Instanciamos localmente solo si no es Web
      final auth = LocalAuthentication();

      // 2. Verificamos disponibilidad de forma segura
      bool puedeAutenticar = false;
      try {
        puedeAutenticar =
            await auth.canCheckBiometrics || await auth.isDeviceSupported();
      } catch (e) {
        debugPrint("Error al verificar soporte biométrico: $e");
      }

      if (!puedeAutenticar || !mounted) return;

      // 3. Autenticamos
      bool autenticado = await auth.authenticate(
        localizedReason: 'Usa tu huella para entrar a Frifalca',
      );

      // 4. CONTROL CRÍTICO DE MONTAJE (Evita el error de dispose)
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
      if (!mounted) return;
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
        nombreDeUsuarioParaGuardar = datos['usuario'];
      } else if (!input.contains('@')) {
        // Si no hay '@' y no se encontró en Firestore
        messenger.showSnackBar(
          const SnackBar(content: Text("Usuario no encontrado")),
        );
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
        SnackBar(
          content: Text(_traducirError(e.code)),
          backgroundColor: Colors.red,
        ),
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
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 15),
            child: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isDark ? Icons.light_mode : Icons.dark_mode,
                  color: Colors.white,
                ),
              ),
              onPressed: widget.onToggleTheme,
            ),
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [const Color(0xFF0D1B2A), const Color(0xFF1B263B)]
                : [const Color(0xFF0251A4), const Color(0xFF00A8CC)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
            child: Column(
              children: [
                const SizedBox(height: 20),
                Image.asset(
                  'assets/frifalca6.png',
                  height: 120,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 30),

                // --- Glassmorphic Login Card ---
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(35),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        _usuarioRecordado != null
                            ? "¡Hola, $_usuarioRecordado!"
                            : "Iniciar Sesión",
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 40),

                      // --- Correo ---
                      if (_usuarioRecordado == null) ...[
                        _buildLabel("CORREO/USUARIO"),
                        const SizedBox(height: 10),
                        _buildTextField(
                          controller: _emailController,
                          hint: "ejemplo@correo.com",
                          icon: Icons.email_outlined,
                        ),
                        const SizedBox(height: 25),
                      ],

                      // --- Contraseña ---
                      _buildLabel("CONTRASEÑA"),
                      const SizedBox(height: 10),
                      _buildTextField(
                        controller: _passwordController,
                        hint: "",
                        icon: _oscurecerPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        obscure: _oscurecerPassword,
                        onIconPressed: () => setState(
                          () => _oscurecerPassword = !_oscurecerPassword,
                        ),
                        isPassword: true,
                      ),
                      // --- Mantener Sesión ---
                      if (_usuarioRecordado == null) ...[
                        SwitchListTile(
                          title: const Text(
                            "Mantener la sesión",
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          value: _mantenerSesion,
                          activeTrackColor: Colors.cyanAccent,
                          onChanged: (val) =>
                              setState(() => _mantenerSesion = val),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],

                      const SizedBox(height: 20),

                      // --- Botón Entrar ---
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyan[600],
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 60),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _procesarLogin,
                        child: const Text(
                          "Iniciar sesión",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      // --- Error Message ---
                      if (_mensajeError.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: Text(
                            _mensajeError,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ),

                // --- Biometría ---
                if (_usuarioRecordado != null && !kIsWeb) ...[
                  const SizedBox(height: 30),
                  GestureDetector(
                    onTap: _autenticarConHuella,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          child: const Icon(
                            Icons.fingerprint,
                            size: 50,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "Ingresar con huella",
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
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
                    child: Text(
                      "Usar otra cuenta",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    VoidCallback? onIconPressed,
    bool isPassword = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.1),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        suffixIcon: IconButton(
          icon: Icon(icon, color: Colors.white.withValues(alpha: 0.5)),
          onPressed: onIconPressed,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Colors.cyanAccent, width: 2),
        ),
      ),
    );
  }
}
