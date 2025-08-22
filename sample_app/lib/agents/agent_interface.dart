// Defines a unified agent interface and common data classes without modifying existing agents.
// This file introduces IAgent, IStatefulAgent, IToolingAgent and shared DTOs to be used
// by future or adapted agents. Existing agents can migrate gradually.

import 'package:sample_app/models/app_settings.dart';

/// Request for an agent inference.
class AgentRequest {
  final String input;
  final Duration? timeout;
  final Map<String, dynamic>? context; // external context variables
  final ResponseFormat? overrideFormat;
  final String? overrideJsonSchema;

  const AgentRequest(
    this.input, {
    this.timeout,
    this.context,
    this.overrideFormat,
    this.overrideJsonSchema,
  });
}

/// Normalized agent response.
class AgentResponse {
  final String text;            // final or current text
  final bool isFinal;           // finality flag (after stop sequence / policy)
  final bool mcpUsed;           // whether MCP enrichment/tools were used
  final double? uncertainty;    // parsed uncertainty 0..1 if available
  final Map<String, dynamic>? meta; // provider/tool metadata (traceId, durations, tokens, etc.)

  const AgentResponse({
    required this.text,
    required this.isFinal,
    this.mcpUsed = false,
    this.uncertainty,
    this.meta,
  });
}

/// Agent capability descriptor.
class AgentCapabilities {
  final bool stateful;            // keeps a dialog/history
  final bool streaming;           // can stream tokens/events
  final bool reasoning;           // applies uncertainty/stop-sequence policy
  final Set<String> tools;        // named tools, e.g. 'docker_exec_java'

  const AgentCapabilities({
    required this.stateful,
    required this.streaming,
    required this.reasoning,
    this.tools = const {},
  });
}

/// Streaming event emitted by an agent when using streaming mode.
class AgentEvent {
  final String type; // 'token' | 'response' | 'tool_call' | 'error' | 'debug'
  final dynamic data;
  const AgentEvent(this.type, this.data);
}

/// Unified agent interface.
abstract class IAgent {
  AgentCapabilities get capabilities;

  /// Single request-response.
  Future<AgentResponse> ask(AgentRequest req);

  /// Optional streaming API. If not supported, return null.
  Stream<AgentEvent>? start(AgentRequest req) => null;

  /// Update runtime settings (LLM provider, formats, MCP, etc.).
  void updateSettings(AppSettings settings);

  /// Cleanup resources.
  void dispose();
}

/// Mixin for stateful agents that maintain a history.
mixin IStatefulAgent on IAgent {
  void clearHistory();
  int get historyDepth;
}

/// Interface for agents exposing tool calls.
abstract class IToolingAgent implements IAgent {
  bool supportsTool(String name);
  Future<Map<String, dynamic>> callTool(
    String name,
    Map<String, dynamic> args, {
    Duration? timeout,
  });
}

/// Text utilities useful for agent implementations and tests.
class AgentTextUtils {
  /// Extracts uncertainty value (0..1) from a text in RU/EN, including percents.
  static double? extractUncertainty(String text) {
    final patterns = <RegExp>[
      RegExp(r'неопредел[её]нн?ость\s*[:=]?\s*([0-9]{1,3}(?:[\.,][0-9]{1,3})?)\s*%?', caseSensitive: false),
      RegExp(r'uncertainty\s*[:=]?\s*([0-9]{1,3}(?:[\.,][0-9]{1,3})?)\s*%?', caseSensitive: false),
      RegExp(r'([0-9]{1,3})\s*%\s*(?:неопредел|uncertainty)', caseSensitive: false),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(text);
      if (m != null) {
        var raw = m.group(1) ?? '';
        raw = raw.replaceAll(',', '.');
        final val = double.tryParse(raw);
        if (val == null) continue;
        final normalized = val > 1 ? val / 100.0 : val;
        if (normalized >= 0 && normalized <= 1) return normalized;
      }
    }
    return null;
  }

  /// Strips a stop token from the end if present; returns (cleanText, hadStop).
  static ({String text, bool hadStop}) stripStopToken(String text, String stopToken) {
    if (text.contains(stopToken)) {
      return (text: text.replaceAll(stopToken, '').trim(), hadStop: true);
    }
    return (text: text, hadStop: false);
  }
}
