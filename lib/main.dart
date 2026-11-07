import 'package:flutter/material.dart';
import 'store.dart';
import 'theme.dart';
import 'screens/ledgers_page.dart';
import 'screens/people_page.dart';
import 'screens/me_page.dart';

final store = Store();

void main() {
  runApp(const LiqianApp());
  store.load();
}

class LiqianApp extends StatelessWidget {
  const LiqianApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '礼钱账本',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _idx = 0;

  static const _tabs = [
    (icon: Icons.book_outlined, selectedIcon: Icons.book, label: '礼簿'),
    (icon: Icons.people_outline, selectedIcon: Icons.people, label: '人情'),
    (icon: Icons.person_outline, selectedIcon: Icons.person, label: '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [const LedgersPage(), const PeoplePage(), const MePage()];
    // 键盘弹起时隐藏悬浮栏（同 iOS 行为，也给人情页搜索胶囊让位）
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: pages[_idx]),
          if (!keyboardOpen)
            Positioned(
              left: 20,
              right: 20,
              bottom: 14,
              child: GlassCapsule(
                radius: 30,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    for (var i = 0; i < _tabs.length; i++)
                      Expanded(
                        child: _tabItem(
                          icon:
                              _idx == i ? _tabs[i].selectedIcon : _tabs[i].icon,
                          label: _tabs[i].label,
                          selected: _idx == i,
                          onTap: () => setState(() => _idx = i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tabItem({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final color = selected ? kCinnabar : kStone;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: selected ? kCinnabar.withOpacity(0.09) : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 23, color: color),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 11.5, color: color, height: 1.1)),
          ],
        ),
      ),
    );
  }
}
