// lib/pages/feed_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../widgets/feed_card.dart';
import 'notifications_screen.dart';
import '../widgets/edit_post_text_sheet.dart';  // ⬅️ เพิ่มบรรทัดนี้
import '../widgets/comment_input_with_mentions.dart'; // ⬅️ เพิ่มบรรทัดนี้
import '../widgets/report_post_sheet.dart';



class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final postsQuery = FirebaseFirestore.instance
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(50);

    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connected'),
        actions: [
          if (myUid == null)
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              ),
            )
          else
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(myUid)
                  .collection('notifications')
                  .where('read', isEqualTo: false)
                  .limit(1)
                  .snapshots(),
              builder: (context, snap) {
                final hasUnread = snap.data?.docs.isNotEmpty ?? false;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      tooltip: 'Notifications',
                      icon: const Icon(Icons.notifications_outlined),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const NotificationsScreen()),
                      ),
                    ),
                    if (hasUnread)
                      Positioned(
                        right: 10,
                        top: 10,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: Theme.of(context).dividerColor.withOpacity(.3),
          ),
        ),
      ),

      // ---------- FEED ----------
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: postsQuery.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return const Center(child: Text('No posts yet.'));
          }

          final docs = snap.data!.docs;
          final bottomSafe =
              120.0 + MediaQuery.of(context).viewPadding.bottom; // กันโดน FAB

          return ListView.builder(
            padding: EdgeInsets.fromLTRB(12, 12, 12, bottomSafe),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final doc = docs[i];
              final d = doc.data();
              final postId = doc.id;

              final authorId = (d['authorId'] as String?) ?? '';
              final authorName = (d['authorName'] as String?) ?? authorId;
              final authorAvatarUrl = d['authorAvatarUrl'] as String?;
              final text = (d['text'] as String?) ?? '';
              final comments = (d['commentsCount'] as int?) ?? 0;
              final media = _normalizeMedia(d['media']);
              final thumbUrl = _firstImageUrl(media);

              final createdAt = (d['createdAt'] is Timestamp)
                  ? (d['createdAt'] as Timestamp).toDate()
                  : null;
              // ⬇️ NEW: ดึง updatedAt เพื่อใช้แสดง "Edited"
              final updatedAt = (d['updatedAt'] is Timestamp)
                  ? (d['updatedAt'] as Timestamp).toDate()
                  : null;

              final myUid = FirebaseAuth.instance.currentUser?.uid;
              final myReactionRef = (myUid == null)
                  ? null
                  : FirebaseFirestore.instance
                      .collection('posts')
                      .doc(postId)
                      .collection('reactions')
                      .doc(myUid);

              final allReactionsRef = FirebaseFirestore.instance
                  .collection('posts')
                  .doc(postId)
                  .collection('reactions');

              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: myReactionRef?.snapshots() ?? const Stream.empty(),
                builder: (context, mySnap) {
                  final likedByMe = mySnap.data?.exists == true;

                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: allReactionsRef.snapshots(),
                    builder: (context, allSnap) {
                      final likesCount = allSnap.data?.docs.length ?? 0;
                      // เพิ่มการตรวจสอบการติดตามสำหรับโพสต์ส่วนตัว
                      final isPrivate = (d['isPrivate'] == true);
                      final isFollowingFut = myUid != null
                          ? FirebaseFirestore.instance
                              .collection('users')
                              .doc(myUid)
                              .collection('following')
                              .doc(authorId)
                              .get()
                              .then((doc) => doc.exists)
                          : Future<bool>.value(false);

                      return FutureBuilder<bool>(
                        future: isFollowingFut,
                        builder: (context, followingSnap) {
                          // ไม่แสดง spinner ในฟีดระหว่างเช็ค
                          if (followingSnap.connectionState ==
                              ConnectionState.waiting) {
                            return const SizedBox.shrink();
                          }

                          final isFollowing = followingSnap.data ?? false;

                          // ถ้าโพสต์ private และยังไม่ได้ตาม → ซ่อนไปเลย
                          if (isPrivate && !isFollowing) {
                            return const SizedBox.shrink();
                          }

                          return FeedCard(
                            postId: postId,
                            authorId: authorId,
                            authorName: authorName,
                            authorAvatarUrl: authorAvatarUrl,
                            media: media,
                            text: text,
                            commentsCount: comments,
                            likesCount: likesCount,
                            likedByMe: likedByMe,
                            isOwn: myUid == authorId,
                            createdAt: createdAt,
                            updatedAt: updatedAt, // ⬅️ ส่งให้แสดง "Edited"
                            onReact: (reaction) {
                              print('Reacted to post $postId with $reaction');
                            },

                            onToggleLike: () async {
                              if (myUid == null) return;
                              if (likedByMe) {
                                await myReactionRef!.delete();
                              } else {
                                await myReactionRef!.set({
                                  'type': 'like',
                                  'createdAt': FieldValue.serverTimestamp(),
                                });
                              }
                            },

                            onComment: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                useSafeArea: true,
                                backgroundColor:
                                    Theme.of(context).colorScheme.surface,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(16)),
                                ),
                                builder: (_) => CommentsSheet(
                                  postId: postId,
                                  postAuthorId: authorId,
                                  postThumbUrl: thumbUrl,
                                ),
                              );
                            },

                            onShare: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Share: coming soon')),
                              );
                            },

                            // --- Report ---
