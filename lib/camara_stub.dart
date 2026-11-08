import 'package:flutter/material.dart';

class PantallaCamara extends StatelessWidget {
  const PantallaCamara({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cámara')),
      body: const Center(
        child: Text('La cámara web solo está disponible en el navegador.'),
      ),
    );
  }
}
