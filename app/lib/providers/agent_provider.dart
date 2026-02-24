import 'dart:convert';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// --- Data Models -------------------------------------------------------------

class LogEntry {
  final String message;
  final String source; // 'info', 'terminal', 'gemini', 'system'
  final String type;   // 'info', 'error', 'success'
  final String timestamp;

  LogEntry({
    required this.message, 
    required this.source, 
    required this.type, 
    required this.timestamp,
  });

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      message: json['message'] ?? '',
      source: json['source'] ?? 'info',
      type: json['type'] ?? 'info',
      timestamp: json['timestamp'] ?? '',
    );
  }
}

class ModelQuota {
  final String name;
  final double percent;
  final int resetSeconds;

  ModelQuota({
    required this.name, 
    required this.percent, 
    required this.resetSeconds,
  });
}

class AgentState {
  final String url;
  final String token;
  final bool isConnected;
  final bool isExecuting;
  final String? activeRepo; 
  final String activeChatId;
  final String activeModel;
  final String? deviceName;
  final Map<String, dynamic>? activeBuild;

  AgentState({
    required this.url,
    required this.token,
    this.isConnected = false,
    this.isExecuting = false,
    this.activeRepo,
    this.activeChatId = 'main',
    this.activeModel = 'gemini-1.5-flash',
    this.deviceName,
    this.activeBuild,
  });

  AgentState copyWith({
    String? url,
    String? token,
    bool? isConnected,
    bool? isExecuting,
    String? activeRepo,
    String? activeChatId,
    String? activeModel,
    String? deviceName,
    Map<String, dynamic>? activeBuild,
    bool clearBuild = false,
  }) {
    return AgentState(
      url: url ?? this.url,
      token: token ?? this.token,
      isConnected: isConnected ?? this.isConnected,
      isExecuting: isExecuting ?? this.isExecuting,
      activeRepo: activeRepo ?? this.activeRepo,
      activeChatId: activeChatId ?? this.activeChatId,
      activeModel: activeModel ?? this.activeModel,
      deviceName: deviceName ?? this.deviceName,
      activeBuild: clearBuild ? null : (activeBuild ?? this.activeBuild),
    );
  }
}

// --- Provider Notifiers ------------------------------------------------------

class LogsNotifier extends StateNotifier<List<LogEntry>> {
  LogsNotifier() : super([]);
  void clear() => state = [];
  void startListening() {
    // Logic for websocket or long polling
  }
  void fetchHistory({bool append = false}) {
    // API logic for history
  }
}

class QuotaNotifier extends StateNotifier<List<ModelQuota>> {
  QuotaNotifier() : super([]);
  void fetchQuotas() {
    // API logic for quotas
  }
}

class PushNotificationService {
  void initialize(dynamic context) {
    // Push init logic
  }
}

// --- Global Providers --------------------------------------------------------

final agentProvider = StateNotifierProvider<AgentNotifier, AgentState>((ref) => AgentNotifier());
final logsProvider = StateNotifierProvider<LogsNotifier, List<LogEntry>>((ref) => LogsNotifier());
final quotaProvider = StateNotifierProvider<QuotaNotifier, List<ModelQuota>>((ref) => QuotaNotifier());
final pushNotificationProvider = Provider((ref) => PushNotificationService());

// --- Main Controller ---------------------------------------------------------

class AgentNotifier extends StateNotifier<AgentState> {
  Timer? _pollingTimer;

  AgentNotifier() : super(AgentState(url: '', token: '')) {
    _loadConfig();
    _startPolling();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
       if (state.url.isNotEmpty && state.isConnected) {
          checkConnection();
       }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    state = state.copyWith(
      url: prefs.getString('agent_url') ?? 'http://100.x.x.x:8742', 
      token: prefs.getString('agent_token') ?? '', 
      activeRepo: prefs.getString('active_repo'), 
      activeChatId: prefs.getString('active_chat_id') ?? 'main',
      activeModel: prefs.getString('active_model') ?? 'gemini-1.5-flash',
    );
    checkConnection();
  }

  Future<void> updateConfig(String url, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('agent_url', url);
    await prefs.setString('agent_token', token);
    state = state.copyWith(url: url, token: token);
    checkConnection();
  }

