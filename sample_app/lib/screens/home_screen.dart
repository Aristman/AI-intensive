import 'package:flutter/material.dart';
import 'package:sample_app/screens/chat_screen.dart';
import 'package:sample_app/screens/multi_agents_screen.dart';
import 'package:sample_app/screens/code_ops_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const ChatScreen(title: 'Чат'),
      const ChatScreen(title: 'Рассуждающая модель', reasoningOverride: true),
      const MultiAgentsScreen(),
      const CodeOpsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Чат'),
          NavigationDestination(icon: Icon(Icons.psychology_outlined), selectedIcon: Icon(Icons.psychology), label: 'Рассуждения'),
          NavigationDestination(icon: Icon(Icons.groups_2_outlined), selectedIcon: Icon(Icons.groups_2), label: 'Два агента'),
          NavigationDestination(icon: Icon(Icons.developer_board_outlined), selectedIcon: Icon(Icons.developer_board), label: 'CodeOps'),
        ],
      ),
    );
  }
}
