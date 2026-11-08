import 'package:flutter/material.dart';

import 'firebase_backend.dart';
import 'tienda_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseBackend.initialize();
  runApp(const TiendaApp());
}
