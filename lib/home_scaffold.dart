// lib/home_scaffold.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'pages/feed_screen.dart';
import 'screens/search/search_pages_groups_screen.dart' as search_pages;
import 'chat_screens.dart';              // ConversationsScreen
import 'pages/profile_screen.dart';
import 'pages/create_post_page.dart';    // ⬅️ เราจะใช้หน้าใหม่ที่อยู่ข้อ 2

class HomeScaffold extends StatefulWidget {
  const HomeScaffold({super.key});
  @override
  State<HomeScaffold> createState() => _HomeScaffoldState();
}

class _HomeScaffoldState extends State<HomeScaffold> {
  int _index = 0;

  final _pages = const [
    FeedScreen(),               // 0
    _SearchEntry(),             // 1
    SizedBox.shrink(),          // 2 (ช่องว่าง FAB)
    ConversationsScreen(),      // 3 (แชท)
    ProfileScreen(),            // 4
  ];

  void _onNavTap(int i) {
    if (i == 2) return; // ช่องของ FAB
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      // Keep the FAB and bottom bar visually anchored when the keyboard opens.
      // This prevents the FAB from moving up with the keyboard. If body
      // scrolling is required while typing, ensure individual pages use
      // scrollables (ListView/SingleChildScrollView) so content isn't hidden.
      resizeToAvoidBottomInset: false,
      body: IndexedStack(index: _index, children: _pages),

      // ===== FAB โพสต์ =====
      floatingActionButton: SizedBox(
        width: 64,
        height: 64,
        child: FloatingActionButton(
          heroTag: 'fab-post',
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          onPressed: () async {
            if (FirebaseAuth.instance.currentUser == null) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อน')),
              );
              return;
            }

            // ไปหน้า “สร้างโพสต์”
            final ok = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => const CreatePostPage()),
            );

            if (ok == true && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('โพสต์แล้ว')),
              );
            }
          },
          child: const Icon(Icons.add, size: 28),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

      // ===== แถบล่าง =====
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BottomAppBar(
              elevation: 10,
              color: cs.surface,
              shadowColor: cs.primary.withOpacity(.15),
              shape: const CircularNotchedRectangle(),
              notchMargin: 8,
              height: 72,
              child: Row(
                children: [
                  Expanded(
                    child: _BarItem(
                      icon: Icons.home_outlined,
                      activeIcon: Icons.home,
                      label: 'Home',
                      selected: _index == 0,
                      onTap: () => _onNavTap(0),
                    ),
                  ),
                  Expanded(
                    child: _BarItem(
                      icon: Icons.search_outlined,
                      activeIcon: Icons.search,
                      label: 'Search',
                      selected: _index == 1,
                      onTap: () => _onNavTap(1),
                    ),
                  ),

                  const SizedBox(width: 40), // เว้นให้ FAB

                  Expanded(
                    child: _BarItem(
                      icon: Icons.chat_bubble_outline,
                      activeIcon: Icons.chat_bubble,
                      label: 'Chat',
                      selected: _index == 3,
                      onTap: () => _onNavTap(3),
                    ),
                  ),
                  Expanded(
                    child: _BarItem(
                      icon: Icons.person_outline,
                      activeIcon: Icons.person,
                      label: 'Profile',
                      selected: _index == 4,
                      onTap: () => _onNavTap(4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return InkResponse(
      onTap: onTap,
      radius: 32,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Center(
              child: Icon(selected ? activeIcon : icon, color: color, size: 26),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: color, height: 1.1),
          ),
        ],
      ),
    );
  }
}

class _SearchEntry extends StatelessWidget {
  const _SearchEntry();
  @override
  Widget build(BuildContext context) =>
      const search_pages.SearchPagesGroupsScreen();
}
