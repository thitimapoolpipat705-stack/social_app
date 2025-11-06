// lib/main_dev.dart
import 'package:flutter/material.dart';
import 'core/firebase_init.dart';
import 'starter_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ ใช้ Firebase Emulator (โหมด Dev)
  await FirebaseBootstrap.init(env: AppEnv.dev);

  runApp(StarterApp());
}
