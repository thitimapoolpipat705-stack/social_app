// lib/auth/reset_password_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _email = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'กรุณากรอกอีเมล');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });

    try {
      // ✅ ใช้โดเมน Hosting จริง + เปิดในแอป เพื่อวิ่งเข้า /reset ที่เราดักไว้
      final acs = ActionCodeSettings(
        url: 'https://social-app-myproject.web.app/reset',
        handleCodeInApp: true,
        androidPackageName: 'com.example.social_app',
        androidInstallApp: true,
        androidMinimumVersion: '21',
        // ถ้า iOS ยังไม่ทำ bundle id ให้ตัดออกไปก่อนได้
        // iOSBundleId: 'com.example.socialApp',
      );

      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: email,
        actionCodeSettings: acs,
      );

      if (!mounted) return;
      setState(() {
        _info = 'ส่งลิงก์รีเซ็ตรหัสผ่านไปที่อีเมลแล้ว';
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message ?? e.code);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'you@example.com',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            if (_info != null)
              Text(_info!, style: const TextStyle(color: Colors.green)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loading ? null : _send,
              child: Text(_loading ? 'Sending…' : 'Send reset link'),
            ),
          ],
        ),
      ),
    );
  }
}
