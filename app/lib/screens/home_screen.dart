import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/agent_provider.dart';
import '../providers/push_provider.dart';
import '../providers/logs_provider.dart';
import '../providers/quota_provider.dart';
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
    Future.microtask(() {
      ref.read(pushNotificationProvider).initialize(context);
      ref.read(logsProvider.notifier).startListening();
      ref.read(quotaProvider.notifier).fetchQuotas();
    });
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
        final phrase = _lastWords.toLowerCase();
        if (phrase.contains('update') && (phrase.contains('site') || phrase.contains('website'))) {
          ref.read(agentProvider.notifier).executeIntent('update-site');
        } else {
          ref.read(agentProvider.notifier).executeCommand(_lastWords);
        }
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
            top: -100.0,
            right: -100.0,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withOpacity(0.05),
              ),
            ).animate(onPlay: (c) => c.repeat()).blur(begin: const Offset(50.0, 50.0), end: const Offset(100.0, 100.0)),
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
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ANTIGRAVITY',
                              style: theme.textTheme.labelLarge?.copyWith(
                                letterSpacing: 4,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const Text(
                              'Bridge Active',
                              style: TextStyle(fontSize: 12, color: Colors.white54),
                            ),
                          ],
                        ),
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

                const SizedBox(height: 16),
                
                // Model Token Quotas
                const _TokenPoolsRow(),

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

                // Real-time Agent Log Feed
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withOpacity(0.9),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 20,
                        offset: const Offset(0, -10),
                      ),
                    ],
                  ),
                  height: 320,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: agentState.isConnected ? Colors.green : Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('AGENT CHAT', 
                                style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white38)),
                            ],
                          ),
                          if (agentState.isExecuting)
                            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ref.watch(logsProvider).isEmpty 
                          ? Center(
                              child: Text(
                                agentState.isConnected ? 'Waiting for agent activity...' : 'Connect to see live logs',
                                style: const TextStyle(color: Colors.white24, fontSize: 13),
                              ),
                            )
                          : ListView.builder(
                              reverse: true,
                              itemCount: ref.watch(logsProvider).length,
                              itemBuilder: (context, index) {
                                final logs = ref.watch(logsProvider).reversed.toList();
                                final log = logs[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${log.timestamp} ', style: GoogleFonts.firaCode(fontSize: 10, color: Colors.white24)),
                                      Expanded(
                                        child: Text(
                                          log.message,
                                          style: GoogleFonts.firaCode(
                                            fontSize: 12,
                                            color: log.type == 'error' ? Colors.redAccent.withOpacity(0.8) : 
                                                   log.type == 'success' ? Colors.greenAccent.withOpacity(0.8) :
                                                   Colors.white70,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
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

// ─── Token Meter Components ──────────────────────────────────────────────────

class _TokenPoolsRow extends ConsumerWidget {
  const _TokenPoolsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotas = ref.watch(quotaProvider);
    if (quotas.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: quotas.map((q) => _QuotaMeter(quota: q)).toList(),
      ),
    );
  }
}

class _QuotaMeter extends StatefulWidget {
  final ModelQuota quota;
  const _QuotaMeter({required this.quota});

  @override
  State<_QuotaMeter> createState() => _QuotaMeterState();
}

class _QuotaMeterState extends State<_QuotaMeter> {
  Timer? _timer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.quota.resetSeconds;
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft > 0) {
        if (mounted) setState(() => _secondsLeft--);
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatTime(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${s}s';
  }

  Color _getModelColor() {
    final name = widget.quota.name.toLowerCase();
    if (name.contains('claude')) return Colors.deepPurpleAccent;
    if (name.contains('gpt')) return const Color(0xFF10B981); // Emerald
    return Colors.blueAccent;
  }

  @override
  Widget build(BuildContext context) {
    final color = _getModelColor();
    final percent = widget.quota.percent;

    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.quota.name, 
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.5)),
              Icon(Icons.token_outlined, size: 10, color: color),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: percent,
              backgroundColor: color.withOpacity(0.1),
              color: color,
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${(percent * 100).toInt()}%', 
                style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
              Row(
                children: [
                   const Icon(Icons.timer_outlined, size: 10, color: Colors.white24),
                   const SizedBox(width: 3),
                   Text(_formatTime(_secondsLeft), 
                    style: const TextStyle(color: Colors.white24, fontSize: 9)),
                ],
              ),
            ],
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
