import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GroupService {
  GroupService._();
  static final instance = GroupService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // =========================
  // Helpers
  // =========================
  String _uidOrThrow() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw 'Not signed in';
    return uid;
  }

  // =========================
  // Group Profile Management
  // =========================
  
  Future<void> updateGroupProfile({
    required String groupId,
    String? name,
    String? description,
    String? photoURL,
    String? coverURL,
  }) async {
    final uid = _uidOrThrow();
    
    // เช็คว่าเป็นเจ้าของกลุ่มหรือไม่
    final groupDoc = await _db.collection('groups').doc(groupId).get();
    if (!groupDoc.exists) throw 'Group not found';
    if (groupDoc.data()?['ownerId'] != uid) throw 'Only owner can update group profile';

    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (description != null) 'description': description.trim(),
      if (photoURL != null) 'photoURL': photoURL,
      if (coverURL != null) 'coverURL': coverURL,
    };

    await _db.collection('groups').doc(groupId).update(updates);
  }

  // =========================
  // Groups
  // =========================
  Future<String> createGroup({
    required String name,
    String description = '',
    String? photoUrl,
    bool isPrivate = false,
  }) async {
    final uid = _uidOrThrow();

    final ref = await _db.collection('groups').add({
      'ownerId': uid,
      'name': name.trim(),
      'description': description.trim(),
      'photoUrl': photoUrl,
      'isPrivate': isPrivate,
      'createdAt': FieldValue.serverTimestamp(),  // == request.time
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // owner เป็นสมาชิกทันที
    await ref.collection('members').doc(uid).set({
      'joinedAt': FieldValue.serverTimestamp(),   // == request.time
      'role': 'member',
    });

    return ref.id;
  }

  Future<void> updateGroup({
    required String groupId,
    String? name,
    String? description,
    String? photoUrl,
    bool? isPrivate,
  }) async {
    final uid = _uidOrThrow();

    final doc = await _db.collection('groups').doc(groupId).get();
    if (!doc.exists) throw 'Group not found';
    if (doc['ownerId'] != uid) throw 'Not group owner';

    await doc.reference.update({
      if (name != null) 'name': name.trim(),
      if (description != null) 'description': description.trim(),
      if (photoUrl != null) 'photoUrl': photoUrl,
      if (isPrivate != null) 'isPrivate': isPrivate,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // =========================
  // Members
  // =========================
  Future<void> joinGroup(String groupId) async {
    final uid = _uidOrThrow();
    await _db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .doc(uid)
        .set({
      'joinedAt': FieldValue.serverTimestamp(), // == request.time
      'role': 'member',
    });
  }

  Future<void> leaveGroup(String groupId) async {
    final uid = _uidOrThrow();
    await _db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .doc(uid)
        .delete();
  }

  Stream<bool> amIMember(String groupId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .doc(uid)
        .snapshots()
        .map((d) => d.exists);
  }

  // =========================
  // Group Posts
  // =========================

  /// สร้างโพสต์: media ควรเป็นลิสต์ของ map เช่น:
  /// [{'url': 'https://...', 'type':'image','filename':'x.jpg'}]
  Future<String> createGroupPost({
    required String groupId,
    required String text,
    List<Map<String, dynamic>>? media,
    String visibility = 'group',
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw 'Not signed in';

    // ต้องเป็นสมาชิกก่อน
    final memberDoc = await _db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .doc(user.uid)
        .get();
    if (!memberDoc.exists) throw 'You must be a member to post';

    final ref = await _db
        .collection('groups')
        .doc(groupId)
        .collection('posts')
        .add({
      'authorId': user.uid,
      'authorName': user.displayName ?? 'Unknown',
      'authorAvatarUrl': user.photoURL,
      'text': text.trim(),
      'media': (media ?? const <Map<String, dynamic>>[]),
      'visibility': visibility,
      'createdAt': FieldValue.serverTimestamp(), // rules: == request.time
      'updatedAt': FieldValue.serverTimestamp(),
      // ไม่เก็บ likedBy/likesCount/comments ใน document แล้ว → ใช้ subcollections แทน
    });

    return ref.id;
  }

  /// Update a group post's text (only author can edit)
  Future<void> updateGroupPost({
    required String groupId,
    required String postId,
    required String text,
  }) async {
    final uid = _uidOrThrow();

    final postRef = _db.collection('groups').doc(groupId).collection('posts').doc(postId);
    final postSnap = await postRef.get();
    if (!postSnap.exists) throw 'Post not found';

    final post = postSnap.data()!;
    if (post['authorId'] != uid) throw 'Not authorized to edit this post';

    await postRef.update({
      'text': text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> groupPosts(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // =========================
  // Likes (subcollection: posts/{postId}/likes/{uid})
  // =========================

  Future<void> toggleLike({
    required String groupId,
    required String postId,
  }) async {
    final uid = _uidOrThrow();
    final likeRef = _db
        .collection('groups')
        .doc(groupId)
        .collection('posts')
        .doc(postId)
        .collection('likes')
        .doc(uid);

    final snap = await likeRef.get();
    if (snap.exists) {
      // unlike
      await likeRef.delete();
    } else {
      // like
      await likeRef.set({
        'createdAt': FieldValue.serverTimestamp(), // rules: == request.time
      });
    }
  }

  /// จำนวนไลค์แบบเรียลไทม์ (นับเอกสารใน subcollection)
  Stream<int> likesCount(String groupId, String postId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('posts')
        .doc(postId)
        .collection('likes')
        .snapshots()
        .map((qs) => qs.size);
  }

  /// ฉันกดไลค์โพสต์นี้อยู่ไหม
  Stream<bool> likedByMe(String groupId, String postId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('posts')
        .doc(postId)
        .collection('likes')
        .doc(uid)
        .snapshots()
        .map((d) => d.exists);
  }

  // =========================
  // Comments (subcollection: posts/{postId}/comments/{cid})
  // =========================

  Future<void> addComment({
    required String groupId,
    required String postId,
    required String text,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw 'Not signed in';

    final commentsCol = _db
        .collection('groups')
        .doc(groupId)
        .collection('posts')
        .doc(postId)
        .collection('comments');

    await commentsCol.add({
      'authorId': user.uid,
      'text': text.trim(),
      'createdAt': FieldValue.serverTimestamp(), // rules: == request.time
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> commentsStream({
    required String groupId,
    required String postId,
  }) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .orderBy('createdAt', descending: false)
        .snapshots();
  }

  Future<void> deleteComment({
    required String groupId,
    required String postId,
    required String commentId,
  }) async {
    final uid = _uidOrThrow();
    final cRef = _db
        .collection('groups')
        .doc(groupId)
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .doc(commentId);

    final snap = await cRef.get();
    if (!snap.exists) return;
    final data = snap.data() as Map<String, dynamic>?;

    // เจ้าของคอมเมนต์เท่านั้น (owner กลุ่มลบได้ใน rules อยู่แล้ว ถ้าจะใช้ฝั่ง client เพิ่ม เช็คสิทธิ์ก่อนก็ได้)
    if (data?['authorId'] != uid) {
      throw 'Not authorized to delete this comment';
    }
    await cRef.delete();
  }

  // =========================
  // Delete post / Delete group
  // =========================

  Future<void> deleteGroupPost({
    required String groupId,
    required String postId,
  }) async {
    final uid = _uidOrThrow();

    final groupRef = _db.collection('groups').doc(groupId);
    final groupSnap = await groupRef.get();
    if (!groupSnap.exists) throw 'Group not found';

    final postRef = groupRef.collection('posts').doc(postId);
    final postSnap = await postRef.get();
    if (!postSnap.exists) throw 'Post not found';

    final post = postSnap.data()!;
    final isAuthor = post['authorId'] == uid;
    final isOwner = groupSnap['ownerId'] == uid;
    if (!isAuthor && !isOwner) {
      throw 'Not authorized to delete this post';
    }

    // ลบ subcollections ของโพสต์: likes, comments
    final likes = await postRef.collection('likes').get();
    for (final d in likes.docs) {
      await d.reference.delete();
    }
    final comments = await postRef.collection('comments').get();
    for (final d in comments.docs) {
      await d.reference.delete();
    }

    await postRef.delete();
  }

  Future<void> deleteGroup(String groupId) async {
    final uid = _uidOrThrow();

    final groupRef = _db.collection('groups').doc(groupId);
    final groupSnap = await groupRef.get();
    if (!groupSnap.exists) throw 'Group not found';
    if (groupSnap['ownerId'] != uid) throw 'Not group owner';

    // ลบ members
    final members = await groupRef.collection('members').get();
    for (final m in members.docs) {
      await m.reference.delete();
    }

    // ลบ posts + subcollections (likes/comments)
    final posts = await groupRef.collection('posts').get();
    for (final p in posts.docs) {
      final pRef = p.reference;
      final likes = await pRef.collection('likes').get();
      for (final l in likes.docs) {
        await l.reference.delete();
      }
      final comments = await pRef.collection('comments').get();
      for (final c in comments.docs) {
        await c.reference.delete();
      }
      await pRef.delete();
    }

    // ลบ group document
    await groupRef.delete();
  }
}
