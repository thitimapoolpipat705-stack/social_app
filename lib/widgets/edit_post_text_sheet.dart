// lib/widgets/edit_post_text_sheet.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class EditPostTextSheet extends StatefulWidget {
  const EditPostTextSheet({
    super.key,
    required this.postId,
    required this.initialText,
  });

  final String postId;
  final String initialText;

  @override
  State<EditPostTextSheet> createState() => _EditPostTextSheetState();
}

class _EditPostTextSheetState extends State<EditPostTextSheet> {
  final _ctl = TextEditingController();
  final _focus = FocusNode();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctl.text = widget.initialText;
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _changed =>
      _ctl.text.trim() != (widget.initialText.trim());

  Future<void> _save() async {
    if (_saving) return;
    final newText = _ctl.text.trim();

    if (newText == widget.initialText.trim()) {
      // ไม่มีการเปลี่ยนแปลง
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่มีการเปลี่ยนแปลง')),
        );
      }
      return;
    }

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .update({
        'text': newText,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context, true); // ส่ง true กลับให้หน้าก่อนหน้า
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('แก้ไขไม่สำเร็จ: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            // Grab handle
            Container(
              height: 5,
              width: 48,
              decoration: BoxDecoration(
                color: t.colorScheme.outlineVariant.withOpacity(.6),
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            const SizedBox(height: 12),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'แก้ไขข้อความโพสต์',
                    style: t.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context, false),
                    child: const Text('ยกเลิก'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton.icon(
                    onPressed: (_saving || !_changed) ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: const Text('บันทึก'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // TextField
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: t.colorScheme.surfaceContainerHighest.withOpacity(.6),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: t.dividerColor.withOpacity(.25),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: TextField(
                    controller: _ctl,
                    focusNode: _focus,
                    autofocus: true,
                    minLines: 4,
                    maxLines: 10,
                    maxLength: 2000,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'พิมพ์ข้อความใหม่…',
                      isDense: true,
                      border: InputBorder.none,
                      counterText: '', // เราจะโชว์เคาน์เตอร์เองด้านล่าง
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
            ),

            // Counter + helper
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Icon(Icons.edit_note_rounded,
                      size: 18, color: t.colorScheme.outline),
                  const SizedBox(width: 6),
                  Text(
                    _changed ? 'มีการแก้ไข' : 'ยังไม่มีการแก้ไข',
                    style: t.textTheme.bodySmall?.copyWith(
                      color: _changed
                          ? t.colorScheme.primary
                          : t.colorScheme.outline,
                      fontWeight: _changed ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_ctl.text.characters.length}/2000',
                    style: t.textTheme.bodySmall?.copyWith(
                      color: t.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
