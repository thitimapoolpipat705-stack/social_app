import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// ✅ ใช้บริการรวมลอจิก follow ที่เราเขียนไว้
import '../services/follow_service.dart';

class FollowRequestsScreen extends StatefulWidget {
  const FollowRequestsScreen({super.key});

  @override
  State<FollowRequestsScreen> createState() => _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends State<FollowRequestsScreen> {
  // เก็บ state ว่าเอกสารไหนกำลังประมวลผล เพื่อ disable ปุ่มเฉพาะแถว
  final Set<String> _busyIds = {};

  // --------- Utils ---------
  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return '';
    final now = DateTime.now();
    final dt = ts.toDate();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Future<Map<String, String?>> _userLite(String uid) async {
    final snap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final d = snap.data() ?? {};
    return {
      'name': (d['displayName'] as String?) ?? 'Unknown User',
      'photo': d['photoURL'] as String?,
    };
  }

  // --------- Actions (call FollowService) ---------
  Future<void> _decline(String requesterUid, String docId, DocumentReference reqRef) async {
    setState(() => _busyIds.add(docId));
    try {
      // ใช้ service ที่รวบลอจิก: ลบคำขอ + ตีธง handled + ส่งแจ้งเตือน declined
      await FollowService.instance.declineRequest(requesterUid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Declined')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyIds.remove(docId));
    }
  }

  Future<void> _accept(String requesterUid, String docId, DocumentReference reqRef) async {
    setState(() => _busyIds.add(docId));
    try {
      // อนุมัติคำขอ: ลบคำขอ + ผูก followers/following + แจ้งเตือน accepted
      await FollowService.instance.approveRequest(requesterUid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Accepted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyIds.remove(docId));
    }
  }

  Future<void> _approveAndFollowBack(String requesterUid, String docId) async {
    setState(() => _busyIds.add(docId));
    try {
      // ✅ ฟีเจอร์ที่ต้องการ: อนุมัติ + ติดตามกลับในคลิกเดียว
      // - ถ้าอีกฝั่ง public จะ follow ได้ทันที
      // - ถ้าอีกฝั่ง private ระบบจะส่งคำขอ follow ไปหาเขาให้
      await FollowService.instance.approveAndFollowBack(requesterUid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Accepted + Followed back')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyIds.remove(docId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final meUid = FirebaseAuth.instance.currentUser!.uid;

    // ✅ ใช้ followRequests เป็น truth source
    final stream = FirebaseFirestore.instance
        .collection('users')
        .doc(meUid)
        .collection('followRequests')
        .orderBy('requestedAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Follow requests')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return const Center(child: Text('ยังไม่มีคำขอ'));
          }

          final docs = snap.data!.docs;

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (context, i) {
              final reqDoc = docs[i];
              final d = reqDoc.data();
              // บางโปรเจกต์ใช้ docId = fromUid ก็รองรับ
              final fromUid = (d['fromUid'] as String?) ?? reqDoc.id;
              final requestedAt = d['requestedAt'] as Timestamp?;

              final isBusy = _busyIds.contains(reqDoc.id);

              return FutureBuilder<Map<String, String?>>(
                future: _userLite(fromUid),
                builder: (context, userSnap) {
                  final name = userSnap.data?['name'] ?? 'Unknown User';
                  final photo = userSnap.data?['photo'];

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage:
                          photo != null ? NetworkImage(photo) : null,
                      child: photo == null ? const Icon(Icons.person) : null,
                    ),
                    title: Text('คำขอติดตามจาก $name'),
                    subtitle: Text(_formatTimestamp(requestedAt)),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: isBusy
                              ? null
                              : () => _decline(fromUid, reqDoc.id, reqDoc.reference),
                          child: isBusy ? const Text('...') : const Text('Decline'),
                        ),
                        // ปุ่ม Accept
                        FilledButton(
                          onPressed: isBusy
                              ? null
                              : () => _accept(fromUid, reqDoc.id, reqDoc.reference),
                          child: isBusy ? const Text('...') : const Text('Accept'),
                        ),
                        // ✅ ปุ่ม Follow back (ตาม requirement)
                        FilledButton.tonalIcon(
                          onPressed: isBusy
                              ? null
                              : () => _approveAndFollowBack(fromUid, reqDoc.id),
                          icon: const Icon(Icons.person_add_alt_1),
                          label: isBusy ? const Text('...') : const Text('Follow back'),
                        ),
                      ],
                    ),
                    onTap: () {
                      // ออปชัน: ไปหน้าโปรไฟล์ผู้ขอ
                      // Navigator.pushNamed(context, '/profile', arguments: fromUid);
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
