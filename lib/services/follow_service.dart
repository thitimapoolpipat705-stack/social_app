import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FollowService {
  FollowService._();
  static final instance = FollowService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ---------------- Helpers ----------------
  String _uidOrThrow() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw 'Not signed in';
    return uid;
  }

  Future<Map<String, String?>> _meLite() async {
    final uid = _uidOrThrow();
    final u = _auth.currentUser!;
    final doc = await _db.collection('users').doc(uid).get();
    final d = doc.data() ?? {};
    return {
      'uid': uid,
      'name': (d['displayName'] as String?) ?? (u.displayName ?? 'Unknown'),
      'photo': (d['photoURL'] as String?) ?? u.photoURL,
    };
  }

  Future<Map<String, String?>> _userLite(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    final d = doc.data() ?? {};
    return {
      'name': (d['displayName'] as String?) ?? 'Unknown User',
      'photo': d['photoURL'] as String?,
    };
  }

  Future<void> _notify(
    String targetUid, {
    required String type,
    required String fromUid,
    required String fromName,
    String? fromPhotoUrl,
    String? title,
    String? body,
    Map<String, dynamic> extra = const {},
  }) async {
    final ref = _db.collection('users').doc(targetUid).collection('notifications').doc();
    await ref.set({
      'type': type,
      'fromUid': fromUid,
      'fromName': fromName,
      if (fromPhotoUrl != null) 'fromPhotoUrl': fromPhotoUrl,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
      ...extra,
    });
  }

  // ---------------- Actions ----------------

  /// กดติดตาม: public ⇒ follow ทันที, private ⇒ ส่งคำขอ
  Future<void> followOrRequest(String targetUid) async {
    final me = _uidOrThrow();
    if (me == targetUid) throw 'Cannot follow yourself';

    // เตรียมข้อมูลผู้ส่งแจ้งเตือนไว้ก่อน (อยู่นอกทรานแซกชัน)
    final meInfo = await _meLite();

    // ธงผลลัพธ์ของทรานแซกชัน เอาไว้ไปแจ้งเตือนภายหลัง
    bool didFollowNow = false;
    bool didCreateRequest = false;

    await _db.runTransaction((tx) async {
      final meRef = _db.collection('users').doc(me);
      final targetRef = _db.collection('users').doc(targetUid);

      final targetSnap = await tx.get(targetRef);
      if (!targetSnap.exists) throw 'User not found';

      final isPrivate = (targetSnap.data()?['isPrivate'] ?? false) == true;

      final alreadyFollowing =
          (await tx.get(targetRef.collection('followers').doc(me))).exists;
      if (alreadyFollowing) return; // no-op

      if (!isPrivate) {
        // follow ทันที (สองฝั่ง)
        tx.set(targetRef.collection('followers').doc(me), {
          'followedAt': FieldValue.serverTimestamp(),
        });
        tx.set(meRef.collection('following').doc(targetUid), {
          'followedAt': FieldValue.serverTimestamp(),
        });
        tx.update(targetRef, {'followersCount': FieldValue.increment(1)});
        tx.update(meRef, {'followingCount': FieldValue.increment(1)});
        didFollowNow = true;
      } else {
        // private → ส่งคำขอ ถ้ายังไม่มี
        final reqRef = targetRef.collection('followRequests').doc(me);
        final reqSnap = await tx.get(reqRef);
        if (!reqSnap.exists) {
          tx.set(reqRef, {
            'fromUid': me,
            'requestedAt': FieldValue.serverTimestamp(),
            'status': 'pending',
          });
          didCreateRequest = true;
        }
      }
    });

    // แจ้งเตือน (นอกทรานแซกชัน)
    if (didFollowNow) {
      await _notify(
        targetUid,
        type: 'follow',
        fromUid: meInfo['uid']!,
        fromName: meInfo['name'] ?? 'Unknown',
        fromPhotoUrl: meInfo['photo'],
      );
    } else if (didCreateRequest) {
      await _notify(
        targetUid,
        type: 'follow_request',
        fromUid: meInfo['uid']!,
        fromName: meInfo['name'] ?? 'Unknown',
        fromPhotoUrl: meInfo['photo'],
      );
    }
  }

  /// ยกเลิกติดตาม
  Future<void> unfollow(String targetUid) async {
    final me = _uidOrThrow();
    if (me == targetUid) return;

    await _db.runTransaction((tx) async {
      final meRef = _db.collection('users').doc(me);
      final targetRef = _db.collection('users').doc(targetUid);

      final wasFollowing =
          (await tx.get(targetRef.collection('followers').doc(me))).exists;

      tx.delete(targetRef.collection('followers').doc(me));
      tx.delete(meRef.collection('following').doc(targetUid));

      if (wasFollowing) {
        tx.update(targetRef, {'followersCount': FieldValue.increment(-1)});
        tx.update(meRef, {'followingCount': FieldValue.increment(-1)});
      }
    });
  }

  /// อนุมัติคำขอ (Batch + แจ้งเตือนนอก batch)
  Future<void> approveRequest(String requesterUid) async {
    final me = _uidOrThrow();
    final meRef = _db.collection('users').doc(me);
    final requesterRef = _db.collection('users').doc(requesterUid);

    final batch = _db.batch();
    final now = FieldValue.serverTimestamp();

    // ลบคำขอ + ผูกความสัมพันธ์สองฝั่ง + ปรับยอด
    batch.delete(meRef.collection('followRequests').doc(requesterUid));
    batch.set(meRef.collection('followers').doc(requesterUid), {'followedAt': now});
    batch.set(requesterRef.collection('following').doc(me), {'followedAt': now});
    batch.update(meRef, {'followersCount': FieldValue.increment(1)});
    batch.update(requesterRef, {'followingCount': FieldValue.increment(1)});
    await batch.commit();

    // ตีธง handled ให้ notif คำขอล่าสุด
    final notifQry = await meRef
        .collection('notifications')
        .where('type', isEqualTo: 'follow_request')
        .where('fromUid', isEqualTo: requesterUid)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();
    if (notifQry.docs.isNotEmpty) {
      await notifQry.docs.first.reference
          .update({'handled': true, 'decision': 'approved'});
    }

    // แจ้งกลับไปยังผู้ส่งคำขอ
    final meInfo = await _meLite();
    await _notify(
      requesterUid,
      type: 'follow_request_accepted',
      fromUid: meInfo['uid']!,
      fromName: meInfo['name'] ?? 'Unknown',
      fromPhotoUrl: meInfo['photo'],
      title: 'Your follow request was accepted',
      body: 'The user has accepted your follow request.',
    );
  }

  /// ปฏิเสธคำขอ
  Future<void> declineRequest(String requesterUid) async {
    final me = _uidOrThrow();
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
      await notifQry.docs.first.reference
          .update({'handled': true, 'decision': 'declined'});
    }

    final meInfo = await _meLite();
    await _notify(
      requesterUid,
      type: 'follow_request_declined',
      fromUid: meInfo['uid']!,
      fromName: meInfo['name'] ?? 'Unknown',
      fromPhotoUrl: meInfo['photo'],
      title: 'Your follow request was declined',
      body: 'The user declined your follow request.',
    );
  }

  /// อนุมัติ + Follow back ในคลิกเดียว (ใช้กับปุ่ม "Follow back")
  /// - ถ้าอีกฝั่ง public ⇒ จะตามได้ทันที
  /// - ถ้าอีกฝั่ง private ⇒ จะส่งคำขอไปแทน
  Future<void> approveAndFollowBack(String requesterUid) async {
    await approveRequest(requesterUid);
    await followOrRequest(requesterUid);
  }

  /// สถานะความสัมพันธ์กับปลายทาง
  /// return: 'following' | 'pending' | 'none'
  Future<String> relationTo(String targetUid) async {
    final me = _auth.currentUser?.uid;
    if (me == null || me == targetUid) return 'none';

    final targetRef = _db.collection('users').doc(targetUid);
    if ((await targetRef.collection('followers').doc(me).get()).exists) {
      return 'following';
    }
    if ((await targetRef.collection('followRequests').doc(me).get()).exists) {
      return 'pending';
    }
    return 'none';
  }
}
