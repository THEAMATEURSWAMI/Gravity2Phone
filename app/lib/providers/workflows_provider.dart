import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'agent_provider.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

class WorkflowRun {
  final int id;
  final String name;
  final String status;
  final String? conclusion;
  final String repo;
  final String url;
  final String visibility;
  final DateTime createdAt;

  WorkflowRun({
    required this.id,
    required this.name,
    required this.status,
    this.conclusion,
    required this.repo,
    required this.url,
    required this.visibility,
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
      visibility: json['visibility'] ?? 'public',
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class GitHubRepo {
  final int id;
  final String name;
  final String fullName;
  final String owner;
  final bool isOrg;
  final String visibility;
  final String? description;

  GitHubRepo({
    required this.id,
    required this.name,
    required this.fullName,
    required this.owner,
    required this.isOrg,
    required this.visibility,
    this.description,
  });

  factory GitHubRepo.fromJson(Map<String, dynamic> json) {
    return GitHubRepo(
      id: json['id'],
      name: json['name'],
      fullName: json['full_name'],
      owner: json['owner'],
      isOrg: json['is_org'] ?? false,
      visibility: json['visibility'] ?? 'public',
      description: json['description'],
    );
  }
}

// ─── Workflows Provider ───────────────────────────────────────────────────────

class WorkflowsState {
  final List<WorkflowRun> runs;
  final List<GitHubRepo> repos;
  final bool isLoadingRuns;
  final bool isLoadingRepos;
  final String? error;

  const WorkflowsState({
    this.runs = const [],
    this.repos = const [],
    this.isLoadingRuns = false,
    this.isLoadingRepos = false,
    this.error,
  });

  WorkflowsState copyWith({
    List<WorkflowRun>? runs,
    List<GitHubRepo>? repos,
    bool? isLoadingRuns,
    bool? isLoadingRepos,
    String? error,
  }) {
    return WorkflowsState(
      runs: runs ?? this.runs,
      repos: repos ?? this.repos,
      isLoadingRuns: isLoadingRuns ?? this.isLoadingRuns,
      isLoadingRepos: isLoadingRepos ?? this.isLoadingRepos,
      error: error,
    );
  }
}

final workflowsProvider = StateNotifierProvider<WorkflowsNotifier, WorkflowsState>((ref) {
  final agentState = ref.watch(agentProvider);
  return WorkflowsNotifier(agentState);
});

class WorkflowsNotifier extends StateNotifier<WorkflowsState> {
  final AgentState agentState;

  WorkflowsNotifier(this.agentState) : super(const WorkflowsState());

  Future<void> fetchRepos() async {
    if (agentState.url.isEmpty || agentState.token.isEmpty) return;
    state = state.copyWith(isLoadingRepos: true, error: null);
    try {
      final response = await http.get(
        Uri.parse('${agentState.url}/repos'),
        headers: {'X-API-Token': agentState.token},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        state = state.copyWith(
          repos: data.map((j) => GitHubRepo.fromJson(j)).toList(),
          isLoadingRepos: false,
        );
      } else {
        state = state.copyWith(isLoadingRepos: false, error: 'Error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      state = state.copyWith(isLoadingRepos: false, error: 'Failed to load repos: $e');
    }
  }

  Future<void> fetchWorkflows(String owner, String repo) async {
    if (agentState.url.isEmpty || agentState.token.isEmpty) return;
    state = state.copyWith(isLoadingRuns: true, error: null);
    try {
      final response = await http.get(
        Uri.parse('${agentState.url}/workflows?owner=$owner&repo=$repo'),
        headers: {'X-API-Token': agentState.token},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        state = state.copyWith(
          runs: data.map((j) => WorkflowRun.fromJson(j)).toList(),
          isLoadingRuns: false,
        );
      } else {
        state = state.copyWith(isLoadingRuns: false, error: 'Error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      state = state.copyWith(isLoadingRuns: false, error: 'Failed to fetch workflows: $e');
    }
  }
}
