import 'package:flutter/material.dart';
import 'package:sample_app/screens/chat_screen.dart';
import 'package:sample_app/screens/multi_agents_screen.dart';
import 'package:sample_app/screens/code_ops_screen.dart';
import 'package:sample_app/screens/github_agent_screen.dart';
import 'package:sample_app/screens/auto_fix_screen.dart';
import 'package:sample_app/screens/reasoning_agent_screen.dart';
import 'package:sample_app/screens/workspace_screen.dart';

enum Screen {
  chat(Icon(Icons.chat_bubble_outline), Icon(Icons.chat_bubble), 'Чат'),
  thinking(Icon(Icons.psychology_outlined), Icon(Icons.psychology), 'Рассуждения'),
  multiAgent(Icon(Icons.groups_2_outlined), Icon(Icons.groups_2), 'Два агента'),
  codeOps(Icon(Icons.developer_board_outlined), Icon(Icons.developer_board), 'CodeOps'),
  autoFix(Icon(Icons.build_outlined), Icon(Icons.build), 'AutoFix'),
  github(Icon(Icons.integration_instructions), Icon(Icons.integration_instructions), 'GitHub'),
  multiStep(Icon(Icons.route_outlined), Icon(Icons.route), 'Многоэтапный'),
  workspace(Icon(Icons.folder_open_outlined), Icon(Icons.folder), 'Рабочее окно');

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
  Screen.autoFix: (v) => AutoFixScreen(key: ValueKey('autofix-$v')),
  Screen.github: (v) => GitHubAgentScreen(key: ValueKey('github-$v')),
  Screen.multiStep: (v) => ReasoningAgentScreen(key: ValueKey('multiStep-$v')),
  Screen.workspace: (v) => WorkspaceScreen(key: ValueKey('workspace-$v')),
};