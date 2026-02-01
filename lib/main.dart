// lib/main.dart
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

// ==== Imports ของโปรเจกต์ ====
import 'firebase_options.dart';
import 'starter_app.dart'; // ✅ ใช้ StarterApp เป็น root
import 'services/messaging_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ป้องกัน error ตอนบูต Firebase
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
    debugPrint('Flutter error: ${details.exception}\n${details.stack}');
  };

  await runZonedGuarded(() async {
    // 1) Firebase Init
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('✅ Firebase initialized');
    } catch (e, st) {
      debugPrint('❌ Firebase init error: $e\n$st');
      if (kReleaseMode) rethrow;
    }

    // 2) App Check (Play Integrity / DeviceCheck)
    // NOTE: App Check can block storage uploads on debug/dev builds if Play
    // Integrity / DeviceCheck attestation fails. Only enable automatic App
    // Check activation in release mode here. For local development, this
    // avoids upload errors like "Object does not exist" caused by failed
    // attestation.
    try {
      if (!kIsWeb && kReleaseMode) {
        if (Platform.isAndroid) {
          await FirebaseAppCheck.instance.activate(
            androidProvider: AndroidProvider.playIntegrity,
          );
        } else if (Platform.isIOS) {
          await FirebaseAppCheck.instance.activate(
            appleProvider: AppleProvider.deviceCheck,
          );
        }
        await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
      }
    } catch (e, st) {
      debugPrint('⚠️ AppCheck activate error: $e\n$st');
      if (kReleaseMode) rethrow;
    }

    // 3) Messaging: register background handler and init messaging service
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await MessagingService.instance.init();
      debugPrint('✅ Messaging initialized');
    } catch (e, st) {
      debugPrint('⚠️ Messaging init error: $e\n$st');
    }

    // ✅ Run app
    runApp(const StarterAppRoot());
  }, (error, stack) {
    debugPrint('Startup error: $error\n$stack');
  });
}

// ✅ Wrapper ให้ StarterApp มี MaterialApp เดียวในระบบ
class StarterAppRoot extends StatelessWidget {
  const StarterAppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Social App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        // Modern gradient-inspired color scheme: Vibrant Purple & Blue
        colorSchemeSeed: const Color(0xFF6366F1), // Indigo - modern & professional
        brightness: Brightness.light,
        // Optional: Fine-tune the color scheme further
        splashFactory: InkRipple.splashFactory,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
      ),
      home: StarterApp(), // << ตัว GoRouter หลักอยู่ใน starter_app.dart
    );
  }
}
