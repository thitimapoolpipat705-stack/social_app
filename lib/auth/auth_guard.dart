import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AuthGuard extends ChangeNotifier {
  AuthGuard() {
    FirebaseAuth.instance.authStateChanges().listen((user) {
      _signedIn = user != null;
      notifyListeners();
    });
  }

  bool _signedIn = FirebaseAuth.instance.currentUser != null;
  bool get signedIn => _signedIn;

  String? redirect(BuildContext context, GoRouterState state) {
    // อนุญาตให้เข้าถึงหน้า sign-in, sign-up ได้เสมอ
    final allowedPaths = ['/sign-in', '/sign-up'];
    if (allowedPaths.contains(state.uri.path)) {
      return signedIn ? '/home' : null;
    }

    // ถ้าไม่ได้ล็อกอิน ให้ไปหน้า sign-in
    if (!signedIn) return '/sign-in';

    // ถ้าล็อกอินแล้วและอยู่หน้าแรก ให้ไปที่ /home
    if (state.uri.path == '/') return '/home';

    // กรณีอื่นๆ ไม่ต้อง redirect
    return null;
  }
}