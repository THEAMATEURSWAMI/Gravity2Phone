import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/workflows_provider.dart';

class WorkflowsScreen extends ConsumerStatefulWidget {
  const WorkflowsScreen({super.key});

  @override
  ConsumerState<WorkflowsScreen> createState() => _WorkflowsScreenState();
}

class _WorkflowsScreenState extends ConsumerState<WorkflowsScreen> {
  final _ownerController = TextEditingController(text: 'THEAMATEURSWAMI');
  final _repoController = TextEditingController(text: 'Gravity2Phone');

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _refresh());
  }

  Future<void> _refresh() async {
    await ref.read(workflowsProvider.notifier).fetchWorkflows(
      _ownerController.text,
      _repoController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final workflows = ref.watch(workflowsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Repository Workflows'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ownerController,
                    decoration: const InputDecoration(labelText: 'Owner', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _repoController,
                    decoration: const InputDecoration(labelText: 'Repo', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: workflows.isEmpty
                ? const Center(child: Text('No workflows found or loading...'))
                : ListView.builder(
                    itemCount: workflows.length,
                    itemBuilder: (context, index) {
                      final run = workflows[index];
                      return _WorkflowTile(run: run);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowTile extends StatelessWidget {
  final WorkflowRun run;
  const _WorkflowTile({required this.run});

  Color _getStatusColor() {
    if (run.status == 'in_progress') return Colors.blue;
    if (run.conclusion == 'success') return Colors.green;
    if (run.conclusion == 'failure') return Colors.red;
    return Colors.grey;
  }

  IconData _getStatusIcon() {
    if (run.status == 'in_progress') return Icons.sync;
    if (run.conclusion == 'success') return Icons.check_circle;
    if (run.conclusion == 'failure') return Icons.error;
    return Icons.help_outline;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.surface,
      child: ListTile(
        leading: Icon(_getStatusIcon(), color: _getStatusColor()),
        title: Text(run.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          '${run.status} • ${DateFormat('MMM d, HH:mm').format(run.createdAt)}',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        trailing: run.conclusion != null 
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getStatusColor().withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                run.conclusion!.toUpperCase(),
                style: TextStyle(color: _getStatusColor(), fontSize: 10, fontWeight: FontWeight.bold),
              ),
            )
          : null,
      ),
    );
  }
}
