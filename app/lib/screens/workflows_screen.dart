import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/workflows_provider.dart';

class WorkflowsScreen extends ConsumerStatefulWidget {
  const WorkflowsScreen({super.key});

  @override
  ConsumerState<WorkflowsScreen> createState() => _WorkflowsScreenState();
}

class _WorkflowsScreenState extends ConsumerState<WorkflowsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedOwner;
  String? _selectedRepo;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    Future.microtask(() => ref.read(workflowsProvider.notifier).fetchRepos());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onRepoTap(GitHubRepo repo) {
    setState(() {
      _selectedOwner = repo.owner;
      _selectedRepo = repo.name;
    });
    ref.read(workflowsProvider.notifier).fetchWorkflows(repo.owner, repo.name);
    _tabController.animateTo(1);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workflowsProvider);
    final theme = Theme.of(context);

    final personalRepos = state.repos.where((r) => !r.isOrg).toList();
    final orgRepos = state.repos.where((r) => r.isOrg).toList();

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('GitHub Actions', style: TextStyle(fontWeight: FontWeight.bold)),
            if (_selectedRepo != null)
              Text(
                '$_selectedOwner/$_selectedRepo',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
              ),
          ],
        ),
        actions: [
          if (state.isLoadingRepos || state.isLoadingRuns)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.read(workflowsProvider.notifier).fetchRepos(),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.folder_outlined), text: 'Repos'),
            Tab(icon: Icon(Icons.rocket_launch_outlined), text: 'Runs'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── REPOS TAB ─────────────────────────────────────────────────────
          _buildRepoList(personalRepos, orgRepos, state, theme),
          // ── RUNS TAB ──────────────────────────────────────────────────────
          _buildRunsList(state, theme),
        ],
      ),
    );
  }

  Widget _buildRepoList(List<GitHubRepo> personal, List<GitHubRepo> org,
      WorkflowsState state, ThemeData theme) {
    if (state.isLoadingRepos) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.repos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(state.error!, style: const TextStyle(color: Colors.redAccent)),
        ),
      );
    }
    if (state.repos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off_outlined, size: 48, color: Colors.white24),
            const SizedBox(height: 12),
            const Text('No repos found.\nMake sure your GITHUB_TOKEN is set in the agent.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (personal.isNotEmpty) ...[
          _sectionHeader('👤  Personal', personal.length, theme),
          ...personal.map((r) => _RepoTile(repo: r, onTap: _onRepoTap)),
        ],
        if (org.isNotEmpty) ...[
          _sectionHeader('🏢  Organizations', org.length, theme),
          ...org.map((r) => _RepoTile(repo: r, onTap: _onRepoTap)),
        ],
      ],
    );
  }

  Widget _sectionHeader(String label, int count, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                  letterSpacing: 1)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count',
                style: TextStyle(fontSize: 11, color: theme.colorScheme.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildRunsList(WorkflowsState state, ThemeData theme) {
    if (_selectedRepo == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.touch_app_outlined, size: 48, color: Colors.white24),
            SizedBox(height: 12),
            Text('Tap a repo in the Repos tab\nto see its workflow runs.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }
    if (state.isLoadingRuns) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.runs.isEmpty) {
      return const Center(
        child: Text('No workflow runs found for this repo.',
            style: TextStyle(color: Colors.white54)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: state.runs.length,
      itemBuilder: (context, index) => _WorkflowTile(run: state.runs[index]),
    );
  }
}

// ─── Repo Tile ────────────────────────────────────────────────────────────────

class _RepoTile extends StatelessWidget {
  final GitHubRepo repo;
  final void Function(GitHubRepo) onTap;
  const _RepoTile({required this.repo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPublic = repo.visibility == 'public';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: theme.colorScheme.surface,
      child: ListTile(
        onTap: () => onTap(repo),
        leading: Icon(
          repo.isOrg ? Icons.apartment : Icons.person_outline,
          color: Colors.white38,
          size: 20,
        ),
        title: Text(repo.name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: repo.description != null && repo.description!.isNotEmpty
            ? Text(repo.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 12))
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _VisibilityBadge(isPublic: isPublic),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─── Workflow Run Tile ─────────────────────────────────────────────────────────

class _WorkflowTile extends StatelessWidget {
  final WorkflowRun run;
  const _WorkflowTile({required this.run});

  Color _statusColor() {
    if (run.status == 'in_progress' || run.status == 'queued') return Colors.blue;
    if (run.conclusion == 'success') return Colors.green;
    if (run.conclusion == 'failure') return Colors.redAccent;
    if (run.conclusion == 'cancelled') return Colors.orange;
    return Colors.grey;
  }

  IconData _statusIcon() {
    if (run.status == 'in_progress') return Icons.sync;
    if (run.status == 'queued') return Icons.schedule;
    if (run.conclusion == 'success') return Icons.check_circle_outline;
    if (run.conclusion == 'failure') return Icons.error_outline;
    if (run.conclusion == 'cancelled') return Icons.cancel_outlined;
    return Icons.help_outline;
  }

  String _statusLabel() {
    if (run.status == 'in_progress') return 'RUNNING';
    if (run.status == 'queued') return 'QUEUED';
    return (run.conclusion ?? run.status).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _statusColor();
    final isInProgress = run.status == 'in_progress' || run.status == 'queued';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_statusIcon(), color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(run.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                _VisibilityBadge(isPublic: run.visibility == 'public'),
              ],
            ),
            const SizedBox(height: 8),
            // Progress bar for in-progress runs
            if (isInProgress) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  backgroundColor: Colors.white12,
                  color: color,
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: color.withOpacity(0.3)),
                  ),
                  child: Text(_statusLabel(),
                      style: TextStyle(
                          color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                Icon(Icons.schedule, size: 12, color: Colors.white38),
                const SizedBox(width: 4),
                Text(
                  DateFormat('MMM d, HH:mm').format(run.createdAt.toLocal()),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _VisibilityBadge extends StatelessWidget {
  final bool isPublic;
  const _VisibilityBadge({required this.isPublic});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isPublic ? Colors.green.withOpacity(0.12) : Colors.orange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isPublic ? Colors.green.withOpacity(0.4) : Colors.orange.withOpacity(0.4),
        ),
      ),
      child: Text(
        isPublic ? '🔓 PUBLIC' : '🔒 PRIVATE',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: isPublic ? Colors.green : Colors.orange,
        ),
      ),
    );
  }
}
