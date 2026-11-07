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
  @override
  Widget build(BuildContext context) {
    final pages = [const LedgersPage(), const PeoplePage(), const MePage()];
    return Scaffold(
      body: pages[_idx],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.book_outlined), selectedIcon: Icon(Icons.book), label: '礼簿'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: '人情'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: '我的'),
        ],
      ),
    );
  }
}
