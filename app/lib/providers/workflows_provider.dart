import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'agent_provider.dart';

final workflowsProvider = StateNotifierProvider<WorkflowsNotifier, List<WorkflowRun>>((ref) {
  final agentState = ref.watch(agentProvider);
  return WorkflowsNotifier(agentState);
});

class WorkflowRun {
  final int id;
  final String name;
  final String status;
  final String? conclusion;
  final String repo;
  final String url;
  final DateTime createdAt;

  WorkflowRun({
    required this.id,
    required this.name,
    required this.status,
    this.conclusion,
    required this.repo,
    required this.url,
    required this.createdAt,
  });

  factory WorkflowRun.fromJson(Map<String, dynamic> json) {
    return WorkflowRun(
      id: json['id'],
      name: json['name'],
      status: json['status'],
      conclusion: json['conclusion'],
      repo: json['repo'],
      url: json['url'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class WorkflowsNotifier extends StateNotifier<List<WorkflowRun>> {
  final AgentState agentState;

  WorkflowsNotifier(this.agentState) : super([]);

  Future<void> fetchWorkflows(String owner, String repo) async {
    if (agentState.url.isEmpty || agentState.token.isEmpty) return;

    try {
      final response = await http.get(
        Uri.parse('${agentState.url}/workflows?owner=$owner&repo=$repo'),
        headers: {
          'X-API-Token': agentState.token,
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        state = data.map((json) => WorkflowRun.fromJson(json)).toList();
      }
    } catch (e) {
      print('Failed to fetch workflows: $e');
    }
  }
}
