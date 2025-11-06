// lib/widgets/report_post_sheet.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ReportPostSheet extends StatefulWidget {
  const ReportPostSheet({
    super.key,
    required this.postId,
    required this.postAuthorId,
    this.postText,
    this.postThumbUrl,
  });

  final String postId;
  final String postAuthorId;
  final String? postText;
  final String? postThumbUrl;

  @override
  State<ReportPostSheet> createState() => _ReportPostSheetState();
}

class _ReportPostSheetState extends State<ReportPostSheet> {
  final _detailCtl = TextEditingController();
  final _scrollCtl = ScrollController();
  bool _submitting = false;
  String _selected = 'Spam';
  bool _done = false;

  final _reasons = const <Map<String, dynamic>>[
    {'label': 'Spam',                      'icon': Icons.report_gmailerrorred_outlined},
    {'label': 'Harassment / Hate',        'icon': Icons.sentiment_dissatisfied_outlined},
    {'label': 'Nudity / Sexual content',  'icon': Icons.no_adult_content},
    {'label': 'Violence / Graphic',       'icon': Icons.emergency_outlined},
    {'label': 'False information',        'icon': Icons.info_outline},
    {'label': 'Other',                    'icon': Icons.more_horiz},
  ];

  @override
  void dispose() {
    _detailCtl.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final db = FirebaseFirestore.instance;
      final me = FirebaseAuth.instance.currentUser;

      // บันทึกรีพอร์ต
      await db.collection('postReports').add({
        'postId': widget.postId,
        'postAuthorId': widget.postAuthorId,
        'reason': _selected,
        'detail': _detailCtl.text.trim(),
        'postText': widget.postText,
        'postThumbUrl': widget.postThumbUrl,
        'reporterUid': me?.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'open',
      });

      // เพิ่มตัวนับ report บนโพสต์ (optional)
      await db.collection('posts').doc(widget.postId).set(
        {'reportCount': FieldValue.increment(1), 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );

      // แจ้งเตือนเจ้าของโพสต์ให้ตรวจ/ลบ (optional – เปิดใช้ได้กับกฎที่เราตั้งไว้)
      if (widget.postAuthorId.isNotEmpty) {
        await db
            .collection('users')
            .doc(widget.postAuthorId)
            .collection('notifications')
            .add({
          'type': 'report_received',
          'fromUid': me?.uid,
          'fromName': me?.displayName ?? '',
          'postId': widget.postId,
          'postThumbUrl': widget.postThumbUrl,
          'title': 'Your post was reported',
          'body': 'Reason: $_selected',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // โชว์สถานะสำเร็จ
      setState(() => _done = true);
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ส่งรีพอร์ตไม่สำเร็จ: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
          child: _done
              ? _SuccessView()
              : SingleChildScrollView(
                  controller: _scrollCtl,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          const Icon(Icons.flag_outlined),
                          const SizedBox(width: 8),
                          Text('Report post',
                              style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: _submitting ? null : () => Navigator.pop(context, false),
                            icon: const Icon(Icons.close),
                          )
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Post preview (เล็ก ๆ)
                      if ((widget.postThumbUrl?.isNotEmpty ?? false) || (widget.postText?.isNotEmpty ?? false))
                        _PostPreview(thumbUrl: widget.postThumbUrl, text: widget.postText),

                      const SizedBox(height: 12),

                      Text('Reason', style: t.textTheme.titleMedium),
                      const SizedBox(height: 8),

                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _reasons.map((r) {
                          final label = r['label'] as String;
                          final icon = r['icon'] as IconData;
                          final selected = _selected == label;
                          return ChoiceChip(
                            selected: selected,
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon, size: 18),
                                const SizedBox(width: 6),
                                Text(label),
                              ],
                            ),
                            onSelected: (v) => setState(() => _selected = label),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 16),

                      Text('More details (optional)', style: t.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _detailCtl,
                        minLines: 3,
                        maxLines: 6,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: 'อธิบายเพิ่มเติมเพื่อช่วยให้ทีมเข้าใจเหตุผลที่รีพอร์ต…',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),

                      const SizedBox(height: 16),

                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _submitting ? null : _submit,
                          icon: _submitting
                              ? const SizedBox(
                                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.send_rounded),
                          label: const Text('Submit'),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _PostPreview extends StatelessWidget {
  const _PostPreview({this.thumbUrl, this.text});
  final String? thumbUrl;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceVariant.withOpacity(.5),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (thumbUrl != null && thumbUrl!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(thumbUrl!, width: 56, height: 56, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                        width: 56, height: 56,
                        color: t.colorScheme.surface,
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image_outlined),
                      )),
            ),
          if (thumbUrl != null && thumbUrl!.isNotEmpty) const SizedBox(width: 10),
          Expanded(
            child: Text(
              (text ?? '').isEmpty ? 'No caption' : text!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.bodyMedium,
            ),
          )
        ],
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        CircleAvatar(
          radius: 28,
          backgroundColor: t.colorScheme.primary.withOpacity(.12),
          child: Icon(Icons.check_rounded, size: 36, color: t.colorScheme.primary),
        ),
        const SizedBox(height: 12),
        Text('Report submitted', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('ขอบคุณสำหรับความร่วมมือของคุณ', style: t.textTheme.bodyMedium),
        const SizedBox(height: 8),
      ],
    );
  }
}
