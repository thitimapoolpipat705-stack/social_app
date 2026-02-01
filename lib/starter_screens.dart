import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

// ✅ import หน้าอื่น
import 'widgets/feed_card.dart';
import 'pages/other_profile_screen.dart'; // ✅ หน้าโปรไฟล์ของผู้อื่น
import 'pages/create_or_edit_post_page.dart';
// removed unused imports to avoid analyzer warnings



final _auth = FirebaseAuth.instance;
final _db = FirebaseFirestore.instance;

// -------------------- Sign In --------------------
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final email = TextEditingController();
  final pass = TextEditingController();
  final _auth = FirebaseAuth.instance;

  bool loading = false;
  bool showPassword = false;
  String? error;

  @override
  void dispose() {
    email.dispose();
    pass.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() { loading = true; error = null; });
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.text.trim(),
        password: pass.text,
      );
      if (!mounted) return;
      // use GoRouter to navigate to home to avoid mixing Navigator instances
      GoRouter.of(context).go('/home');
    } on FirebaseAuthException catch (e) {
      setState(() => error = e.message ?? e.code);
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _resetPassword() async {
    String targetEmail = email.text.trim();
    if (targetEmail.isEmpty) {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reset password'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Your email',
              hintText: 'you@example.com',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
          ],
        ),
      );
      if (ok != true) return;
      targetEmail = controller.text.trim();
    }

    try {
      final actionCodeSettings = ActionCodeSettings(
        url: 'https://social-app-myproject.web.app/reset',
        handleCodeInApp: true,
        androidPackageName: 'com.example.social_app',
        androidInstallApp: true,
        androidMinimumVersion: '21',
      );

      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: targetEmail,
        actionCodeSettings: actionCodeSettings,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset link sent. Check your email.')),
      );
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? e.code)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = !loading && email.text.trim().isNotEmpty && pass.text.isNotEmpty;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              cs.primary.withOpacity(.08),
              cs.primaryContainer.withOpacity(.04),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              elevation: 14,
              shadowColor: cs.primary.withOpacity(.25),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                        const SizedBox(height: 16),
                      Text('MindSocial',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text('Sign in to continue',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 20),

                      // Error
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: (error == null)
                            ? const SizedBox.shrink()
                            : Container(
                                key: const ValueKey('err'),
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 4),
                                decoration: BoxDecoration(
                                  color: cs.errorContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.error_outline, color: cs.error),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(error!, style: TextStyle(color: cs.onErrorContainer)),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      const SizedBox(height: 6),

                      // Email
                      TextField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon: const Icon(Icons.mail_outline),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          filled: true,
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),

                      // Password
                      TextField(
                        controller: pass,
                        obscureText: !showPassword,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(showPassword ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => showPassword = !showPassword),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          filled: true,
                        ),
                        onSubmitted: (_) => canSubmit ? _signIn() : null,
                      ),

                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: loading ? null : _resetPassword,
                          child: const Text('Forgot password?'),
                        ),
                      ),

                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          onPressed: canSubmit ? _signIn : null,
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: loading
                              ? const SizedBox(
                                  width: 22, height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.4),
                                )
                              : const Text('Sign in'),
                        ),
                      ),

                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: Divider(color: cs.outlineVariant)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text('or', style: TextStyle(color: cs.onSurfaceVariant)),
                          ),
                          Expanded(child: Divider(color: cs.outlineVariant)),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // ปุ่มไปสมัครสมาชิก
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('New here?', style: TextStyle(color: cs.onSurfaceVariant)),
                          const SizedBox(width: 4),
                          TextButton(
                            onPressed: loading
                                ? null
                                : () {
                                    // use GoRouter for top-level route navigation
                                    GoRouter.of(context).push('/sign-up');
                                  },
                            child: const Text('Create account'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


// -------------------- Sign Up --------------------
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final email = TextEditingController();
  final pass = TextEditingController();
  final displayName = TextEditingController();
  bool loading = false;
  String? error;

  Future<void> _createUserDoc(User u) async {
    await _db.collection('users').doc(u.uid).set({
      'displayName': displayName.text.trim().isEmpty
          ? 'New User'
          : displayName.text.trim(),
      'photoURL': null,
      'isPrivate': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  void dispose() {
    email.dispose();
    pass.dispose();
    displayName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              cs.primaryContainer.withOpacity(.06),
              cs.secondaryContainer.withOpacity(.04),
            ],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              elevation: 14,
              shadowColor: cs.primary.withOpacity(.25),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // ไอคอน/หัวเรื่อง
                      Container(
                        width: 64, height: 64,
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(Icons.star_rounded, size: 34, color: cs.primary),
                      ),
                      const SizedBox(height: 16),
                      Text('Create your account',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text('Join the community in seconds',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 20),

                      // Error
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: (error == null)
                            ? const SizedBox.shrink()
                            : Container(
                                key: const ValueKey('err2'),
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 4),
                                decoration: BoxDecoration(
                                  color: cs.errorContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.error_outline, color: cs.error),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(error!, style: TextStyle(color: cs.onErrorContainer)),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      const SizedBox(height: 6),

                      // Display name
                      TextField(
                        controller: displayName,
                        decoration: InputDecoration(
                          labelText: 'Display name',
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          filled: true,
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),

                      // Email
                      TextField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon: const Icon(Icons.mail_outline),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          filled: true,
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),

                      // Password
                      TextField(
                        controller: pass,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          filled: true,
                        ),
                      ),

                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          onPressed: loading
                              ? null
                              : () async {
                                  setState(() { loading = true; error = null; });
                                  try {
                                    final cred = await _auth.createUserWithEmailAndPassword(
                                      email: email.text.trim(),
                                      password: pass.text,
                                    );

                                    if (!mounted) return;
                                    // Use GoRouter to navigate to home (replace stack)
                                    GoRouter.of(context).go('/home');

                                    unawaited(_createUserDoc(cred.user!).catchError((e) {
                                      debugPrint('createUserDoc failed: $e');
                                    }));
                                  } on FirebaseAuthException catch (e) {
                                    setState(() => error = e.message ?? e.code);
                                  } finally {
                                    if (mounted) setState(() => loading = false);
                                  }
                                },
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: loading
                              ? const SizedBox(
                                  width: 22, height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.4),
                                )
                              : const Text('Create account'),
                        ),
                      ),

                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: Divider(color: cs.outlineVariant)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text('or', style: TextStyle(color: cs.onSurfaceVariant)),
                          ),
                          Expanded(child: Divider(color: cs.outlineVariant)),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // ไปหน้า Sign in
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Already have an account?', style: TextStyle(color: cs.onSurfaceVariant)),
                          const SizedBox(width: 4),
                          TextButton(
                            onPressed: loading
                                ? null
                                : () {
                                    // return to sign-in using GoRouter
                                    GoRouter.of(context).go('/sign-in');
                                  },
                            child: const Text('Sign in'),
                          ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------- Feed Screen --------------------
class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final postsQuery = FirebaseFirestore.instance
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(50);

    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Feed')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>( // type specific
  stream: postsQuery.snapshots(),
  builder: (context, snap) {
    if (snap.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snap.hasError) {
      return Center(child: Text('Error: ${snap.error}'));
    }
    if (!snap.hasData || snap.data!.docs.isEmpty) {
      return const Center(child: Text('No posts yet.'));
    }

    final docs = snap.data!.docs;

    return ListView.builder(
      itemCount: docs.length,
      itemBuilder: (_, i) {
        final doc = docs[i];
        final Map<String, dynamic> d = doc.data(); // Ensure type safety
        final postId = doc.id;

        final authorId = (d['authorId'] as String?) ?? '';
        final authorName = (d['authorName'] as String?) ?? authorId;
        final authorAvatarUrl = d['authorAvatarUrl'] as String?;
        final text = (d['text'] as String?) ?? '';
        final comments = (d['commentsCount'] as int?) ?? 0;

        // Image URL from 'media' — handle case where 'media' is a list or string
  // imageUrl not used here (kept _firstImageUrl helper below); remove unused local

        final myRef = uid == null
            ? null
            : FirebaseFirestore.instance
                .collection('posts')
                .doc(postId)
                .collection('reactions')
                .doc(uid);

        final allRef = FirebaseFirestore.instance
            .collection('posts')
            .doc(postId)
            .collection('reactions');

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>( 
          stream: myRef?.snapshots() ?? const Stream.empty(),
          builder: (context, mySnap) {
            final likedByMe = mySnap.data?.exists == true;

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>( 
              stream: allRef.snapshots(),
              builder: (context, allSnap) {
                final likesCount = allSnap.data?.docs.length ?? 0;

                return FeedCard(
                  postId: postId,
                  authorId: authorId,
                  authorName: authorName,
                  authorAvatarUrl: authorAvatarUrl,
                  // Handle media: If it's a List, map it. If it's a String, wrap it in a list.
                  media: (d['media'] is List)
                      ? (d['media'] as List)
                          .map((e) => Map<String, dynamic>.from(e))
                          .toList()
                      : (d['media'] is String)
                          ? [{'url': d['media']}] // Wrap String as URL
                          : const <Map<String, dynamic>>[], 
                  text: text,
                  commentsCount: comments,
                  likesCount: likesCount,
                  likedByMe: likedByMe,
                  reactionType: mySnap.data?.data()?['type'] as String?,
                  isOwn: uid == authorId,
                  // action: เปิดโปรไฟล์ผู้โพสต์
                  onAuthorTap: () {
                    if (authorId == uid) return; // ไม่เปิดโปรไฟล์ตัวเอง
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            OtherProfileScreen(otherUid: authorId),
                      ),
                    );
                  },
                  // action: ไลค์/ยกเลิกไลค์
                  onToggleLike: () async {
                    if (uid == null) return;
                    if (likedByMe) {
                      await myRef!.delete();
                    } else {
                      await myRef!.set({
                        'type': 'like',
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                    }
                  },
                  onReact: (type) async {
                    if (uid == null || myRef == null) return;
                    final current = mySnap.data?.data()?['type'] as String?;
                    if (current == type) {
                      // toggle off
                      await myRef.delete();
                    } else {
                      await myRef.set({
                        'type': type,
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                    }
                  },
                  // action: คอมเมนต์
                  onComment: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Comments: coming soon')),
                    );
                  },
                  // action: แชร์/รีพอร์ต
                  onShare: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Share: coming soon')),
                    );
                  },
                  onReport: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Report: coming soon')),
                    );
                  },
                  // action: แก้ไขโพสต์
                  onEdit: () async {
                    final ok = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CreateOrEditPostPage(postId: postId),
                      ),
                    );
                    if (ok == true && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Post updated')),
                      );
                    }
                  },
                  // action: ลบโพสต์
                  onDelete: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Delete post'),
                        content:
                            const Text('Are you sure you want to delete this post?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await FirebaseFirestore.instance
                          .collection('posts')
                          .doc(postId)
                          .delete();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Deleted')));
                      }
                    }
                  },
                );
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

// (helper removed — use shared helper in pages/feed_screen.dart)

