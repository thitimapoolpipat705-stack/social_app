// lib/services/firestore_service.dart
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// ใช้ส่งไฟล์จากหน้า Create/Edit
class UploadPart {
  final Uint8List bytes;
  final String filename;        // ex. abc.jpg / xyz.mp4
  final String contentType;     // ex. image/jpeg, video/mp4
  final String type;            // 'image' | 'video'
  UploadPart({
    required this.bytes,
    required this.filename,
    required this.contentType,
    required this.type,
  });
}

class FirestoreService {
  FirestoreService._();
  static final instance = FirestoreService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _storage = FirebaseStorage.instance;

  /// อ่านชื่อ/รูปจาก users/{uid}
  Future<Map<String, String?>> _authorMeta(String uid) async {
    try {
      final snap = await _db.collection('users').doc(uid).get();
      final data = snap.data() ?? const {};
      return {
        'name': (data['displayName'] as String?) ?? uid,
        'avatar': data['photoURL'] as String?,
      };
    } catch (_) {
      return {'name': uid, 'avatar': null};
    }
  }

  /// อัปโหลดไฟล์ตัวเดียว -> คืน URL
    Future<String> _uploadPostFile({
    required String uid,
    required String postId,
    required UploadPart part,
  }) async {
    try {
      // ✅ path ต้องตรงกับ storage.rules: posts/{uid}/{postId}/{filename}
      final ref = _storage.ref('posts/$uid/$postId/${part.filename}');

      // 🔎 DEBUG: ดูว่าเราอัปไป bucket/เส้นทางไหน และ auth ใคร
      // ignore: avoid_print
      print('[UPLOAD] bucket=${ref.bucket} path=${ref.fullPath} '
            'uid=${_auth.currentUser?.uid} filename=${part.filename} '
            'ctype=${part.contentType}');

      final task = await ref.putData(
        part.bytes,
        SettableMetadata(
          contentType: part.contentType,
          // (ออปชัน) เก็บ owner/postId ไว้ใน metadata เพื่อ debug ง่ายขึ้น
          customMetadata: {
            'ownerUid': uid,
            'postId': postId,
          },
        ),
      );

      final url = await task.ref.getDownloadURL();
      // ignore: avoid_print
      print('[UPLOAD] OK -> $url');
      return url;
    } on FirebaseException catch (e, st) {
      // ignore: avoid_print
      print('[UPLOAD][FirebaseException] code=${e.code} msg=${e.message}\n$st');
      rethrow; // โยนให้ UI จับแสดง error
    } catch (e, st) {
      // ignore: avoid_print
      print('[UPLOAD][Unknown] $e\n$st');
      rethrow;
    }
  }


  /// อัปโหลดหลายไฟล์แล้วคืน media list สำหรับเก็บในโพสต์
  Future<List<Map<String, dynamic>>> _uploadAllPostMedia({
    required String uid,
    required String postId,
    required List<UploadPart> parts,
  }) async {
    final out = <Map<String, dynamic>>[];
    for (final p in parts) {
      final url = await _uploadPostFile(uid: uid, postId: postId, part: p);
      out.add({
        'url': url,
        'type': p.type,         // 'image' | 'video'
        'filename': p.filename,
      });
    }
    return out;
  }

  /// สร้างโพสต์ใหม่ (อัปโหลดสื่อก่อน แล้วอัปเดต media ลงโพสต์)
  Future<void> createPost({
    required String uid,
    required String text,
    required List<UploadPart> newMedia,
  }) async {
    final meta = await _authorMeta(uid);

    // สร้างเอกสารเปล่า media=[] ก่อน เพื่อได้ postId
    final docRef = await _db.collection('posts').add({
      'authorId': uid,
      'authorName': meta['name'],
      'authorAvatarUrl': meta['avatar'],
      'text': text,
      'media': [], // จะอัปเดตภายหลัง
      'visibility': 'public',
      'commentsCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // อัปโหลดไฟล์ แล้วอัปเดต media array
    if (newMedia.isNotEmpty) {
      final media = await _uploadAllPostMedia(
        uid: uid,
        postId: docRef.id,
        parts: newMedia,
      );
      await docRef.update({
        'media': media,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// แก้ไขโพสต์ (รวมของเดิม + ของใหม่)
  Future<void> updatePost({
    required String postId,
    required String uid,
    required String newText,
    required List<Map<String, dynamic>> existingMedia, // จากหน้า Edit
    required List<UploadPart> newMedia,                // ใหม่ (อัปขึ้น Storage)
  }) async {
    // อัปโหลดของใหม่
    List<Map<String, dynamic>> uploaded = const [];
    if (newMedia.isNotEmpty) {
      uploaded = await _uploadAllPostMedia(
        uid: uid,
        postId: postId,
        parts: newMedia,
      );
    }

    // รวมสื่อเดิม(ที่ผู้ใช้ยังคงไว้) + สื่อใหม่
    final merged = <Map<String, dynamic>>[
      ...existingMedia.map((m) => Map<String, dynamic>.from(m)),
      ...uploaded,
    ];

    await _db.collection('posts').doc(postId).update({
      'text': newText,
      'media': merged,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// (ออปชัน) ลบโพสต์ + ลบไฟล์ใน Storage
  Future<void> deletePost({
    required String postId,
    required String uid,
  }) async {
    // ลบไฟล์ทั้งหมดในโฟลเดอร์ posts/{uid}/{postId}/
    final dir = _storage.ref('posts/$uid/$postId');
    try {
      final list = await dir.listAll();
      for (final f in list.items) {
        await f.delete();
      }
    } catch (_) {
      // ข้ามได้ ถ้าไม่มีไฟล์
    }
    await _db.collection('posts').doc(postId).delete();
  }
}


