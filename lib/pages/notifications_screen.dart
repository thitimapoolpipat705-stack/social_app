import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/follow_service.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  // ---------- helpers ----------
  String _sectionOf(DateTime t) {
    final now = DateTime.now();
    final d0 = DateTime(now.year, now.month, now.day);
    final d1 = DateTime(t.year, t.month, t.day);
    final diffDays = d0.difference(d1).inDays;
    if (diffDays == 0) return 'Today';
    if (diffDays <= 7) return 'This week';
    return 'Earlier';
  }

  String _timeAgo(DateTime t) {
    final now = DateTime.now();
    final d = now.difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    final w = (d.inDays / 7).floor();
    if (w < 5) return '${w}w';
    return '${t.year}/${t.month.toString().padLeft(2, '0')}/${t.day.toString().padLeft(2, '0')}';
  }

  IconData _icon(String type) {
    switch (type) {
      case 'like':
        return Icons.favorite_rounded;
      case 'comment':
        return Icons.mode_comment_rounded;
      case 'follow':
        return Icons.person_add_rounded;
      case 'follow_request':
        return Icons.person_add_alt_rounded;
      case 'follow_request_declined':
        return Icons.block_rounded;
      case 'follow_request_accepted':
        return Icons.check_circle_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _iconBg(BuildContext ctx, String type) {
    final cs = Theme.of(ctx).colorScheme;
    switch (type) {
      case 'like':
        return cs.errorContainer;
      case 'comment':
        return cs.secondaryContainer;
      case 'follow':
        return cs.primaryContainer;
      case 'follow_request':
        return cs.surfaceVariant;
      case 'follow_request_declined':
        return cs.errorContainer;
      case 'follow_request_accepted':
        return cs.primaryContainer;
      default:
        return cs.surfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Please sign in')));
    }

    final query = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(200);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Mark all read',
            icon: const Icon(Icons.done_all_outlined),
            onPressed: () async {
              final qs = await query.get();
              final batch = FirebaseFirestore.instance.batch();
              for (final d in qs.docs) {
                if ((d.data()['read'] as bool?) != true) {
                  batch.update(d.reference, {'read': true});
                }
              }
              await batch.commit();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Marked all as read')),
                );
              }
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: Theme.of(context).dividerColor.withOpacity(.2),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('No notifications yet'));
          }

          final sections = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
          for (final d in docs) {
            final data = d.data();
            final ts = (data['createdAt'] is Timestamp)
                ? (data['createdAt'] as Timestamp).toDate()
                : DateTime.now();
            sections.putIfAbsent(_sectionOf(ts), () => []).add(d);
          }
          final order = ['Today', 'This week', 'Earlier'];

          final bottomSafe = 100.0 + MediaQuery.of(context).viewPadding.bottom;

          return ListView(
            padding: EdgeInsets.fromLTRB(12, 12, 12, bottomSafe),
            children: [
              for (final sec in order)
                if (sections.containsKey(sec)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 12, 6, 8),
                    child: Text(sec,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  ...sections[sec]!.map(
                    (doc) {
                      final data = doc.data();
                      final type = (data['type'] ?? 'info') as String;
                      final ts = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                      return _NotifCard(
                        doc: doc,
                        icon: _icon(type),
                        iconBg: _iconBg(context, type),
                        timeAgo: _timeAgo(ts),
                      );
                    },
                  ).toList(),
                ],
            ],
          );
        },
      ),
    );
  }
}

