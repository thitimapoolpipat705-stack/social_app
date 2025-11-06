// lib/core/reset_link_handler.dart
import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ResetLinkHandler {
  ResetLinkHandler._();
  static final instance = ResetLinkHandler._();

  final _auth = FirebaseAuth.instance;
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _sub;

  Future<void> init(BuildContext context) async {
    _appLinks = AppLinks();

    // ลิงก์ที่ใช้เปิดแอปครั้งแรก
    final initial = await _appLinks.getInitialLink();
    if (initial != null) _handleUri(context, initial);

    // ลิงก์ใหม่ขณะรันอยู่
    _sub?.cancel();
    _sub = _appLinks.uriLinkStream.listen((uri) => _handleUri(context, uri));
  }

  void dispose() => _sub?.cancel();

  Future<void> _handleUri(BuildContext context, Uri uri) async {
    debugPrint('🔗 incoming link: $uri');

    // เรารองรับเฉพาะ path /reset
    final pathOk = uri.path == '/reset' || uri.path.startsWith('/reset/');
    if (!pathOk) return;

    final mode = uri.queryParameters['mode'];
    final oobCode = uri.queryParameters['oobCode'];
    if (oobCode == null) {
      _toast(context, 'ลิงก์ไม่ถูกต้อง (ไม่มี oobCode)');
      return;
    }

    try {
      if (mode == 'resetPassword') {
        if (!context.mounted) return;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _SetNewPasswordPage(oobCode: oobCode),
        ));
      } else if (mode == 'verifyEmail') {
        await _auth.applyActionCode(oobCode);
        await _auth.currentUser?.reload();
        _toast(context, 'ยืนยันอีเมลเรียบร้อย');
      } else {
        _toast(context, 'โหมดไม่รองรับ: $mode');
      }
    } on FirebaseAuthException catch (e) {
      _toast(context, 'ลิงก์ไม่ถูกต้องหรือหมดอายุ (${e.code})');
    } catch (e) {
      _toast(context, 'เกิดข้อผิดพลาด: $e');
    }
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _SetNewPasswordPage extends StatefulWidget {
  final String oobCode;
  const _SetNewPasswordPage({required this.oobCode});

  @override
  State<_SetNewPasswordPage> createState() => _SetNewPasswordPageState();
}

class _SetNewPasswordPageState extends State<_SetNewPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _pass = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      // ตรวจสอบโค้ดก่อน
      await FirebaseAuth.instance.verifyPasswordResetCode(widget.oobCode);

      // ยืนยันตั้งรหัสใหม่
      await FirebaseAuth.instance.confirmPasswordReset(
        code: widget.oobCode,
        newPassword: _pass.text,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ตั้งรหัสผ่านใหม่เรียบร้อย')),
      );
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ล้มเหลว: ${e.code}')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ตั้งรหัสผ่านใหม่')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('กรอกรหัสผ่านใหม่ของคุณ'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pass,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'รหัสผ่านใหม่',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.length < 6) return 'อย่างน้อย 6 ตัวอักษร';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: Text(_loading ? 'กำลังบันทึก…' : 'ยืนยัน'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
