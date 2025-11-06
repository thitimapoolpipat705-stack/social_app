import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/page_service.dart';
import '../../widgets/feed_card.dart';
import '../../widgets/comments_sheet.dart';
import 'edit_page_screen.dart';

class PageFeedScreen extends StatefulWidget {
  final String pageId;
  final String pageName;
  const PageFeedScreen({super.key, required this.pageId, required this.pageName});

  @override
  State<PageFeedScreen> createState() => _PageFeedScreenState();
}

class _PageFeedScreenState extends State<PageFeedScreen> {
  final _text = TextEditingController();
  bool _posting = false;
  String? _error;
  final List<XFile> _images = [];
  final List<XFile> _videos = [];
  final _picker = ImagePicker();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String _inferContentType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    return 'application/octet-stream';
  }

  Future<void> _pickMedia() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photos (multi-select)'),
              onTap: () => Navigator.pop(context, 'photos'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video (pick one)'),
              onTap: () => Navigator.pop(context, 'video'),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;

    if (action == 'photos') {
      final picked = await _picker.pickMultiImage(imageQuality: 85);
      if (picked.isNotEmpty) {
        setState(() => _images.addAll(picked.take(8 - _images.length)));
      }
    } else if (action == 'video') {
      final f = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
      if (f != null) setState(() => _videos.add(f));
    }
  }

  Future<List<Map<String, dynamic>>> _uploadMedia() async {
    final out = <Map<String, dynamic>>[];
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // Upload images
    for (int i = 0; i < _images.length; i++) {
      final f = _images[i];
      final file = File(f.path);
      final ext = f.name.contains('.') ? f.name.split('.').last : 'jpg';
      final name = 'img_$i.$ext';
      
      final ref = FirebaseStorage.instance
          .ref()
          .child('page-posts')
          .child(widget.pageId)
          .child(timestamp.toString())
          .child(name);

      final meta = SettableMetadata(
        contentType: _inferContentType(name),
        cacheControl: 'public, max-age=3600',
      );

      final task = await ref.putFile(file, meta);
      final url = await task.ref.getDownloadURL();
      out.add({'url': url, 'type': 'image', 'filename': name});
    }

    // Upload videos
    for (int i = 0; i < _videos.length; i++) {
      final f = _videos[i];
      final file = File(f.path);
      final ext = f.name.contains('.') ? f.name.split('.').last : 'mp4';
      final name = 'vid_$i.$ext';
      
      final ref = FirebaseStorage.instance
          .ref()
          .child('page-posts')
          .child(widget.pageId)
          .child(timestamp.toString())
          .child(name);

      final meta = SettableMetadata(
        contentType: _inferContentType(name),
        cacheControl: 'public, max-age=3600',
      );

      final task = await ref.putFile(file, meta);
      final url = await task.ref.getDownloadURL();
      out.add({'url': url, 'type': 'video', 'filename': name});
    }

    return out;
  }

  Future<void> _post() async {
    final t = _text.text.trim();
    if (t.isEmpty && _images.isEmpty && _videos.isEmpty) return;

    setState(() { _posting = true; _error = null; });
    try {
      List<Map<String, dynamic>>? media;
      if (_images.isNotEmpty || _videos.isNotEmpty) {
        media = await _uploadMedia();
      }

      await PageService.instance.createPagePost(
        pageId: widget.pageId,
        text: t,
        media: media,
      );
      
      _text.clear();
      setState(() {
        _images.clear();
        _videos.clear();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _deletePost(String postId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await PageService.instance.deletePagePost(pageId: widget.pageId, postId: postId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post deleted')),
        );
      }
    }
  }

  Future<void> _editPost(String postId, String currentText) async {
    final newText = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (dialogContext) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(dialogContext).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: TextEditingController(text: currentText),
              decoration: const InputDecoration(
                labelText: 'Edit post',
                border: OutlineInputBorder(),
              ),
              maxLines: 5,
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, currentText),
                  child: const Text('Update'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (newText != null && newText != currentText) {
      await PageService.instance.updatePagePost(
        pageId: widget.pageId,
        postId: postId,
        text: newText,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post updated')),
        );
      }
    }
  }

  Future<void> _deletePage() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete page?'),
        content: const Text('This action cannot be undone. All posts will be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await PageService.instance.deletePage(widget.pageId);
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Page deleted')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final posts = PageService.instance.pagePosts(widget.pageId);
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('pages').doc(widget.pageId).snapshots(),
      builder: (context, snapshot) {
        final isOwner = snapshot.data?.data()?['ownerId'] == currentUserId;

        return Scaffold(
      appBar: AppBar(
        title: Text(widget.pageName),
        actions: [
          if (isOwner) PopupMenuButton(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit),
                  title: Text('Edit Page'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_forever, color: Colors.red),
                  title: Text('Delete Page', style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            onSelected: (val) {
              switch (val) {
                case 'edit':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditPageScreen(pageId: widget.pageId),
                    ),
                  );
                  break;
                case 'delete':
                  _deletePage();
                  break;
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Post input box - แสดงเฉพาะเจ้าของเพจ
          if (isOwner) Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceVariant.withOpacity(.1),
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _text,
                  decoration: const InputDecoration(
                    hintText: 'Share something with your followers...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                if (_images.isNotEmpty || _videos.isNotEmpty) ...[
                  SizedBox(
                    height: 100,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _images.length + _videos.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final isImage = i < _images.length;
                        final file = isImage ? _images[i] : _videos[i - _images.length];
                        return Stack(
                          children: [
                            Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                color: scheme.surfaceVariant,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: isImage
                                    ? Image.file(File(file.path), fit: BoxFit.cover)
                                    : const Icon(Icons.videocam_outlined, size: 32),
                              ),
                            ),
                            Positioned(
                              top: 4, right: 4,
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    if (isImage) {
                                      _images.removeAt(i);
                                    } else {
                                      _videos.removeAt(i - _images.length);
                                    }
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black45,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _posting ? null : _pickMedia,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Media'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _posting ? null : _post,
                      icon: _posting 
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      label: Text(_posting ? 'Posting...' : 'Post'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: scheme.error)),
            ),

          // Posts list
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: posts,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.article_outlined, size: 64, color: scheme.outline),
                          const SizedBox(height: 16),
                          Text(
                            'No posts yet',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Start sharing with your followers!',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final docs = snap.data!.docs;
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final doc = docs[i];
                    final data = doc.data();
                    final uid = FirebaseAuth.instance.currentUser?.uid;
                    final authorId = data['authorId'] as String? ?? '';
                    final isOwn = uid == authorId;

                    return FeedCard(
                      postId: doc.id,
                      authorId: authorId,
                      authorName: data['authorName'] as String? ?? 'Unknown',
                      authorAvatarUrl: data['authorAvatarUrl'] as String?,
                      text: data['text'] as String?,
                      media: _normalizeMedia(data['media']),
                      commentsCount: (data['commentsCount'] as int?) ?? 0,
                      likesCount: (data['likesCount'] as int?) ?? 0,
                      likedByMe: ((data['likedBy'] as List?)?.contains(uid)) ?? false,
                      onReact: (reaction) {
                        print('Reacted to page post ${doc.id} with $reaction');
                      },
                      isOwn: isOwn,
                      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
                      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
                      onToggleLike: () => PageService.instance.toggleLike(
                        pageId: widget.pageId,
                        postId: doc.id,
                      ),
                      onComment: () {
                        CommentsSheet.show(
                          context,
                          collection: 'pages',
                          docId: widget.pageId,
                          subCollection: 'posts',
                          subDocId: doc.id,
                          hasComments: data['commentsCount'] > 0,
                          onComment: (text) async {
                            await PageService.instance.createPagePostComment(
                              pageId: widget.pageId,
                              postId: doc.id,
                              text: text,
                            );
                          },
                          onDeleteComment: isOwner
                              ? (commentId) => PageService.instance.deletePagePostComment(
                                  pageId: widget.pageId,
                                  postId: doc.id,
                                  commentId: commentId,
                                )
                              : null,
                        );
                      },
                      onShare: () {
                        // TODO: Implement sharing
                      },
                      onReport: isOwn ? null : () {
                        // TODO: Implement reporting
                      },
                      onEdit: isOwn ? () => _editPost(doc.id, data['text'] as String? ?? '') : null,
                      onDelete: isOwn ? () => _deletePost(doc.id) : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
      },
    );
  }

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
}
