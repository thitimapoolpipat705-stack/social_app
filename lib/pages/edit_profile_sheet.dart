// lib/pages/edit_profile_sheet.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditProfileSheet extends StatefulWidget {
  const EditProfileSheet({super.key});

  @override
  State<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<EditProfileSheet> {
  final _nameCtl = TextEditingController();
  final _bioCtl = TextEditingController();

  // preview จากบัญชีปัจจุบัน / Firestore
  String _currentAvatarUrl = '';
  String _currentCoverUrl = '';

  // ไฟล์ใหม่ที่เลือก (ยังไม่อัปโหลด)
  Uint8List? _avatarBytes;
  Uint8List? _coverBytes;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final u = FirebaseAuth.instance.currentUser;
    _nameCtl.text = u?.displayName ?? '';

    final uid = u?.uid;
    if (uid != null) {
      FirebaseFirestore.instance.collection('users').doc(uid).get().then((doc) {
        if (!mounted) return;
        final data = doc.data();
        if (data != null) {
          _bioCtl.text = (data['bio'] ?? '').toString();
          _currentCoverUrl = (data['coverUrl'] ?? '').toString();
          // ถ้า photoURL ใน Auth ว่าง ลองดึงจาก Firestore
          _currentAvatarUrl =
              (u?.photoURL?.isNotEmpty == true) ? u!.photoURL! : (data['photoURL'] ?? '').toString();
        }
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _bioCtl.dispose();
    super.dispose();
  }

  Future<Uint8List?> _pickAndCompress({required bool isCover}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 3000,
      maxHeight: 3000,
      imageQuality: 98,
    );
    if (picked == null) return null;

    final raw = await picked.readAsBytes();
    // ปกอาจอยากได้กว้างขึ้นนิด ส่วนโปรไฟล์ 1:1 ก็โอเค
    final compressed = await FlutterImageCompress.compressWithList(
      raw,
      minWidth: isCover ? 1200 : 640,
      minHeight: isCover ? 600 : 640,
      quality: 86,
      format: CompressFormat.jpeg, // กัน HEIC
    );
    return compressed;
  }

  Future<void> _pickAvatar() async {
    final bytes = await _pickAndCompress(isCover: false);
    if (bytes == null) return;
    setState(() => _avatarBytes = bytes);
  }

  Future<void> _pickCover() async {
    final bytes = await _pickAndCompress(isCover: true);
    if (bytes == null) return;
    setState(() => _coverBytes = bytes);
  }

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final newName = _nameCtl.text.trim();
    final newBio = _bioCtl.text.trim();

    if (newName.isEmpty && newBio.isEmpty && _avatarBytes == null && _coverBytes == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    setState(() => _saving = true);
    try {
      String? avatarUrl = _currentAvatarUrl;
      String? coverUrl = _currentCoverUrl;

      // 1) อัปโหลดรูปใหม่ (ถ้ามี)
      final storage = FirebaseStorage.instance;

      if (_avatarBytes != null) {
        final ref = storage.ref('user-photos/$uid/avatar.jpg');
        await ref.putData(
          _avatarBytes!,
          SettableMetadata(
            contentType: 'image/jpeg',
            cacheControl: 'public, max-age=3600',
          ),
        );
        avatarUrl = await ref.getDownloadURL();
      }

      if (_coverBytes != null) {
        final ref = storage.ref('user-photos/$uid/cover.jpg');
        await ref.putData(
          _coverBytes!,
          SettableMetadata(
            contentType: 'image/jpeg',
            cacheControl: 'public, max-age=3600',
          ),
        );
        coverUrl = await ref.getDownloadURL();
      }

      // 2) อัปเดต Auth (ชื่อ/รูปโปรไฟล์)
      if (newName.isNotEmpty && newName != user.displayName) {
        await user.updateDisplayName(newName);
      }
      if ((avatarUrl ?? '').isNotEmpty && avatarUrl != user.photoURL) {
        await user.updatePhotoURL(avatarUrl);
      }
      await user.reload();

      // 3) อัปเดต Firestore
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final snap = await userRef.get();

      final displayNameToWrite =
          newName.isNotEmpty ? newName : (FirebaseAuth.instance.currentUser?.displayName ?? '');

      final dataToSet = <String, dynamic>{
        'displayName': displayNameToWrite,
        'displayNameLower': displayNameToWrite.toLowerCase(),
        'bio': newBio,
        if ((avatarUrl ?? '').isNotEmpty) 'photoURL': avatarUrl,
        if ((coverUrl ?? '').isNotEmpty) 'coverUrl': coverUrl,
        'email': user.email,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (!snap.exists) {
        dataToSet['createdAt'] = FieldValue.serverTimestamp();
      }
      await userRef.set(dataToSet, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกโปรไฟล์แล้ว')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('บันทึกล้มเหลว: $e')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets;

    // รูปที่จะแสดงตอนพรีวิว (ถ้ามีไฟล์ใหม่ → ใช้ไฟล์ใหม่; ไม่มีก็ใช้ URL ปัจจุบัน)
    ImageProvider? _avatarImageProvider() {
      if (_avatarBytes != null) return MemoryImage(_avatarBytes!);
      if (_currentAvatarUrl.isNotEmpty) return NetworkImage(_currentAvatarUrl);
      return null;
    }

    Widget _coverWidget() {
      if (_coverBytes != null) {
        return Image.memory(_coverBytes!, fit: BoxFit.cover);
      }
      if (_currentCoverUrl.isNotEmpty) {
        return Image.network(
          _currentCoverUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade300),
        );
      }
      return Container(color: Theme.of(context).colorScheme.surfaceVariant);
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 12,
          bottom: 16 + insets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // drag handle
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),

            // ====== พรีวิว COVER + ปุ่มแก้ ======
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  children: [
                    Positioned.fill(child: _coverWidget()),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: FilledButton.tonalIcon(
                        onPressed: _saving ? null : _pickCover,
                        icon: const Icon(Icons.photo),
                        label: const Text('Change cover'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ====== พรีวิว AVATAR + ปุ่มแก้ ======
            GestureDetector(
              onTap: _saving ? null : _pickAvatar,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundImage: _avatarImageProvider(),
                    child: _avatarImageProvider() == null
                        ? const Icon(Icons.camera_alt, size: 28)
                        : null,
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit, size: 16, color: Colors.white),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Display name
            TextField(
              controller: _nameCtl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Display name',
                hintText: 'ใส่ชื่อที่จะแสดง',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            // Bio
            TextField(
              controller: _bioCtl,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Bio',
                hintText: 'คำอธิบายสั้น ๆ เกี่ยวกับตัวคุณ',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 12),

            // Save button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_saving ? 'Saving...' : 'Save changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
