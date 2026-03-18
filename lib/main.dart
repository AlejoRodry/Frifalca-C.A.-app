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
import 'registro_trabajador_screen.dart';
import 'componentes_de_inventario.dart' as comp;
import 'package:google_fonts/google_fonts.dart';
import 'theme.dart';
import 'dart:ui';

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

  // Manejo de errores visuales (Debug)
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      child: Container(
        color: const Color(0xFF0A2540),
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.bug_report, color: Color(0xFF00D4FF), size: 50),
              const SizedBox(height: 15),
              Text(
                "Error de Renderizado:\n${details.exception}",
                style: const TextStyle(color: Colors.white, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  };

  // Prueba de vida: Margen extendido para carga de recursos pesados en Web
  Timer(Duration(seconds: kIsWeb ? 25 : 12), () {
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

    // Inicialización de Firebase con un timeout extendido para Web
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(Duration(seconds: kIsWeb ? 20 : 10));

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
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.trackpad,
        },
      ),
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
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

  void _entrarComoInvitado() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 25),
            const Text(
              "Estado del Inventario",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 25),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('Productos')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text("Error al cargar datos");
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                int sacoFisico = 0, sacoComp = 0;
                int bolsaFisico = 0, bolsaComp = 0;

                for (var doc in snapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (doc.id == "NZAtCFwTfLTwb3xiiOUk") {
                    sacoFisico = (data['stock_fisico'] as num? ?? 0).toInt();
                    sacoComp = (data['stock_comprometido'] as num? ?? 0)
                        .toInt();
                  }
                  if (doc.id == "DWDbVnRf5nqGu8uTu3KA") {
                    bolsaFisico = (data['stock_fisico'] as num? ?? 0).toInt();
                    bolsaComp = (data['stock_comprometido'] as num? ?? 0)
                        .toInt();
                  }
                }

                return comp.InventarioResumenCard(
                  sacoFisico: sacoFisico,
                  sacoComp: sacoComp,
                  bolsaFisico: bolsaFisico,
                  bolsaComp: bolsaComp,
                  onAjustar: (id, cantidad) {},
                  readOnly: true,
                );
              },
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cerrar"),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarModalContrasena() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 25),
                const Text(
                  "Ingreso con Contraseña",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 25),
                if (_usuarioRecordado == null) ...[
                  _buildLabel("CORREO/USUARIO", isModal: true),
                  const SizedBox(height: 10),
                  _buildTextField(
                    controller: _emailController,
                    hint: "ejemplo@correo.com",
                    icon: Icons.email_outlined,
                    isModal: true,
                  ),
                  const SizedBox(height: 20),
                ],
                _buildLabel("CONTRASEÑA", isModal: true),
                const SizedBox(height: 10),
                _buildTextField(
                  controller: _passwordController,
                  hint: "****",
                  icon: _oscurecerPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  obscure: _oscurecerPassword,
                  onIconPressed: () => setModalState(
                    () => _oscurecerPassword = !_oscurecerPassword,
                  ),
                  isPassword: true,
                  isModal: true,
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _procesarLogin();
                  },
                  child: const Text(
                    "Entrar ahora",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_usuarioRecordado != null) ...[
                  const SizedBox(height: 15),
                  TextButton.icon(
                    onPressed: _entrarComoInvitado,
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text("Ver Inventario General (Público)"),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(context);
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
                    child: const Text(
                      "Usar otra cuenta",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
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
                ? [const Color(0xFF05121F), AppColors.primary]
                : [AppColors.primary, const Color(0xFF0E3D6B)],
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

                // --- Glassmorphic Login Card (Optimizado para Web) ---
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Container(
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
                          style: Theme.of(context).textTheme.displayLarge
                              ?.copyWith(color: Colors.white, fontSize: 24),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.secondary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 40),

                        // --- LÓGICA HÍBRIDA: WEB vs MÓVIL ---
                        if (kIsWeb) ...[
                          // WEB: Todo directo en pantalla
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
                          _buildLabel("CONTRASEÑA"),
                          const SizedBox(height: 10),
                          _buildTextField(
                            controller: _passwordController,
                            hint: "****",
                            icon: _oscurecerPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            obscure: _oscurecerPassword,
                            onIconPressed: () => setState(
                              () => _oscurecerPassword = !_oscurecerPassword,
                            ),
                            isPassword: true,
                          ),
                          if (_usuarioRecordado == null) ...[
                            SwitchListTile(
                              title: const Text(
                                "Mantener la sesión",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                              value: _mantenerSesion,
                              activeTrackColor: AppColors.secondary,
                              onChanged: (val) =>
                                  setState(() => _mantenerSesion = val),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ],
                          const SizedBox(height: 25),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.secondary,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 60),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
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
                          // Link de inventario público solo si el usuario está recordado
                          if (_usuarioRecordado != null) ...[
                            const SizedBox(height: 20),
                            TextButton.icon(
                              onPressed: _entrarComoInvitado,
                              icon: const Icon(
                                Icons.visibility_outlined,
                                size: 18,
                              ),
                              label: const Text(
                                "Ver Inventario General (Público)",
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white70,
                              ),
                            ),
                          ],
                        ] else ...[
                          // MÓVIL: Pantalla limpia
                          if (_usuarioRecordado != null) ...[
                            _buildAuthButton(
                              label: "Usar Huella Digital",
                              icon: Icons.fingerprint_rounded,
                              onPressed: _autenticarConHuella,
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                            const SizedBox(height: 20),
                            TextButton.icon(
                              onPressed: _entrarComoInvitado,
                              icon: const Icon(
                                Icons.visibility_outlined,
                                size: 18,
                              ),
                              label: const Text(
                                "Ver Inventario General (Público)",
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white70,
                              ),
                            ),
                          ] else
                            const Text(
                              "Bienvenido a Frifalca",
                              style: TextStyle(color: Colors.white70),
                            ),
                          const SizedBox(height: 20),
                          _buildAuthButton(
                            label: "Ingresar con contraseña",
                            icon: Icons.lock_outline_rounded,
                            onPressed: _mostrarModalContrasena,
                            color: AppColors.secondary,
                            isPrimary: true,
                          ),
                        ],
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

                        // --- Cambio de Usuario (Branding Frifalca) ---
                        if (_usuarioRecordado != null) ...[
                          const SizedBox(height: 20),
                          TextButton(
                            onPressed: () async {
                              final prefs =
                                  await SharedPreferences.getInstance();
                              // Limpiamos solo los datos del usuario, conservamos el tema
                              await prefs.remove('user_name');
                              await prefs.remove('correo_recordado');
                              await prefs.remove('user_password');

                              if (!context.mounted) return;

                              // Reiniciamos a la pantalla de login principal limpia
                              Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => Login(
                                    title: widget.title,
                                    onToggleTheme: widget.onToggleTheme,
                                  ),
                                ),
                                (route) => false,
                              );
                            },
                            child: Text(
                              "¿No eres tú? Iniciar sesión con otra cuenta",
                              style: GoogleFonts.inter(
                                color: AppColors.secondary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const RegistroTrabajadorScreen(),
                              ),
                            );
                          },
                          child: const Text(
                            "¿Fuiste pre-autorizado? Registrate aquí",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    required Color color,
    bool isPrimary = false,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          elevation: isPrimary ? 2 : 0,
        ),
      ),
    );
  }

  Widget _buildLabel(String text, {bool isModal = false}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          color: isModal ? Colors.grey[700] : Colors.white70,
          fontSize: 11,
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
    bool isModal = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(color: isModal ? Colors.black87 : Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: isModal
              ? Colors.grey.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.4),
        ),
        filled: true,
        fillColor: isModal
            ? Colors.grey.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.1),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            icon,
            color: isModal
                ? Colors.grey[600]
                : Colors.white.withValues(alpha: 0.5),
          ),
          onPressed: onIconPressed,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(
            color: isModal
                ? Colors.grey.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: AppColors.secondary, width: 2),
        ),
      ),
    );
  }
}
