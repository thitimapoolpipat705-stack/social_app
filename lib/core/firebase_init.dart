// lib/core/firebase_init.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../firebase_options.dart';

enum AppEnv { dev, prod }

class FirebaseBootstrap {
  static Future<void> init({required AppEnv env, String? deviceHost}) async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    if (env == AppEnv.dev) {
      // ✅ เลือก host ให้เหมาะกับแพลตฟอร์ม
      final host = deviceHost ??
          (kIsWeb
              ? 'localhost'
              : Platform.isAndroid
                  ? '10.0.2.2'
                  : 'localhost');

      const authPort = 9099;
      const firestorePort = 8080;
      const storagePort = 9199;
      const functionsPort = 5001; // ให้ตรงกับ emulator ของคุณ
      const functionsRegion = 'us-central1'; // ให้ตรงกับ region ที่ใช้งาน

      FirebaseFirestore.instance.useFirestoreEmulator(host, firestorePort);
      await FirebaseAuth.instance.useAuthEmulator(host, authPort);
      FirebaseStorage.instance.useStorageEmulator(host, storagePort);
      FirebaseFunctions.instanceFor(region: functionsRegion)
          .useFunctionsEmulator(host, functionsPort);

      // ตัวเลือก: เปิด persistence ใน dev
      FirebaseFirestore.instance.settings =
          const Settings(persistenceEnabled: true);
    }
  }
}
