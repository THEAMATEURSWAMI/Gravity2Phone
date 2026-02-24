import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'agent_provider.dart';

class LogEntry {
  final String timestamp;
  final String message;
  final String type;
  final String source;

  LogEntry({
    required this.timestamp, 
    required this.message, 
    required this.type, 
    this.source = 'system'
  });

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      timestamp: json['timestamp'] ?? '', 
      message: json['message'] ?? '',
      type: json['type'] ?? 'info',
      source: json['source'] ?? 'system',
    );
  }
}

final logsProvider = StateNotifierProvider<LogsNotifier, List<LogEntry>>((ref) {
  final agentState = ref.watch(agentProvider);
  final notifier = LogsNotifier(agentState);
  
  if (agentState.isConnected) {
    Future.delayed(const Duration(milliseconds: 500), () => notifier.startListening());
  }
  
  return notifier;
});

class LogsNotifier extends StateNotifier<List<LogEntry>> {
  final AgentState agentState;
  StreamSubscription? _subscription;
  http.Client? _client;
  int _historyOffset = 0;

  LogsNotifier(this.agentState) : super([]);

  Future<void> fetchHistory({bool append = false}) async {
    if (agentState.url.isEmpty || !agentState.isConnected) return;
    
    try {
      final response = await http.get(
        Uri.parse('${agentState.url}/history?limit=50&offset=$_historyOffset'),
        headers: {'X-API-Token': agentState.token},
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final history = data.map((json) => LogEntry.fromJson(json)).toList();
        
        if (append) {
          state = [...history, ...state];
        } else {
          state = history;
        }
        _historyOffset += history.length;
      }
    } catch (e) {
      // Silent fail
    }
  }

  void startListening() {
    if (agentState.url.isEmpty || !agentState.isConnected) return;
    
    _historyOffset = 0;
    fetchHistory();
    
    _subscription?.cancel();
    _client?.close();
    
    final url = Uri.parse('${agentState.url}/logs');
    final request = http.Request('GET', url);
    
    request.headers['X-API-Token'] = agentState.token;
    request.headers['Accept'] = 'text/event-stream';
    request.headers['Cache-Control'] = 'no-cache';

    _client = http.Client();
    
    _client!.send(request).then((response) {
      if (response.statusCode != 200) {
        return;
      }

      _subscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line.trim().startsWith('data: ')) {
              try {
                final jsonStr = line.trim().substring(6);
                final data = jsonDecode(jsonStr);
                final entry = LogEntry.fromJson(data);
                
                state = [...state, entry];
                if (state.length > 100) {
                  state = state.sublist(state.length - 100);
                }
              } catch (e) {}
            }
          });
    }).catchError((e) {});
  }

  void clear() {
    state = [];
    _historyOffset = 0;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _client?.close();
    super.dispose();
  }
}
