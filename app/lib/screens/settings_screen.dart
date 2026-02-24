import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/agent_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _urlController;
  late TextEditingController _tokenController;

  @override
  void initState() {
    super.initState();
    final state = ref.read(agentProvider);
    _urlController = TextEditingController(text: state.url);
    _tokenController = TextEditingController(text: state.token);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent Settings'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Agent URL',
                hintText: 'http://100.x.x.x:8742',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tokenController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API Secret Token',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await ref.read(agentProvider.notifier).updateConfig(
                    _urlController.text,
                    _tokenController.text,
                  );
                  if (mounted) Navigator.pop(context);
                },
                style: ElevatedButton.fromMaterialScheme(
                  Theme.of(context).colorScheme.primaryContainer,
                ),
                child: const Text('Save and Connect'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
