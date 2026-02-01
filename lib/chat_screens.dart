// lib/chat_screens.dart
import 'dart:async';
// dart:typed_data not needed in this file

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'chat_repository.dart';

/// รายการห้องแชทของฉัน
class ConversationsScreen extends StatelessWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = ChatRepository();
    final me = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>( 
        stream: repo.myConversations(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return const Center(child: Text('No conversations yet'));
          }

          final docs = snap.data!.docs;

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final d = docs[i].data();
              final cid = docs[i].id;
              final members = (d['members'] as List).cast<String>();
              final otherUid = members.firstWhere((u) => u != me, orElse: () => me ?? '');
              final subtitle = (d['lastMessage'] ?? '') as String? ?? '';

              return ListTile(
  leading: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('users').doc(otherUid).snapshots(),
    builder: (context, userSnap) {
      final user = userSnap.data?.data();
      final name = (user?['displayName'] ?? 'Unknown') as String;
      final photo = (user?['photoURL'] ?? '') as String;
      return CircleAvatar(
        backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
        child: photo.isEmpty ? Text(name.isNotEmpty ? name[0] : '?') : null,
      );
    },
  ),
  title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('users').doc(otherUid).snapshots(),
    builder: (context, s) => Text((s.data?.data()?['displayName'] ?? 'Unknown').toString()),
  ),
  subtitle: Text(subtitle.isEmpty ? ' ' : subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
  onTap: () async {
    final uidMe = FirebaseAuth.instance.currentUser?.uid;
    if (uidMe == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please sign in to chat')));
      return;
    }

    if (otherUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid user')));
      return;
    }

    try {
      // Conversation already exists in the list; use its id
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatRoomScreen(cid: cid, otherUid: otherUid)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cannot open chat: $e')));
    }
  },
);


            },
          );
        },
      ),
    );
  }
}


class ChatRoomScreen extends StatefulWidget {
  final String cid;
  final String otherUid;
  const ChatRoomScreen({super.key, required this.cid, required this.otherUid});

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final repo = ChatRepository();
  final input = TextEditingController();
  final _picker = ImagePicker();

  bool _sending = false;
  Timer? _typingDebounce;

  @override
  void initState() {
    super.initState();
    repo.markRead(widget.cid);
  }

