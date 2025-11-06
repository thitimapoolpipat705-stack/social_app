import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EditPageScreen extends StatefulWidget {
  final String pageId;
  const EditPageScreen({super.key, required this.pageId});

  @override
  State<EditPageScreen> createState() => _EditPageScreenState();
}

class _EditPageScreenState extends State<EditPageScreen> {
  final _nameCtl = TextEditingController();
  final _bioCtl = TextEditingController();
  bool _isPrivate = false;
  String? _currentPhotoUrl;

  XFile? _picked;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _bioCtl.dispose();
    super.dispose();
  }

  Future<void> _loadPage() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('pages')
          .doc(widget.pageId)
          .get();
      
      if (!snap.exists) {
        if (mounted) Navigator.pop(context);
        return;
      }

      final data = snap.data()!;
      setState(() {
        _nameCtl.text = data['name'] ?? '';
        _bioCtl.text = data['bio'] ?? '';
        _isPrivate = data['isPrivate'] ?? false;
        _currentPhotoUrl = data['photoUrl'];
      });
    } catch (e) {
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _pickImage() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x != null) setState(() => _picked = x);
  }

  Future<String?> _uploadIfNeed() async {
    if (_picked == null) return _currentPhotoUrl;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final ext = _picked!.name.split('.').last;
    final path = 'page-photos/${widget.pageId}/${DateTime.now().millisecondsSinceEpoch}.$ext';
    try {
      // refresh token
      try { await user.getIdToken(true); } catch (_) {}
      final snap = await FirebaseStorage.instance.ref(path).putFile(File(_picked!.path));
      return await snap.ref.getDownloadURL();
    } on FirebaseException catch (e) {
      throw 'Upload failed (${e.code}): ${e.message ?? ''}';
    }
  }

  Future<void> _submit() async {
    final name = _nameCtl.text.trim();
    final bio = _bioCtl.text.trim();
    if (name.isEmpty) { setState(() => _error = 'Please enter page name'); return; }

    setState(() { _submitting = true; _error = null; });
    try {
      final photoUrl = await _uploadIfNeed();
      await FirebaseFirestore.instance
          .collection('pages')
          .doc(widget.pageId)
          .update({
        'name': name,
        'bio': bio,
        'photoUrl': photoUrl,
        'isPrivate': _isPrivate,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Page updated!')),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Page')),
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
                      backgroundImage: _picked != null
                          ? FileImage(File(_picked!.path))
                          : (_currentPhotoUrl != null ? NetworkImage(_currentPhotoUrl!) : null) as ImageProvider?,
                      child: _picked == null && _currentPhotoUrl == null
                          ? const Icon(Icons.camera_alt_outlined)
                          : null,
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
              minLines: 3,
              maxLines: 5,
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
                label: Text(_submitting ? 'Saving…' : 'Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}