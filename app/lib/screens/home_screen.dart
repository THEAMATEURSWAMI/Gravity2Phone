import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../providers/agent_provider.dart';
import 'settings_screen.dart';
import 'workflows_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  String _lastWords = '';

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize();
    setState(() {});
  }

  void _startListening() async {
    await _speechToText.listen(onResult: (result) {
      setState(() {
        _lastWords = result.recognizedWords;
      });
      if (result.finalResult && _lastWords.isNotEmpty) {
        ref.read(agentProvider.notifier).executeCommand(_lastWords);
      }
    });
    setState(() {});
  }

  void _stopListening() async {
    await _speechToText.stop();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final agentState = ref.watch(agentProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          // Background Glow
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withOpacity(0.05),
              ),
            ).animate(onPlay: (c) => c.repeat()).blur(begin: 50, end: 100),
          ),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ANTIGRAVITY',
                            style: theme.textTheme.labelLarge?.copyWith(
                              letterSpacing: 4,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const Text(
                            'Bridge Active',
                            style: TextStyle(fontSize: 12, color: Colors.white54),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          _StatusIndicator(isConnected: agentState.isConnected),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.rocket_launch, color: Colors.white24),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const WorkflowsScreen()),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.settings, color: Colors.white24),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const SettingsScreen()),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Main Voice Button
                Center(
                  child: GestureDetector(
                    onLongPressStart: (_) => _startListening(),
                    onLongPressEnd: (_) => _stopListening(),
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.surface,
                        border: Border.all(
                          color: _speechToText.isListening 
                              ? theme.colorScheme.primary 
                              : Colors.white10,
                          width: 2,
                        ),
                        boxShadow: [
                          if (_speechToText.isListening)
                            BoxShadow(
                              color: theme.colorScheme.primary.withOpacity(0.3),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          _speechToText.isListening ? FontAwesomeIcons.microphone : FontAwesomeIcons.bolt,
                          size: 48,
                          color: _speechToText.isListening 
                              ? theme.colorScheme.primary 
                              : Colors.white24,
                        ),
                      ),
                    )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scale(begin: const Offset(1, 1), end: _speechToText.isListening ? const Offset(1.1, 1.1) : const Offset(1, 1)),
                  ),
                ),

                const SizedBox(height: 32),

                Center(
                  child: Text(
                    _speechToText.isListening ? 'Listening...' : 'Hold to Speak',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: _speechToText.isListening ? theme.colorScheme.primary : Colors.white38,
                    ),
                  ),
                ),

                const Spacer(),

                // Terminal / Last Output
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withOpacity(0.8),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  ),
                  height: 300,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('COMMAND LOG', style: TextStyle(letterSpacing: 1, fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white38)),
                          if (agentState.isExecuting)
                            const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(
                            agentState.lastOutput ?? 'Ready for your command, Swami.',
                            style: GoogleFonts.firaCode(
                              fontSize: 13,
                              color: agentState.isConnected ? Colors.white70 : Colors.redAccent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  final bool isConnected;
  const _StatusIndicator({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isConnected ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isConnected ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected ? Colors.green : Colors.red,
            ),
          ).animate(onPlay: (c) => c.repeat()).fade(begin: 0.5, end: 1.0, duration: 1.seconds),
          const SizedBox(width: 8),
          Text(
            isConnected ? 'SYNCED' : 'OFFLINE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isConnected ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
    );
  }
}
