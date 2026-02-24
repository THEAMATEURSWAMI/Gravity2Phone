import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'agent_provider.dart';

class ModelQuota {
  final String name;
  final String modelId;
  final int usedTokens;
  final int totalTokens;
  final DateTime resetAt;
  final int resetSeconds;

  ModelQuota({
    required this.name,
    required this.modelId,
    required this.usedTokens,
    required this.totalTokens,
    required this.resetAt,
    required this.resetSeconds,
  });

  double get percent => usedTokens / totalTokens;

  factory ModelQuota.fromJson(Map<String, dynamic> json) {
    return ModelQuota(
      name: json['name'],
      modelId: json['model_id'],
      usedTokens: json['used_tokens'],
      totalTokens: json['total_tokens'],
      resetAt: DateTime.parse(json['reset_at']),
      resetSeconds: json['reset_seconds'],
    );
  }
}

final quotaProvider = StateNotifierProvider<QuotaNotifier, List<ModelQuota>>((ref) {
  final agentState = ref.watch(agentProvider);
  return QuotaNotifier(agentState);
});

class QuotaNotifier extends StateNotifier<List<ModelQuota>> {
  final AgentState agentState;

  QuotaNotifier(this.agentState) : super([]);

  Future<void> fetchQuotas() async {
    if (agentState.url.isEmpty || agentState.token.isEmpty) return;
    
    try {
      final response = await http.get(
        Uri.parse('${agentState.url}/quota'),
        headers: {'X-API-Token': agentState.token},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        state = data.map((j) => ModelQuota.fromJson(j)).toList();
      }
    } catch (e) {
      print('Failed to fetch quotas: $e');
    }
  }
}
