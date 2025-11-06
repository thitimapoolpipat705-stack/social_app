import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _checkAuthAndRedirect();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _checkAuthAndRedirect();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _checkAuthAndRedirect();
  }

  void _checkAuthAndRedirect() {
    final auth = FirebaseAuth.instance;
    final context = navigator?.context;
    if (context == null) return;

    // ถ้าไม่ได้ล็อกอินและไม่ได้อยู่ในหน้าล็อกอิน/สมัครสมาชิก
    if (auth.currentUser == null &&
        !_isAuthRoute(ModalRoute.of(context))) {
      navigator?.pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  bool _isAuthRoute(ModalRoute<dynamic>? route) {
    if (route == null) return false;
    final settings = route.settings;
    return settings.name == '/login' || 
           settings.name == '/register' ||
           settings.name == '/forgot-password';
  }
}