class _NotifCard extends StatefulWidget {
  const _NotifCard({
    required this.doc,
    required this.icon,
    required this.iconBg,
    required this.timeAgo,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final IconData icon;
  final Color iconBg;
  final String timeAgo;

  @override
  State<_NotifCard> createState() => _NotifCardState();
}

class _NotifCardState extends State<_NotifCard> {
  bool _working = false;
  String? _finalState; // 'accepted' | 'declined'
  bool _readLocally = false;

  Map<String, dynamic> get _data => widget.doc.data();
  String get _type => (_data['type'] ?? 'info') as String;
  String get _fromUid => (_data['fromUid'] ?? '') as String;
  String get _fromName => (_data['fromName'] ?? '') as String;
  String get _title => (_data['title'] ?? '') as String;
  String get _body => (_data['body'] ?? '') as String;

  @override
  void initState() {
    super.initState();
    _readLocally = (_data['read'] ?? false) as bool;
  }

  Future<void> _markRead() async {
    if (_readLocally) return;
    setState(() => _readLocally = true);
    try {
      await widget.doc.reference.update({'read': true});
    } catch (_) {/* no-op */}
  }

  Future<void> _handleAccept() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await FollowService.instance.approveRequest(_fromUid);
      // ตีธง handled ในแจ้งเตือนนี้ (กติกา rules เราอนุญาต)
      await widget.doc.reference.update({'handled': true, 'decision': 'approved', 'read': true});
      if (!mounted) return;
      setState(() {
        _finalState = 'accepted';
        _readLocally = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Follow request accepted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _handleDecline() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await FollowService.instance.declineRequest(_fromUid);
      await widget.doc.reference.update({'handled': true, 'decision': 'declined', 'read': true});
      if (!mounted) return;
      setState(() {
        _finalState = 'declined';
        _readLocally = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Follow request declined')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final timeAgo = widget.timeAgo;

    // แสดงปุ่ม “Follow back” เมื่อเป็นการแจ้งเตือน type=follow และยังไม่ได้ตาม
    final showFollowBack = _type == 'follow';

    // การ์ด
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _markRead,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // leading icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: widget.iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(widget.icon, color: cs.onSecondaryContainer),
              ),
              const SizedBox(width: 12),

              // --- แทนที่ตั้งแต่คอมเมนต์ // text เดิม ---
Expanded(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // บรรทัดหัวข้อ + เวลา
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ข้อความหัวข้อ (ตัดบรรทัดได้)
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (_fromName.isNotEmpty)
                    TextSpan(
                      text: _fromName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  if (_fromName.isNotEmpty) const TextSpan(text: ' '),
                  TextSpan(text: _title.isNotEmpty ? _title : _fallbackTitle(_type)),
                ],
              ),
              softWrap: true,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.start,
            ),
          ),
          const SizedBox(width: 8),
          Text(timeAgo, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),

      if (_body.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          _body,
          style: Theme.of(context).textTheme.bodySmall,
          softWrap: true,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ],

      // แถวปุ่ม แยกบรรทัดลงมา ป้องกันเบียดข้อความ
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerRight,
        child: Builder(
          builder: (context) {
            // follow request => แสดงปุ่ม accept/decline
            if (_type == 'follow_request') {
              if (_finalState == null) {
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: _working ? null : _handleDecline,
                      child: _working
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Decline'),
                    ),
                    FilledButton(
                      onPressed: _working ? null : _handleAccept,
                      child: _working
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Accept'),
                    ),
                  ],
                );
              } else {
                final cs = Theme.of(context).colorScheme;
                final accepted = _finalState == 'accepted';
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: accepted ? cs.primaryContainer : cs.surfaceVariant,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(accepted ? Icons.check_circle : Icons.block,
                          size: 16,
                          color: accepted ? cs.onPrimaryContainer : cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text(
                        accepted ? 'Accepted' : 'Declined',
                        style: TextStyle(
                          color: accepted ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }
            }

            // แจ้งเตือนแบบ follow ปกติ → ปุ่ม Follow back (ถ้าจำเป็น)
            final showFollowBack = _type == 'follow';
            if (showFollowBack) {
              return FutureBuilder<String>(
                future: FollowService.instance.relationTo(_fromUid),
                builder: (context, snap) {
                  if (!snap.hasData || snap.data == 'following') return const SizedBox.shrink();
                  if (snap.data == 'pending') {
                    return const Text('Requested', style: TextStyle(fontWeight: FontWeight.w600));
                  }
                  return FilledButton.tonal(
                    onPressed: _working
                        ? null
                        : () async {
                            setState(() => _working = true);
                            try {
                              await FollowService.instance.followOrRequest(_fromUid);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Following')),
                              );
                              setState(() {}); // refresh สถานะ
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            } finally {
                              if (mounted) setState(() => _working = false);
                            }
                          },
                    child: _working
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Follow back'),
                  );
                },
              );
            }

            // กรณีอื่น ๆ ไม่มีปุ่ม
            return const SizedBox.shrink();
          },
        ),
      ),
    ],
  ),
),
// --- จบส่วนแทนที่ ---

              const SizedBox(width: 4),
              if (!_readLocally)
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _fallbackTitle(String type) {
    switch (type) {
      case 'like':
        return 'liked your post';
      case 'comment':
        return 'commented on your post';
      case 'follow':
        return 'started following you';
      case 'follow_request':
        return 'sent you a follow request';
      case 'follow_request_declined':
        return 'your follow request was declined';
      case 'follow_request_accepted':
        return 'your follow request was accepted';
      default:
        return 'Notification';
    }
  }
}
