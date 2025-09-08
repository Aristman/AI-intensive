// Defines a unified agent interface and common data classes without modifying existing agents.
// ignore_for_file: constant_identifier_names
// This file introduces IAgent, IStatefulAgent, IToolingAgent and shared DTOs to be used
// by future or adapted agents. Existing agents can migrate gradually.

import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/models/user_profile.dart';

/// Request for an agent inference.
class AgentRequest {
  final String input;
  final Duration? timeout;
  final Map<String, dynamic>? context; // external context variables
  final ResponseFormat? overrideFormat;
  final String? overrideJsonSchema;
  final String? authToken; // optional auth token for per-request authentication

  const AgentRequest(
    this.input, {
    this.timeout,
    this.context,
    this.overrideFormat,
    this.overrideJsonSchema,
    this.authToken,
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
  final String? systemPrompt;     // base system/system-like prompt used by the agent (if any)
  final List<String> responseRules; // concise rules/guidelines for formatting the answer

  const AgentCapabilities({
    required this.stateful,
    required this.streaming,
    required this.reasoning,
    this.tools = const {},
    this.systemPrompt,
    this.responseRules = const [],
  });
}

/// Streaming event emitted by an agent when using streaming mode.
enum AgentStage {
  pipeline_start,
  intent_classified,
  code_generation_started,
  code_generated,
  ask_create_tests,
  test_generation_started,
  test_generated,
  docker_exec_started,
  docker_exec_progress,
  docker_exec_result,
  analysis_started,
  analysis_result,
  refine_tests_started,
  refine_tests_result,
  pipeline_complete,
  pipeline_error,
}

enum AgentSeverity { info, warning, error, debug }

/// Streaming event emitted by an agent when using streaming mode.
class AgentEvent {
  final String id;           // unique event id (e.g., uuid)
  final String runId;        // correlation id of a pipeline run
  final AgentStage stage;    // pipeline stage
  final AgentSeverity severity; // default info
  final String message;      // short human-readable message
  final double? progress;    // 0.0..1.0 overall pipeline progress
  final int? stepIndex;      // current step index (1-based)
  final int? totalSteps;     // total number of steps in pipeline
  final DateTime timestamp;  // event time
  final Map<String, dynamic>? meta; // structured payload per stage

  AgentEvent({
    required this.id,
    required this.runId,
    required this.stage,
    this.severity = AgentSeverity.info,
    required this.message,
    this.progress,
    this.stepIndex,
    this.totalSteps,
    DateTime? timestamp,
    this.meta,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Legacy compatibility constructor (optional). Not used yet, but handy for gradual migration.
  factory AgentEvent.legacy(String type, dynamic data) => AgentEvent(
        id: 'legacy',
        runId: 'legacy',
        stage: AgentStage.pipeline_error,
        severity: AgentSeverity.warning,
        message: 'Legacy event: $type',
        meta: {'data': data},
      );
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

  // ===== Authorization & Limits (backward-compatible defaults) =====
  /// Current authenticated role. Defaults to 'guest'.
  String get role => 'guest';

  /// True if authenticated (by default, no-op auth means true).
  bool get isAuthenticated => true;

  /// Get current limits. Null or unlimited by default.
  AgentLimits? get limits => null;

  /// Authenticate using an optional token. Default always succeeds.
  /// Implementations may override and persist auth state.
  Future<bool> authenticate(String? token) async => true;

  /// Authorization check for an action with optional requiredRole.
  /// Default allows everything for backward compatibility.
  bool authorize(String action, {String? requiredRole}) => true;
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

// ===== Auth / Roles / Limits utilities =====

/// Simple role helpers. Order: guest < user < admin.
class AgentRoles {
  static const String guest = 'guest';
  static const String user = 'user';
  static const String admin = 'admin';

  static int rank(String? role) {
    switch (role) {
      case admin:
        return 3;
      case user:
        return 2;
      case guest:
      default:
        return 1;
    }
  }

  static bool allows(String actual, String? required) {
    if (required == null || required.isEmpty) return true;
    return rank(actual) >= rank(required);
  }
}

/// Request/usage limits. By default unlimited.
class AgentLimits {
  final int? requestsPerHour;

  const AgentLimits({this.requestsPerHour});

  const AgentLimits.unlimited() : requestsPerHour = null;

  bool get isUnlimited => requestsPerHour == null || requestsPerHour! <= 0;
}

/// Minimal sliding window rate limiter (minute window).
class SimpleRateLimiter {
  final int? perHour;
  final List<DateTime> _hits = <DateTime>[];

  SimpleRateLimiter(this.perHour);

  bool allow() {
    if (perHour == null || perHour! <= 0) return true; // unlimited
    final now = DateTime.now();
    final windowStart = now.subtract(const Duration(hours: 1));
    // purge
    _hits.removeWhere((t) => t.isBefore(windowStart));
    if (_hits.length >= perHour!) return false;
    _hits.add(now);
    return true;
  }
}

/// Drop-in mixin to add basic auth/role/limits behavior to agents.
/// Implements IAgent's auth-related members so that classes can `with` this
/// mixin and satisfy the interface without needing a specific superclass.
mixin AuthPolicyMixin implements IAgent {
  
  String _role = AgentRoles.guest;
  AgentLimits _limits = const AgentLimits.unlimited();
  SimpleRateLimiter _limiter = SimpleRateLimiter(null);
  bool _authed = false; // backward-compat: treat unauth as guest until authenticate called

  @override
  String get role => _role;

  @override
  bool get isAuthenticated => _authed;

  @override
  AgentLimits get limits => _limits;

  /// Configure policy (e.g., from app settings or server side)
  void updateAuthPolicy({String? role, AgentLimits? limits}) {
    if (role != null) _role = role;
    if (limits != null) {
      _limits = limits;
      _limiter = SimpleRateLimiter(limits.requestsPerHour);
    }
  }

  @override
  Future<bool> authenticate(String? token) async {
    // Default token acceptance: if token provided, mark as authenticated user; otherwise stay guest but authed.
    _authed = true;
    // Simple heuristic role assignment: if token present, elevate to 'user' by default.
    if (token != null && token.isNotEmpty && AgentRoles.rank(_role) < AgentRoles.rank(AgentRoles.user)) {
      _role = AgentRoles.user;
    }
    return true;
  }

  @override
  bool authorize(String action, {String? requiredRole}) {
    // Default policy: allow if role satisfies requiredRole (if provided).
    return AgentRoles.allows(_role, requiredRole);
  }

  /// Ensures authentication, role authorization and rate limits.
  /// Throws StateError on violation.
  Future<void> ensureAuthorized(AgentRequest req, {required String action, String? requiredRole}) async {
    if (!isAuthenticated) {
      await authenticate(req.authToken);
    }
    // Опционально повышаем роль из профиля пользователя, если передан в контексте
    final ctx = req.context;
    final p = ctx != null ? ctx['user_profile'] : null;
    final pr = (p is Map && p['role'] is String) ? (p['role'] as String) : null;
    if (pr != null && pr.isNotEmpty) {
      if (AgentRoles.rank(pr) > AgentRoles.rank(_role)) {
        _role = pr;
      }
    }
    if (!authorize(action, requiredRole: requiredRole)) {
      throw StateError('Access denied: role "$_role" is insufficient for action "$action" (required: $requiredRole).');
    }
    if (!_limiter.allow()) {
      throw StateError('Rate limit exceeded for action "$action" (limit: ${_limits.requestsPerHour}/hour).');
    }
  }
}

// ===== User Profile awareness (optional) =====

/// Optional interface for agents that can utilize user profile data.
/// Implementations are free to ignore it; existing agents remain compatible.
abstract class IUserProfileAware {
  /// Returns current user profile snapshot used by the agent (if any).
  UserProfile? get userProfile;

  /// Allows updating user profile used by the agent (no-op by default).
  void setUserProfile(UserProfile? profile);
}