onReport: () async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => ReportPostSheet(
      postId: postId,
      postAuthorId: authorId,
      postText: text,
      postThumbUrl: thumbUrl,
    ),
  );
  if (ok == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ขอบคุณที่ช่วยรายงานโพสต์')),
    );
  }
},

// --- Edit ---
onEdit: (myUid == authorId)
    ? () async {
        final ok = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (_) => EditPostTextSheet(
            postId: postId,
            initialText: text, // <- ส่งข้อความเดิม
          ),
        );
        if (ok == true && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Post updated')),
          );
        }
      }
    : null, // <— ต้องมี comma ปิดพารามิเตอร์

// --- Delete ---
onDelete: (myUid == authorId)
    ? () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete post'),
            content: const Text('Are you sure you want to delete this post?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await FirebaseFirestore.instance
              .collection('posts')
              .doc(postId)
              .delete();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Deleted')),
            );
          }
        }
      }
    : null,

                            onAuthorTap: () {}, // TODO: เปิดโปรไฟล์ผู้เขียน
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// ---------- Bottom sheet (Stateful ปลอดภัยเรื่อง dispose) ----------
class CommentsSheet extends StatefulWidget {
  const CommentsSheet({
    super.key,
    required this.postId,
    required this.postAuthorId,
    this.postThumbUrl,
  });

  final String postId;
  final String postAuthorId;
  final String? postThumbUrl;

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  @override
  Widget build(BuildContext context) {
    final commentsRef = FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .collection('comments')
        .orderBy('createdAt', descending: true);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),

              // ===== รายการคอมเมนต์ =====
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: commentsRef.snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final items = snap.data?.docs ?? const [];
                    if (items.isEmpty) {
                      return const Center(child: Text('No comments'));
                    }
                    return ListView.separated(
                      controller: scrollCtrl,
                      reverse: true,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 0),
                      itemBuilder: (_, i) {
                        final c = items[i].data();
                        final authorId = (c['authorId'] ?? '') as String? ?? '';
                        final name = (c['authorName'] ?? authorId) as String? ?? '';
                        final text = (c['text'] ?? '') as String? ?? '';
                        final ts = (c['createdAt'] is Timestamp)
                            ? (c['createdAt'] as Timestamp).toDate()
                            : null;

                        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          future: (authorId.isEmpty)
                              ? Future.value(null)
                              : FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(authorId)
                                  .get(),
                          builder: (context, userSnap) {
                            final photoURL =
                                (userSnap.data?.data()?['photoURL'] ?? '') as String? ?? '';
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: (photoURL.isNotEmpty)
                                    ? NetworkImage(photoURL)
                                    : null,
                                child: (photoURL.isEmpty)
                                    ? const Icon(Icons.person)
                                    : null,
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  if (ts != null)
                                    Text(
                                      _timeAgo(ts),
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                ],
                              ),
                              subtitle: Text(text),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),

