import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../services/page_service.dart';

class CreatePageScreen extends StatefulWidget {
  const CreatePageScreen({super.key});

  @override
  State<CreatePageScreen> createState() => _CreatePageScreenState();
}

class _CreatePageScreenState extends State<CreatePageScreen> {
  final _nameCtl = TextEditingController();
  final _bioCtl = TextEditingController();
  bool _isPrivate = false;

  XFile? _picked;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameCtl.dispose();
    _bioCtl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x != null) setState(() => _picked = x);
  }

  // Image upload is handled after creating page to satisfy storage rules

  Future<void> _submit() async {
    final name = _nameCtl.text.trim();
    final bio = _bioCtl.text.trim();
    if (name.isEmpty) { setState(() => _error = 'Please enter page name'); return; }

    setState(() { _submitting = true; _error = null; });
    try {
      // Create page first (so storage rules that check page owner can pass)
      final pageId = await PageService.instance.createPage(
        name: name,
        bio: bio,
        photoUrl: null,
        isPrivate: _isPrivate,
      );

      String? photoUrl;
      if (_picked != null) {
        // refresh token to avoid expired-token issues
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser == null) throw 'Not signed in';
        await currentUser.getIdToken(true);

        final ext = _picked!.name.split('.').last;
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final path = 'page-photos/$pageId/$timestamp.$ext';
        try {
          final snap = await FirebaseStorage.instance.ref(path).putFile(File(_picked!.path));
          photoUrl = await snap.ref.getDownloadURL();
          // update page with photoUrl
          await PageService.instance.updatePage(pageId: pageId, photoUrl: photoUrl);
        } catch (e) {
          // If upload failed, remove created page to avoid orphan (best-effort)
          try { await PageService.instance.deletePage(pageId); } catch (_) {}
          rethrow;
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(pageId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Page created!')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Create Page')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceVariant.withOpacity(.35),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: _pickImage,
                    borderRadius: BorderRadius.circular(48),
                    child: CircleAvatar(
                      radius: 36,
                      backgroundImage: _picked != null ? FileImage(File(_picked!.path)) : null,
                      child: _picked == null ? const Icon(Icons.camera_alt_outlined) : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _nameCtl,
                      decoration: const InputDecoration(labelText: 'Page name', hintText: 'e.g. Daily Quotes'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bioCtl,
              minLines: 3, maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Bio / Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _isPrivate,
              onChanged: (v) => setState(() => _isPrivate = v),
              title: const Text('Private page'),
              subtitle: const Text('Only approved followers can see posts'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(_submitting ? 'Creating…' : 'Create Page'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
