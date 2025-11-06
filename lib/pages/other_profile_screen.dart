import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../chat_repository.dart';
import '../chat_screens.dart';
import 'edit_profile_sheet.dart';

class OtherProfileScreen extends StatefulWidget {
  final String otherUid;
  const OtherProfileScreen({super.key, required this.otherUid});

  @override
  State<OtherProfileScreen> createState() => _OtherProfileScreenState();
}

class _OtherProfileScreenState extends State<OtherProfileScreen> {
  Map<String, dynamic>? userData;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.otherUid)
          .get();
      if (!mounted) return;
      if (snap.exists) {
        setState(() {
          userData = snap.data();
          loading = false;
        });
      } else {
        setState(() {
          error = 'User not found';
          loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Future<void> _openChat() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in first')),
      );
      return;
    }
    if (me == widget.otherUid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can't chat with yourself")),
      );
      return;
    }
    try {
      final repo = ChatRepository();
      final cid = await repo.openConversationWith(widget.otherUid);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatRoomScreen(cid: cid, otherUid: widget.otherUid),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Open chat failed: $e')),
      );
    }
  }

  void _openEditProfile() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const EditProfileSheet(),
    ).then((_) => _loadUserData());
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (error != null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(error!)));
    }

    final displayName = (userData?['displayName'] as String?) ?? 'Unknown User';
    final photoURL = userData?['photoURL'] as String?;
    final coverURL = userData?['coverUrl'] as String?;
    final isPrivate = (userData?['isPrivate'] as bool?) ?? false;
    final followerCount = (userData?['followersCount'] as int?) ?? 0;
    final followingCount = (userData?['followingCount'] as int?) ?? 0;
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isMyProfile = currentUid == widget.otherUid;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Theme.of(context).colorScheme.onBackground,
        title: Text(isMyProfile ? 'My Profile' : displayName),
        actions: [
          if (!isMyProfile)
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  builder: (_) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.block),
                          title: const Text('Block User'),
                          onTap: () {
                            Navigator.pop(context);
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.flag),
                          title: const Text('Report'),
                          onTap: () {
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadUserData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              // Cover + avatar stack
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: 220,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(.06),
                      image: coverURL != null
                          ? DecorationImage(
                              image: NetworkImage(coverURL),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withOpacity(0.15),
                            Colors.transparent,
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),

                  // Avatar positioned
                  Positioned(
                    left: 16,
                    bottom: -48,
                    child: CircleAvatar(
                      radius: 48,
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      backgroundImage: (photoURL != null && photoURL.isNotEmpty)
                          ? NetworkImage(photoURL)
                          : null,
                      child: (photoURL == null || photoURL.isEmpty)
                          ? Icon(Icons.person, size: 48, color: Theme.of(context).colorScheme.onSurface)
                          : null,
                    ),
                  ),
                ],
              ),

              // White card with details
              const SizedBox(height: 56),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Material(
                  borderRadius: BorderRadius.circular(12),
                  elevation: 2,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Centered name + bio
                        Text(
                          displayName,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        if (userData?['bio'] != null && (userData!['bio'] as String).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text(
                              userData!['bio'] as String,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),

                        const SizedBox(height: 12),

                        // Action buttons (centered)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: 40,
                              child: _FollowButton(otherUid: widget.otherUid),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 40,
                              child: isMyProfile
                                  ? FilledButton(
                                      onPressed: _openEditProfile,
                                      style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                      child: const Text('Edit profile'),
                                    )
                                  : OutlinedButton(
                                      onPressed: _openChat,
                                      style: OutlinedButton.styleFrom(
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.chat_bubble_outline, size: 18),
                                          SizedBox(width: 6),
                                          Text('Message'),
                                        ],
                                      ),
                                    ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Stats
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _StatItem(count: (userData?['postsCount'] ?? 0), label: 'Posts'),
                            _StatItem(count: followerCount, label: 'Followers'),
                            _StatItem(count: followingCount, label: 'Following'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Posts section header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Posts', style: Theme.of(context).textTheme.titleMedium),
                    // could add sort/filter icon here
                    const SizedBox.shrink(),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Posts grid (same permissions as before)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: SizedBox(
                  height: 400,
                  child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseAuth.instance.currentUser != null
                        ? FirebaseFirestore.instance
                            .collection('users')
                            .doc(FirebaseAuth.instance.currentUser!.uid)
                            .collection('following')
                            .doc(widget.otherUid)
                            .snapshots()
                        : null,
                    builder: (context, followSnap) {
                      final canSeeContent = !isPrivate || isMyProfile || followSnap.data?.exists == true;

                      if (!canSeeContent) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_outline, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text('This account is private', style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 6),
                              Text('Follow to see posts', style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        );
                      }

                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('posts')
                            .where('authorId', isEqualTo: widget.otherUid)
                            .orderBy('createdAt', descending: true)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }

                          final posts = snapshot.data?.docs ?? [];
                          if (posts.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.photo_library_outlined, size: 48, color: Colors.grey.shade400),
                                  const SizedBox(height: 12),
                                  Text('No posts yet', style: Theme.of(context).textTheme.titleMedium),
                                ],
                              ),
                            );
                          }

                          return GridView.builder(
                            physics: const BouncingScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 4,
                              crossAxisSpacing: 4,
                            ),
                            itemCount: posts.length,
                            itemBuilder: (context, index) {
                              final post = posts[index].data();
                              final media = post['media'] as List?;
                              final firstMediaUrl = media?.isNotEmpty == true ? (media!.first as Map)['url'] as String? : null;

                              return ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: GestureDetector(
                                  onTap: () {},
                                  child: Container(
                                    color: Theme.of(context).colorScheme.surfaceVariant,
                                    child: firstMediaUrl != null
                                        ? Image.network(firstMediaUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.error_outline))
                                        : const Center(child: Icon(Icons.article_outlined)),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final int count;
  final String label;
  const _StatItem({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          count.toString(),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _FollowButton extends StatelessWidget {
  final String otherUid;
  const _FollowButton({required this.otherUid});

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) {
      return OutlinedButton(
        onPressed: null,
        child: const Text('Sign in first'),
      );
    }
    if (me == otherUid) {
      return const SizedBox.shrink();
    }

    final db = FirebaseFirestore.instance;

    final otherUserDoc = db.collection('users').doc(otherUid).snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>( 
      stream: otherUserDoc,
      builder: (context, otherSnap) {
        final isPrivate = (otherSnap.data?.data()?['isPrivate'] == true);

        final followingDoc = db
            .collection('users')
            .doc(me)
            .collection('following')
            .doc(otherUid)
            .snapshots();

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>( 
          stream: followingDoc,
          builder: (context, folSnap) {
            final isFollowing = folSnap.data?.exists == true;

            if (isFollowing) {
              return FilledButton.tonal(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Unfollow?'),
                      content: const Text('Stop following this user?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Unfollow'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await _unfollow(db, me, otherUid);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Unfollowed')),
                      );
                    }
                  }
                },
                child: const Text('Following'),
              );
            }

            if (isPrivate) {
              final reqDoc = db
                  .collection('users')
                  .doc(otherUid)
                  .collection('followRequests')
                  .doc(me)
                  .snapshots();
              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>( 
                stream: reqDoc,
                builder: (context, reqSnap) {
                  final requested = reqSnap.data?.exists == true;

                  if (requested) {
                    return OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.hourglass_top),
                      label: const Text('Requested'),
                    );
                  }

                  return FilledButton.icon(
                    onPressed: () async {
                      await _requestFollow(db, me, otherUid);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Follow request sent')),
                        );
                      }
                    },
                    icon: const Icon(Icons.person_add_alt),
                      label: const Text('Follow'),
                  );
                },
              );
            }

            return FilledButton.icon(
              onPressed: () async {
                await _followNow(db, me, otherUid);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Following')),
                  );
                }
              },
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Follow'),
            );
          },
        );
      },
    );
  }

  Future<void> _followNow(
      FirebaseFirestore db, String me, String other) async {
    final batch = db.batch();
    final now = FieldValue.serverTimestamp();

    final meFollowing = db.collection('users').doc(me).collection('following').doc(other);
    final otherFollowers = db.collection('users').doc(other).collection('followers').doc(me);

    batch.set(meFollowing, {'followedAt': now});
    batch.set(otherFollowers, {'followedAt': now});

    batch.set(db.collection('users').doc(me),
        {'followingCount': FieldValue.increment(1)}, SetOptions(merge: true));
    batch.set(db.collection('users').doc(other),
        {'followersCount': FieldValue.increment(1)}, SetOptions(merge: true));

    final notifRef =
        db.collection('users').doc(other).collection('notifications').doc();
    batch.set(notifRef, {
      'type': 'follow_accepted', 
      'fromUid': me,
      'createdAt': now,
      'read': false,
      'message': 'started following you'
    });

    await batch.commit();
  }

  Future<void> _requestFollow(
      FirebaseFirestore db, String me, String other) async {
    final now = FieldValue.serverTimestamp();
    final req = db.collection('users').doc(other).collection('followRequests').doc(me);
    await req.set({'requestedAt': now});

    await db.collection('users').doc(other).collection('notifications').add({
      'type': 'follow_request',
      'fromUid': me,
      'createdAt': now,
      'read': false,
      'message': 'requested to follow you'
    });
  }

  Future<void> _unfollow(
      FirebaseFirestore db, String me, String other) async {
    final batch = db.batch();
    final meFollowing = db.collection('users').doc(me).collection('following').doc(other);
    final otherFollowers = db.collection('users').doc(other).collection('followers').doc(me);

    batch.delete(meFollowing);
    batch.delete(otherFollowers);

    batch.set(db.collection('users').doc(me),
        {'followingCount': FieldValue.increment(-1)}, SetOptions(merge: true));
    batch.set(db.collection('users').doc(other),
        {'followersCount': FieldValue.increment(-1)}, SetOptions(merge: true));

    await batch.commit();
  }
}
