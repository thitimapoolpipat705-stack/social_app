// lib/screens/search/search_pages_groups_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../page/page_feed_screen.dart';
import '../group/group_feed_screen.dart';
import '../search/search_people_follow_screen.dart';
import '../../pages/other_profile_screen.dart';

class SearchPagesGroupsScreen extends StatefulWidget {
  const SearchPagesGroupsScreen({super.key});
  @override
  State<SearchPagesGroupsScreen> createState() => _SearchPagesGroupsScreenState();
}

class _SearchPagesGroupsScreenState extends State<SearchPagesGroupsScreen> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final queryText = _q.text.trim();

    // ---------- Build prefix queries ----------
    // Pages
    Query<Map<String, dynamic>> pagesQuery =
        FirebaseFirestore.instance.collection('pages');
    if (queryText.isNotEmpty) {
      pagesQuery = pagesQuery
          .orderBy('name')
          .startAt([queryText])
          .endAt(['$queryText\uf8ff'])
          .limit(25);
    } else {
      pagesQuery = pagesQuery.orderBy('createdAt', descending: true).limit(10);
    }

    // Groups
    Query<Map<String, dynamic>> groupsQuery =
        FirebaseFirestore.instance.collection('groups');
    if (queryText.isNotEmpty) {
      groupsQuery = groupsQuery
          .orderBy('name')
          .startAt([queryText])
          .endAt(['$queryText\uf8ff'])
          .limit(25);
    } else {
      groupsQuery = groupsQuery.orderBy('createdAt', descending: true).limit(10);
    }

  // People: ถ้าเริ่มด้วย @ ให้ค้น username, ไม่งั้นค้น displayName
  final peopleIsUsername = queryText.startsWith('@');
  final peopleWord = peopleIsUsername ? queryText.substring(1) : queryText;

    Stream<QuerySnapshot<Map<String, dynamic>>>? peopleStream;
    if (peopleWord.isNotEmpty) {
      // Use a safe fallback stream ordered by displayName and filter client-side.
      // This avoids relying on `displayNameLower` / `usernameLower` being present.
      peopleStream = FirebaseFirestore.instance
          .collection('users')
          .orderBy('displayName')
          .limit(200)
          .snapshots();
    }

    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        actions: [
          IconButton(
            tooltip: 'Advanced',
            icon: const Icon(Icons.tune),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchPeopleFollowScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search box
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _q,
              decoration: InputDecoration(
                hintText: 'ค้นหาเพื่อน (@username) / เพจ / กลุ่ม',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: (_q.text.isEmpty)
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _q.clear()),
                      ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),

          Expanded(
            child: ListView(
              children: [
                // ---------- PEOPLE ----------
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text('People', style: Theme.of(context).textTheme.titleMedium),
                ),
                if (peopleStream == null)
                  const _EmptyListTile(text: 'พิมพ์ชื่อหรือ @username เพื่อค้นหาเพื่อน')
                else
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: peopleStream,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) return const _LoadingTile();

                      final q = peopleWord.toLowerCase();
                      final isUsernameMode = peopleIsUsername;

                      final docs = (snap.data?.docs ?? const [])
                          .where((d) => d.id != myUid)
                          .where((d) {
                            final data = d.data();
                            final displayLower = (data['displayNameLower'] as String?) ?? (data['displayName'] as String? ?? '').toLowerCase();
                            final usernameLower = (data['usernameLower'] as String?) ?? (data['username'] as String? ?? '').toLowerCase();
                            return q.isEmpty || (!isUsernameMode && displayLower.contains(q)) || (isUsernameMode && usernameLower.contains(q));
                          })
                          .toList();

                      if (docs.isEmpty) return const _EmptyListTile(text: 'ไม่พบผู้ใช้');

                      return Column(
                        children: docs.map((d) {
                          final u = d.data();
                          final displayName = (u['displayName'] ?? 'Unknown').toString();
                          final username = (u['username'] ?? '').toString();
                          final photoURL = (u['photoURL'] ?? '').toString();
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundImage: (photoURL.isNotEmpty) ? NetworkImage(photoURL) : null,
                              child: (photoURL.isEmpty) ? const Icon(Icons.person) : null,
                            ),
                            title: Text(
                              displayName,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: (username.isNotEmpty) ? Text('@$username') : null,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              // Open other user's profile
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => OtherProfileScreen(otherUid: d.id),
                                ),
                              );
                            },
                          );
                        }).toList(),
                      );
                    },
                  ),

                const Divider(),

                // ---------- PAGES ----------
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text('Pages', style: Theme.of(context).textTheme.titleMedium),
                ),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: pagesQuery.snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData) return const _LoadingTile();
                    final docs = snap.data!.docs;
                    if (docs.isEmpty) {
                      return const _EmptyListTile(text: 'No pages found');
                    }
                    return Column(
                      children: docs.map((d) {
                        final data = d.data();
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.pages)),
                          title: Text(data['name'] ?? 'Untitled'),
                          subtitle:
                              Text((data['isPrivate'] == true) ? 'Private' : 'Public'),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PageFeedScreen(
                                  pageId: d.id,
                                  pageName: data['name'] ?? 'Page',
                                ),
                              ),
                            );
                          },
                        );
                      }).toList(),
                    );
                  },
                ),

                const Divider(),

                // ---------- GROUPS ----------
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text('Groups', style: Theme.of(context).textTheme.titleMedium),
                ),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: groupsQuery.snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData) return const _LoadingTile();
                    final docs = snap.data!.docs;
                    if (docs.isEmpty) {
                      return const _EmptyListTile(text: 'No groups found');
                    }
                    return Column(
                      children: docs.map((d) {
                        final data = d.data();
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.groups)),
                          title: Text(data['name'] ?? 'Untitled'),
                          subtitle:
                              Text((data['isPrivate'] == true) ? 'Private' : 'Public'),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => GroupFeedScreen(
                                  groupId: d.id,
                                  groupName: data['name'] ?? 'Group',
                                ),
                              ),
                            );
                          },
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingTile extends StatelessWidget {
  const _LoadingTile();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _EmptyListTile extends StatelessWidget {
  const _EmptyListTile({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(text, textAlign: TextAlign.center),
    );
  }
}
