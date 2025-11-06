// lib/pages/create_or_edit_post_page.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/firestore_service.dart';

class CreateOrEditPostPage extends StatefulWidget {
  final String? postId; // null = สร้างใหม่, not-null = แก้ไข
  const CreateOrEditPostPage({super.key, this.postId});

  @override
  State<CreateOrEditPostPage> createState() => _CreateOrEditPostPageState();
}
    
class _CreateOrEditPostPageState extends State<CreateOrEditPostPage> {
  final _textCtl = TextEditingController();
  bool _loading = false;
  String? _error;

  // media ใหม่ที่เลือกในหน้านี้
  final List<_NewMedia> _newMedia = [];

  // media เดิมที่โพสต์มีอยู่ (แก้ไขเท่านั้น)
  List<Map<String, dynamic>> _existingMedia = [];

  bool get _isEdit => widget.postId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _loadExisting();
    }
  }

  // Load existing post data
Future<void> _loadExisting() async {
  setState(() => _loading = true);
  try {
    final doc = await FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .get();
    if (!doc.exists) {
      setState(() {
        _error = 'Post not found';
        _loading = false;
      });
      return;
    }
    final data = doc.data() as Map<String, dynamic>;
    _textCtl.text = (data['text'] as String?) ?? '';

    final raw = data['media'];
    _existingMedia = _normalizeExistingMedia(raw);

    setState(() => _loading = false);
  } catch (e) {
    setState(() {
      _error = e.toString();
      _loading = false;
    });
  }
}

List<Map<String, dynamic>> _normalizeExistingMedia(dynamic raw) {
  if (raw == null) return [];
  if (raw is String) {
    return [
      {'url': raw, 'type': _guessType(raw)},
    ];
  }
  if (raw is List) {
    final out = <Map<String, dynamic>>[];
    for (final it in raw) {
      if (it is String) {
        out.add({'url': it, 'type': _guessType(it)});
      } else if (it is Map) {
        final m = Map<String, dynamic>.from(it);
        m['type'] ??= _guessType(m['url'] as String? ?? '');
        out.add(m);
      }
    }
    return out;
  }
  return [];
}

String _guessType(String url) {
  final u = url.toLowerCase();
  if (u.endsWith('.mp4') || u.endsWith('.mov') || u.contains('video')) return 'video';
  return 'image';
}


  // _pickImages function (แก้ไขการบีบอัดภาพ)
Future<void> _pickImages() async {
  final picker = ImagePicker();
  final files = await picker.pickMultiImage(maxWidth: 2048, maxHeight: 2048, imageQuality: 95);
  if (files == null || files.isEmpty) return; // ถ้าไม่เลือกไฟล์

  for (final f in files) {
    final raw = await f.readAsBytes();  // อ่านไฟล์เป็น bytes
    final compressed = await FlutterImageCompress.compressWithList(
      raw,
      minWidth: 1080,
      minHeight: 1080,
      quality: 85,
      format: CompressFormat.jpeg,
    );

    _newMedia.add(_NewMedia(
      bytes: compressed,
      filename: f.name.endsWith('.jpg') || f.name.endsWith('.jpeg')
          ? f.name
          : '${DateTime.now().millisecondsSinceEpoch}.jpg',
      contentType: 'image/jpeg',
      type: 'image',
    ));
  }
  setState(() {});
}

Future<void> _pickVideo() async {
  final picker = ImagePicker();
  final f = await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 2));
  if (f == null) return;
  final bytes = await f.readAsBytes();
  _newMedia.add(_NewMedia(
    bytes: bytes,
    filename: f.name.isNotEmpty ? f.name : '${DateTime.now().millisecondsSinceEpoch}.mp4',
    contentType: 'video/mp4',
    type: 'video',
  ));
  setState(() {});
}

  Future<void> _save() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    setState(() => _error = 'Not signed in');
    return;
  }
  final text = _textCtl.text.trim();
  if (text.isEmpty && _existingMedia.isEmpty && _newMedia.isEmpty) {
    setState(() => _error = 'Post is empty');
    return;
  }

  setState(() {
    _loading = true;
    _error = null;
  });

  try {
    if (_isEdit) {
      await FirestoreService.instance.updatePost(
        postId: widget.postId!,
        uid: uid,
        newText: text,
        existingMedia: _existingMedia,
        newMedia: _newMedia.map((m) => m.toUploadPart()).toList(),
      );
    } else {
      await FirestoreService.instance.createPost(
        uid: uid,
        text: text,
        newMedia: _newMedia.map((m) => m.toUploadPart()).toList(),
      );
    }
    if (!mounted) return;
    Navigator.pop(context, true);
  } catch (e) {
    setState(() => _error = e.toString());
  } finally {
    if (mounted) setState(() => _loading = false);
  }
}


  @override
  void dispose() {
    _textCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEdit ? 'Edit post' : 'Create post';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: Text(_isEdit ? 'Save' : 'Post'),
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: _textCtl,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: 'Write a caption...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // Existing media (edit mode)
                if (_existingMedia.isNotEmpty) ...[
                  Text('Existing media', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _existingMedia.map((m) {
                      final url = m['url'] as String? ?? '';
                      final type = m['type'] as String? ?? 'image';
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 96,
                              height: 96,
                              color: Colors.black12,
                              alignment: Alignment.center,
                              child: type == 'image'
                                  ? Image.network(url, width: 96, height: 96, fit: BoxFit.cover)
                                  : const Icon(Icons.videocam_outlined, size: 28),
                            ),
                          ),
                          Positioned(
                            top: 4, right: 4,
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _existingMedia.remove(m); // remove from list (ลบจริงตอน Save)
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black54, borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.all(2),
                                child: const Icon(Icons.close, color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ],

                if (_newMedia.isNotEmpty) ...[
                  Text('New media', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _newMedia.map((m) {
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 96,
                              height: 96,
                              color: Colors.black12,
                              alignment: Alignment.center,
                              child: m.type == 'image'
                                  ? Image.memory(m.bytes, width: 96, height: 96, fit: BoxFit.cover)
                                  : const Icon(Icons.videocam_outlined, size: 28),
                            ),
                          ),
                          Positioned(
                            top: 4, right: 4,
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _newMedia.remove(m);
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black54, borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.all(2),
                                child: const Icon(Icons.close, color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ],

                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickImages,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Photos'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _pickVideo,
                      icon: const Icon(Icons.videocam_outlined),
                      label: const Text('Video'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _loading ? null : _save,
                      icon: const Icon(Icons.send),
                      label: Text(_isEdit ? 'Save' : 'Post'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _NewMedia {
  final Uint8List bytes;
  final String filename;
  final String contentType; // 'image/jpeg' | 'video/mp4'
  final String type;        // 'image' | 'video'
  _NewMedia({
    required this.bytes,
    required this.filename,
    required this.contentType,
    required this.type,
  });

  UploadPart toUploadPart() => UploadPart(
        bytes: bytes,
        filename: filename,
        contentType: contentType,
        type: type,
      );
}
