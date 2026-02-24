import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/agent_provider.dart';

class RepoSelectionScreen extends ConsumerStatefulWidget {
  const RepoSelectionScreen({super.key});

  @override
  ConsumerState<RepoSelectionScreen> createState() => _RepoSelectionScreenState();
}

class _RepoSelectionScreenState extends ConsumerState<RepoSelectionScreen> {
  List<dynamic> _repos = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchRepos();
  }

  Future<void> _fetchRepos() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      final repos = await ref.read(agentProvider.notifier).fetchRepos();
      if (mounted) {
        setState(() {
          _repos = repos;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load repositories';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final agentState = ref.watch(agentProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0D12), // Corrected color literal
      appBar: AppBar(
        title: const Text('SELECT PROJECT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.white54)),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _fetchRepos,
                        child: Text('RETRY', style: TextStyle(color: theme.colorScheme.primary)),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _repos.length,
                  itemBuilder: (context, index) {
                    final repo = _repos[index] as Map<String, dynamic>;
                    final String repoName = repo['full_name'] ?? 'Unknown Repo';
                    final String visibility = repo['visibility'] ?? 'public';
                    final bool isSelected = agentState.activeRepo == repoName;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: () {
                          ref.read(agentProvider.notifier).setActiveRepo(repoName);
                          Navigator.pop(context);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? theme.colorScheme.primary.withOpacity(0.1) 
                                : Colors.white.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected 
                                  ? theme.colorScheme.primary.withOpacity(0.3) 
                                  : Colors.white.withOpacity(0.05),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.check_circle : (visibility == 'private' ? Icons.lock_outline : Icons.folder_outlined),
                                color: isSelected ? theme.colorScheme.primary : (visibility == 'private' ? Colors.orangeAccent.withOpacity(0.5) : Colors.white38),
                                size: 18,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      repoName.split('/').last.toUpperCase(),
                                      style: TextStyle(
                                        color: isSelected ? theme.colorScheme.primary : Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      repoName,
                                      style: const TextStyle(
                                        color: Colors.white24,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'ACTIVE',
                                    style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
