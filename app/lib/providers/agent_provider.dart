import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AgentState {
  final String url;
  final String token;
  final bool isConnected;
  final bool isExecuting;

  AgentState({
    required this.url,
    required this.token,
    this.isConnected = false,
    this.isExecuting = false,
  });

  AgentState copyWith({
    String? url,
    String? token,
    bool? isConnected,
    bool? isExecuting,
  }) {
    return AgentState(
      url: url ?? this.url,
      token: token ?? this.token,
      isConnected: isConnected ?? this.isConnected,
      isExecuting: isExecuting ?? this.isExecuting,
    );
  }
}

final agentProvider = StateNotifierProvider<AgentNotifier, AgentState>((ref) {
  return AgentNotifier();
});

class AgentNotifier extends StateNotifier<AgentState> {
  AgentNotifier() : super(AgentState(url: '', token: '')) {
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('agent_url') ?? 'http://100.x.x.x:8742';
    final token = prefs.getString('agent_token') ?? '';
    state = state.copyWith(url: url, token: token);
    checkConnection();
  }

  Future<void> updateConfig(String url, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('agent_url', url);
    await prefs.setString('agent_token', token);
    state = state.copyWith(url: url, token: token);
    checkConnection();
  }

  Future<bool> checkConnection() async {
    if (state.url.isEmpty) return false;
    try {
      final response = await http.get(Uri.parse('${state.url}/health')).timeout(const Duration(seconds: 3));
      final isConnected = response.statusCode == 200;
      state = state.copyWith(isConnected: isConnected);
      return isConnected;
    } catch (_) {
      state = state.copyWith(isConnected: false);
      return false;
    }
  }

  Future<void> executeCommand(String command) async {
    if (state.url.isEmpty || state.token.isEmpty) return;
    
    state = state.copyWith(isExecuting: true);
    
    try {
      final response = await http.post(
        Uri.parse('${state.url}/command'),
        headers: {
          'Content-Type': 'application/json',
          'X-API-Token': state.token,
        },
        body: jsonEncode({
          'command': command,
          'async_run': false,
        }),
      );
      // Results are streamed via LogsProvider, so we just clear execution status
      state = state.copyWith(isExecuting: false);
    } catch (e) {
      state = state.copyWith(isExecuting: false);
    }
  }

  Future<void> executeIntent(String intent, {Map<String, dynamic>? params}) async {
    if (state.url.isEmpty || state.token.isEmpty) return;
    
    state = state.copyWith(isExecuting: true);
    
    try {
      await http.post(
        Uri.parse('${state.url}/intent'),
        headers: {
          'Content-Type': 'application/json',
          'X-API-Token': state.token,
        },
        body: jsonEncode({
          'intent': intent,
          'params': params ?? {},
        }),
      );
      state = state.copyWith(isExecuting: false);
    } catch (e) {
      state = state.copyWith(isExecuting: false);
    }
  }

  Future<void> respondToApproval(String approvalId, bool accept) async {
    if (state.url.isEmpty || state.token.isEmpty) return;
    
    try {
      await http.post(
        Uri.parse('${state.url}/approve/$approvalId?accept=$accept'),
        headers: {
          'X-API-Token': state.token,
        },
      );
    } catch (e) {
      // Slient fail for background ops
    }
  }
}
