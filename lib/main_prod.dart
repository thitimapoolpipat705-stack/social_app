// lib/main_prod.dart
import 'package:flutter/material.dart';
import 'core/firebase_init.dart';
import 'starter_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // โปรดักชัน: ไม่ต่อ Emulator
  await FirebaseBootstrap.init(env: AppEnv.prod);
  runApp(StarterApp());
}
