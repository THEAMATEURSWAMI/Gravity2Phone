import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/agent_provider.dart';

class RepoSelectionScreen extends ConsumerStatefulWidget {
  const RepoSelectionScreen({super.key});

  @override
  ConsumerState<RepoSelectionScreen> createState() => _RepoSelectionScreenState();
}

class _RepoSelectionScreenState extends ConsumerState<RepoSelectionScreen> {
  List<dynamic>? _repos;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRepos();
  }

  Future<void> _loadRepos() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repos = await ref.read(agentProvider.notifier).fetchRepos();
      setState(() {
        _repos = repos;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load projects. Check your connection.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final agentState = ref.watch(agentProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          'SELECT PROJECT',
          style: theme.textTheme.labelLarge?.copyWith(
            letterSpacing: 2,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainValue.center,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.white54)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadRepos,
                        child: const Text('RETRY'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(24),
                  itemCount: (_repos?.length ?? 0) + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      // Option to clear selection
                      final isSelected = agentState.activeRepo == null;
                      return _RepoTile(
                        name: 'GLOBAL CONTEXT',
                        description: 'No specific project folder',
                        isSelected: isSelected,
                        onTap: () {
                          ref.read(agentProvider.notifier).setActiveRepo(null);
                          Navigator.pop(context);
                        },
                      );
                    }

                    final repo = _repos![index - 1];
                    final fullName = repo['full_name'];
                    final name = repo['name'];
                    final isSelected = agentState.activeRepo == fullName;

                    return _RepoTile(
                      name: name.toUpperCase(),
                      description: fullName,
                      isSelected: isSelected,
                      onTap: () {
                        ref.read(agentProvider.notifier).setActiveRepo(fullName);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
    );
  }
}

class _RepoTile extends StatelessWidget {
  final String name;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;

  const _RepoTile({
    required this.name,
    required this.description,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? theme.colorScheme.primary.withOpacity(0.1) : Colors.white.withOpacity(0.02),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? theme.colorScheme.primary : Colors.white.withOpacity(0.05),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check_circle : Icons.folder_outlined,
                color: isSelected ? theme.colorScheme.primary : Colors.white24,
                size: 20,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: isSelected ? theme.colorScheme.primary : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Colors.white24,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ).animate().fadeIn(delay: 50.ms).slideY(begin: 0.1),
    );
  }
}
