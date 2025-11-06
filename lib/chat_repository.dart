// lib/chat_repository.dart
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ChatRepository {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _storage = FirebaseStorage.instance;

  // ---------- Helpers ----------
  String _cidFor(String a, String b) {
    final x = [a, b]..sort();
    return '${x[0]}_${x[1]}';
  }

  String _timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

  // เดา contentType จากนามสกุลแบบง่าย
  String _inferContentType(String filename) {
    final lower = filename.toLowerCase();
    // Images
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    // Videos
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.avi')) return 'video/x-msvideo';
    if (lower.endsWith('.wmv')) return 'video/x-ms-wmv';
    if (lower.endsWith('.3gp')) return 'video/3gpp';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    // Default
    return lower.startsWith('video/') ? lower : 'application/octet-stream';
  }

  // ---------- Conversations ----------
  Future<String> openConversationWith(String otherUid) async {
    final me = _auth.currentUser?.uid;
    if (me == null) throw 'Not signed in';
    if (me == otherUid) throw 'Cannot chat with yourself';

    final cid = _cidFor(me, otherUid);
    final convRef = _db.collection('conversations').doc(cid);

    await convRef.set({
      'members': [me, otherUid],
      'lastMessage': null,
      'lastSenderId': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await convRef.collection('memberStates').doc(me).set({
      'lastReadAt': FieldValue.serverTimestamp(),
      'typing': false,
    }, SetOptions(merge: true));

    return cid;
  }

  // ---------- Text message ----------
  Future<void> sendText(String cid, String text) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw 'Not signed in';

    final convRef = _db.collection('conversations').doc(cid);
    final msgRef = convRef.collection('messages').doc();

    final batch = _db.batch();

    batch.set(msgRef, {
      'senderId': uid,
      'text': text,
      'media': [],
      'createdAt': FieldValue.serverTimestamp(),
    });

    batch.update(convRef, {
      'lastMessage': text,
      'lastSenderId': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.set(
      convRef.collection('memberStates').doc(uid),
      {'lastReadAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  // ---------- Upload media to Storage ----------
  // path: chat_media/{cid}/{uid}/{filename}
  // คืนค่า downloadURL
  Future<String> uploadMediaBytes({
    required String cid,
    required Uint8List bytes,
    required String filename, // ควรมีนามสกุล .jpg/.png/.mp4 ...
    String? contentType,      // ถ้าไม่ส่งมาจะเดาจากชื่อไฟล์
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw 'Not signed in';

    // สร้างชื่อไฟล์กันชนกัน (ถ้า dev ส่งชื่อซ้ำมา)
    final safeName = filename.trim().isEmpty
        ? '${_timestamp()}.bin'
        : filename.replaceAll(RegExp(r'[^\w\.\-]'), '_');

  final ref = _storage
    .ref()
    .child('chat_media')
    .child(cid)
    .child(uid)
    .child(safeName);

    final meta = SettableMetadata(
      contentType: contentType ?? _inferContentType(safeName),
      cacheControl: 'public, max-age=31536000',
    );

    try {
      final task = await ref.putData(bytes, meta);
      final url = await task.ref.getDownloadURL();
      return url;
    } catch (e) {
      throw 'Upload failed for storage path "${ref.fullPath}" (bucket: ${ref.bucket}): $e';
    }
  }

  // ---------- Send media message ----------
  // mediaList โครงสร้างแนะนำ:
  // [{'url': 'https://...', 'type': 'image'|'video', 'filename': 'xxx.jpg'}]
  Future<void> sendMedia(String cid, List<Map<String, dynamic>> mediaList) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw 'Not signed in';

    final convRef = _db.collection('conversations').doc(cid);
    final msgRef = convRef.collection('messages').doc();

    await msgRef.set({
      'senderId': uid,
      'text': '',
      'media': mediaList,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await convRef.update({
      'lastMessage': '[Media]',
      'lastSenderId': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Convenience: อัปโหลด "รูป" เดียว แล้วส่งทันที
  Future<void> uploadAndSendSingleImage({
    required String cid,
    required Uint8List bytes,
    String filename = '',
  }) async {
    final name = filename.isEmpty ? '${_timestamp()}.jpg' : filename;
    final url = await uploadMediaBytes(
      cid: cid,
      bytes: bytes,
      filename: name,
      contentType: _inferContentType(name),
    );
    await sendMedia(cid, [
      {'url': url, 'type': 'image', 'filename': name},
    ]);
  }

  // ---------- Delete / Edit message ----------
  // หมายเหตุ: Firestore Rules ของคุณปัจจุบัน "ห้าม update/delete message"
  // ถ้าจะใช้สองเมธอดด้านล่าง ต้องอนุญาตใน rules ด้วย
  Future<void> deleteMessage(String cid, String mid, String senderId) async {
    final uid = _auth.currentUser?.uid;
    if (uid != senderId) throw 'Permission denied';
    await _db.collection('conversations').doc(cid).collection('messages').doc(mid).delete();
  }

  Future<void> editMessage(String cid, String mid, String newText, String senderId) async {
    final uid = _auth.currentUser?.uid;
    if (uid != senderId) throw 'Permission denied';
    await _db
        .collection('conversations')
        .doc(cid)
        .collection('messages')
        .doc(mid)
        .update({'text': newText});
  }

  // ---------- Typing / Read ----------
  Future<void> setTyping(String cid, bool typing) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db
        .collection('conversations')
        .doc(cid)
        .collection('memberStates')
        .doc(uid)
        .set({'typing': typing}, SetOptions(merge: true));
  }

  Future<void> markRead(String cid) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db
        .collection('conversations')
        .doc(cid)
        .collection('memberStates')
        .doc(uid)
        .set({'lastReadAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  // ---------- Streams ----------
  Stream<QuerySnapshot<Map<String, dynamic>>> messages(String cid) {
    return _db
        .collection('conversations')
        .doc(cid)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> myConversations() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _db
        .collection('conversations')
        .where('members', arrayContains: uid)
        .orderBy('updatedAt', descending: true)
        .snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> memberState(String cid, String uid) {
    return _db
        .collection('conversations')
        .doc(cid)
        .collection('memberStates')
        .doc(uid)
        .snapshots();
  }
}
