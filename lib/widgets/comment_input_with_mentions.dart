import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CommentInputWithMentions extends StatefulWidget {
  const CommentInputWithMentions({
    super.key,
    required this.postId,
    this.onSubmitted,                // callback หลังบันทึกสำเร็จ
    this.notifyMentions = true,      // ส่ง noti ให้ผู้ถูกแท็ก
  });

  final String postId;
  final Future<void> Function()? onSubmitted;
  final bool notifyMentions;

  @override
  State<CommentInputWithMentions> createState() => _CommentInputWithMentionsState();
}

class _CommentInputWithMentionsState extends State<CommentInputWithMentions> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _overlay = LayerLink();

  OverlayEntry? _entry;
  bool _showing = false;
  List<_UserLite> _suggestions = [];
  String _currentQuery = '';
  Timer? _debounce;

  // แคชรายชื่อที่เราตามอยู่ → จำกัดข้อเสนอเฉพาะคนเหล่านี้
  final _followingIds = <String>{};
  final _followingUsers = <String, _UserLite>{}; // uid -> user

  @override
  void initState() {
    super.initState();
    _prefetchFollowing();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeOverlay();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ---------- Overlay helpers ----------
  void _removeOverlay() {
    _entry?.remove();
    _entry = null;
    _showing = false;
  }

  void _showOverlay() {
    if (_showing) return;
    final overlay = Overlay.of(context);
    _entry = OverlayEntry(builder: (_) {
      final theme = Theme.of(context);
      return Positioned(
        left: 12,
        right: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 56, // ให้อยู่เหนือปุ่มส่ง
        child: CompositedTransformFollower(
          link: _overlay,
          showWhenUnlinked: false,
          offset: const Offset(0, -8),
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(10),
            color: theme.colorScheme.surface,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (_, i) {
                  final u = _suggestions[i];
                  final hasPhoto = (u.photoURL?.isNotEmpty ?? false);
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      backgroundImage: hasPhoto ? NetworkImage(u.photoURL!) : null,
                      child: hasPhoto ? null : const Icon(Icons.person),
                    ),
                    title: Text(u.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('@${u.username ?? u.displayName.toLowerCase().replaceAll(' ', '')}',
                        style: theme.textTheme.bodySmall),
                    onTap: () => _insertMention(u),
                  );
                },
              ),
            ),
          ),
        ),
      );
    });
    overlay.insert(_entry!);
    _showing = true;
  }

  // ---------- Data ----------
  Future<void> _prefetchFollowing() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    final db = FirebaseFirestore.instance;
    final f = await db.collection('users').doc(me.uid).collection('following').limit(200).get();
    if (f.docs.isEmpty) return;

    _followingIds.addAll(f.docs.map((e) => e.id));

    // batch ดึงโปรไฟล์
    final ids = _followingIds.toList();
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10);
      final q = await db.collection('users').where(FieldPath.documentId, whereIn: chunk).get();
      for (final d in q.docs) {
        final u = _UserLite.fromDoc(d);
        _followingUsers[u.uid] = u;
      }
    }
    if (mounted) setState(() {});
  }

  // ค้นผู้ใช้เมื่อเจอ token ที่ขึ้นต้นด้วย @ (debounce)
  Future<void> _searchUsers(String q) async {
    final token = q.trim().toLowerCase();
    if (token.isEmpty || _followingUsers.isEmpty) {
      _suggestions = [];
      _removeOverlay();
      if (mounted) setState(() {});
      return;
    }

    // กรองจากแคชที่เรามี (เร็ว ไม่เผา quota)
    final all = _followingUsers.values.toList();
    all.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

    _suggestions = all.where((u) {
      final dn = u.displayName.toLowerCase();
      final un = (u.username ?? '').toLowerCase();
      return dn.contains(token) || un.contains(token);
    }).take(8).toList();

    if (_suggestions.isEmpty) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
    if (mounted) setState(() {});
  }

  // แทรก mention แทน token ปัจจุบัน
  void _insertMention(_UserLite user) {
    final text = _input.text;
    final cursor = _input.selection.baseOffset;
    if (cursor < 0) return;

    // หาตำแหน่ง token ล่าสุดที่ขึ้นต้นด้วย @
    final start = text.lastIndexOf('@', cursor - 1);
    if (start < 0) return;

    // ขยาย token จนถึงช่องว่าง/สิ้นสุด
    int end = cursor;
    while (end < text.length && !RegExp(r'\s').hasMatch(text[end])) {
      end++;
    }

    final before = text.substring(0, start);
    final after = text.substring(end);
    final handle = user.username != null && user.username!.isNotEmpty
        ? user.username!
        : user.displayName.toLowerCase().replaceAll(' ', '');
    final inserted = '@$handle ';

    final newText = '$before$inserted$after';
    _input.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: (before + inserted).length),
    );
    _removeOverlay();
  }

  // ดึงรายชื่อ uid ที่ถูก mention จากข้อความ:
  // 1) จับ @username → หาโดย usernameLower
  // 2) ถ้าไม่เจอ ลองแมตช์ displayNameLower แบบตรงตัว
  Future<List<String>> _extractMentionUids(String text) async {
    final atWords = RegExp(r'@([A-Za-z0-9_.]+)').allMatches(text).map((m) => m.group(1)!).toSet();
    if (atWords.isEmpty) return [];

    final db = FirebaseFirestore.instance;
    final uids = <String>[];

    // ลองหาด้วย usernameLower (รวมทีละ 10)
    final usernames = atWords.map((e) => e.toLowerCase()).toList();
    for (var i = 0; i < usernames.length; i += 10) {
      final chunk = usernames.sublist(i, i + 10 > usernames.length ? usernames.length : i + 10);
      final q = await db.collection('users')
          .where('usernameLower', whereIn: chunk)
          .get();
      for (final d in q.docs) {
        uids.add(d.id);
      }
    }

    // ถ้าบางคำยังไม่เจอ → ลอง displayNameLower
    final still = usernames.where((u) => !_containsUidOfUsername(uids, u)).toList();
    for (final name in still) {
      final q = await db.collection('users')
          .where('displayNameLower', isEqualTo: name)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) uids.add(q.docs.first.id);
    }

    return uids.toSet().toList();
  }

  bool _containsUidOfUsername(List<String> uids, String usernameLower) {
    // helper placeholder — เราแค่เช็กจากการค้นรอบแรกว่ามี uid แล้วหรือยัง
    // (จริง ๆ ไม่สามารถ mapping กลับ username ได้โดยตรงถ้าไม่เก็บเพิ่ม)
    // ใช้เพื่อหลีกเลี่ยงค้นชื่อซ้ำมากเกินไป
    return false;
  }

  Future<void> _notifyMentions({
    required List<String> mentionedUids,
    required String preview,
  }) async {
    if (!widget.notifyMentions || mentionedUids.isEmpty) return;
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    for (final uid in mentionedUids) {
      if (uid == me.uid) continue; // ไม่เตือนตัวเอง
      final ref = db.collection('users').doc(uid).collection('notifications').doc();
      batch.set(ref, {
        'type': 'mention',
        'fromUid': me.uid,
        'fromName': me.displayName ?? '',
        'postId': widget.postId,
        'postThumbUrl': null,
        'title': 'mentioned you in a comment',
        'body': preview,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> _send() async {
    final me = FirebaseAuth.instance.currentUser;
    final text = _input.text.trim();
    if (me == null || text.isEmpty) return;

    final mentioned = await _extractMentionUids(text);

    final db = FirebaseFirestore.instance;
    final postRef = db.collection('posts').doc(widget.postId);

    await postRef.collection('comments').add({
      'authorId': me.uid,
      'authorName': me.displayName ?? '',
      'text': text,
      'mentionedUids': mentioned,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // เพิ่ม counter
    await db.runTransaction((tx) async {
      tx.update(postRef, {'commentsCount': FieldValue.increment(1)});
    });

    // แจ้งผู้ถูกแท็ก
    final preview = text.length > 60 ? '${text.substring(0, 60)}…' : text;
    await _notifyMentions(mentionedUids: mentioned, preview: preview);

    _input.clear();
    _removeOverlay();
    if (widget.onSubmitted != null) await widget.onSubmitted!();
  }

  // ตรวจ token ทุกครั้งที่พิมพ์ (debounce)
  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      final text = _input.text;
      final cursor = _input.selection.baseOffset;
      if (cursor <= 0) {
        _removeOverlay();
        return;
      }
      final start = text.lastIndexOf('@', cursor - 1);
      if (start < 0) {
        _removeOverlay();
        return;
      }
      // token ปัจจุบัน: @xxxxx (จนกว่าจะเจอช่องว่าง)
      int end = cursor;
      while (end < text.length && !RegExp(r'\s').hasMatch(text[end])) {
        end++;
      }
      final token = text.substring(start + 1, end); // ไม่รวม '@'
      _currentQuery = token;
      await _searchUsers(token);
    });
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _overlay,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              focusNode: _focus,
              minLines: 1,
              maxLines: 4,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                hintText: 'เขียนคอมเมนต์… (@ชื่อ หรือ @username เพื่อแท็ก)',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _send,
            child: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}

// ===== Model เบา ๆ =====
class _UserLite {
  final String uid;
  final String displayName;
  final String? username;
  final String? photoURL;
  _UserLite({required this.uid, required this.displayName, this.username, this.photoURL});

  factory _UserLite.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? {};
    return _UserLite(
      uid: d.id,
      displayName: (data['displayName'] as String?) ?? '',
      username: (data['username'] as String?) ?? (data['usernameLower'] as String?),
      photoURL: data['photoURL'] as String?,
    );
  }
}
