import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String baseUrl = "https://incidencias-backend-abt2.onrender.com";

// =========================================================
// UTILIDADES COMPARTIDAS
// =========================================================

/// Lee el token JWT guardado en el dispositivo.
Future<String> obtenerToken() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('token') ?? "";
}

/// Se usa cuando el servidor responde 401 (token vencido o inválido):
/// borra la sesión local y manda al usuario al Login.
Future<void> sesionExpirada(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text("Tu sesión expiró. Inicia sesión de nuevo.")),
  );
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginPage()),
    (route) => false,
  );
}

/// Cierra la sesión: borra TODO lo guardado localmente (token, nombre, rol)
/// y regresa al Login eliminando las pantallas anteriores, para que el botón
/// "atrás" no pueda volver a los módulos privados.
Future<void> cerrarSesion(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginPage()),
    (route) => false,
  );
}

/// Pregunta antes de salir. Se usa tanto en la barra superior como en el Perfil,
/// para que cerrar sesión funcione igual en los dos lugares.
Future<void> confirmarCierreSesion(BuildContext context) async {
  final confirmar = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text("Cerrar Sesión"),
      content: const Text("¿Está seguro de que desea salir de la aplicación?"),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text("Cancelar"),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text("Cerrar Sesión"),
        ),
      ],
    ),
  );

  if (confirmar == true && context.mounted) {
    await cerrarSesion(context);
  }
}

String formatearFecha(dynamic valor) {
  final DateTime? fecha = DateTime.tryParse('$valor')?.toLocal();
  if (fecha == null) return 'Desconocida';
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(fecha.day)}/${dos(fecha.month)}/${fecha.year} '
      '${dos(fecha.hour)}:${dos(fecha.minute)}';
}

/// Mensaje centrado que además permite "jalar para refrescar".
Widget mensajeRefrescable(String texto, Future<void> Function() onRefresh) {
  return RefreshIndicator(
    onRefresh: onRefresh,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 200),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              texto,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ),
        ),
      ],
    ),
  );
}

void main() {
  runApp(const SistemaIncidencias());
}

class SistemaIncidencias extends StatelessWidget {
  const SistemaIncidencias({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Incidencias Escolares',
      theme: ThemeData(
        primarySwatch: Colors.red,
        useMaterial3: false,
      ),
      home: const CheckAuthPage(),
    );
  }
}

// =========================================================
// VERIFICACIÓN DE SESIÓN INICIAL
// =========================================================
class CheckAuthPage extends StatefulWidget {
  const CheckAuthPage({super.key});

  @override
  State<CheckAuthPage> createState() => _CheckAuthPageState();
}

class _CheckAuthPageState extends State<CheckAuthPage> {
  @override
  void initState() {
    super.initState();
    _verificarSesion();
  }

  Future<void> _verificarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) =>
            token != null ? const NavigationPage() : const LoginPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

// =========================================================
// PANTALLA DE LOGIN
// =========================================================
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _cargando = false;

  Future<void> _iniciarSesion() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Complete todos los campos")),
      );
      return;
    }

    setState(() => _cargando = true);

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": _emailController.text.trim(),
          "password": _passwordController.text,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
        await prefs.setString('nombre', data['usuario']['nombre']);
        await prefs.setString('rol', data['usuario']['rol']);

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const NavigationPage()),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['mensaje'] ?? "Error al iniciar sesión")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "No se pudo conectar con el servidor. Si estaba dormido, espera unos segundos e intenta de nuevo."),
        ),
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(25.0),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.school, size: 80, color: Colors.red),
                const SizedBox(height: 10),
                const Text(
                  "Incidencias INFRAMEN",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 30),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: "Correo Electrónico",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "Contraseña",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 25),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: _cargando ? null : _iniciarSesion,
                    child: _cargando
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("Iniciar Sesión",
                            style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _cargando
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const RegistroPage()),
                          );
                        },
                  child: const Text("¿No tienes cuenta? Regístrate"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =========================================================
// PANTALLA DE REGISTRO
// =========================================================
class RegistroPage extends StatefulWidget {
  const RegistroPage({super.key});

  @override
  State<RegistroPage> createState() => _RegistroPageState();
}

class _RegistroPageState extends State<RegistroPage> {
  final _nombreController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmarController = TextEditingController();
  bool _cargando = false;

  void _mostrar(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje)),
    );
  }

  Future<void> _registrar() async {
    final nombre = _nombreController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (nombre.isEmpty || email.isEmpty || password.isEmpty) {
      _mostrar("Complete todos los campos");
      return;
    }
    if (!email.contains("@")) {
      _mostrar("Ingrese un correo válido");
      return;
    }
    if (password.length < 6) {
      _mostrar("La contraseña debe tener al menos 6 caracteres");
      return;
    }
    if (password != _confirmarController.text) {
      _mostrar("Las contraseñas no coinciden");
      return;
    }

    setState(() => _cargando = true);

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/registro"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "nombre": nombre,
          "email": email,
          "password": password,
        }),
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;
      if (response.statusCode == 200) {
        _mostrar("Cuenta creada correctamente. Ahora inicia sesión.");
        Navigator.pop(context);
      } else {
        _mostrar(data['mensaje'] ?? "Error al registrar el usuario");
      }
    } catch (e) {
      if (!mounted) return;
      _mostrar(
          "No se pudo conectar con el servidor. Si estaba dormido, espera unos segundos e intenta de nuevo.");
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Crear cuenta"),
        backgroundColor: Colors.red,
      ),
      body: Padding(
        padding: const EdgeInsets.all(25.0),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: _nombreController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: "Nombre completo",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: "Correo Electrónico",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "Contraseña (mínimo 6 caracteres)",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _confirmarController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "Confirmar contraseña",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 25),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: _cargando ? null : _registrar,
                    child: _cargando
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("Registrarme",
                            style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =========================================================
// NAVEGACIÓN PRINCIPAL (con nombre, rol y cerrar sesión)
// =========================================================
class NavigationPage extends StatefulWidget {
  const NavigationPage({super.key});

  @override
  State<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> {
  int _currentIndex = 0;
  String _nombreUsuario = "";
  String _rolUsuario = "";

  final List<Widget> _paginas = [
    const ReportarPage(),
    const MisReportesPage(),
    const EstadisticasPage(),
    const ResueltosPage(),
  ];

  @override
  void initState() {
    super.initState();
    _cargarDatosUsuario();
  }

  Future<void> _cargarDatosUsuario() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _nombreUsuario = prefs.getString('nombre') ?? "Usuario";
      _rolUsuario = prefs.getString('rol') ?? "Usuario";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Hola, $_nombreUsuario ($_rolUsuario)",
          style: const TextStyle(fontSize: 16),
        ),
        backgroundColor: Colors.red,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: "Exportar reportes PDF",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const GenerarReportePage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.account_circle),
            tooltip: "Mi perfil",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const PerfilPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Cerrar Sesión",
            onPressed: () => confirmarCierreSesion(context),
          ),
        ],
      ),
      body: _paginas[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.red,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.campaign), label: 'Reportar'),
          BottomNavigationBarItem(
              icon: Icon(Icons.assignment), label: 'Mis Reportes'),
          BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart), label: 'Estadísticas'),
          BottomNavigationBarItem(
              icon: Icon(Icons.check_circle), label: 'Resueltos'),
        ],
      ),
    );
  }
}

