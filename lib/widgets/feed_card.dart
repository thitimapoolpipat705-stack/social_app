// lib/widgets/feed_card.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

class FeedCard extends StatelessWidget {
  final String postId;
  final String authorId;
  final String authorName;
  final String? authorAvatarUrl;

  /// [{'url':..., 'type':'image'|'video'}]
  final List<Map<String, dynamic>> media;

  final String? text;
  final int commentsCount;
  final int likesCount;
  final bool likedByMe;
  final String? reactionType; // 'like','love','haha','wow','sad','angry'
  final bool isOwn;

  /// เวลาโพสต์ (เอาไปแสดงเป็น “2m / 1h / 3d …”)
  final DateTime? createdAt;

  /// 🔥 ใหม่: ใช้แสดง "Edited" ถ้าแก้ไขหลังสร้าง
  final DateTime? updatedAt;

  final VoidCallback onToggleLike;
  final ValueChanged<String> onReact;  // Changed from optional to required
  final VoidCallback onComment;
  final VoidCallback? onShare;
  final VoidCallback? onReport;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onAuthorTap;

  /// เวลากด @mention ในแคปชัน
  final ValueChanged<String>? onMentionTap;

  const FeedCard({
    super.key,
    required this.postId,
    required this.authorId,
    required this.authorName,
    required this.media,
    required this.commentsCount,
    required this.likesCount,
    required this.likedByMe,
    required this.onReact,  // Add required onReact
    this.reactionType,
    required this.onToggleLike,
    required this.onComment,
    this.onShare,
    this.onReport,
    this.isOwn = false,
    this.text,
    this.authorAvatarUrl,
    this.onEdit,
    this.onDelete,
    this.onAuthorTap,
    this.createdAt,
    this.updatedAt,
    this.onMentionTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final firstImage = _firstImage(); // (provider, isValid)
    final isEdited = (updatedAt != null && createdAt != null && updatedAt!.isAfter(createdAt!));

    return Card(
      elevation: 1.5,
      color: t.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ========== Header ==========
            InkWell(
              onTap: onAuthorTap,
              borderRadius: BorderRadius.circular(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: (authorAvatarUrl?.isNotEmpty ?? false)
                        ? NetworkImage(authorAvatarUrl!)
                        : null,
                    child: !(authorAvatarUrl?.isNotEmpty ?? false)
                        ? Text(
                            authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),

                  // ชื่อ + เวลาแบบไทม์ไลน์ + Edited
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            authorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (createdAt != null) ...[
                          const SizedBox(width: 6),
                          const Text('•'),
                          const SizedBox(width: 6),
                          TimeAgo(createdAt!),
                        ],
                        if (isEdited) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: t.colorScheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text('Edited', style: t.textTheme.labelSmall),
                          ),
                        ],
                      ],
                    ),
                  ),

