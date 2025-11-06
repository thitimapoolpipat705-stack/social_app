import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'notification_service.dart';

/// Handles Firebase Cloud Messaging token lifecycle and foreground handlers.
class MessagingService {
  MessagingService._();
  static final instance = MessagingService._();

  final _messaging = FirebaseMessaging.instance;
  final _db = FirebaseFirestore.instance;

  String? _currentToken;
  String? _currentUid;

  Future<void> init() async {
    // Request permissions (iOS)
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      log('FCM permission: $settings');
    } catch (e) {
      log('FCM permission request failed: $e');
    }

    // Handle initial token and refreshes
    try {
      final token = await _messaging.getToken();
      _currentToken = token;
      if (token != null) await _saveTokenForCurrentUser(token);
      _messaging.onTokenRefresh.listen((t) async {
        log('FCM token refreshed: $t');
        _currentToken = t;
        await _saveTokenForCurrentUser(t);
      });
    } catch (e) {
      log('Failed to obtain FCM token: $e');
    }

    // Listen to auth changes so we can attach/detach token to user doc
    FirebaseAuth.instance.userChanges().listen((user) async {
      final prev = _currentUid;
      _currentUid = user?.uid;
      // If token exists, move it to the new user's doc
      if (_currentToken != null) {
        if (prev != null && prev != _currentUid) {
          await _removeToken(prev, _currentToken!);
        }
        if (_currentUid != null) {
          await _saveToken(_currentUid!, _currentToken!);
        }
      }
    });

    // Foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      log('FCM onMessage: ${message.messageId} ${message.notification} ${message.data}');
      // Create an in-app notification entry so it appears in the app's notifications UI
      final data = message.data;
      try {
        final fromUid = data['fromUid'] as String?;
        final title = message.notification?.title ?? data['title'] as String?;
        final body = message.notification?.body ?? data['body'] as String?;
        if (_currentUid != null) {
          NotificationService.instance.createNotification(
            targetUid: _currentUid!,
            type: data['type'] ?? 'chat',
            title: title,
            body: body,
            fromUid: fromUid,
            extra: {'data': data},
          );
        }
      } catch (e) {
        log('Failed to create in-app notification from FCM: $e');
      }
    });

    // Handle when user taps notification and opens the app
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      log('FCM onMessageOpenedApp: ${message.messageId} ${message.data}');
      // Optionally handle deep link/navigation here by writing logic in the app
    });
  }

  Future<void> _saveTokenForCurrentUser(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _saveToken(uid, token);
  }

  Future<void> _saveToken(String uid, String token) async {
    try {
      final uRef = _db.collection('users').doc(uid);
      await uRef.set({'fcmTokens': FieldValue.arrayUnion([token])}, SetOptions(merge: true));
      log('Saved FCM token for $uid');
    } catch (e) {
      log('Failed to save token to Firestore: $e');
    }
  }

  Future<void> _removeToken(String uid, String token) async {
    try {
      final uRef = _db.collection('users').doc(uid);
      await uRef.update({'fcmTokens': FieldValue.arrayRemove([token])});
      log('Removed FCM token for $uid');
    } catch (e) {
      log('Failed to remove token from Firestore (might be missing): $e');
    }
  }
}

/// Background message handler must be a top-level function
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Note: avoid heavy operations here. We log the message and optionally write
  // a small notification doc if needed by your design.
  log('FCM background message: ${message.messageId} ${message.data}');
}
