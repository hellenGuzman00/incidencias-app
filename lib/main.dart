import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

const String baseUrl = "https://incidencias-backend-abt2.onrender.com";

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
      home: const NavigationPage(),
    );
  }
}

class NavigationPage extends StatefulWidget {
  const NavigationPage({super.key});

  @override
  State<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> {
  int _currentIndex = 0;

  final List<Widget> _paginas = [
    const ReportarPage(),
    const MisReportesPage(),
    const EstadisticasPage(),
    const ResueltosPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _paginas[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.red,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.campaign),
            label: 'Reportar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment),
            label: 'Mis Reportes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Estadísticas',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.check_circle),
            label: 'Resueltos',
          ),
        ],
      ),
    );
  }
}

// Pantalla 1: Reportar con Cámara
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
    final XFile? foto = await _picker.pickImage(
      source: fuente,
      imageQuality: 70,
    );
    if (foto != null) {
      setState(() {
        _imagenSeleccionada = File(foto.path);
      });
    }
  }

  Future<void> registrarIncidencia() async {
    if (descripcionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Por favor ingrese una descripción")),
      );
      return;
    }

    setState(() {
      _enviando = true;
    });

    try {
      final uri = Uri.parse("$baseUrl/incidencias");
      final request = http.MultipartRequest("POST", uri);
      request.fields['categoria_id'] = categoriaSeleccionada;
      request.fields['descripcion'] = descripcionController.text;

      if (_imagenSeleccionada != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'imagen',
            _imagenSeleccionada!.path,
          ),
        );
      }

      final response = await request.send();

      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("¡Incidencia reportada con éxito!")),
        );
        descripcionController.clear();
        setState(() {
          _imagenSeleccionada = null;
        });
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error al registrar la incidencia")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error de conexión: $e")),
      );
    } finally {
      setState(() {
        _enviando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Reportar Incidencia"),
        backgroundColor: Colors.red,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Categoría del problema:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
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
                  if (valor != null) {
                    setState(() {
                      categoriaSeleccionada = valor;
                    });
                  }
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
                        child: Image.file(
                          _imagenSeleccionada!,
                          fit: BoxFit.cover,
                        ),
                      )
                    : const Center(
                        child: Text("Sin evidencia fotográfica"),
                      ),
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
                      : const Text(
                          "Registrar Incidencia",
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// Pantalla 2: Mis Reportes
class MisReportesPage extends StatefulWidget {
  const MisReportesPage({super.key});

  @override
  State<MisReportesPage> createState() => _MisReportesPageState();
}

class _MisReportesPageState extends State<MisReportesPage> {
  late Future<List<dynamic>> _futureIncidencias;

  Future<List<dynamic>> _obtenerIncidencias() async {
    final response = await http.get(Uri.parse("$baseUrl/incidencias"));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Error al obtener los datos");
    }
  }

  @override
  void initState() {
    super.initState();
    _futureIncidencias = _obtenerIncidencias();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mis Reportes"),
        backgroundColor: Colors.red,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _futureIncidencias = _obtenerIncidencias();
              });
            },
          )
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _futureIncidencias,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("No hay incidencias registradas"));
          }

          final lista = snapshot.data!;
          return ListView.builder(
            itemCount: lista.length,
            itemBuilder: (context, index) {
              final item = lista[index];
              final String? nombreImagen = item['imagen'];

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: ListTile(
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
                      : const Icon(Icons.report_problem, size: 40, color: Colors.orange),
                  title: Text(
                    item['categoria'] ?? 'Sin Categoria',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(item['descripcion'] ?? ''),
                  trailing: Chip(
                    label: Text(
                      item['estado'] ?? 'Pendiente',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    backgroundColor: item['estado'] == 'Resuelto'
                        ? Colors.green
                        : Colors.orange,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// Pantalla 3: Estadísticas (Para Guía 3)
class EstadisticasPage extends StatelessWidget {
  const EstadisticasPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Estadísticas"),
        backgroundColor: Colors.red,
      ),
      body: const Center(
        child: Text("Módulo de Estadísticas (Guía 3)"),
      ),
    );
  }
}

// Pantalla 4: Resueltos (Para Guía 4)
class ResueltosPage extends StatelessWidget {
  const ResueltosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Resueltos"),
        backgroundColor: Colors.red,
      ),
      body: const Center(
        child: Text("Módulo de Reportes Resueltos (Guía 4)"),
      ),
    );
  }
}