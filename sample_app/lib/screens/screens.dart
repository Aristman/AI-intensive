import 'package:flutter/material.dart';
import 'package:sample_app/screens/chat_screen.dart';
import 'package:sample_app/screens/multi_agents_screen.dart';
import 'package:sample_app/screens/code_ops_screen.dart';
import 'package:sample_app/screens/github_agent_screen.dart';

enum Screen {
  chat(Icon(Icons.chat_bubble_outline), Icon(Icons.chat_bubble), 'Чат'),
  thinking(Icon(Icons.psychology_outlined), Icon(Icons.psychology), 'Рассуждения'),
  multiAgent(Icon(Icons.groups_2_outlined), Icon(Icons.groups_2), 'Два агента'),
  codeOps(Icon(Icons.developer_board_outlined), Icon(Icons.developer_board), 'CodeOps'),
  github(Icon(Icons.integration_instructions), Icon(Icons.integration_instructions), 'GitHub');

  final Icon icon;
  final Icon selectedIcon;
  final String label;

  const Screen(this.icon, this.selectedIcon, this.label);
}

typedef ScreenFactory = Widget Function(int version);

/// Single source of truth for screen widgets by enum.
final Map<Screen, ScreenFactory> screenFactories = <Screen, ScreenFactory>{
  Screen.chat: (v) => ChatScreen(key: ValueKey('chat-$v'), title: Screen.chat.label),
  Screen.thinking: (v) => ChatScreen(key: ValueKey('reasoning-$v'), title: Screen.thinking.label, reasoningOverride: true),
  Screen.multiAgent: (v) => MultiAgentsScreen(key: ValueKey('multi-$v')),
  Screen.codeOps: (v) => CodeOpsScreen(key: ValueKey('codeops-$v')),
  Screen.github: (v) => GitHubAgentScreen(key: ValueKey('github-$v')),
};