import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

class StatusService {
  StatusService._privateConstructor();
  static final StatusService _instance = StatusService._privateConstructor();
  factory StatusService() => _instance;

  // Reactive safe/danger status
  final RxBool _isSafe = true.obs;
  bool _loaded = false;

  // Tracks whether the status was set by the disaster detection system
  // so we know the auto-revert is expected behavior
  bool _autoSet = false;

  // Real-time Firestore listener so background changes sync to foreground UI
  StreamSubscription<DocumentSnapshot>? _firestoreListener;

  // Getter
  RxBool get isSafe => _isSafe;

  /// Whether the current status was set automatically by disaster detection
  bool get isAutoSet => _autoSet;

  // Mark user as safe (called by disaster detection when no disasters found)
  void setSafe() {
    _autoSet = true;
    _isSafe.value = true;
  }

  // Mark user as in danger (called by disaster detection when disaster found)
  void setDanger() {
    _autoSet = true;
    _isSafe.value = false;
  }

  // Mark user as safe/danger manually (called by user toggle)
  void setManual(bool safe) {
    _autoSet = false;
    _isSafe.value = safe;
  }

  /// Load the user's actual safety status from Firestore
  /// and start a real-time listener for background service changes
  Future<void> loadFromFirestore() async {
    if (_loaded) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final data = doc.data();
        if (data != null && data.containsKey('isSafe')) {
          _isSafe.value = data['isSafe'] as bool;
        }
      }

      // Start real-time listener so background service changes
      // are reflected in the foreground UI immediately
      _startFirestoreListener(user.uid);

      _loaded = true;
    } catch (_) {
      // If Firestore fails, keep the default (safe)
    }
  }

  /// Listen for real-time Firestore changes (e.g. from background isolate)
  void _startFirestoreListener(String uid) {
    _firestoreListener?.cancel();
    _firestoreListener = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data();
        if (data != null && data.containsKey('isSafe')) {
          final firestoreSafe = data['isSafe'] as bool;
          // Only sync if value actually differs (avoid loops)
          if (_isSafe.value != firestoreSafe) {
            _autoSet = true; // came from system/background
            _isSafe.value = firestoreSafe;
          }
        }
      }
    });
  }

  /// Reset loaded flag (call on logout so next login reloads)
  void reset() {
    _firestoreListener?.cancel();
    _firestoreListener = null;
    _isSafe.value = true;
    _loaded = false;
    _autoSet = false;
  }
}