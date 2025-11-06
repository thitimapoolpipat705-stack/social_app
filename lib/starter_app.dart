import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'starter_screens.dart';
import 'home_scaffold.dart';
import 'auth/auth_guard.dart';

class StarterApp extends StatefulWidget {
  const StarterApp({super.key});

  @override
  State<StarterApp> createState() => _StarterAppState();
}

class _StarterAppState extends State<StarterApp> {
  late final AuthGuard _authGuard;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _authGuard = AuthGuard();
    _router = GoRouter(
      initialLocation: '/sign-in',
      routes: [
        GoRoute(path: '/sign-in', builder: (_, __) => const SignInScreen()),
        GoRoute(path: '/sign-up', builder: (_, __) => const SignUpScreen()),
        GoRoute(path: '/home', builder: (_, __) => const HomeScaffold()),
      ],
      redirect: _authGuard.redirect,
      refreshListenable: _authGuard,
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ ใช้ Router widget แทน ไม่สร้าง MaterialApp ซ้อน
    return Router(
      routerDelegate: _router.routerDelegate,
      routeInformationParser: _router.routeInformationParser,
      routeInformationProvider: _router.routeInformationProvider,
      backButtonDispatcher: RootBackButtonDispatcher(),
    );
  }
}
