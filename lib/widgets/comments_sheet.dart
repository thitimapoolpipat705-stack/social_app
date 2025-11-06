import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CommentsSheet extends StatefulWidget {
  final String collection;
  final String docId;
  final String? subCollection;
  final String? subDocId;
  final bool hasComments;
  final Future<void> Function(String text) onComment;
  final Future<void> Function(String commentId)? onDeleteComment;

  const CommentsSheet({
    super.key,
    required this.collection,
    required this.docId,
    this.subCollection,
    this.subDocId,
    required this.hasComments,
    required this.onComment,
    this.onDeleteComment,
  });

  static void show(BuildContext context, {
    required String collection,
    required String docId,
    String? subCollection,
    String? subDocId,
    required bool hasComments,
    required Future<void> Function(String text) onComment,
    Future<void> Function(String commentId)? onDeleteComment,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(0, 0, 0, MediaQuery.of(context).viewInsets.bottom),
        child: CommentsSheet(
          collection: collection,
          docId: docId,
          subCollection: subCollection,
          subDocId: subDocId,
          hasComments: hasComments,
          onComment: onComment,
          onDeleteComment: onDeleteComment,
        ),
      ),
    );
  }

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _text = TextEditingController();
  bool _posting = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _posting = true;
      _error = null;
    });
    try {
      await widget.onComment(text);
      _text.clear();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final commentsRef = widget.subCollection != null
        ? FirebaseFirestore.instance
            .collection(widget.collection)
            .doc(widget.docId)
            .collection(widget.subCollection!)
            .doc(widget.subDocId)
            .collection('comments')
        : FirebaseFirestore.instance
            .collection(widget.collection)
            .doc(widget.docId)
            .collection('comments');

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline),
                const SizedBox(width: 8),
                Text('Comments',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          if (!widget.hasComments) ...[
            const Expanded(
              child: Center(
                child: Text('No comments yet'),
              ),
            ),
          ] else ...[
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: commentsRef
                    .orderBy('createdAt', descending: false)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final comments = snapshot.data!.docs;
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    separatorBuilder: (_, __) => const Divider(height: 16),
                    itemCount: comments.length,
                    itemBuilder: (_, i) {
                      final c = comments[i];
                      final data = c.data();
                      final isAuthor = data['authorId'] == currentUserId;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundImage: data['authorAvatarUrl'] != null
                                ? NetworkImage(data['authorAvatarUrl']!)
                                : null,
                            child: data['authorAvatarUrl'] == null
                                ? const Icon(Icons.person_outline, size: 20)
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      data['authorName'] ?? 'Unknown',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    if (data['createdAt'] != null) ...[
                                      Text(
                                        _formatDate(data['createdAt']),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                    if (isAuthor && widget.onDeleteComment != null) ...[
                                      const Spacer(),
                                      IconButton(
                                        onPressed: () => widget.onDeleteComment!(c.id),
                                        icon: const Icon(Icons.delete_outline,
                                            size: 18),
                                      ),
                                    ],
                                  ],
                                ),
                                Text(data['text'] ?? ''),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Write a comment...',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _posting ? null : _post,
                  icon: _posting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: scheme.error)),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  String _formatDate(Timestamp ts) {
    final now = DateTime.now();
    final date = ts.toDate();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${date.day}/${date.month}/${date.year}';
  }
}