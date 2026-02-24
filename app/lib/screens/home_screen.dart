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
      if (!mounted) return;
      setState(() => _lastWords = result.recognizedWords);
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
                // Minimal Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'ANTIGRAVITY',
                        style: theme.textTheme.labelLarge?.copyWith(
                          letterSpacing: 4,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.rocket_launch, color: Colors.white24, size: 20),
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkflowsScreen())),
                          ),
                          IconButton(
                            icon: const Icon(Icons.settings, color: Colors.white24, size: 20),
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Main Bridge Action
                Center(
                  child: GestureDetector(
                    onLongPressStart: (_) => _startListening(),
                    onLongPressEnd: (_) => _stopListening(),
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.surface,
                        border: Border.all(
                          color: _speechToText.isListening ? theme.colorScheme.primary : Colors.white10,
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
                          _speechToText.isListening ? FontAwesomeIcons.microphone : FontAwesomeIcons.bridgeWater,
                          size: 40,
                          color: _speechToText.isListening ? theme.colorScheme.primary : Colors.white24,
                        ),
                      ),
                    )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scale(begin: const Offset(1, 1), end: _speechToText.isListening ? const Offset(1.1, 1.1) : const Offset(1, 1)),
                  ),
                ),

                const SizedBox(height: 24),

                Center(
                  child: Text(
                    _speechToText.isListening ? 'Listening...' : 'Hold to Speak',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: _speechToText.isListening ? theme.colorScheme.primary : Colors.white24,
                      letterSpacing: 1,
                    ),
                  ),
                ),

                const Spacer(),
                
                // Compact Token Meters
                const _TokenPoolsRow(),
                const SizedBox(height: 12),

                // Real-time Agent Log Feed
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withOpacity(0.95),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  ),
                  height: 300,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              _StatusDot(isConnected: agentState.isConnected),
                              const SizedBox(width: 10),
                              Text(agentState.isConnected ? 'SYNCED' : 'OFFLINE', 
                                style: TextStyle(
                                  letterSpacing: 2, fontWeight: FontWeight.bold, fontSize: 10, 
                                  color: agentState.isConnected ? Colors.green.withOpacity(0.7) : Colors.red.withOpacity(0.7)
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('|  AGENT CHAT', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white24)),
                            ],
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white24, size: 16),
                                onPressed: () => ref.read(logsProvider.notifier).clear(),
                                tooltip: 'Clear',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: 12),
                              if (agentState.isExecuting)
                                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ref.watch(logsProvider).isEmpty 
                          ? Center(
                              child: Text(
                                agentState.isConnected ? 'Bridge active. Waiting for logs...' : 'Agent offline.',
                                style: const TextStyle(color: Colors.white24, fontSize: 12),
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
                                      Text('${log.timestamp} ', style: GoogleFonts.firaCode(fontSize: 10, color: Colors.white12)),
                                      Expanded(
                                        child: Text(
                                          log.message,
                                          style: GoogleFonts.firaCode(
                                            fontSize: 12,
                                            color: log.type == 'error' ? Colors.redAccent.withOpacity(0.7) : 
                                                   log.type == 'success' ? Colors.greenAccent.withOpacity(0.7) :
                                                   Colors.white60,
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

class _StatusDot extends StatelessWidget {
  final bool isConnected;
  const _StatusDot({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: isConnected ? Colors.green : Colors.red,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: (isConnected ? Colors.green : Colors.red).withOpacity(0.4),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    ).animate(onPlay: (c) => c.repeat()).fade(begin: 0.4, end: 1.0, duration: 800.ms);
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
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.quota.name.toLowerCase();
    final color = name.contains('claude') ? Colors.deepPurpleAccent : const Color(0xFF10B981);
    final percent = widget.quota.percent;

    return Container(
      width: 130,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.quota.name.split(' ')[0], 
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 9, letterSpacing: 0.5)),
              Text(_formatTime(_secondsLeft), style: const TextStyle(color: Colors.white12, fontSize: 8)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(1),
            child: LinearProgressIndicator(
              value: percent,
              backgroundColor: color.withOpacity(0.05),
              color: color.withOpacity(0.8),
              minHeight: 2,
            ),
          ),
        ],
      ),
    );
  }
}
