import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _db = FirebaseFirestore.instance;
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // ====== internal helpers ======
  Future<Map<String, String?>> _actorLite({String? overrideUid}) async {
    final uid = overrideUid ?? _uid;
    if (uid == null) return {};
    final u = FirebaseAuth.instance.currentUser;
    final snap = await _db.collection('users').doc(uid).get();
    final d = snap.data() ?? {};
    return {
      'uid': uid,
      'name': (d['displayName'] as String?) ?? (u?.displayName ?? 'Unknown'),
      'photo': (d['photoURL'] as String?) ?? u?.photoURL,
    };
  }

  Future<void> _create({
    required String targetUid,
    required String type, // 'like' | 'comment' | 'follow' | 'follow_request' | 'follow_request_accepted' | 'follow_request_declined'
    String? postId,
    String? commentId,
    String? title,
    String? body,
    String? fromUid, // ถ้าไม่ส่งจะใช้ current user
    String? fromName,
    String? fromPhotoUrl,
    Map<String, dynamic> extra = const {},
  }) async {
    final actor = await _actorLite(overrideUid: fromUid);
    final col = _db.collection('users').doc(targetUid).collection('notifications');
    await col.add({
      'type': type,
      'fromUid': actor['uid'],
      if (fromName != null) 'fromName': fromName else if (actor['name'] != null) 'fromName': actor['name'],
      if (fromPhotoUrl != null) 'fromPhotoUrl': fromPhotoUrl else if (actor['photo'] != null) 'fromPhotoUrl': actor['photo'],
      if (postId != null) 'postId': postId,
      if (commentId != null) 'commentId': commentId,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
      ...extra,
    });
  }

  /// Public wrapper to create a notification entry for a user.
  /// This delegates to the internal `_create` implementation.
  Future<void> createNotification({
    required String targetUid,
    required String type,
    String? postId,
    String? commentId,
    String? title,
    String? body,
    String? fromUid,
    String? fromName,
    String? fromPhotoUrl,
    Map<String, dynamic> extra = const {},
  }) async {
    return _create(
      targetUid: targetUid,
      type: type,
      postId: postId,
      commentId: commentId,
      title: title,
      body: body,
      fromUid: fromUid,
      fromName: fromName,
      fromPhotoUrl: fromPhotoUrl,
      extra: extra,
    );
  }

  // ====== public helpers ======

  // ไลก์โพสต์
  Future<void> notifyLike({required String ownerUid, required String postId}) {
    return _create(
      targetUid: ownerUid,
      type: 'like',
      postId: postId,
      title: 'Someone liked your post',
    );
  }

  // คอมเมนต์โพสต์
  Future<void> notifyComment({
    required String ownerUid,
    required String postId,
    String? commentId,
    String? body, // ใช้เป็น preview ข้อความคอมเมนต์
  }) {
    return _create(
      targetUid: ownerUid,
      type: 'comment',
      postId: postId,
      commentId: commentId,
      title: 'New comment on your post',
      body: body,
    );
  }

  // โปรไฟล์ private → ส่งคำขอติดตาม
  Future<void> sendFollowRequest(String targetUid) {
    return _create(
      targetUid: targetUid,
      type: 'follow_request',
      title: 'New follow request',
    );
  }

  // โปรไฟล์ public → มีคนติดตามเราแล้ว
  Future<void> notifyNewFollower(String targetUid) {
    return _create(
      targetUid: targetUid,
      type: 'follow',
      title: 'You have a new follower',
    );
  }

  // เจ้าของโปรไฟล์ “อนุมัติ” คำขอ
  Future<void> acceptFollowRequest({
    required String requesterUid,
    String? myUid, // ปล่อยว่างได้ จะใช้ current user
  }) async {
    final me = myUid ?? _uid;
    if (me == null) return;

    final meRef = _db.collection('users').doc(me);
    final requesterRef = _db.collection('users').doc(requesterUid);
    final now = FieldValue.serverTimestamp();

    // 1) เขียนความสัมพันธ์ + ลบคำขอ + นับยอด (atomic)
    final batch = _db.batch();
    batch.delete(meRef.collection('followRequests').doc(requesterUid));
    batch.set(meRef.collection('followers').doc(requesterUid), {'followedAt': now}, SetOptions(merge: true));
    batch.set(requesterRef.collection('following').doc(me), {'followedAt': now}, SetOptions(merge: true));
    batch.set(meRef, {'followersCount': FieldValue.increment(1)}, SetOptions(merge: true));
    batch.set(requesterRef, {'followingCount': FieldValue.increment(1)}, SetOptions(merge: true));
    await batch.commit();

    // 2) ตีธง handled ให้ notif คำขอนี้ (อันล่าสุด)
    final notifQry = await meRef
        .collection('notifications')
        .where('type', isEqualTo: 'follow_request')
        .where('fromUid', isEqualTo: requesterUid)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();
    if (notifQry.docs.isNotEmpty) {
      await notifQry.docs.first.reference.update({'handled': true, 'decision': 'approved'});
    }

    // 3) แจ้งกลับผู้ร้องขอว่า “ถูกอนุมัติ”
    await _create(
      targetUid: requesterUid,
      type: 'follow_request_accepted',
      title: 'Your follow request was accepted',
      body: 'You can now follow their posts.',
      fromUid: me,
    );
  }

  // เจ้าของโปรไฟล์ “ปฏิเสธ”
  Future<void> declineFollowRequest({
    required String requesterUid,
    String? myUid,
  }) async {
    final me = myUid ?? _uid;
    if (me == null) return;

    final meRef = _db.collection('users').doc(me);
    await meRef.collection('followRequests').doc(requesterUid).delete();

    final notifQry = await meRef
        .collection('notifications')
        .where('type', isEqualTo: 'follow_request')
        .where('fromUid', isEqualTo: requesterUid)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();
    if (notifQry.docs.isNotEmpty) {
      await notifQry.docs.first.reference.update({'handled': true, 'decision': 'declined'});
    }

    await _create(
      targetUid: requesterUid,
      type: 'follow_request_declined',
      title: 'Your follow request was declined',
      fromUid: me,
    );
  }

  // มาร์คอ่านทั้งหมดของฉัน
  Future<void> markAllRead() async {
    final uid = _uid;
    if (uid == null) return;
    final qs = await _db
        .collection('users').doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .get();
    final wb = _db.batch();
    for (final d in qs.docs) {
      wb.update(d.reference, {'read': true});
    }
    await wb.commit();
  }
}