// =========================================================
// PESTAÑA 1: REPORTAR INCIDENCIA (envía el token)
// =========================================================
class ReportarPage extends StatefulWidget {
  const ReportarPage({super.key});

  @override
  State<ReportarPage> createState() => _ReportarPageState();
}

class _ReportarPageState extends State<ReportarPage> {
  final descripcionController = TextEditingController();
  String categoriaSeleccionada = "1";
  File? _imagenSeleccionada;
  bool _enviando = false;
  final ImagePicker _picker = ImagePicker();

  Future<void> _seleccionarImagen(ImageSource fuente) async {
    final XFile? foto =
        await _picker.pickImage(source: fuente, imageQuality: 70);
    if (foto != null) {
      setState(() => _imagenSeleccionada = File(foto.path));
    }
  }

  Future<void> registrarIncidencia() async {
    if (descripcionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Por favor ingrese una descripción")),
      );
      return;
    }

    setState(() => _enviando = true);

    try {
      final token = await obtenerToken();

      final uri = Uri.parse("$baseUrl/incidencias");
      final request = http.MultipartRequest("POST", uri);

      request.headers['Authorization'] = "Bearer $token";
      request.fields['categoria_id'] = categoriaSeleccionada;
      request.fields['descripcion'] = descripcionController.text;

      if (_imagenSeleccionada != null) {
        request.files.add(
          await http.MultipartFile.fromPath('imagen', _imagenSeleccionada!.path),
        );
      }

      final response = await request.send();

      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("¡Incidencia reportada con éxito!")),
        );
        descripcionController.clear();
        setState(() => _imagenSeleccionada = null);
      } else if (response.statusCode == 401) {
        await sesionExpirada(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error al registrar incidencia")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error de conexión: $e")),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Categoría del problema:",
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          DropdownButton<String>(
            value: categoriaSeleccionada,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: "1", child: Text("Infraestructura")),
              DropdownMenuItem(value: "2", child: Text("Electricidad")),
              DropdownMenuItem(value: "3", child: Text("Informática")),
              DropdownMenuItem(value: "4", child: Text("Limpieza")),
              DropdownMenuItem(value: "5", child: Text("Internet")),
            ],
            onChanged: (valor) {
              if (valor != null) setState(() => categoriaSeleccionada = valor);
            },
          ),
          const SizedBox(height: 15),
          TextField(
            controller: descripcionController,
            maxLines: 3,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: "Descripción detallada",
            ),
          ),
          const SizedBox(height: 20),
          Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: _imagenSeleccionada != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(_imagenSeleccionada!, fit: BoxFit.cover),
                  )
                : const Center(child: Text("Sin evidencia fotográfica")),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                onPressed: () => _seleccionarImagen(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text("Cámara"),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: () => _seleccionarImagen(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text("Galería"),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _enviando ? null : registrarIncidencia,
              child: _enviando
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("Registrar Incidencia",
                      style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================
// PESTAÑA 2: MIS REPORTES (búsqueda, filtros y acciones solo para Admin)
// =========================================================
class MisReportesPage extends StatefulWidget {
  const MisReportesPage({super.key});

  @override
  State<MisReportesPage> createState() => _MisReportesPageState();
}

class _MisReportesPageState extends State<MisReportesPage> {
  late Future<List<dynamic>> _futureIncidencias;
  final TextEditingController _buscarController = TextEditingController();
  Timer? _debounce;

  // "" significa "sin filtro" (Todas / Todos)
  String _categoriaFiltro = "";
  String _estadoFiltro = "";
  List<dynamic> _categorias = [];
  String _rolUsuario = "";

  bool get _hayFiltros =>
      _buscarController.text.trim().isNotEmpty ||
      _categoriaFiltro.isNotEmpty ||
      _estadoFiltro.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _futureIncidencias = _obtenerIncidenciasFiltradas();
    _cargarCategorias();
    _obtenerRol();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _buscarController.dispose();
    super.dispose();
  }

  Future<void> _obtenerRol() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _rolUsuario = prefs.getString('rol') ?? "Usuario";
    });
  }

  Future<void> _cargarCategorias() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/categorias"));
      if (response.statusCode == 200 && mounted) {
        setState(() {
          _categorias = jsonDecode(response.body);
        });
      }
    } catch (_) {}
  }

  /// Arma la URL con los filtros activos, por ejemplo:
  /// /incidencias?buscar=cable&categoria_id=2&estado=Pendiente
  Future<List<dynamic>> _obtenerIncidenciasFiltradas() async {
    final Map<String, String> queryParams = {};

    final texto = _buscarController.text.trim();
    if (texto.isNotEmpty) queryParams['buscar'] = texto;
    if (_categoriaFiltro.isNotEmpty) {
      queryParams['categoria_id'] = _categoriaFiltro;
    }
    if (_estadoFiltro.isNotEmpty) queryParams['estado'] = _estadoFiltro;

    final uri = Uri.parse("$baseUrl/incidencias").replace(
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Error al cargar incidencias");
    }
  }

  void _aplicarFiltros() {
    setState(() {
      _futureIncidencias = _obtenerIncidenciasFiltradas();
    });
  }

  /// Para "jalar para refrescar": vuelve a consultar con los filtros actuales.
  Future<void> _recargar() async {
    final nueva = _obtenerIncidenciasFiltradas();
    setState(() {
      _futureIncidencias = nueva;
    });
    try {
      await nueva;
    } catch (_) {}
  }

  /// Búsqueda en tiempo real: espera 400 ms sin que el usuario escriba
  /// antes de consultar, para no mandar una petición por cada letra.
  void _onBuscarChanged(String _) {
    setState(() {}); // actualiza al instante el botón de limpiar (X)
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _aplicarFiltros);
  }

  void _limpiarBusqueda() {
    _debounce?.cancel();
    _buscarController.clear();
    _aplicarFiltros();
  }

  void _limpiarFiltros() {
    _debounce?.cancel();
    _buscarController.clear();
    setState(() {
      _categoriaFiltro = "";
      _estadoFiltro = "";
    });
    _aplicarFiltros();
  }

  Future<void> _marcarComoResuelto(int id) async {
    try {
      final token = await obtenerToken();
      final response = await http.put(
        Uri.parse("$baseUrl/incidencias/$id/estado"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({"estado": "Resuelto"}),
      );

      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Incidencia marcada como Resuelta")),
        );
        _recargar();
      } else if (response.statusCode == 401) {
        await sesionExpirada(context);
      } else {
        final err = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err['mensaje'] ?? "Error de permisos")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al actualizar estado: $e")),
      );
    }
  }

  Future<void> _eliminarIncidencia(int id) async {
    try {
      final token = await obtenerToken();
      final response = await http.delete(
        Uri.parse("$baseUrl/incidencias/$id"),
        headers: {"Authorization": "Bearer $token"},
      );

      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Incidencia eliminada correctamente")),
        );
        _recargar();
      } else if (response.statusCode == 401) {
        await sesionExpirada(context);
      } else {
        final err = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err['mensaje'] ?? "Error al eliminar")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al eliminar: $e")),
      );
    }
  }

  void _mostrarDialogoResolver(int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Marcar como Resuelto"),
        content: const Text("¿Confirmas que esta incidencia ya fue solucionada?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              Navigator.pop(context);
              _marcarComoResuelto(id);
            },
            child: const Text("Confirmar"),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoEliminar(int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Eliminar Incidencia"),
        content: const Text(
            "¿Está seguro de eliminar este reporte? Esta acción no se puede deshacer."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _eliminarIncidencia(id);
            },
            child: const Text("Eliminar"),
          ),
        ],
      ),
    );
  }

  /// Desplegable con etiqueta flotante (Categoría / Estado).
  Widget _desplegable({
    required String etiqueta,
    required String valor,
    required List<DropdownMenuItem<String>> items,
    required void Function(String) onCambio,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: etiqueta,
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: const OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: valor,
          isExpanded: true,
          isDense: true,
          items: items,
          onChanged: (nuevo) {
            if (nuevo != null) onCambio(nuevo);
          },
        ),
      ),
    );
  }

  Widget _barraDeFiltros() {
    return Container(
      color: Colors.grey[100],
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          TextField(
            controller: _buscarController,
            onChanged: _onBuscarChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) {
              _debounce?.cancel();
              _aplicarFiltros();
            },
            decoration: InputDecoration(
              hintText: "Buscar por descripción...",
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _buscarController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: "Borrar búsqueda",
                      onPressed: _limpiarBusqueda,
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 0, horizontal: 15),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _desplegable(
                  etiqueta: "Categoría",
                  valor: _categoriaFiltro,
                  items: [
                    const DropdownMenuItem<String>(
                        value: "", child: Text("Todas")),
                    ..._categorias.map<DropdownMenuItem<String>>(
                      (c) => DropdownMenuItem<String>(
                        value: c['id'].toString(),
                        child: Text(
                          c['nombre'].toString(),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onCambio: (nuevo) {
                    setState(() {
                      _categoriaFiltro = nuevo;
                    });
                    _aplicarFiltros();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _desplegable(
                  etiqueta: "Estado",
                  valor: _estadoFiltro,
                  items: const [
                    DropdownMenuItem<String>(value: "", child: Text("Todos")),
                    DropdownMenuItem<String>(
                        value: "Pendiente", child: Text("Pendiente")),
                    DropdownMenuItem<String>(
                        value: "Resuelto", child: Text("Resuelto")),
                  ],
                  onCambio: (nuevo) {
                    setState(() {
                      _estadoFiltro = nuevo;
                    });
                    _aplicarFiltros();
                  },
                ),
              ),
            ],
          ),
          if (_hayFiltros)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _limpiarFiltros,
                icon: const Icon(Icons.filter_alt_off, size: 18),
                label: const Text("Limpiar filtros"),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _barraDeFiltros(),
        Expanded(
          child: FutureBuilder<List<dynamic>>(
            future: _futureIncidencias,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                return mensajeRefrescable(
                    "No se pudieron cargar los reportes.\nDesliza hacia abajo para reintentar.",
                    _recargar);
              } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return mensajeRefrescable(
                    _hayFiltros
                        ? "No se encontraron incidencias con esos filtros"
                        : "No hay incidencias registradas",
                    _recargar);
              }

              final lista = snapshot.data!;
              return RefreshIndicator(
                onRefresh: _recargar,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: lista.length,
                  itemBuilder: (context, index) {
                    final item = lista[index];
                    final String? nombreImagen = item['imagen'];
                    final String estado = item['estado'] ?? 'Pendiente';
                    final int id = item['id'];

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: ListTile(
                        isThreeLine: true,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  DetalleIncidenciaPage(incidencia: item),
                            ),
                          );
                        },
                        leading: nombreImagen != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.network(
                                  "$baseUrl/uploads/$nombreImagen",
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(Icons.broken_image, size: 40),
                                ),
                              )
                            : const Icon(Icons.report_problem,
                                size: 40, color: Colors.orange),
                        title: Text(
                          item['categoria'] ?? 'Sin Categoría',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['descripcion'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              "Por: ${item['usuario'] ?? 'Anónimo'}",
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 12),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Chip(
                              label: Text(
                                estado,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 10),
                              ),
                              backgroundColor: estado == 'Resuelto'
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                            // Solo el Admin puede resolver y eliminar
                            if (_rolUsuario == 'Admin') ...[
                              if (estado != 'Resuelto')
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 36, minHeight: 36),
                                  icon: const Icon(Icons.check_circle_outline,
                                      color: Colors.green),
                                  tooltip: "Marcar como Resuelto",
                                  onPressed: () => _mostrarDialogoResolver(id),
                                ),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 36, minHeight: 36),
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red),
                                tooltip: "Eliminar Reporte",
                                onPressed: () => _mostrarDialogoEliminar(id),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// =========================================================
// PESTAÑA 3: ESTADÍSTICAS (gráfico de barras)
// =========================================================
class EstadisticasPage extends StatefulWidget {
  const EstadisticasPage({super.key});

  @override
  State<EstadisticasPage> createState() => _EstadisticasPageState();
}

class _EstadisticasPageState extends State<EstadisticasPage> {
  late Future<List<dynamic>> _futureEstadisticas;

  final List<Color> _colores = [
    Colors.red,
    Colors.blue,
    Colors.orange,
    Colors.green,
    Colors.purple,
  ];

  Future<List<dynamic>> _obtenerEstadisticas() async {
    final response =
        await http.get(Uri.parse("$baseUrl/estadisticas/categorias"));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Error al obtener estadísticas");
    }
  }

  Future<void> _recargar() async {
    final nueva = _obtenerEstadisticas();
    setState(() {
      _futureEstadisticas = nueva;
    });
    try {
      await nueva;
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _futureEstadisticas = _obtenerEstadisticas();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _futureEstadisticas,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return mensajeRefrescable(
              "No se pudieron cargar las estadísticas.\nDesliza hacia abajo para reintentar.",
              _recargar);
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return mensajeRefrescable("No hay datos para mostrar", _recargar);
        }

        final datos = snapshot.data!;
        final int totalGeneral =
            datos.fold<int>(0, (sum, item) => sum + (item['total'] as int));

        if (totalGeneral == 0) {
          return mensajeRefrescable("Aún no hay incidencias reportadas", _recargar);
        }

        final int maxTotal = datos
            .map<int>((item) => item['total'] as int)
            .reduce((a, b) => a > b ? a : b);
        final double maxY = (maxTotal + 1).toDouble();

        return RefreshIndicator(
          onRefresh: _recargar,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text(
                  "Distribución por Categoría",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 260,
                  child: BarChart(
                    BarChartData(
                      maxY: maxY,
                      barTouchData: BarTouchData(enabled: true),
                      titlesData: FlTitlesData(
                        show: true,
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            interval: 1,
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 42,
                            getTitlesWidget: (value, meta) {
                              final int index = value.toInt();
                              if (index < 0 || index >= datos.length) {
                                return const SizedBox.shrink();
                              }
                              final String nombre =
                                  datos[index]['categoria'] ?? '';
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  nombre,
                                  style: const TextStyle(fontSize: 10),
                                  textAlign: TextAlign.center,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      gridData:
                          const FlGridData(show: true, drawVerticalLine: false),
                      barGroups: List.generate(datos.length, (index) {
                        final int total = datos[index]['total'];
                        return BarChartGroupData(
                          x: index,
                          barRods: [
                            BarChartRodData(
                              toY: total.toDouble(),
                              color: _colores[index % _colores.length],
                              width: 22,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                Card(
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Total General de Reportes: $totalGeneral",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Divider(),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: datos.length,
                          itemBuilder: (context, index) {
                            final item = datos[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    _colores[index % _colores.length],
                                radius: 8,
                              ),
                              title: Text(item['categoria']),
                              trailing: Text(
                                "${item['total']} reportes",
                                style:
                                    const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// =========================================================
// PESTAÑA 4: RESUELTOS
// =========================================================
class ResueltosPage extends StatefulWidget {
  const ResueltosPage({super.key});

  @override
  State<ResueltosPage> createState() => _ResueltosPageState();
}

class _ResueltosPageState extends State<ResueltosPage> {
  late Future<List<dynamic>> _futureResueltos;

  Future<List<dynamic>> _obtenerResueltos() async {
    final response =
        await http.get(Uri.parse("$baseUrl/incidencias/resueltas"));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Error al cargar incidencias resueltas");
    }
  }

  Future<void> _recargar() async {
    final nueva = _obtenerResueltos();
    setState(() {
      _futureResueltos = nueva;
    });
    try {
      await nueva;
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _futureResueltos = _obtenerResueltos();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _futureResueltos,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return mensajeRefrescable(
              "No se pudieron cargar los reportes.\nDesliza hacia abajo para reintentar.",
              _recargar);
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return mensajeRefrescable("Aún no hay incidencias resueltas", _recargar);
        }

        final lista = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _recargar,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: lista.length,
            itemBuilder: (context, index) {
              final item = lista[index];
              final String? nombreImagen = item['imagen'];

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: ListTile(
                  isThreeLine: true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            DetalleIncidenciaPage(incidencia: item),
                      ),
                    );
                  },
                  leading: nombreImagen != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(
                            "$baseUrl/uploads/$nombreImagen",
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.broken_image, size: 40),
                          ),
                        )
                      : const Icon(Icons.check_circle,
                          size: 40, color: Colors.green),
                  title: Text(
                    item['categoria'] ?? 'Sin Categoría',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['descripcion'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        "Por: ${item['usuario'] ?? 'Anónimo'}",
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                  trailing: const Chip(
                    label: Text(
                      'Resuelto',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    backgroundColor: Colors.green,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// =========================================================
// PANTALLA DE DETALLE DE INCIDENCIA
// =========================================================
class DetalleIncidenciaPage extends StatelessWidget {
  final Map<String, dynamic> incidencia;

  const DetalleIncidenciaPage({super.key, required this.incidencia});

  @override
  Widget build(BuildContext context) {
    final String? nombreImagen = incidencia['imagen'];
    final String estado = incidencia['estado'] ?? 'Pendiente';
    final String urlImagen = "$baseUrl/uploads/$nombreImagen";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Detalle de Incidencia"),
        backgroundColor: Colors.red,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (nombreImagen != null)
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          VisorImagenPage(urlImagen: urlImagen),
                    ),
                  );
                },
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 360),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      urlImagen,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const Padding(
                        padding: EdgeInsets.all(30),
                        child: Icon(Icons.broken_image, size: 100),
                      ),
                    ),
                  ),
                ),
              )
            else
              Container(
                height: 150,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(child: Text("Sin Evidencia Fotográfica")),
              ),
            if (nombreImagen != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  "Toca la imagen para verla en pantalla completa",
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    incidencia['categoria'] ?? 'Sin Categoría',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                Chip(
                  label: Text(estado, style: const TextStyle(color: Colors.white)),
                  backgroundColor:
                      estado == 'Resuelto' ? Colors.green : Colors.orange,
                ),
              ],
            ),
            const Divider(height: 30),
            const Text("Descripción:",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 5),
            Text(incidencia['descripcion'] ?? "Sin descripción",
                style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 15),
            Text(
              "Reportado por: ${incidencia['usuario'] ?? 'Desconocido'}",
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 5),
            Text(
              "Fecha de reporte: ${formatearFecha(incidencia['fecha'])}",
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================
// VISOR DE IMAGEN A PANTALLA COMPLETA (zoom con pellizco)
// =========================================================
class VisorImagenPage extends StatelessWidget {
  final String urlImagen;

  const VisorImagenPage({super.key, required this.urlImagen});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text("Evidencia fotográfica"),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Image.network(
            urlImagen,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.broken_image,
              size: 100,
              color: Colors.white54,
            ),
          ),
        ),
      ),
    );
  }
}

// =========================================================
// PANTALLA DE PERFIL DE USUARIO (Guía 8)
// =========================================================
class PerfilPage extends StatefulWidget {
  const PerfilPage({super.key});

  @override
  State<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends State<PerfilPage> {
  Map<String, dynamic>? _usuarioData;
  bool _cargando = true;
  String? _error;
  // true si el rol guardado en el token ya no coincide con el de la base de datos
  bool _rolDesactualizado = false;

  @override
  void initState() {
    super.initState();
    _obtenerPerfil();
  }

  /// Pide los datos ACTUALES del usuario al servidor, enviando el token guardado.
  Future<void> _obtenerPerfil() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final token = await obtenerToken();
      final response = await http.get(
        Uri.parse("$baseUrl/perfil"),
        headers: {"Authorization": "Bearer $token"},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final prefs = await SharedPreferences.getInstance();
        final rolLocal = prefs.getString('rol') ?? "";
        if (!mounted) return;
        setState(() {
          _usuarioData = data;
          _rolDesactualizado = rolLocal.isNotEmpty && rolLocal != data['rol'];
          _cargando = false;
        });
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        // Token inválido o vencido: se destruye la sesión y se vuelve al Login
        await sesionExpirada(context);
      } else {
        setState(() {
          _error = "No se pudo cargar la información del usuario";
          _cargando = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Error de conexión. Verifica tu internet e intenta de nuevo.";
        _cargando = false;
      });
    }
  }

  Widget _tarjetaDato(IconData icono, String titulo, String valor) {
    return Card(
      elevation: 3,
      child: ListTile(
        leading: Icon(icono, color: Colors.red),
        title: Text(titulo),
        subtitle: Text(valor),
      ),
    );
  }

  List<Widget> _contenidoPerfil() {
    final data = _usuarioData!;
    final String nombre = (data['nombre'] ?? '').toString();
    final String inicial = nombre.isNotEmpty ? nombre[0].toUpperCase() : "?";
    final String miembroDesde =
        formatearFecha(data['fecha_registro']).split(' ').first;

    return [
      const SizedBox(height: 10),
      Center(
        child: CircleAvatar(
          radius: 50,
          backgroundColor: Colors.red[100],
          child: Text(
            inicial,
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
        ),
      ),
      const SizedBox(height: 20),
      if (_rolDesactualizado)
        Card(
          color: Colors.orange[50],
          child: const ListTile(
            leading: Icon(Icons.info_outline, color: Colors.orange),
            title: Text("Tu rol fue actualizado"),
            subtitle: Text(
              "Cierra sesión y vuelve a iniciar para aplicar tus nuevos permisos.",
            ),
          ),
        ),
      _tarjetaDato(Icons.person, "Nombre Completo", nombre),
      _tarjetaDato(Icons.email, "Correo Electrónico",
          (data['email'] ?? '').toString()),
      _tarjetaDato(
          Icons.security, "Rol asignado", (data['rol'] ?? 'Usuario').toString()),
      _tarjetaDato(Icons.calendar_today, "Miembro desde", miembroDesde),
    ];
  }

  Widget _bloqueError() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 60, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            _error ?? "Error al cargar la información del usuario",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _obtenerPerfil,
            icon: const Icon(Icons.refresh),
            label: const Text("Reintentar"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Perfil de Usuario"),
        backgroundColor: Colors.red,
      ),
      body: RefreshIndicator(
        onRefresh: _obtenerPerfil,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            if (_cargando && _usuarioData == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_usuarioData == null)
              _bloqueError()
            else
              ..._contenidoPerfil(),
            const SizedBox(height: 30),
            // El botón de cerrar sesión siempre está disponible, incluso si falla la carga
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.logout, color: Colors.white),
                label: const Text(
                  "CERRAR SESIÓN",
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                onPressed: () => confirmarCierreSesion(context),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// =========================================================
// GENERACIÓN DE REPORTES PDF (Guía 9)
// =========================================================
class GenerarReportePage extends StatefulWidget {
  const GenerarReportePage({super.key});

  @override
  State<GenerarReportePage> createState() => _GenerarReportePageState();
}

class _GenerarReportePageState extends State<GenerarReportePage> {
  // Fechas elegidas en pantalla (opcionales)
  DateTime? _fechaInicio;
  DateTime? _fechaFin;

  bool _cargando = false;
  String? _error;
  bool _consultado = false;
  List<dynamic> _incidencias = [];

  // Sube con cada consulta nueva para obligar a PdfPreview a regenerar el PDF
  int _version = 0;

  // Datos de la consulta que está en pantalla (para el encabezado del PDF)
  DateTime? _rangoInicio;
  DateTime? _rangoFin;
  String _generadoPor = "";

  String _dos(int n) => n.toString().padLeft(2, '0');

  /// 05/10/2026
  String _fmt(DateTime d) => "${_dos(d.day)}/${_dos(d.month)}/${d.year}";

  /// 2026-10-05 (formato que espera el servidor)
  String _aIso(DateTime d) => "${d.year}-${_dos(d.month)}-${_dos(d.day)}";

  /// Zona horaria del dispositivo, por ejemplo "-06:00" en El Salvador.
  /// El servidor la usa para que "hoy" signifique hoy en TU hora, no en UTC.
  String _offsetZonaHoraria() {
    final Duration d = DateTime.now().timeZoneOffset;
    final String signo = d.isNegative ? '-' : '+';
    final int minutos = d.inMinutes.abs();
    return "$signo${_dos(minutos ~/ 60)}:${_dos(minutos % 60)}";
  }

  String _textoPeriodo() {
    if (_rangoInicio == null && _rangoFin == null) return "Todo el historial";
    if (_rangoInicio != null && _rangoFin != null) {
      return "Del ${_fmt(_rangoInicio!)} al ${_fmt(_rangoFin!)}";
    }
    if (_rangoInicio != null) return "Desde el ${_fmt(_rangoInicio!)}";
    return "Hasta el ${_fmt(_rangoFin!)}";
  }

  void _mostrar(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje)),
    );
  }

  Future<void> _seleccionarFecha(bool esInicio) async {
    final DateTime? elegida = await showDatePicker(
      context: context,
      initialDate: (esInicio ? _fechaInicio : _fechaFin) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (elegida != null && mounted) {
      setState(() {
        if (esInicio) {
          _fechaInicio = elegida;
        } else {
          _fechaFin = elegida;
        }
      });
    }
  }

  void _limpiarFechas() {
    setState(() {
      _fechaInicio = null;
      _fechaFin = null;
    });
  }

  /// Pide al servidor las incidencias del rango elegido (requiere sesión).
  Future<void> _consultarDatos() async {
    if (_fechaInicio != null &&
        _fechaFin != null &&
        _fechaInicio!.isAfter(_fechaFin!)) {
      _mostrar("La fecha de inicio no puede ser posterior a la fecha de fin");
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final token = await obtenerToken();
      final prefs = await SharedPreferences.getInstance();
      final String nombre = prefs.getString('nombre') ?? "";
      final String rol = prefs.getString('rol') ?? "";

      final Map<String, String> params = {'tz': _offsetZonaHoraria()};
      if (_fechaInicio != null) params['fecha_inicio'] = _aIso(_fechaInicio!);
      if (_fechaFin != null) params['fecha_fin'] = _aIso(_fechaFin!);

      final uri = Uri.parse("$baseUrl/incidencias/exportar")
          .replace(queryParameters: params);
      final response = await http.get(
        uri,
        headers: {"Authorization": "Bearer $token"},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        setState(() {
          _incidencias = jsonDecode(response.body) as List<dynamic>;
          _consultado = true;
          _cargando = false;
          _version++;
          _rangoInicio = _fechaInicio;
          _rangoFin = _fechaFin;
          _generadoPor = nombre.isEmpty ? "" : "$nombre ($rol)";
        });
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        await sesionExpirada(context);
      } else {
        String mensaje = "No se pudieron cargar las incidencias";
        try {
          mensaje = (jsonDecode(response.body)['mensaje'] ?? mensaje).toString();
        } catch (_) {}
        setState(() {
          _error = mensaje;
          _cargando = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Error de conexión. Verifica tu internet e intenta de nuevo.";
        _cargando = false;
      });
    }
  }

  /// Cuadro de una cifra del resumen estadístico dentro del PDF.
  pw.Widget _cajaResumen(String titulo, String valor, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.only(right: 6),
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          children: [
            pw.Text(
              valor,
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: color,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(titulo, style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      ),
    );
  }

  /// Construye el documento PDF con los datos cargados.
  Future<Uint8List> _generarPdf(PdfPageFormat format) async {
    final pdf = pw.Document(
      title: 'Reporte consolidado de incidencias',
      author: 'INFRAMEN',
    );

    // ---- Resumen estadístico (se calcula con los mismos datos de la tabla) ----
    final int total = _incidencias.length;
    final int resueltas =
        _incidencias.where((e) => e['estado'] == 'Resuelto').length;
    final int pendientes = total - resueltas;
    final String porcentaje =
        total == 0 ? "0" : ((resueltas / total) * 100).toStringAsFixed(0);

    final Map<String, List<int>> porCategoria = {};
    for (final item in _incidencias) {
      final String categoria = (item['categoria'] ?? 'Sin categoría').toString();
      final List<int> fila = porCategoria.putIfAbsent(categoria, () => [0, 0, 0]);
      fila[0]++; // total
      if (item['estado'] == 'Resuelto') {
        fila[2]++; // resueltas
      } else {
        fila[1]++; // pendientes
      }
    }
    final categoriasOrdenadas = porCategoria.entries.toList()
      ..sort((a, b) => b.value[0].compareTo(a.value[0]));

    final DateTime ahora = DateTime.now();
    final String generado = "${_fmt(ahora)} ${_dos(ahora.hour)}:${_dos(ahora.minute)}";

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(32),
        // Por defecto el paquete limita a 20 páginas; con historiales largos fallaría
        maxPages: 500,
        footer: (pw.Context ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            "Página ${ctx.pageNumber} de ${ctx.pagesCount}",
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ),
        build: (pw.Context ctx) => [
          // ---------- Encabezado institucional ----------
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 10),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.red800, width: 2),
              ),
            ),
            child: pw.Column(
              children: [
                pw.Text(
                  "INSTITUTO NACIONAL 'GENERAL FRANCISCO MENENDEZ'",
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  "INFRAMEN - Sistema de Gestión de Incidencias",
                  style: const pw.TextStyle(fontSize: 11),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  "REPORTE CONSOLIDADO DE INCIDENCIAS",
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.red800,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text("Período: ${_textoPeriodo()}",
                  style: const pw.TextStyle(fontSize: 10)),
              pw.Text("Generado: $generado",
                  style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
          if (_generadoPor.isNotEmpty)
            pw.Text("Generado por: $_generadoPor",
                style: const pw.TextStyle(fontSize: 10)),

          // ---------- Resumen estadístico ----------
          pw.SizedBox(height: 16),
          pw.Text(
            "RESUMEN ESTADÍSTICO",
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            children: [
              _cajaResumen("Total de incidencias", "$total", PdfColors.grey800),
              _cajaResumen("Pendientes", "$pendientes", PdfColors.orange800),
              _cajaResumen("Resueltas", "$resueltas", PdfColors.green800),
              _cajaResumen("% Resueltas", "$porcentaje%", PdfColors.red800),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: ['Categoría', 'Total', 'Pendientes', 'Resueltas'],
            data: categoriasOrdenadas
                .map((e) => [
                      e.key,
                      '${e.value[0]}',
                      '${e.value[1]}',
                      '${e.value[2]}',
                    ])
                .toList(),
            headerStyle: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.red800),
            cellStyle: const pw.TextStyle(fontSize: 10),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1.4),
              3: const pw.FlexColumnWidth(1.4),
            },
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.center,
              2: pw.Alignment.center,
              3: pw.Alignment.center,
            },
          ),

          // ---------- Detalle de incidencias ----------
          pw.SizedBox(height: 18),
          pw.Text(
            "DETALLE DE INCIDENCIAS",
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ['ID', 'Categoría', 'Descripción', 'Estado', 'Fecha'],
            data: _incidencias
                .map((item) => [
                      item['id'].toString(),
                      (item['categoria'] ?? '').toString(),
                      (item['descripcion'] ?? '').toString(),
                      (item['estado'] ?? '').toString(),
                      formatearFecha(item['fecha']),
                    ])
                .toList(),
            headerStyle: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.red800),
            cellStyle: const pw.TextStyle(fontSize: 9),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FixedColumnWidth(28),
              1: const pw.FlexColumnWidth(2.2),
              2: const pw.FlexColumnWidth(5),
              3: const pw.FlexColumnWidth(1.8),
              4: const pw.FlexColumnWidth(2.6),
            },
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.center,
              4: pw.Alignment.center,
            },
          ),
          pw.SizedBox(height: 16),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              "Total de incidencias reportadas: $total",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  Widget _vistaPrevia() {
    return PdfPreview(
      // La llave cambia con cada consulta: así la vista previa se regenera con los datos nuevos
      key: ValueKey(_version),
      build: _generarPdf,
      allowPrinting: true,
      allowSharing: true,
      canChangeOrientation: false,
      canChangePageFormat: false,
      canDebug: false,
      pdfFileName: "reporte_incidencias_${_aIso(DateTime.now())}.pdf",
    );
  }

  Widget _contenido() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.grey),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _consultarDatos,
              icon: const Icon(Icons.refresh),
              label: const Text("Reintentar"),
            ),
          ],
        ),
      );
    }
    if (!_consultado) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            "Elige un rango de fechas (opcional) y presiona\n\"Cargar Datos para PDF\"",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.grey),
          ),
        ),
      );
    }
    if (_incidencias.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            "No se encontraron incidencias en el rango seleccionado",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.grey),
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            "${_incidencias.length} incidencias listas para exportar (${_textoPeriodo()})",
            style: TextStyle(color: Colors.grey[700], fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(child: _vistaPrevia()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Exportar Reportes PDF"),
        backgroundColor: Colors.red,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    const Text(
                      "Filtro por Rango de Fechas",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Déjalas vacías para exportar todo el historial",
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.date_range),
                            label: Text(_fechaInicio == null
                                ? "Fecha Inicio"
                                : _fmt(_fechaInicio!)),
                            onPressed: () => _seleccionarFecha(true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.date_range),
                            label: Text(_fechaFin == null
                                ? "Fecha Fin"
                                : _fmt(_fechaFin!)),
                            onPressed: () => _seleccionarFecha(false),
                          ),
                        ),
                      ],
                    ),
                    if (_fechaInicio != null || _fechaFin != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _limpiarFechas,
                          icon: const Icon(Icons.clear, size: 18),
                          label: const Text("Quitar fechas"),
                        ),
                      ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red),
                        onPressed: _cargando ? null : _consultarDatos,
                        icon: const Icon(Icons.picture_as_pdf,
                            color: Colors.white),
                        label: const Text(
                          "Cargar Datos para PDF",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(child: _contenido()),
          ],
        ),
      ),
    );
  }
}