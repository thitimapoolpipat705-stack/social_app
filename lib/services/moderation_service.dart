// lib/services/moderation_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class ModerationService {
  ModerationService._();
  static final instance = ModerationService._();

  final _db = FirebaseFirestore.instance;

  Future<void> reportPost({
    required String postId,
    required String postOwnerId,
    required String reporterUid,
    required String reason,
    String? details,
  }) async {
    final batch = _db.batch();
    final repRef = _db.collection('reports').doc(); // /reports/<auto>
    batch.set(repRef, {
      'type': 'post',
      'postId': postId,
      'postOwnerId': postOwnerId,
      'reporterUid': reporterUid,
      'reason': reason,
      'details': details ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'open', // open/handled
    });

    final postRef = _db.collection('posts').doc(postId);
    batch.set(postRef, {'reportCount': FieldValue.increment(1)}, SetOptions(merge: true));

    final notiRef = _db.collection('users').doc(postOwnerId).collection('notifications').doc();
    batch.set(notiRef, {
      'type': 'post_reported',
      'postId': postId,
      'title': 'โพสต์ของคุณถูกรีพอร์ต',
      'body': 'มีผู้ใช้รายงานว่าไม่เหมาะสม: $reason',
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }
}