         PopupMenuButton<String>(
  onSelected: (val) {
    switch (val) {
      case 'edit':   onEdit?.call();   break;
      case 'delete': onDelete?.call(); break;
      case 'share':  onShare?.call();  break;
      case 'report': onReport?.call(); break;
    }
  },
  itemBuilder: (context) => [
    if (isOwn) const PopupMenuItem(value: 'edit', child: Text('Edit')),
    if (isOwn) const PopupMenuItem(value: 'delete', child: Text('Delete')),
    const PopupMenuItem(value: 'share', child: Text('Share')),
    const PopupMenuItem(value: 'report', child: Text('Report')),
  ],
),


                ],
              ),
            ),

            // ========== Media ==========
            if (firstImage != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Image(
                    image: firstImage,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: t.colorScheme.surfaceVariant,
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              ),
            ],

            // ========== Caption ==========
            if ((text ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              _Caption(text: text!, onMentionTap: onMentionTap),
            ],

            const SizedBox(height: 12),

            // ========== Actions / Meta ==========
            Row(
              children: [
                // ปุ่มคอมเมนต์ + จำนวนคอมเมนต์
                InkWell(
                  onTap: onComment,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.mode_comment_outlined, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          _commentsText(commentsCount),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (reactionType != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            ReactionButton.getEmojiForType(reactionType!),
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      Text(
                        _likesText(likedByMe, likesCount),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),

                // ปุ่ม Like / Reactions (tap = toggle, long-press = pick reaction)
                ReactionButton(
                  likedByMe: likedByMe,
                  reactionType: reactionType,
                  onTap: onToggleLike,
                  onReact: onReact,  // Now required, so we just pass it directly
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _commentsText(int n) => n <= 0 ? '0 comments' : '$n comment${n == 1 ? '' : 's'}';

  String _likesText(bool likedByMe, int likes) {
    if (likes <= 0) return '0 likes';
    if (likedByMe) return likes > 1 ? 'You & ${likes - 1} others' : 'You';
    return '$likes likes';
  }

  /// ดึงรูปแรก (รองรับทั้ง URL และ base64/ data:image)
  ImageProvider? _firstImage() {
    for (final m in media) {
      final type = (m['type'] as String?) ?? 'image';
      final raw = (m['url'] as String?)?.trim();
      if (type != 'image' || raw == null || raw.isEmpty) continue;

      // URL
      if (raw.startsWith('http')) return NetworkImage(raw);

      // data:image;base64,xxxx
      final base64Str = raw.startsWith('data:image')
          ? raw.split(',').last
          : raw;

      try {
        final bytes = base64Decode(base64Str);
        return MemoryImage(bytes);
      } catch (_) {
        // รูปเสีย/ไม่ใช่ base64 — ข้าม
      }
    }
    return null;
  }
}

/// แคปชันที่รองรับการคลิก @mentions + #tags
class _Caption extends StatelessWidget {
  final String text;
  final ValueChanged<String>? onMentionTap;
  const _Caption({required this.text, this.onMentionTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final spans = <InlineSpan>[];

    final regex = RegExp(r'(@[A-Za-z0-9_.]+)|(#\w+)|([^\s@#]+)|(\s+)');
    final matches = regex.allMatches(text);

    for (final m in matches) {
      final seg = m.group(0)!;

      if (seg.startsWith('@')) {
        final uname = seg.substring(1);
        spans.add(
          TextSpan(
            text: seg,
            style: t.textTheme.bodyMedium?.copyWith(
              color: t.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
            recognizer: (onMentionTap == null)
                ? null
                : (TapGestureRecognizer()..onTap = () => onMentionTap!(uname)),
          ),
        );
      } else if (seg.startsWith('#')) {
        spans.add(
          TextSpan(
            text: seg,
            style: t.textTheme.bodyMedium?.copyWith(
              color: t.colorScheme.secondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      } else {
        spans.add(TextSpan(text: seg, style: t.textTheme.bodyMedium));
      }
    }

    return Text.rich(TextSpan(children: spans));
  }
}

/// A small button that supports tap (toggle like) and long-press to pick a
/// reaction (like, love, haha, wow, sad, angry). Uses an OverlayEntry to show
/// the reaction picker above the button.
class ReactionButton extends StatefulWidget {
  final bool likedByMe;
  final String? reactionType;
  final VoidCallback onTap;
  final ValueChanged<String> onReact;

  const ReactionButton({
    required this.likedByMe,
    required this.onTap,
    required this.onReact,
    this.reactionType,
  });

  // Helper to convert reaction type to emoji from outside the state class
  static String getEmojiForType(String type) {
    // replicate mapping used in _ReactionButtonState
    const reactions = [
      {'type': 'like', 'emoji': '👍'},
      {'type': 'love', 'emoji': '❤️'},
      {'type': 'haha', 'emoji': '😆'},
      {'type': 'wow', 'emoji': '😮'},
      {'type': 'sad', 'emoji': '😢'},
      {'type': 'angry', 'emoji': '😡'},
    ];
    return reactions.firstWhere((r) => r['type'] == type, orElse: () => {'emoji': '❤️'})['emoji']!;
  }

  @override
  State<ReactionButton> createState() => _ReactionButtonState();
}

class _ReactionButtonState extends State<ReactionButton> {
  OverlayEntry? _entry;

  // หน่วงเวลาแยก tap vs hold
  Timer? _pressTimer;
  bool _didShowPicker = false;
  static const _holdThreshold = Duration(milliseconds: 450);

  static const _reactions = <Map<String, String>>[
    {'type': 'like', 'emoji': '👍'},
    {'type': 'love', 'emoji': '❤️'},
    {'type': 'haha', 'emoji': '😆'},
    {'type': 'wow', 'emoji': '😮'},
    {'type': 'sad', 'emoji': '😢'},
    {'type': 'angry', 'emoji': '😡'},
  ];

  static String getEmojiForType(String type) {
    return _reactions.firstWhere(
      (r) => r['type'] == type,
      orElse: () => {'emoji': '❤️'},
    )['emoji']!;
  }

  void _cancelPressTimer() {
    _pressTimer?.cancel();
    _pressTimer = null;
  }

  void _showPicker() {
    if (_entry != null) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final btnSize = renderBox.size;
    final screen = MediaQuery.of(context).size;

    // --- คำนวณความกว้างประมาณการ + จำกัดความกว้างสูงสุดของแถบ ---
    const itemExtent = 44.0; // hit target ต่อไอคอน
    const pickerHeight = 56.0;

    final estimatedWidth = _reactions.length * itemExtent + 16.0; // + padding
    final maxWidth = screen.width - 16.0; // margin ซ้าย/ขวา 8px
    final effectiveWidth = estimatedWidth.clamp(0.0, maxWidth);

    // จัดกึ่งกลางตามปุ่ม แล้ว clamp ไม่ให้เกินขอบ
    double left = offset.dx + btnSize.width / 2 - effectiveWidth / 2;
    left = left.clamp(8.0, screen.width - effectiveWidth - 8.0);

    // พยายามแสดงด้านบน ถ้าไม่พอค่อยลงล่าง
    double top = offset.dy - pickerHeight - 8.0;
    if (top < 8.0) {
      top = offset.dy + btnSize.height + 8.0;
      if (top + pickerHeight > screen.height - 8.0) {
        top = (screen.height - pickerHeight - 8.0)
            .clamp(8.0, screen.height - 8.0);
      }
    }

    _entry = OverlayEntry(builder: (context) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _removeEntry,
        child: Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: maxWidth,      // กันล้นขอบจอ
                    minHeight: pickerHeight, // ความสูงคงที่
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(40),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
                      ],
                    ),
                    // ถ้ากว้างไม่พอจะเลื่อนในแนวนอน
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: _reactions.map((r) {
                          return InkWell(
                            onTap: () {
                              widget.onReact(r['type']!);
                              _removeEntry();
                            },
                            borderRadius: BorderRadius.circular(30),
                            child: SizedBox(
                              width: itemExtent,
                              height: 40,
                              child: Center(
                                child: Text(
                                  r['emoji']!,
                                  style: const TextStyle(fontSize: 22),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });

    Overlay.of(context).insert(_entry!);
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _cancelPressTimer();
    _removeEntry();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconColor =
        widget.likedByMe ? Colors.pinkAccent : Theme.of(context).iconTheme.color;

    final Widget display = widget.reactionType == null
        ? Icon(widget.likedByMe ? Icons.favorite : Icons.favorite_border, color: iconColor)
        : Text(getEmojiForType(widget.reactionType!), style: const TextStyle(fontSize: 20));

    // แตะสั้น = toggle like, กดค้าง > 450ms = เปิดแถบ
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        _didShowPicker = false;
        _cancelPressTimer();
        _pressTimer = Timer(_holdThreshold, () {
          _didShowPicker = true;
          _showPicker();
        });
      },
      onTapUp: (_) {
        final waiting = _pressTimer?.isActive ?? false;
        _cancelPressTimer();
        if (!_didShowPicker && waiting) {
          widget.onTap(); // toggle like
        }
      },
      onTapCancel: _cancelPressTimer,
      // ถ้าเริ่มลากเพื่อสกรอลล์ ให้ยกเลิกไม่ให้แถบเด้ง
      onVerticalDragStart: (_) => _cancelPressTimer(),
      onHorizontalDragStart: (_) => _cancelPressTimer(),
      child: Container(
        padding: const EdgeInsets.all(6),
        child: display,
      ),
    );
  }
}

/// ===== เวลาแบบไทม์ไลน์ (อัปเดตทุก 1 นาที) =====
class TimeAgo extends StatefulWidget {
  final DateTime time;
  const TimeAgo(this.time, {super.key});

  @override
  State<TimeAgo> createState() => _TimeAgoState();
}

class _TimeAgoState extends State<TimeAgo> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final diff = DateTime.now().difference(widget.time);
    String label;
    if (diff.inSeconds < 60) {
      label = 'just now';
    } else if (diff.inMinutes < 60) {
      label = '${diff.inMinutes}m';
    } else if (diff.inHours < 24) {
      label = '${diff.inHours}h';
    } else if (diff.inDays < 7) {
      label = '${diff.inDays}d';
    } else {
      final w = (diff.inDays / 7).floor();
      label = '${w}w';
    }
    return Text(label, style: Theme.of(context).textTheme.bodySmall);
  }
}
