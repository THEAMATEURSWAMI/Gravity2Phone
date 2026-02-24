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
  late TextEditingController _nameController;
  String _selectedIcon = 'computer';

  final List<Map<String, dynamic>> _iconOptions = [
    {'id': 'computer', 'label': 'DESKTOP', 'icon': Icons.laptop},
    {'id': 'pi', 'label': 'RASPBERRY PI', 'icon': Icons.memory},
    {'id': 'arduino', 'label': 'ARDUINO', 'icon': Icons.developer_board},
    {'id': 'mobile', 'label': 'PORTABLE', 'icon': Icons.smartphone},
  ];

  @override
  void initState() {
    super.initState();
    final state = ref.read(agentProvider);
    _urlController = TextEditingController(text: state.url);
    _tokenController = TextEditingController(text: state.token);
    _nameController = TextEditingController(text: state.deviceName ?? '');
    _selectedIcon = state.deviceIcon;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D12),
      appBar: AppBar(
        title: const Text('AGENT SETTINGS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('CONNECTION'),
              const SizedBox(height: 16),
              _buildTextField(_urlController, 'AGENT URL', 'http://100.x.x.x:8742'),
              const SizedBox(height: 16),
              _buildTextField(_tokenController, 'SECRET TOKEN', '••••••••', obscure: true),
              const SizedBox(height: 32),
              
              _buildSectionHeader('IDENTITY'),
              const SizedBox(height: 16),
              _buildTextField(_nameController, 'DEVICE NAME', 'e.g. My Mac Studio'),
              const SizedBox(height: 16),
              _buildIconPicker(),
              const SizedBox(height: 48),
              
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await ref.read(agentProvider.notifier).updateConfig(
                      _urlController.text,
                      _tokenController.text,
                      name: _nameController.text.isEmpty ? null : _nameController.text,
                      icon: _selectedIcon,
                    );
                    if (mounted) Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('SAVE AND SYNC', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 2,
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, String hint, {bool obscure = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 1),
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white10),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: InputBorder.none,
          floatingLabelBehavior: FloatingLabelBehavior.always,
        ),
      ),
    );
  }

  Widget _buildIconPicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<String>(
          value: _selectedIcon,
          dropdownColor: const Color(0xFF161922),
          decoration: const InputDecoration(
            labelText: 'DEVICE ICON',
            labelStyle: TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 1),
            border: InputBorder.none,
            floatingLabelBehavior: FloatingLabelBehavior.always,
          ),
          items: _iconOptions.map((opt) => DropdownMenuItem(
            value: opt['id'] as String,
            child: Row(
              children: [
                Icon(opt['icon'] as IconData, color: Colors.white54, size: 18),
                const SizedBox(width: 12),
                Text(opt['label'] as String, style: const TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
          )).toList(),
          onChanged: (val) {
            if (val != null) setState(() => _selectedIcon = val);
          },
        ),
      ),
    );
  }
}
