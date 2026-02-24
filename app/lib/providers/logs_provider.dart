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
      timestamp: DateTime.now().toLocal().toString().split(' ')[1].split('.')[0], 
      message: json['message'] ?? '',
      type: json['type'] ?? 'info',
    );
  }
}

final logsProvider = StateNotifierProvider<LogsNotifier, List<LogEntry>>((ref) {
  final agentState = ref.watch(agentProvider);
  final notifier = LogsNotifier(agentState);
  
  // Automatically start/stop listening based on connection status
  if (agentState.isConnected) {
    // Small delay to ensure the event loop is ready
    Future.delayed(const Duration(milliseconds: 500), () => notifier.startListening());
  }
  
  return notifier;
});

class LogsNotifier extends StateNotifier<List<LogEntry>> {
  final AgentState agentState;
  StreamSubscription? _subscription;
  http.Client? _client;

  LogsNotifier(this.agentState) : super([]);

  void startListening() {
    if (agentState.url.isEmpty || !agentState.isConnected) return;
    
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
        state = [...state, LogEntry(timestamp: '', message: '❌ Log stream failed: ${response.statusCode}', type: 'error')];
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
                
                // Add to state and keep it bounded
                state = [...state, entry];
                if (state.length > 50) {
                  state = state.sublist(state.length - 50);
                }
              } catch (e) {
                // Ignore parsing errors for partial/malformed lines
              }
            }
          }, onError: (e) {
            if (mounted) {
               state = [...state, LogEntry(timestamp: '', message: '⚠️ Connection lost', type: 'error')];
            }
          });
    }).catchError((e) {
      if (mounted) {
        state = [...state, LogEntry(timestamp: '', message: '❌ Stream error: $e', type: 'error')];
      }
    });
  }

  void clear() {
    state = [];
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _client?.close();
    super.dispose();
  }
}