              // ===== กล่องพิมพ์ “เดียว” ด้านล่าง (รองรับ @mention) =====
              const Divider(height: 0),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  12, 8, 12, MediaQuery.of(context).viewInsets.bottom + 12,
                ),
                child: CommentInputWithMentions(
                  postId: widget.postId,
                  onSubmitted: () async {
                    if (mounted) setState(() {}); // รีเฟรชหลังส่งคอมเมนต์
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}


// ===== Utils =====
List<Map<String, dynamic>> _normalizeMedia(dynamic media) {
  if (media == null) return const <Map<String, dynamic>>[];
  if (media is String) return [{'url': media, 'type': _typeFromUrl(media)}];
  if (media is List) {
    final out = <Map<String, dynamic>>[];
    for (final item in media) {
      if (item == null) continue;
      if (item is String) {
        out.add({'url': item, 'type': _typeFromUrl(item)});
      } else if (item is Map) {
        final map = Map<String, dynamic>.from(item as Map);
        map['type'] ??= _typeFromUrl(map['url'] as String? ?? '');
        out.add(map);
      }
    }
    return out;
  }
  return const <Map<String, dynamic>>[];
}

String _typeFromUrl(String url) {
  final u = url.toLowerCase();
  if (u.endsWith('.mp4') || u.endsWith('.mov') || u.contains('video')) {
    return 'video';
  }
  return 'image';
}

String? _firstImageUrl(List<Map<String, dynamic>> media) {
  for (final m in media) {
    final type = (m['type'] as String?) ?? 'image';
    final url = (m['url'] as String?)?.trim();
    if (type == 'image' && url != null && url.isNotEmpty) return url;
  }
  return null;
}

String _timeAgo(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  final weeks = (diff.inDays / 7).floor();
  if (weeks < 5) return '${weeks}w';
  return '${t.year}/${t.month.toString().padLeft(2, '0')}/${t.day.toString().padLeft(2, '0')}';
}

/// เขียนแจ้งเตือนคอมเมนต์
Future<void> _notifyComment({
  required String postAuthorId,
  required String postId,
  required String fromUid,
  required String fromName,
  required String previewText,
  String? postThumbUrl,
}) async {
  try {
    final notifRef = FirebaseFirestore.instance
        .collection('users')
        .doc(postAuthorId)
        .collection('notifications')
        .doc();

    await notifRef.set({
      'type': 'comment',
      'fromUid': fromUid,
      'fromName': fromName,
      'postId': postId,
      'postThumbUrl': postThumbUrl,
      'title': 'commented on your post',
      'body': previewText,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  } catch (e) {
    debugPrint('notify comment failed: $e');
  }
}

// ✨ UPDATED: Dialog รายงานโพสต์ + บันทึกเข้า Firestore (reports + counter + noti)
Future<void> _openReportPostDialog(
  BuildContext context, {
  required String postId,
  required String postAuthorId,
  required String? postText,
  required String? postThumbUrl,
}) async {
  final reasons = <String>[
    'Spam',
    'Harassment / Hate',
    'Nudity / Sexual content',
    'Violence / Graphic',
    'False information',
    'Other',
  ];
  String selected = reasons.first;
  final detailCtl = TextEditingController();

  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Report post'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            value: selected,
            items: reasons
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (v) => selected = v ?? reasons.first,
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: detailCtl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'More details (optional)',
              hintText: 'Explain what is wrong…',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Submit'),
        ),
      ],
    ),
  );

  if (ok != true) return;

  final db = FirebaseFirestore.instance;
  final me = FirebaseAuth.instance.currentUser;

  try {
    final batch = db.batch();

    // 1) เก็บเคสรีพอร์ต
    final repRef = db.collection('postReports').doc();
    batch.set(repRef, {
      'postId': postId,
      'postAuthorId': postAuthorId,
      'reason': selected,
      'detail': detailCtl.text.trim(),
      'postText': postText,
      'postThumbUrl': postThumbUrl,
      'reporterUid': me?.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'open', // open | reviewing | resolved
    });

    // 2) เพิ่มตัวนับบนโพสต์
    final postRef = db.collection('posts').doc(postId);
    batch.set(postRef, {'reportCount': FieldValue.increment(1)}, SetOptions(merge: true));

    // 3) แจ้งเตือนเจ้าของโพสต์
    final notiRef = db
        .collection('users')
        .doc(postAuthorId)
        .collection('notifications')
        .doc();
    batch.set(notiRef, {
      'type': 'post_reported',
      'postId': postId,
      'postThumbUrl': postThumbUrl,
      'title': 'โพสต์ของคุณถูกรีพอร์ต',
      'body': 'เหตุผล: $selected',
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report submitted. Thank you.')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Report failed: $e')),
      );
    }
  }
}

// ✨ ADDED: ดึง username จากข้อความคอมเมนต์ (@username)
List<String> _extractMentionUsernames(String text) {
  final re = RegExp(r'@([A-Za-z0-9_.]+)'); // อนุญาต a-z 0-9 _ .
  return re
      .allMatches(text)
      .map((m) => m.group(1)!.trim().toLowerCase())
      .toSet() // กันซ้ำ
      .toList();
}

// ✨ ADDED: แจ้งเตือน mention ไปยังผู้ใช้ที่ถูกแท็ก
Future<void> _notifyMentions({
  required List<String> usernames,
  required String fromUid,
  required String fromName,
  required String postId,
  required String? postThumbUrl,
  required String previewText,
}) async {
  final db = FirebaseFirestore.instance;

  // พยายามหา user ด้วย usernameLower ก่อน ถ้าไม่มี ลองด้วย displayNameLower
  for (final uname in usernames) {
    String? targetUid;

    // หาโดย usernameLower
    final q1 = await db
        .collection('users')
        .where('usernameLower', isEqualTo: uname)
        .limit(1)
        .get();
    if (q1.docs.isNotEmpty) {
      targetUid = q1.docs.first.id;
    } else {
      // สำรอง: displayNameLower
      final q2 = await db
          .collection('users')
          .where('displayNameLower', isEqualTo: uname)
          .limit(1)
          .get();
      if (q2.docs.isNotEmpty) {
        targetUid = q2.docs.first.id;
      }
    }

    if (targetUid == null || targetUid == fromUid) continue;

    try {
      await db
          .collection('users')
          .doc(targetUid)
          .collection('notifications')
          .add({
        'type': 'mention',
        'fromUid': fromUid,
        'fromName': fromName,
        'postId': postId,
        'postThumbUrl': postThumbUrl,
        'title': 'mentioned you in a comment',
        'body': previewText,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('notify mention to $uname failed: $e');
    }
  }
}
