import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:undergrad_app/screens/askpermission.dart';
import 'package:undergrad_app/screens/homepage.dart';
import 'package:undergrad_app/screens/login.dart';
import 'package:undergrad_app/screens/verifyemail.dart';
import 'package:undergrad_app/services/background_service.dart';

class Wrapper extends StatefulWidget {
  const Wrapper({super.key});

  @override
  State<Wrapper> createState() => _WrapperState();
}

class _WrapperState extends State<Wrapper> {
  bool _loading = true;
  User? _user;
  bool _hasAllPermissions = false;
  late final _authListener;

  @override
  void initState() {
    super.initState();

    // Listen for login/logout events
    _authListener = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        try {
          await user.reload();
        } catch (_) {
          // User may have been deleted — treat as logged out
          if (mounted) {
            setState(() {
              _user = null;
              _loading = false;
            });
          }
          return;
        }
        user = FirebaseAuth.instance.currentUser;

        if (user != null) {
          // Save UID and start background service on first login
          await saveUserUidForBackground(user.uid);
          final bgService = FlutterBackgroundService();
          if (!(await bgService.isRunning())) {
            await bgService.startService();
          }

          // Only check permissions after user is logged in and verified
          if (user.emailVerified) {
            await _checkPermissions();
          }
        }
      }

      if (mounted) {
        setState(() {
          _user = user;
          _loading = false;
        });
      }
    });

    _checkUser(); // initial check
  }

  Future<void> _checkPermissions() async {
    final locationPerm = await Geolocator.checkPermission();
    final notifPerm = await Permission.notification.status;

    if (mounted) {
      setState(() {
        _hasAllPermissions =
            locationPerm == LocationPermission.always &&
            notifPerm.isGranted;
      });
    }
  }

  _checkUser() async {
    User? user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      try {
        await user.reload();
      } catch (_) {
        // User may have been deleted
        if (mounted) {
          setState(() {
            _user = null;
            _loading = false;
          });
        }
        return;
      }
      user = FirebaseAuth.instance.currentUser;

      if (user != null && user.emailVerified) {
        await _checkPermissions();
      }
    }

    if (mounted) {
      setState(() {
        _user = user;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _authListener.cancel(); 
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_user == null) {
      return const login();
    }

    if (_user!.emailVerified) {
      if (!_hasAllPermissions) {
        return const AskPermissionPage();
      }
      return const Homepage();
    }

    return const verify();
  }
}