  @override
  void dispose() {
    input.dispose();
    _typingDebounce?.cancel();
    // ปิด typing เมื่อออกจากหน้า
    unawaited(repo.setTyping(widget.cid, false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        elevation: 0.5,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        titleSpacing: 0,
        title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('users').doc(widget.otherUid).snapshots(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Row(
                children: [
                  CircleAvatar(radius: 18),
                  SizedBox(width: 12),
                  Text('Loading...')
                ],
              );
            }
            final userData = userSnap.data?.data();
            final profilePic = userData?['photoURL'] ?? '';
            final userName = userData?['displayName'] ?? 'Unknown';

            return Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage: profilePic.isNotEmpty ? NetworkImage(profilePic) : null,
                  child: profilePic.isEmpty ? Text(userName.isNotEmpty ? userName[0] : '?') : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(userName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      // show typing/online state
                      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: repo.memberState(widget.cid, widget.otherUid),
                        builder: (ctx, s2) {
                          final data = s2.data?.data();
                          final typing = data?['typing'] as bool? ?? false;
                          final online = data?['online'] as bool? ?? false;
                          if (typing) return Text('typing...', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.primary));
                          if (online) return Text('online', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.green));
                          return const SizedBox.shrink();
                        },
                      )
                    ],
                  ),
                ),
                IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert)),
              ],
            );
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>( 
              stream: repo.messages(widget.cid),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                final msgs = snap.data?.docs ?? [];

                return NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    // เมื่อเลื่อน/เห็นข้อความแล้ว ให้ markRead
                    repo.markRead(widget.cid);
                    return false;
                  },
                  child: ListView.builder(
                    reverse: true,
                    itemCount: msgs.length,
                    itemBuilder: (_, i) {
                      final doc = msgs[i];
                      final m = doc.data();
                      final mid = doc.id;

                      final mine = m['senderId'] == myUid;
                      final text = (m['text'] ?? '') as String;
                      final ts = (m['createdAt'] as Timestamp?)?.toDate();
                      final media = _normalizeMedia(m['media']);

                      return _MessageBubble(
                        mine: mine,
                        text: text,
                        media: media,
                        timeText: (ts == null)
                            ? ''
                            : '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}',
                        // read receipt: เทียบกับ lastReadAt ของอีกฝั่ง
                        readBuilder: () => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>( 
                          stream: repo.memberState(widget.cid, widget.otherUid),
                          builder: (context, s2) {
                            final lastRead = (s2.data?.data()?['lastReadAt'] as Timestamp?)?.toDate();
                            final sentAt = ts;
                            final read = (lastRead != null && sentAt != null && lastRead.isAfter(sentAt));
                            return mine
                                ? Icon(
                                    read ? Icons.done_all : Icons.check,
                                    size: 16,
                                    color: read ? Colors.blue : Theme.of(context).hintColor,
                                  )
                                : const SizedBox.shrink();
                          },
                        ),
                        // เมนูค้างสำหรับแก้/ลบ (owner เท่านั้น)
                        onLongPress: mine
                            ? () => _showMessageMenu(mid: mid, originalText: text, senderId: m['senderId'])
                            : null,
                      );
                    },
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Row(
                children: [
                  // rounded input bar
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6)],
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.add_a_photo_outlined, size: 20),
                            onPressed: _sending ? null : _pickAndSendMedia,
                          ),
                          Expanded(
                            child: TextField(
                              controller: input,
                              minLines: 1,
                              maxLines: 4,
                              decoration: InputDecoration.collapsed(hintText: 'Message...'),
                              onChanged: _handleTypingChanged,
                              onSubmitted: (_) => _sendText(),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // quick emoji hint
                          IconButton(
                            icon: const Icon(Icons.emoji_emotions_outlined, size: 20),
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // circular send button
                  Material(
                    shape: const CircleBorder(),
                    color: _sending ? Theme.of(context).disabledColor : Theme.of(context).colorScheme.primary,
                    child: IconButton(
                      icon: _sending
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send, color: Colors.white),
                      onPressed: _sending ? null : _sendText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== Typing handling =====
  void _handleTypingChanged(String value) {
    // เปิด typing ทันทีที่พิมพ์
    repo.setTyping(widget.cid, true);
    // debounce เพื่อลดการเขียนถี่
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 900), () {
      repo.setTyping(widget.cid, false);
    });
  }

  // ===== Send text =====
  Future<void> _sendText() async {
    final text = input.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await repo.sendText(widget.cid, text);
      input.clear();
      await repo.markRead(widget.cid);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Send failed: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ===== Pick & Send media =====
  Future<void> _pickAndSendMedia() async {
    if (!mounted) return;
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

    try {
      setState(() => _sending = true);

      final List<Map<String, dynamic>> mediaList = [];

      if (action == 'photos') {
  final files = await _picker.pickMultiImage(imageQuality: 95, maxWidth: 2048, maxHeight: 2048);
  for (final f in files) {
    final bytes = await f.readAsBytes();
    final url = await repo.uploadMediaBytes(
      cid: widget.cid,
      bytes: bytes,
      filename: f.name.isNotEmpty ? f.name : '${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    mediaList.add({'url': url, 'type': 'image', 'filename': f.name});
  }
} else if (action == 'video') {
  final f = await _picker.pickVideo(
    source: ImageSource.gallery,
    maxDuration: const Duration(minutes: 2),
  );
  if (f != null) {
    final bytes = await f.readAsBytes();
    final url = await repo.uploadMediaBytes(
      cid: widget.cid,
      bytes: bytes,
      filename: f.name.isNotEmpty ? f.name : '${DateTime.now().millisecondsSinceEpoch}.mp4',
      contentType: 'video/mp4',
    );
    mediaList.add({
      'url': url,
      'type': 'video',
      'filename': f.name,
      'duration': 0, // TODO: Get actual duration if needed
    });
  }
}


      if (mediaList.isNotEmpty) {
        await repo.sendMedia(widget.cid, mediaList);
        await repo.markRead(widget.cid);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Send media failed: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ===== Context menu for message (edit/delete) =====
  Future<void> _showMessageMenu({required String mid, required String originalText, required String senderId}) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    if (choice == 'edit') {
      final ctl = TextEditingController(text: originalText);
      final ok = await showDialog<bool>(

        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Edit message'),
          content: TextField(
            controller: ctl,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),

          ],
        ),
      );
      if (ok == true) {
        try {
          await repo.editMessage(widget.cid, mid, ctl.text.trim(), senderId);
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Edit failed (rules?): $e')),

          );
        }
      }
    } else if (choice == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete message'),
          content: const Text('Are you sure you want to delete this message?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),

          ],
        ),
      );
      if (confirm == true) {
        try {
          await repo.deleteMessage(widget.cid, mid, senderId);
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed (rules?): $e')),
          );
        }
      }
    }
  }

  // ===== Helpers =====
  List<Map<String, dynamic>> _normalizeMedia(dynamic raw) {
    if (raw == null) return const <Map<String, dynamic>>[];
    if (raw is String) return [{'url': raw, 'type': _inferType(raw)}];
    if (raw is List) {
      final out = <Map<String, dynamic>>[];
      for (final it in raw) {
        if (it == null) continue;
        if (it is String) {
          out.add({'url': it, 'type': _inferType(it)});
        } else if (it is Map) {
          final m = Map<String, dynamic>.from(it);
          m['type'] ??= _inferType(m['url'] as String? ?? '');
          out.add(m);
        }
      }
      return out;
    }
    return const <Map<String, dynamic>>[];
  }

  String _inferType(String url) {
    final u = url.toLowerCase();
    if (u.endsWith('.mp4') || u.endsWith('.mov') || u.contains('video')) return 'video';
    return 'image';
  }
}

