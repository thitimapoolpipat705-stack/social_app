// lib/pages/profile_screen.dart
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../starter_screens.dart';
import '../screens/group/create_group_screen.dart';
import 'package:go_router/go_router.dart';


class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  User? get _user => FirebaseAuth.instance.currentUser;

  // These functions will be implemented later when adding social features

  // ===== BottomSheet: Edit profile (cover + avatar + name + bio) =====
  Future<void> _openEditProfile() async {
    final user = _user;
    if (user == null) return;

    final snap = await _db.collection('users').doc(user.uid).get();
    final data = Map<String, dynamic>.from(snap.data() ?? {});

    final nameCtl = TextEditingController(text: user.displayName ?? (data['displayName'] ?? ''));
    final bioCtl  = TextEditingController(text: (data['bio'] ?? '').toString());
    String? coverUrl = (data['coverUrl'] as String?)?.trim();
    String? photoUrl = (user.photoURL?.isNotEmpty == true) ? user.photoURL : (data['photoURL'] as String?);

    Future<String?> _pickAndUpload({required bool isCover}) async {
      try {
        final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          imageQuality: isCover ? 85 : 80,
          maxWidth: isCover ? 1280 : 512,
          maxHeight: isCover ? 720 : 512,
        );
        if (picked == null) return null;
        
        final file = File(picked.path);
        final fileSize = await file.length();
        final maxSize = isCover ? 5 * 1024 * 1024 : 2 * 1024 * 1024; // 5MB for cover, 2MB for avatar
        
        if (fileSize > maxSize) {
          if (!mounted) return null;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('File too large (max ${maxSize ~/ (1024 * 1024)}MB)')),
          );
          return null;
        }

        // Refresh token to avoid expired auth causing unauthorized error
        if (user.uid.isNotEmpty) {
          try {
            await user.getIdToken(true);
          } catch (_) {}
        }

        // Upload to Firebase Storage
        final ref = _storage.ref()
          .child('user-photos')
          .child(user.uid)
          .child(isCover ? 'cover.jpg' : 'avatar.jpg');
          
        final uploadTask = await ref.putFile(
          file,
          SettableMetadata(
            contentType: 'image/jpeg',
            cacheControl: 'public, max-age=3600',
          ),
        );
        
        final downloadUrl = await uploadTask.ref.getDownloadURL();

        // If this is profile photo, update Auth profile first
        if (!isCover) {
          await user.updatePhotoURL(downloadUrl);
        }

        // Save new URL to Firestore
        await _db.collection('users').doc(user.uid).set({
          isCover ? 'coverUrl' : 'photoURL': downloadUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        
        return downloadUrl;
      } catch (e) {
        if (!mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading image: $e')),
        );
        return null;
      }
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16, right: 16, top: 16,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Center(child: Text('Edit profile', style: Theme.of(context).textTheme.titleLarge)),
                  const SizedBox(height: 16),

                  // Cover
                  GestureDetector(
                    onTap: () async {
                      final url = await _pickAndUpload(isCover: true);
                      if (url != null) {
                        coverUrl = url;
                        setSheet((){});
                        setState(() {}); // Refresh parent after upload
                      }
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          height: 120,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey[300],
                            image: coverUrl != null && coverUrl!.isNotEmpty
                              ? DecorationImage(image: NetworkImage(coverUrl!), fit: BoxFit.cover)
                              : null,
                          ),
                        ),
                        Container(
                          height: 120,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.black26,
                          ),
                          child: const Center(child: Icon(Icons.photo_camera, color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Avatar
                  Center(
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundImage: photoUrl != null && photoUrl!.isNotEmpty
                            ? NetworkImage(photoUrl!)
                            : null,
                          child: photoUrl == null || photoUrl!.isEmpty
                            ? const Icon(Icons.person, size: 40)
                            : null,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: GestureDetector(
                            onTap: () async {
                              final url = await _pickAndUpload(isCover: false);
                              if (url != null) {
                                photoUrl = url;
                                setSheet((){});
                                setState(() {});
                              }
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: const EdgeInsets.all(6),
                              child: const Icon(Icons.edit, color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  TextField(
                    controller: nameCtl,
                    decoration: const InputDecoration(labelText: 'Display name'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bioCtl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Bio'),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () async {
                      final newName = nameCtl.text.trim();
                      final newBio  = bioCtl.text.trim();
                      if (newName.isNotEmpty && newName != (user.displayName ?? '')) {
                        await _user!.updateDisplayName(newName);
                      }
                      await _db.collection('users').doc(user.uid).set({
                        'displayName': newName.isNotEmpty ? newName : (user.displayName ?? ''),
                        'displayNameLower': (newName.isNotEmpty ? newName : (user.displayName ?? '')).toLowerCase(),
                        'bio': newBio,
                        'photoURL': photoUrl,
                        'coverUrl': coverUrl,
                        'updatedAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));
                      if (mounted) setState(() {}); // Refresh parent after save
                      if (mounted) Navigator.pop(context, true);
                    },
                    child: const Text('Save changes'),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );

    if (saved == true) {
      await _user?.reload();
      if (mounted) setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
      }
    }
  }

  // ===== Settings sheet =====
  Future<void> _openSettings() async {
    final user = _user;
    if (user == null) return;

    final doc = await _db.collection('users').doc(user.uid).get();
    bool isPrivate = (doc.data()?['isPrivate'] ?? false) as bool;

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.dashboard_customize_outlined),
                    title: const Text('Create Page'),
                    onTap: () {
                      Navigator.pop(context);
                      // try to navigate to a page-creation route; adjust if your app uses a different route
                      try {
                        Navigator.pushNamed(context, '/page/create');
                      } catch (_) {
                        // route may not exist; show a simple message
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Create Page not implemented')));
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.group_add_outlined),
                    title: const Text('Create Group'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateGroupScreen()));
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('Private account'),
                    subtitle: const Text('Only approved followers/members can see your posts'),
                    trailing: Switch.adaptive(
                      value: isPrivate,
                      onChanged: (v) async {
                        // update immediately
                        await _db.collection('users').doc(user.uid).set({'isPrivate': v}, SetOptions(merge: true));
                        setSheetState(() => isPrivate = v);
                        if (mounted) setState(() {});
                      },
                    ),
                    onTap: null,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Sign out'),
                    onTap: () async {
                      // close the settings sheet first (it's a bottom sheet)
                      Navigator.pop(context);
                      try {
                        await FirebaseAuth.instance.signOut();
                        // AuthGuard will redirect to /sign-in; avoid calling GoRouter
                        // here to prevent double-navigation that can conflict with
                        // GoRouter's internal navigator updates.
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error signing out: $e')),
                          );
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: Center(
          child: FilledButton(
            onPressed: () {
              // use GoRouter instead of Navigator to avoid navigator instance mismatch
              GoRouter.of(context).go('/sign-in');
            },
            child: const Text('Sign in'),
          ),
        ),
      );
    }

    final userDocStream = _db.collection('users').doc(user.uid).snapshots();
    final myPostsStream = _db
        .collection('posts')
        .where('authorId', isEqualTo: user.uid)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        // Settings button (opens actions: Create Page, Create Group, Privacy toggle, Sign out)
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () => _openSettings(),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>( 
        stream: userDocStream,
        builder: (context, snap) {
          final data = Map<String, dynamic>.from(snap.data?.data() ?? {});
          final displayName = (user.displayName?.isNotEmpty == true)
              ? user.displayName!
              : (data['displayName'] ?? 'No name').toString();

          final handle = (data['username'] ?? user.email?.split('@').first ?? '').toString();
          final coverUrl = (data['coverUrl'] ?? '').toString();
          final photoURL = (user.photoURL?.isNotEmpty == true)
              ? user.photoURL!
              : (data['photoURL'] ?? '').toString();

          final postsCount     = (data['postsCount'] ?? 0) as int;
          final followersCount = (data['followersCount'] ?? 0) as int;
          final followingCount = (data['followingCount'] ?? 0) as int;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 220,
                backgroundColor: Theme.of(context).colorScheme.surface,
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      Positioned.fill(
                        child: coverUrl.isNotEmpty
                            ? Image.network(coverUrl, fit: BoxFit.cover)
                            : Container(color: Theme.of(context).colorScheme.surfaceVariant),
                      ),
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        child: Container(
                          height: 36,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.background,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: -24,
                        child: CircleAvatar(
                          radius: 44,
                          backgroundColor: Theme.of(context).colorScheme.background,
                          child: CircleAvatar(
                            radius: 40,
                            backgroundImage: (photoURL.isNotEmpty) ? NetworkImage(photoURL) : null,
                            child: (photoURL.isEmpty) ? const Icon(Icons.person, size: 40) : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ), // SliverAppBar

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 40, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        displayName,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      if (handle.isNotEmpty)
                        Text(
                          '@$handle',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                        ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _openEditProfile,
                          child: const Text('Edit profile'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _StatItem(count: postsCount, label: 'posts'),
                          _StatItem(count: followersCount, label: 'followers'),
                          _StatItem(count: followingCount, label: 'following'),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ====== Posts ======
                      Row(
                        children: [
                          Text('Posts', style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 12),

                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>( 
                        stream: myPostsStream, 
                        builder: (context, ps) {
                          if (ps.connectionState == ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 24),
                              child: LinearProgressIndicator(),
                            );
                          }

                          final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(ps.data?.docs ?? []);
                          docs.sort((a, b) {
                            final ta = (a.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
                            final tb = (b.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
                            return tb.compareTo(ta);
                          });

                          if (docs.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(child: Text('No posts yet')),
                            );
                          }

                          return ListView.builder(
                            itemCount: docs.length,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemBuilder: (_, i) {
                              final d = docs[i].data();
                              final text = (d['text'] ?? '').toString();
                              final media = d['media'];
                              String? imageUrl;
                              if (media is List && media.isNotEmpty) {
                                final first = media.first;
                                if (first is String) imageUrl = first;
                                if (first is Map && first['url'] is String) imageUrl = first['url'];
                              }

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (imageUrl != null)
                                      ClipRRect(
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                        child: Image.network(imageUrl, fit: BoxFit.cover),
                                      ),
                                    if (text.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Text(text),
                                      ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
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
    final t = Theme.of(context);
    return Column(
      children: [
        Text('$count', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        Text(label, style: t.textTheme.bodySmall),
      ],
    );
  }
}
