import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PageService {
  PageService._();
  static final instance = PageService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ========= Posts =========
  Future<void> createPagePost({
    required String pageId,
    required String text,
    List<Map<String, dynamic>>? media,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw 'Not signed in';

    final pageRef = _db.collection('pages').doc(pageId);
    final pageSnap = await pageRef.get();
    if (!pageSnap.exists) throw 'Page not found';

    // Check if user is page owner
    if (pageSnap.data()?['ownerId'] != user.uid) {
      throw 'Only page owner can post';
    }

    final postRef = pageRef.collection('posts').doc();
    await postRef.set({
      'text': text,
      'media': media,
      'authorId': user.uid,
      'authorName': user.displayName ?? 'Unknown',
      'authorAvatarUrl': user.photoURL,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'likesCount': 0,
      'commentsCount': 0,
      'likedBy': [],
      'comments': [],
    });
  }

  Future<void> updatePagePost({
    required String pageId,
    required String postId,
    required String text,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw 'Not signed in';

    final postRef = _db
        .collection('pages')
        .doc(pageId)
        .collection('posts')
        .doc(postId);

    final post = await postRef.get();
    if (!post.exists) throw 'Post not found';
    if (post.data()?['authorId'] != uid) throw 'Not authorized';

    await postRef.update({
      'text': text,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deletePagePost({
    required String pageId,
    required String postId,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw 'Not signed in';

    final postRef = _db
        .collection('pages')
        .doc(pageId)
        .collection('posts')
        .doc(postId);

    final post = await postRef.get();
    if (!post.exists) throw 'Post not found';
    if (post.data()?['authorId'] != uid) throw 'Not authorized';

    await postRef.delete();
  }

  Future<void> toggleLike({
    required String pageId,
    required String postId,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw 'Not signed in';

    final postRef = _db
        .collection('pages')
        .doc(pageId)
        .collection('posts')
        .doc(postId);

    final post = await postRef.get();
    if (!post.exists) throw 'Post not found';

    final likedBy = (post.data()?['likedBy'] as List?)?.cast<String>() ?? [];
    final isLiked = likedBy.contains(uid);

    await postRef.update({
      'likedBy': isLiked
          ? FieldValue.arrayRemove([uid])
          : FieldValue.arrayUnion([uid]),
      'likesCount': FieldValue.increment(isLiked ? -1 : 1),
    });
  }

  Future<void> deletePage(String pageId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw 'Not signed in';

    final pageRef = _db.collection('pages').doc(pageId);
    final page = await pageRef.get();
    
    if (!page.exists) throw 'Page not found';
    if (page.data()?['ownerId'] != uid) throw 'Not authorized';

    // Delete all posts
    final posts = await pageRef.collection('posts').get();
    final batch = _db.batch();
    for (final post in posts.docs) {
      batch.delete(post.reference);
    }
    batch.delete(pageRef);
    await batch.commit();
  }

  // ========= Pages =========
  Future<String> createPage({
    required String name,
    String bio = '',
    String? photoUrl,
    bool isPrivate = false,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw 'Not signed in';

    final ref = await _db.collection('pages').add({
      'ownerId': user.uid,
      'ownerName': user.displayName ?? 'Unknown',
      'ownerAvatarUrl': user.photoURL,
      'name': name.trim(),
      'bio': bio.trim(),
      'photoUrl': photoUrl,
      'isPrivate': isPrivate,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updatePage({
    required String pageId,
    String? name,
    String? bio,
    String? photoUrl,
    bool? isPrivate,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw 'Not signed in';

    final doc = await _db.collection('pages').doc(pageId).get();
    if (!doc.exists) throw 'Page not found';
    if (doc['ownerId'] != uid) throw 'Not page owner';

    await doc.reference.update({
      if (name != null) 'name': name.trim(),
      if (bio != null) 'bio': bio.trim(),
      if (photoUrl != null) 'photoUrl': photoUrl,
      if (isPrivate != null) 'isPrivate': isPrivate,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ========= Followers =========
  Future<void> followPage(String pageId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw 'Not signed in';
    await _db.collection('pages').doc(pageId)
      .collection('followers').doc(uid).set({
        'followedAt': FieldValue.serverTimestamp(), // == request.time
      });
  }

  Future<void> unfollowPage(String pageId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw 'Not signed in';
    await _db.collection('pages').doc(pageId)
      .collection('followers').doc(uid).delete();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> myPages() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _db
        .collection('pages')
        .where('ownerId', isEqualTo: uid)
        .snapshots();
  }

  Stream<bool> amIFollower(String pageId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _db.collection('pages').doc(pageId)
      .collection('followers').doc(uid)
      .snapshots()
      .map((d) => d.exists);
  }

  // Posts feed
  Stream<QuerySnapshot<Map<String, dynamic>>> pagePosts(String pageId) {
    return _db
        .collection('pages')
        .doc(pageId)
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();
  }

  // ========= Comments (subcollection) =========
  Future<void> createPagePostComment({
    required String pageId,
    required String postId,
    required String text,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw 'Not signed in';

    final commentRef = _db
        .collection('pages')
        .doc(pageId)
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .doc();

    await commentRef.set({
      'text': text.trim(),
      'authorId': user.uid,
      'authorName': user.displayName ?? 'Unknown',
      'authorAvatarUrl': user.photoURL,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Increment commentsCount
    await _db
        .collection('pages')
        .doc(pageId)
        .collection('posts')
        .doc(postId)
        .update({
      'commentsCount': FieldValue.increment(1),
    });
  }

  Future<void> deletePagePostComment({
    required String pageId,
    required String postId,
    required String commentId,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw 'Not signed in';

    final commentRef = _db
        .collection('pages')
        .doc(pageId)
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .doc(commentId);

    final comment = await commentRef.get();
    if (!comment.exists) throw 'Comment not found';
    if (comment.data()?['authorId'] != uid) throw 'Not authorized';

    await commentRef.delete();

    // Decrement commentsCount
    await _db
        .collection('pages')
        .doc(pageId)
        .collection('posts')
        .doc(postId)
        .update({
      'commentsCount': FieldValue.increment(-1),
    });
  }
}
