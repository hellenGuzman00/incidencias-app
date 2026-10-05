import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const SistemaIncidencias());
}

class SistemaIncidencias extends StatelessWidget {
  const SistemaIncidencias({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Incidencias Escolares",
      theme: ThemeData(
        primarySwatch: Colors.red,
      ),
      home: const InicioPage(),
    );
  }
}

class InicioPage extends StatefulWidget {
  const InicioPage({super.key});

  @override
  State<InicioPage> createState() => _InicioPageState();
}

class _InicioPageState extends State<InicioPage> {
  final descripcionController = TextEditingController();
  String categoriaSeleccionada = "1";

  Future<void> registrarIncidencia() async {
    final url = Uri.parse(
        "https://incidencias-backend-abt2.onrender.com/incidencias");

    await http.post(
      url,
      headers: {
        "Content-Type": "application/json"
      },
      body: jsonEncode({
        "categoria_id": categoriaSeleccionada,
        "descripcion": descripcionController.text
      }),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text("Incidencia registrada correctamente")),
    );
    descripcionController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Incidencias Escolares"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
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
                setState(() {
                  categoriaSeleccionada = valor!;
                });
              },
            ),
            const SizedBox(height: 20),
            TextField(
              controller: descripcionController,
              maxLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: "Descripción de la incidencia",
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: registrarIncidencia,
              child: const Text("Registrar Incidencia"),
            )
          ],
        ),
      ),
    );
  }
}