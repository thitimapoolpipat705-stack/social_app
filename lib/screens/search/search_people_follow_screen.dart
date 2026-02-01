import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../pages/other_profile_screen.dart';

class SearchPeopleFollowScreen extends StatefulWidget {
  const SearchPeopleFollowScreen({super.key});

  @override
  State<SearchPeopleFollowScreen> createState() => _SearchPeopleFollowScreenState();
}

class _SearchPeopleFollowScreenState extends State<SearchPeopleFollowScreen> {
  final _qCtl = TextEditingController();

  /// โหมดกรอง (เลือกได้ทีละ 1 อย่าง)
  bool _onlyMutual = true;   // ติดตามกันสองทาง
  bool _onlyIFollow = false; // ฉันติดตาม
  bool _onlyFollowMe = false;// ติดตามฉัน

  @override
  void dispose() {
    _qCtl.dispose();
    super.dispose();
  }

  void _setFilter({bool mutual = false, bool iFollow = false, bool followMe = false}) {
    setState(() {
      _onlyMutual   = mutual;
      _onlyIFollow  = iFollow;
      _onlyFollowMe = followMe;
    });
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) {
      return const Scaffold(body: Center(child: Text('Sign in first')));
    }

    final db = FirebaseFirestore.instance;

    final followingStream = db
        .collection('users').doc(myUid)
        .collection('following')
        .snapshots();

    final followersStream = db
        .collection('users').doc(myUid)
        .collection('followers')
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Search people')),
      body: Column(
        children: [
          // ค้นหา
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _qCtl,
              decoration: InputDecoration(
                hintText: 'ค้นหาชื่อหรือ @username',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: (_qCtl.text.isEmpty)
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _qCtl.clear()),
                      ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),

          // ตัวกรอง (ใช้ ChoiceChips แบบ single-selection ให้ดูสะอาดบนมือถือ)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('ติดตามกันสองทาง'),
                  selected: _onlyMutual,
                  onSelected: (v) => _setFilter(mutual: v),
                  selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                  backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                  elevation: 0,
                ),
                ChoiceChip(
                  label: const Text('ฉันติดตาม'),
                  selected: _onlyIFollow,
                  onSelected: (v) => _setFilter(iFollow: v),
                  selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                  backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                  elevation: 0,
                ),
                ChoiceChip(
                  label: const Text('ติดตามฉัน'),
                  selected: _onlyFollowMe,
                  onSelected: (v) => _setFilter(followMe: v),
                  selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                  backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                  elevation: 0,
                ),
              ],
            ),
          ),
          const Divider(height: 0),

          // รายชื่อ
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: followingStream,
              builder: (context, f1) {
                final followingIds = <String>{};
                for (final d in (f1.data?.docs ?? const [])) {
                  followingIds.add(d.id);
                }

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: followersStream,
                  builder: (context, f2) {
                    final followersIds = <String>{};
                    for (final d in (f2.data?.docs ?? const [])) {
                      followersIds.add(d.id);
                    }

                    // ---------- Query ผู้ใช้ ----------
                    final raw = _qCtl.text.trim();
                    final isUsernameMode = raw.startsWith('@');
                    final q = isUsernameMode ? raw.substring(1).toLowerCase() : raw.toLowerCase();

                    // For compatibility: many user docs may not have `displayNameLower` or `usernameLower`.
                    // To be resilient, we query a limited ordered set by `displayName` and then
                    // perform case-insensitive matching in the client using available fields.
                    final usersStream = db.collection('users').orderBy('displayName').limit(200).snapshots();

                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: usersStream,
                      builder: (context, us) {
                        if (us.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

                        final listDocs = (us.data?.docs ?? const []).where((d) => d.id != myUid).toList();

                        final items = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                        for (final doc in listDocs) {
                          final data = doc.data();
                          final displayLower = (data['displayNameLower'] as String?) ?? (data['displayName'] as String? ?? '').toLowerCase();
                          final usernameLower = (data['usernameLower'] as String?) ?? (data['username'] as String? ?? '').toLowerCase();

                          final matches = q.isEmpty || (!isUsernameMode && displayLower.contains(q)) || (isUsernameMode && usernameLower.contains(q));
                          if (!matches) continue;

                          final uid = doc.id;
                          final iFollow = followingIds.contains(uid);
                          final followMe = followersIds.contains(uid);

                          bool pass = true;
                          if (_onlyMutual) pass = iFollow && followMe;
                          if (_onlyIFollow) pass = iFollow;
                          if (_onlyFollowMe) pass = followMe;

                          if (pass) items.add(doc);
                        }

                        if (items.isEmpty) return const Center(child: Text('ไม่พบผู้ใช้ที่ตรงเงื่อนไข'));

                        return ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(height: 0),
                          itemBuilder: (_, i) {
                            final d = items[i].data();
                            final uid = items[i].id;

                            final name = (d['displayName'] ?? 'Unknown').toString();
                            final photoURL = (d['photoURL'] ?? '').toString();
                            final username = (d['username'] ?? '').toString();

                            final iFollow = followingIds.contains(uid);
                            final followMe = followersIds.contains(uid);
                            final mutual = iFollow && followMe;

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: photoURL.isNotEmpty ? NetworkImage(photoURL) : null,
                                child: photoURL.isEmpty ? const Icon(Icons.person) : null,
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                  if (mutual) const _Badge(color: Colors.green, label: 'Mutual'),
                                  if (!mutual && iFollow) const _Badge(color: Colors.blue, label: 'I follow'),
                                  if (!mutual && followMe) const _Badge(color: Colors.amber, label: 'Follows me'),
                                ],
                              ),
                              subtitle: Text(username.isNotEmpty ? '@$username' : 'uid: $uid', maxLines: 2, overflow: TextOverflow.ellipsis),
                              onTap: () {
                                // Open other user's profile
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => OtherProfileScreen(otherUid: uid),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    ); // usersStream
                  }, // followersStream builder
                ); // followersStream
              }, // followingStream builder
            ), // followingStream
          ), // Expanded
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.6)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