/// UI ของบับเบิลข้อความ + สื่อ
class _MessageBubble extends StatelessWidget {
  final bool mine;
  final String text;
  final List<Map<String, dynamic>> media;
  final String timeText;
  final Widget Function() readBuilder;
  final VoidCallback? onLongPress;

  const _MessageBubble({
    required this.mine,
    required this.text,
    required this.media,
    required this.timeText,
    required this.readBuilder,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = mine ? null : cs.surfaceVariant;

    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(mine ? 16 : 4),
      bottomRight: Radius.circular(mine ? 4 : 16),
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Material(
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
            minWidth: 48.0,
          ),
          child: InkWell(
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              decoration: BoxDecoration(
                color: bg,
                gradient: mine
                    ? LinearGradient(
                        colors: [cs.primaryContainer, cs.primary.withOpacity(.95)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 2)),
                ],
                borderRadius: borderRadius,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (media.isNotEmpty) ...[
                      ...media.map((m) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _mediaPreview(context, m),
                          )).toList(),
                    ],
                    if (text.isNotEmpty)
                      Text(text, style: Theme.of(context).textTheme.bodyMedium),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(timeText,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey)),
                          if (mine) ...[
                            const SizedBox(width: 4),
                            readBuilder(),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mediaPreview(BuildContext context, Map<String, dynamic> m) {
    final type = (m['type'] as String?) ?? 'image';
    final url = (m['url'] as String?) ?? '';

    if (type == 'image') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AspectRatio(
          aspectRatio: 1,
          child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) {
            return Container(
              color: Colors.black12,
              alignment: Alignment.center,
              child: const Icon(Icons.broken_image_outlined),
            );
          }),
        ),
      );
    } else {
      // Use a dedicated VideoPreview widget so we can initialize a
      // VideoPlayerController and provide play/pause controls.
      final double maxW = MediaQuery.of(context).size.width * 0.6;
      final double w = maxW < 220.0 ? maxW : 220.0;
      final double h = w * 9.0 / 16.0;
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: w,
          height: h,
          child: VideoPreview(url: url),
        ),
      );
    }
  }
}

/// Small video preview/player used inside chat bubbles.
class VideoPreview extends StatefulWidget {
  final String url;
  const VideoPreview({super.key, required this.url});

  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..setLooping(false)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {
          _initialized = true;
        });
      }).catchError((e) {
        // ignore init errors, show fallback UI
        if (!mounted) return;
        setState(() => _initialized = false);
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (!(_controller?.value.isInitialized ?? false)) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        _playing = false;
      } else {
        _controller!.play();
        _playing = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return Container(
        color: Colors.black12,
        alignment: Alignment.center,
        child: const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final aspect = _controller?.value.aspectRatio ?? (16 / 9);
    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(aspectRatio: aspect, child: VideoPlayer(_controller!)),
          if (!_playing)
            Container(
              color: Colors.black26,
            ),
          if (!_playing)
            const Icon(Icons.play_circle_fill, size: 48, color: Colors.white70),
        ],
      ),
    );
  }
}
