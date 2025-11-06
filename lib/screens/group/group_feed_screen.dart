// lib/features/groups/group_feed_screen.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../widgets/feed_card.dart';
import '../../services/group_service.dart';
import 'edit_group_screen.dart';
import '../../pages/feed_screen.dart';

class GroupFeedScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  const GroupFeedScreen({super.key, required this.groupId, required this.groupName});

  @override
  State<GroupFeedScreen> createState() => _GroupFeedScreenState();
}

class _GroupFeedScreenState extends State<GroupFeedScreen> {
  final _controller = TextEditingController();
  bool _isLoading = false;
  String? _error;
  XFile? _pickedImage;

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (x != null) setState(() => _pickedImage = x);
  }

  void _removePicked() => setState(() => _pickedImage = null);

  String _inferContentType(String extLower) {
    switch (extLower) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _handleSubmit() async {
    final t = _controller.text.trim();
    if (t.isEmpty && _pickedImage == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // ก่อนอัปโหลดเช็กว่าเป็นสมาชิกกลุ่ม (กัน storage 403)
      final memberSnap = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('members')
          .doc(_currentUid)
          .get();
      if (!memberSnap.exists) {
        throw 'You must join this group before posting.';
      }

      List<Map<String, dynamic>> media = <Map<String, dynamic>>[];

      if (_pickedImage != null) {
        // อัปโหลดเข้า path ที่ตรง Storage Rules: group-posts/{gid}/{postIdOrTs}/{file}
        final name = _pickedImage!.name;
        final ext = name.contains('.') ? name.split('.').last : 'jpg';
        final ts = DateTime.now().millisecondsSinceEpoch;
        final storagePath = 'group-posts/${widget.groupId}/$ts/$ts.$ext';

        final meta = SettableMetadata(
          contentType: _inferContentType(ext.toLowerCase()),
          cacheControl: 'public, max-age=3600',
        );

        final file = File(_pickedImage!.path);
        try {
          // Ensure user is still signed in and refresh token to avoid expired-token
          // caused 403/401 from Firebase Storage.
          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser == null) throw 'Not signed in';
          await currentUser.getIdToken(true);

          final snap = await FirebaseStorage.instance.ref(storagePath).putFile(file, meta);
          final url = await snap.ref.getDownloadURL();

          media = [
            {'url': url, 'type': 'image', 'filename': '$ts.$ext'}
          ];
        } on FirebaseException catch (e, st) {
          // Provide clearer message for the user and print stacktrace for debug.
          final msg = 'Upload failed (${e.code}): ${e.message ?? ''}';
          // ignore: avoid_print
          print('Storage upload error: $msg\n$st');
          throw '$msg. Please check Storage Rules membership and AppCheck settings.';
        }
      }

      await GroupService.instance.createGroupPost(
        groupId: widget.groupId,
        text: t,
        media: media,
      );

      _controller.clear();
      setState(() => _pickedImage = null);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Posted successfully')),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Group'),
        content: const Text('Are you sure you want to delete this group? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await GroupService.instance.deleteGroup(widget.groupId);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group deleted successfully')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final posts = GroupService.instance.groupPosts(widget.groupId);
    final currentUserId = _currentUid;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('groups').doc(widget.groupId).snapshots(),
              builder: (context, snapshot) {
                final photoURL = (snapshot.data?.data() as Map<String, dynamic>?)?['photoURL'] as String?;
                return Container(
                  width: 32,
                  height: 32,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    image: photoURL != null
                        ? DecorationImage(
                            image: NetworkImage(photoURL),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: photoURL == null
                      ? Icon(
                          Icons.group_outlined,
                          size: 20,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        )
                      : null,
                );
              },
            ),
            Expanded(child: Text(widget.groupName)),
          ],
        ),
        actions: [
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('groups').doc(widget.groupId).snapshots(),
            builder: (context, groupSnap) {
              if (!groupSnap.hasData) return const SizedBox();
              final groupDoc = groupSnap.data!;
              final ownerId = (groupDoc.data() as Map<String, dynamic>?)?['ownerId'] as String?;
              final isCreator = ownerId == currentUserId;

              if (isCreator) {
                return Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Edit group',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditGroupScreen(groupId: widget.groupId),
                        ),
                      ),
                    ),
                    PopupMenuButton(
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          onTap: _deleteGroup,
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Delete Group', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }

              return StreamBuilder<bool>(
                stream: GroupService.instance.amIMember(widget.groupId),
                builder: (context, memberSnap) {
                  final isMember = memberSnap.data == true;
                  if (isMember) {
                    return TextButton.icon(
                      onPressed: () => GroupService.instance.leaveGroup(widget.groupId),
                      icon: const Icon(Icons.exit_to_app),
                      label: const Text('Leave'),
                      style: TextButton.styleFrom(foregroundColor: Colors.white),
                    );
                  } else {
                    return TextButton.icon(
                      onPressed: () => GroupService.instance.joinGroup(widget.groupId),
                      icon: const Icon(Icons.group_add),
                      label: const Text('Join'),
                      style: TextButton.styleFrom(foregroundColor: Colors.white),
                    );
                  }
                },
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // กล่องโพสต์ (เฉพาะสมาชิก)
          StreamBuilder<bool>(
            stream: GroupService.instance.amIMember(widget.groupId),
            builder: (context, snap) {
              final isMember = snap.data == true;
              if (!isMember) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      'Join this group to post and interact with members',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                );
              }

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Column(
                      children: [
                        if (_pickedImage != null)
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  File(_pickedImage!.path),
                                  width: double.infinity,
                                  height: 160,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: InkWell(
                                  onTap: _removePicked,
                                  child: Container(
                                    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                                    padding: const EdgeInsets.all(6),
                                    child: const Icon(Icons.close, color: Colors.white, size: 18),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            IconButton(
                              onPressed: _isLoading ? null : _pickImage,
                              icon: const Icon(Icons.photo_camera_back_outlined),
                              tooltip: 'Attach image',
                            ),
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                decoration: const InputDecoration(
                                  hintText: 'Post to the group…',
                                  border: OutlineInputBorder(),
                                ),
                                enabled: !_isLoading,
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: _isLoading ? null : _handleSubmit,
                              icon: const Icon(Icons.send),
                              label: Text(_isLoading ? 'Posting...' : 'Post'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(_error!, style: const TextStyle(color: Colors.red)),
                    ),
                ],
              );
            },
          ),
          const Divider(height: 8),

          // รายการโพสต์
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: posts,
              builder: (context, snap) {
                if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.post_add_outlined, size: 48, color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
                          const SizedBox(height: 8),
                          const Text('No group posts yet.'),
                          const SizedBox(height: 8),
                          Text('Be the first to post in this group!', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  );
                }

                final docs = snap.data!.docs;
                return ListView.builder(
                  itemCount: docs.length,
                  padding: const EdgeInsets.only(top: 8),
                  itemBuilder: (_, i) {
                    final doc = docs[i];
                    final d = doc.data();

                    final authorId = d['authorId'] as String?;
                    final isMyPost = authorId == currentUserId;

                    // media ต้องเป็น List<Map<String,dynamic>>
          final mediaList = ((d['media'] as List?) ?? const <dynamic>[])
            .where((e) => e != null)
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
            .toList();

                    // ถ้า authorId ว่าง ให้ fallback ทันที (กัน null crash)
                    final Future<DocumentSnapshot<Map<String, dynamic>>>? futureUser =
                        (authorId == null || authorId.isEmpty)
                            ? null
                            : FirebaseFirestore.instance.collection('users').doc(authorId).get();

                    Widget buildCard(String authorName, String? authorPhoto,
                        {required int likesCount, required bool likedByMe, required int commentsCount}) {
                      return FeedCard(
                        postId: doc.id,
                        authorId: authorId ?? '',
                        authorName: authorName,
                        authorAvatarUrl: authorPhoto,
                        text: d['text'] as String?,
                        media: mediaList,
                        commentsCount: commentsCount,
                        likesCount: likesCount,
                        likedByMe: likedByMe,
                        isOwn: isMyPost,
                        onReact: (reaction) {
                          print('Reacted to group post ${doc.id} with $reaction');
                        },
                        createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
                        updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
                        onToggleLike: () => GroupService.instance.toggleLike(
                          groupId: widget.groupId,
                          postId: doc.id,
                        ),
                        onComment: () {
                          // Open the same CommentsSheet used on the main Feed to keep UI consistent
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            useSafeArea: true,
                            backgroundColor: Theme.of(context).colorScheme.surface,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                            ),
                            builder: (_) => CommentsSheet(
                              postId: doc.id,
                              postAuthorId: authorId ?? '',
                              postThumbUrl: (() {
                                for (final m in mediaList) {
                                  final type = (m['type'] as String?) ?? 'image';
                                  final url = (m['url'] as String?)?.trim();
                                  if (type == 'image' && url != null && url.isNotEmpty) return url;
                                }
                                return null;
                              })(),
                            ),
                          );
                        },
                        onShare: () {},
                        onReport: isMyPost ? null : () {},
                        onEdit: isMyPost
                            ? () async {
                                final editCtl = TextEditingController(text: d['text'] as String? ?? '');
                                final ok = await showDialog<bool?>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Edit post'),
                                    content: TextField(
                                      controller: editCtl,
                                      autofocus: true,
                                      minLines: 1,
                                      maxLines: 8,
                                      decoration: const InputDecoration(hintText: 'Edit your post'),
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
                                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('SAVE')),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  try {
                                    await GroupService.instance.updateGroupPost(groupId: widget.groupId, postId: doc.id, text: editCtl.text.trim());
                                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Post updated')));
                                  } catch (e) {
                                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                                  }
                                }
                              }
                            : null,
                        onDelete: isMyPost
                            ? () => GroupService.instance.deleteGroupPost(
                                  groupId: widget.groupId,
                                  postId: doc.id,
                                )
                            : null,
                      );
                    }

                    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      future: futureUser,
                      builder: (context, userSnap) {
                        final userData = userSnap.data?.data();
                        final userName = userData?['displayName'] as String? ?? 'Unknown User';
                        final userPhoto = userData?['photoURL'] as String?;

                        return StreamBuilder<int>(
                          stream: GroupService.instance.likesCount(widget.groupId, doc.id),
                          builder: (context, likeCntSnap) {
                            final likesCount = likeCntSnap.data ?? 0;

                            return StreamBuilder<bool>(
                              stream: GroupService.instance.likedByMe(widget.groupId, doc.id),
                              builder: (context, likedSnap) {
                                final likedByMe = likedSnap.data ?? false;

                                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                  stream: FirebaseFirestore.instance
                                      .collection('groups')
                                      .doc(widget.groupId)
                                      .collection('posts')
                                      .doc(doc.id)
                                      .collection('comments')
                                      .snapshots(),
                                  builder: (context, cSnap) {
                                    final commentsCount = cSnap.data?.size ?? 0;
                                    return buildCard(userName, userPhoto,
                                        likesCount: likesCount,
                                        likedByMe: likedByMe,
                                        commentsCount: commentsCount);
                                  },
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
          ),
        ],
      ),
    );
  }
}