  Future<void> setActiveRepo(String? repo) async {
    final prefs = await SharedPreferences.getInstance();
    if (repo == null) await prefs.remove('active_repo');
    else await prefs.setString('active_repo', repo);
    state = state.copyWith(activeRepo: repo);
  }

  Future<void> setActiveModel(String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_model', modelId);
    state = state.copyWith(activeModel: modelId);
  }

  Future<void> setActiveChat(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_chat_id', chatId);
    state = state.copyWith(activeChatId: chatId);
  }

  Future<bool> checkConnection() async {
    if (state.url.isEmpty) return false;
    try {
      final repoQuery = state.activeRepo != null ? '?context_repo=${state.activeRepo}' : '';
      final resp = await http.get(Uri.parse('${state.url}/health$repoQuery')).timeout(const Duration(seconds: 3));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        state = state.copyWith(
          isConnected: true, 
          deviceName: data['device'],
          activeBuild: data['active_build'],
          clearBuild: data['active_build'] == null,
        );
        return true;
      }
      state = state.copyWith(isConnected: false);
      return false;
    } catch (_) {
      state = state.copyWith(isConnected: false);
      return false;
    }
  }

  Future<void> executeCommand(String command) async {
    if (state.url.isEmpty || state.token.isEmpty) return;
    state = state.copyWith(isExecuting: true);
    try {
      await http.post(
        Uri.parse('${state.url}/command'),
        headers: {'Content-Type': 'application/json', 'X-API-Token': state.token},
        body: jsonEncode({
          'command': command,
          'async_run': false,
          'context_repo': state.activeRepo,
          'context_chat_id': state.activeChatId,
        }),
      );
    } finally {
      state = state.copyWith(isExecuting: false);
    }
  }

  Future<void> askGemini(String message) async {
    if (state.url.isEmpty || state.token.isEmpty) return;
    state = state.copyWith(isExecuting: true);
    try {
      await http.post(
        Uri.parse('${state.url}/chat'),
        headers: {'Content-Type': 'application/json', 'X-API-Token': state.token},
        body: jsonEncode({
          'message': message,
          'context_repo': state.activeRepo,
          'context_chat_id': state.activeChatId,
          'model_id': state.activeModel,
        }),
      );
    } finally {
      state = state.copyWith(isExecuting: false);
    }
  }

  Future<void> uploadAsset(String filePath) async {
    if (state.url.isEmpty || state.token.isEmpty) return;
    state = state.copyWith(isExecuting: true);
    try {
      final req = http.MultipartRequest('POST', Uri.parse('${state.url}/upload'));
      req.headers['X-API-Token'] = state.token;
      if (state.activeRepo != null) req.headers['X-Context-Repo'] = state.activeRepo!;
      req.files.add(await http.MultipartFile.fromPath('file', filePath));
      await req.send();
    } finally {
      state = state.copyWith(isExecuting: false);
    }
  }

  Future<void> executeIntent(String intent, {Map<String, dynamic>? params}) async {
    if (state.url.isEmpty || state.token.isEmpty) return;
    state = state.copyWith(isExecuting: true);
    try {
      await http.post(
        Uri.parse('${state.url}/intent'),
        headers: {'Content-Type': 'application/json', 'X-API-Token': state.token},
        body: jsonEncode({
          'intent': intent,
          'params': params ?? {},
          'context_repo': state.activeRepo,
          'context_chat_id': state.activeChatId,
        }),
      );
    } finally {
      state = state.copyWith(isExecuting: false);
    }
  }

  Future<List<dynamic>> fetchRepos() async {
    if (state.url.isEmpty || state.token.isEmpty) return [];
    try {
      final resp = await http.get(Uri.parse('${state.url}/repos'), headers: {'X-API-Token': state.token});
      if (resp.statusCode == 200) return jsonDecode(resp.body);
    } catch (_) {}
    return [];
  }

  Future<void> respondToApproval(String approvalId, bool accept) async {
    if (state.url.isEmpty || state.token.isEmpty) return;
    try {
      await http.post(Uri.parse('${state.url}/approve/$approvalId?accept=$accept'), headers: {'X-API-Token': state.token});
    } catch (_) {}
  }
}
