// lib/features/groups/create_group_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/group_service.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});
  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameCtl = TextEditingController();
  final _descCtl = TextEditingController();
  bool _isPrivate = false;

  XFile? _picked;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameCtl.dispose();
    _descCtl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x != null) setState(() => _picked = x);
  }

  String _inferContentType(String extLower) {
    switch (extLower) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _submit() async {
    final name = _nameCtl.text.trim();
    final description = _descCtl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter group name');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      // 1) สร้างกลุ่มก่อน (ให้ owner กลายเป็นสมาชิกด้วย)
      final gid = await GroupService.instance.createGroup(
        name: name,
        description: description,
        photoUrl: null, // อัปเดตทีหลังถ้ามีรูป
        isPrivate: _isPrivate,
      );

      // 2) ถ้ามีรูป -> อัปโหลดด้วย path ที่ rule อนุญาต: group-photos/{gid}/...
      String? photoUrl;
      if (_picked != null) {
        final ext = _picked!.name.contains('.') ? _picked!.name.split('.').last : 'jpg';
        // Use owner UID for storage path to match storage.rules (/group-photos/{ownerUid}/{file})
        final ownerUid = FirebaseAuth.instance.currentUser?.uid;
        if (ownerUid == null) throw 'Not signed in';
        final path = 'group-photos/$ownerUid/$gid.$ext';
        final meta = SettableMetadata(contentType: _inferContentType(ext.toLowerCase()));

        try {
          // Refresh token just before uploading to avoid expired/stale token issues
          await FirebaseAuth.instance.currentUser?.getIdToken(true);

          final snap = await FirebaseStorage.instance.ref(path).putFile(File(_picked!.path), meta);
          photoUrl = await snap.ref.getDownloadURL();

          // 3) อัปเดตฟิลด์ photoUrl ของกลุ่ม
          await GroupService.instance.updateGroup(groupId: gid, photoUrl: photoUrl);
        } on FirebaseException catch (e) {
          // Best-effort cleanup: delete the created group document if upload failed
          try {
            await GroupService.instance.deleteGroup(gid);
          } catch (_) {}

          // Surface clearer message to user (rules/App Check are common culprits)
          throw FirebaseException(
            plugin: e.plugin,
            code: e.code,
            message: 'Failed to upload group photo: ${e.message}.\n'
                'This can be caused by Storage Rules (missing member/owner doc) or App Check settings.\n'
                'Ensure the group document exists and your auth token is valid.',
          );
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(gid);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group created!')));
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
      appBar: AppBar(title: const Text('Create Group')),
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
                      decoration: const InputDecoration(labelText: 'Group name'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtl,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _isPrivate,
              onChanged: (v) => setState(() => _isPrivate = v),
              title: const Text('Private group'),
              subtitle: const Text('Only members can see posts'),
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
                label: Text(_submitting ? 'Creating…' : 'Create Group'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
