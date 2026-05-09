import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:undergrad_app/screens/login.dart';
import 'package:undergrad_app/screens/askpermission.dart';

class verify extends StatefulWidget {
  const verify({super.key});

  @override
  State<verify> createState() => _verifyState();
}

class _verifyState extends State<verify> {
  Timer? _countdownTimer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final creationTime = user.metadata.creationTime;
    if (creationTime == null) return;

    final deadline = creationTime.add(const Duration(minutes: 15));
    final remaining = deadline.difference(DateTime.now()).inSeconds;

    if (remaining <= 0) {
      _autoDeleteAccount();
      return;
    }

    setState(() => _secondsLeft = remaining);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        _countdownTimer?.cancel();
        _autoDeleteAccount();
      }
    });
  }

  Future<void> _autoDeleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Get.offAll(() => const login());
      return;
    }

    try {
      final uid = user.uid;
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).delete();
      } catch (_) {}
      await user.delete();
    } catch (_) {
      await FirebaseAuth.instance.signOut();
    }

    Get.offAll(() => const login());
    Get.snackbar(
      "Session Expired",
      "Account deleted — email not verified within 15 minutes. Please sign up again.",
      snackPosition: SnackPosition.TOP,
      duration: const Duration(seconds: 5),
    );
  }

  // Send verification email
  sendverifylink() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Get.snackbar("Error", "No user session found. Please log in again.",
          snackPosition: SnackPosition.TOP);
      return;
    }
    await user.sendEmailVerification();
    Get.snackbar(
      "Link Sent",
      "Verification link sent to your email",
      snackPosition: SnackPosition.TOP,
    );
  }

  // Reload user and check verification
  reload() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Get.snackbar("Error", "No user session found. Please log in again.",
          snackPosition: SnackPosition.TOP);
      return;
    }

    try {
      await user.reload();
    } catch (e) {
      Get.snackbar("Error", "Could not verify. Check your connection.",
          snackPosition: SnackPosition.TOP);
      return;
    }

    // Re-fetch after reload to get updated emailVerified
    final refreshedUser = FirebaseAuth.instance.currentUser;
    if (refreshedUser != null && refreshedUser.emailVerified) {
      _countdownTimer?.cancel();
      Get.offAll(() => const AskPermissionPage());
    } else {
      Get.snackbar(
        "Not verified",
        "Email is still not verified",
        snackPosition: SnackPosition.TOP,
      );
    }
  }

  String _formatTime(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Email Verification"),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.exit_to_app),
          onPressed: () async {
            await FirebaseAuth.instance.signOut();
            Get.offAll(() => const login());
          },
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF2A5298), Color(0xFF2A5298)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Container(
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 35,
                      backgroundColor: Colors.blue,
                      child: Icon(Icons.email_outlined,
                          size: 40, color: Colors.white),
                    ),
                    const SizedBox(height: 25),
                    Text(
                      "Verify your email to continue",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _secondsLeft > 0
                          ? "Time remaining: ${_formatTime(_secondsLeft)}"
                          : "Time expired",
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: _secondsLeft <= 120 ? Colors.red : Colors.grey[600],
                        fontWeight: _secondsLeft <= 120
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: reload,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          "Check Verification",
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: sendverifylink,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          "Send Verification Email",
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}