// lib/pages/create_post_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class CreatePostPage extends StatefulWidget {
  const CreatePostPage({super.key});

  @override
  State<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends State<CreatePostPage> {
  final _textCtl = TextEditingController();
  final _picker = ImagePicker();
  final List<XFile> _images = [];
  final List<XFile> _videos = [];
  bool _posting = false;

  @override
  void dispose() {
    _textCtl.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photos (multi-select)'),
              onTap: () => Navigator.pop(context, 'photos'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video (pick one)'),
              onTap: () => Navigator.pop(context, 'video'),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;

    if (action == 'photos') {
      final picked = await _picker.pickMultiImage(imageQuality: 85);
      if (picked.isNotEmpty) {
        setState(() => _images.addAll(picked.take(8 - _images.length)));
      }
    } else if (action == 'video') {
      final f = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 5));
      if (f != null) setState(() => _videos.add(f));
    }
  }

  String _inferContentType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    return 'application/octet-stream';
  }

  /// Upload selected images/videos and return media descriptors
  Future<List<Map<String, dynamic>>> _uploadAll(String postId, String uid) async {
    final storage = FirebaseStorage.instance;
    final out = <Map<String, dynamic>>[];

    for (int i = 0; i < _images.length; i++) {
      final f = _images[i];
      final file = File(f.path);
      final ext = f.name.contains('.') ? f.name.split('.').last : 'jpg';
      final name = 'img_${i}.${ext}';
      final ref = storage.ref().child('posts').child(uid).child(postId).child(name);
      final meta = SettableMetadata(contentType: _inferContentType(name), cacheControl: 'public, max-age=3600');
      try {
        debugPrint('⬆️ Uploading ${ref.fullPath} to bucket ${ref.bucket}');
        final task = await ref.putFile(file, meta);
        final url = await task.ref.getDownloadURL();
        debugPrint('✅ Upload success: $url');
        out.add({'url': url, 'type': 'image', 'filename': name});
      } catch (e, st) {
        debugPrint('❌ Upload error for "${ref.fullPath}": $e\n$st');
        // add path info to help debugging
        throw 'Upload failed for storage path "${ref.fullPath}" (bucket: ${ref.bucket}): $e';
      }
    }

    for (int i = 0; i < _videos.length; i++) {
      final f = _videos[i];
      final file = File(f.path);
      final ext = f.name.contains('.') ? f.name.split('.').last : 'mp4';
      final name = 'vid_${i}.${ext}';
      final ref = storage.ref().child('posts').child(uid).child(postId).child(name);
      final meta = SettableMetadata(contentType: _inferContentType(name), cacheControl: 'public, max-age=3600');
      try {
        debugPrint('⬆️ Uploading video ${ref.fullPath} to bucket ${ref.bucket}');
        final task = await ref.putFile(file, meta);
        final url = await task.ref.getDownloadURL();
        debugPrint('✅ Upload success: $url');
        out.add({'url': url, 'type': 'video', 'filename': name});
      } catch (e, st) {
        debugPrint('❌ Upload error for "${ref.fullPath}": $e\n$st');
        throw 'Upload failed for storage path "${ref.fullPath}" (bucket: ${ref.bucket}): $e';
      }
    }

    return out;
  }

  Future<void> _submit() async {
    if (_posting) return;
    final me = FirebaseAuth.instance.currentUser;
    final text = _textCtl.text.trim();

    if (me == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in')),
      );
      return;
    }
    if (text.isEmpty && _images.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('พิมพ์ข้อความหรือเลือกรูปอย่างน้อย 1 รายการ')),
      );
      return;
    }

    try {
      setState(() => _posting = true);

      // เตรียมเอกสารล่วงหน้า เอา postId ไปตั้ง path storage
      final posts = FirebaseFirestore.instance.collection('posts');
      final doc = posts.doc();

    // อัปโหลดสื่อ (รูป/วิดีโอ) ถ้ามี
    final mediaList = await _uploadAll(doc.id, me.uid);

      // สร้างโพสต์ใหม่ใน Firestore
      await doc.set({
        'authorId': me.uid,
        'authorName': me.displayName ?? me.uid,
        'authorAvatarUrl': me.photoURL ?? '',
        'text': text,
        'media': mediaList,                 // [] ก็ได้
        'visibility': 'public',
        'commentsCount': 0,
        'createdAt': FieldValue.serverTimestamp(),  // ⬅️ สำคัญ ผ่าน rules
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // เพิ่มจำนวนโพสต์ใน users
      await FirebaseFirestore.instance.collection('users').doc(me.uid).update({
        'postsCount': FieldValue.increment(1),  // เพิ่มจำนวนโพสต์
      });

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Post failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canPost = !_posting && (_textCtl.text.trim().isNotEmpty || _images.isNotEmpty);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create post'),
        actions: [
          TextButton(
            onPressed: canPost ? _submit : null,
            child: const Text('Post'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Theme.of(context).dividerColor.withOpacity(.2)),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // กล่องพิมพ์
            TextField(
              controller: _textCtl,
              maxLines: null,
              decoration: InputDecoration(
                hintText: "What's on your mind?",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.all(12),
                fillColor: cs.surfaceVariant.withOpacity(.25),
                filled: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),

            // พรีวิวรูปเป็นกริด + ปุ่มเพิ่ม
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // ปุ่มเพิ่มสื่อ (รูป/วิดีโอ)
                InkWell(
                  onTap: _posting ? null : _pickMedia,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 96,
                    height: 96,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: cs.surfaceVariant.withOpacity(.5),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: const Icon(Icons.add_a_photo_outlined),
                  ),
                ),
                // แสดงรูปที่เลือก
                ..._images.map((x) {
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(x.path),
                          width: 96,
                          height: 96,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        right: 4,
                        top: 4,
                        child: InkWell(
                          onTap: _posting ? null : () => setState(() => _images.remove(x)),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.all(2),
                            child: const Icon(Icons.close, size: 16, color: Colors.white),
                          ),
                        ),
                      )
                    ],
                  );
                }),
                // แสดงวิดีโอที่เลือก
                ..._videos.map((v) {
                  final name = v.name.isNotEmpty ? v.name : v.path.split('/').last;
                  return Stack(
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.black12,
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.videocam_outlined, size: 32),
                              const SizedBox(height: 4),
                              Flexible(child: Text(name, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        right: 4,
                        top: 4,
                        child: InkWell(
                          onTap: _posting ? null : () => setState(() => _videos.remove(v)),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.all(2),
                            child: const Icon(Icons.close, size: 16, color: Colors.white),
                          ),
                        ),
                      )
                    ],
                  );
                }),
              ],
            ),

            if (_posting) ...[
              const SizedBox(height: 20),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}
