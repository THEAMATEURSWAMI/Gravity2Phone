import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'agent_provider.dart';

class LogEntry {
  final String timestamp;
  final String message;
  final String type;

  LogEntry({required this.timestamp, required this.message, required this.type});

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      timestamp: DateTime.now().toLocal().toString().split(' ')[1].split('.')[0], // Local time
      message: json['message'],
      type: json['type'] ?? 'info',
    );
  }
}

final logsProvider = StateNotifierProvider<LogsNotifier, List<LogEntry>>((ref) {
  final agentState = ref.watch(agentProvider);
  return LogsNotifier(agentState);
});

class LogsNotifier extends StateNotifier<List<LogEntry>> {
  final AgentState agentState;
  StreamSubscription? _subscription;

  LogsNotifier(this.agentState) : super([]);

  void startListening() {
    if (agentState.url.isEmpty || !agentState.isConnected) return;
    
    _subscription?.cancel();
    
    final url = Uri.parse('${agentState.url}/logs');
    final request = http.Request('GET', url);
    
    // Antigravity Bridge specific: SSE doesn't always need auth if local, but we pass it anyway
    request.headers['X-API-Token'] = agentState.token;
    request.headers['Accept'] = 'text/event-stream';

    final client = http.Client();
    
    client.send(request).then((response) {
      if (response.statusCode != 200) {
        state = [...state, LogEntry(timestamp: '', message: '❌ Log stream failed: ${response.statusCode}', type: 'error')];
        return;
      }

      _subscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line.startsWith('data: ')) {
              try {
                final data = jsonDecode(line.substring(6));
                final entry = LogEntry.fromJson(data);
                state = [...state, entry];
                // Keep only last 50 logs to save memory
                if (state.length > 50) {
                  state = state.sublist(state.length - 50);
                }
              } catch (e) {
                // Ignore malformed lines
              }
            }
          }, onError: (e) {
            state = [...state, LogEntry(timestamp: '', message: '⚠️ Connection lost', type: 'error')];
          }, onDone: () {
            // Auto-reconnect or just stop
          });
    });
  }

  void clear() {
    state = [];
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
