// ─────────────────────────────────────────────────────────────
// 6. PANTALLA DE WEBCAM (solo se usa en el navegador)
// Usa directamente la API del navegador (getUserMedia), abre la cámara
// UNA sola vez, muestra la vista previa y devuelve la foto tomada.
// ─────────────────────────────────────────────────────────────
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class PantallaCamara extends StatefulWidget {
  const PantallaCamara({super.key});

  @override
  State<PantallaCamara> createState() => _PantallaCamaraState();
}

class _PantallaCamaraState extends State<PantallaCamara> {
  static int _contador = 0;
  late final String _idVista;
  final web.HTMLVideoElement _video = web.HTMLVideoElement();
  web.MediaStream? _stream;
  bool lista = false;
  String? error;

  @override
  void initState() {
    super.initState();
    // Elemento <video> de HTML donde se ve la webcam
    _video
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', '');
    _video.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'contain';

    // Registramos el <video> para poder mostrarlo como widget de Flutter
    _idVista = 'webcam-${_contador++}';
    ui_web.platformViewRegistry
        .registerViewFactory(_idVista, (int _) => _video);

    iniciarCamara();
  }

  Future<void> iniciarCamara() async {
    try {
      final constraints = web.MediaStreamConstraints(
        video: true.toJS,
      );

      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(constraints)
          .toDart;
      _stream = stream;
      _video.srcObject = stream;
      setState(() => lista = true);
    } catch (e) {
      setState(() => error = 'No se pudo abrir la cámara: $e\n\n'
          'Pasos para solucionarlo:\n'
          '1. Cierra completamente esta pestaña y abre una nueva.\n'
          '2. Asegúrate de que Zoom, Teams u otra app no la estén usando.\n'
          '3. Reinicia la terminal con "flutter run -d chrome".');
    }
  }

  void tomarFoto() {
    // Copiamos el cuadro actual del video a un <canvas> y lo pasamos a JPG
    final canvas = web.HTMLCanvasElement()
      ..width = _video.videoWidth
      ..height = _video.videoHeight;
    canvas.context2D.drawImage(_video, 0, 0);
    final dataUrl = canvas.toDataURL('image/jpeg', 0.9.toJS);
    final Uint8List bytes = base64Decode(dataUrl.split(',').last);

    apagarCamara();
    Navigator.pop(context, bytes); // Regresa la foto a la pantalla principal
  }

  void apagarCamara() {
    final stream = _stream;
    if (stream == null) return;
    for (final pista in stream.getTracks().toDart) {
      pista.stop();
    }
    _stream = null;
    _video.srcObject = null;
  }

  @override
  void dispose() {
    apagarCamara(); // Libera la webcam al salir
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tomar una foto')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
                  const Text(
                    'Mira a la cámara y sonríe 😊',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.pink.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.pink.shade100),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: error != null
                          ? SingleChildScrollView(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text('📷',
                                      style: TextStyle(fontSize: 40)),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'No pudimos iniciar la cámara',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(error!, textAlign: TextAlign.left),
                                ],
                              ),
                            )
                          : HtmlElementView(viewType: _idVista),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!lista && error == null)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 10),
                          Text('Conectando con la cámara…'),
                        ],
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: error != null
                          ? () => Navigator.pop(context)
                          : lista
                              ? tomarFoto
                              : null,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(error == null ? 'Capturar foto' : 'Cerrar'),
                    ),
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
