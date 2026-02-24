import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'agent_provider.dart';

final pushNotificationProvider = Provider<PushNotificationService>((ref) {
  return PushNotificationService(ref);
});

class PushNotificationService {
  final Ref ref;

  PushNotificationService(this.ref);

  Future<void> initialize(BuildContext context) async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // Request permissions for iOS/Android 13+
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Subscribe to the 'all' topic for system-wide dings
    await messaging.subscribeToTopic('all');

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _handleMessage(message, context);
    });

    // Handle message open app
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleMessage(message, context);
    });
  }

  void _handleMessage(RemoteMessage message, BuildContext context) {
    if (message.data['type'] == 'approval_request') {
      final approvalId = message.data['approval_id'];
      _showApprovalDialog(
        context,
        message.notification?.title ?? 'Approval Required',
        message.notification?.body ?? 'The agent is requesting permission to proceed.',
        approvalId,
      );
    }
  }

  void _showApprovalDialog(BuildContext context, String title, String body, String approvalId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(agentProvider.notifier).respondToApproval(approvalId, false);
              Navigator.pop(context);
            },
            child: const Text('REJECT', style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(agentProvider.notifier).respondToApproval(approvalId, true);
              Navigator.pop(context);
            },
            child: const Text('ACCEPT'),
          ),
        ],
      ),
    );
  }
}
