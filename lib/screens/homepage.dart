import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:undergrad_app/screens/friendlist.dart';
import 'package:undergrad_app/screens/login.dart';
import 'package:undergrad_app/screens/weather.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:undergrad_app/services/status_service.dart';
import 'package:undergrad_app/services/disaster_alert_service.dart';
import 'package:undergrad_app/services/background_service.dart';
import 'package:undergrad_app/screens/settings.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> with TickerProviderStateMixin {
  final user = FirebaseAuth.instance.currentUser;
  final DisasterAlertService _disasterService = DisasterAlertService();

  String _username = '';
  String _email = '';

  // Animations
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    setAppForeground(true); // tell background service app is open
    _disasterService.start();
    _loadUserData();
    StatusService().loadFromFirestore(); // sync local status with Firestore

    // Pulse animation for status circle
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Fade-in for the whole body
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();

    // Slide-up for the button area
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    _slideController.forward();
  }

  void _loadUserData() async {
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();

      if (doc.exists && mounted) {
        setState(() {
          _username = doc.data()?['username'] ?? '';
          _email = doc.data()?['email'] ?? user!.email ?? '';
        });
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  void _toggleStatus() async {
    final currentlySafe = StatusService().isSafe.value;
    final newSafe = !currentlySafe;

    // Use setManual so disaster detection knows this was a user override
    StatusService().setManual(newSafe);

    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user!.uid).set({
      'isSafe': newSafe,
      'lastStatusUpdate': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    Get.snackbar(
      newSafe ? "Marked Safe" : "Marked Not Safe",
      newSafe
          ? "Your friends can see you're okay"
          : "Your friends will be notified",
      snackPosition: SnackPosition.TOP,
      margin: const EdgeInsets.all(20),
      duration: const Duration(seconds: 2),
      backgroundColor: newSafe
          ? Colors.green.withValues(alpha: 0.9)
          : Colors.red.withValues(alpha: 0.9),
      colorText: Colors.white,
      borderRadius: 12,
      icon: Icon(
        newSafe ? Icons.shield : Icons.warning_amber_rounded,
        color: Colors.white,
      ),
    );
  }

  @override
  void dispose() {
    setAppForeground(false); // allow background service to resume notifications
    _pulseController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  signout() async {
    try {
      StatusService().reset(); // clear local status for next login
      _disasterService.stop(); // stop foreground disaster monitoring

      // Clear the stored UID so background service stops updating this user
      await saveUserUidForBackground('');

      await FirebaseAuth.instance.signOut();
      Get.offAll(() => const login());
    } catch (e) {
      Get.snackbar(
        "Logout Failed",
        e.toString(),
        snackPosition: SnackPosition.TOP,
        margin: const EdgeInsets.all(20),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          "Disaster Alert",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Obx(() {
        bool safe = StatusService().isSafe.value;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: safe
                  ? [const Color(0xFF0F2027), const Color(0xFF2C5364)]
                  : [const Color(0xFF3D0000), const Color(0xFF8B0000)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
                child: Column(
                  children: [
                    const Spacer(flex: 2),

                    // ─── Animated Status Circle ───
                    ScaleTransition(
                      scale: _pulseAnimation,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeInOut,
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: safe
                              ? Colors.green.withValues(alpha: 0.15)
                              : Colors.red.withValues(alpha: 0.15),
                          border: Border.all(
                            color: safe
                                ? Colors.greenAccent.withValues(alpha: 0.5)
                                : Colors.redAccent.withValues(alpha: 0.5),
                            width: 3,
                          ),
                        ),
                        child: Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 500),
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: safe
                                    ? [Colors.green, Colors.green.shade800]
                                    : [Colors.red, Colors.red.shade900],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: safe
                                      ? Colors.greenAccent
                                          .withValues(alpha: 0.4)
                                      : Colors.redAccent
                                          .withValues(alpha: 0.4),
                                  blurRadius: 30,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              transitionBuilder: (child, anim) =>
                                  ScaleTransition(scale: anim, child: child),
                              child: Icon(
                                safe
                                    ? Icons.check_rounded
                                    : Icons.warning_rounded,
                                key: ValueKey(safe),
                                size: 60,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ─── Status Text ───
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.2),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: Text(
                        safe ? "You are Safe" : "Not Safe",
                        key: ValueKey(safe),
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: Text(
                        safe
                            ? "No disasters detected in your area"
                            : "A disaster has been detected near you",
                        key: ValueKey("sub_$safe"),
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.white60,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    const Spacer(flex: 2),

                    // ─── Toggle Button ───
                    SlideTransition(
                      position: _slideAnimation,
                      child: Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 400),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: safe
                                        ? Colors.red.withValues(alpha: 0.3)
                                        : Colors.green.withValues(alpha: 0.3),
                                    blurRadius: 15,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: _toggleStatus,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      safe ? Colors.red.shade600 : Colors.green.shade600,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 18),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 0,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 300),
                                      transitionBuilder: (child, anim) =>
                                          RotationTransition(
                                        turns: anim,
                                        child: child,
                                      ),
                                      child: Icon(
                                        safe
                                            ? Icons.warning_amber_rounded
                                            : Icons.shield_rounded,
                                        key: ValueKey("btn_$safe"),
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      safe ? "I'm Not Safe" : "I'm Safe",
                                      style: GoogleFonts.poppins(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: Text(
                              safe
                                  ? "Tap if you're affected by a disaster"
                                  : "Tap when you're safe again",
                              key: ValueKey("hint_$safe"),
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.white38,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        );
      }),

      // ─── Redesigned Drawer ───
      drawer: _buildDrawer(isDark),
    );
  }

  Widget _buildDrawer(bool isDark) {
    return Drawer(
      backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // ─── Drawer Header ───
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 28),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F2027), Color(0xFF2C5364)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius:
                  BorderRadius.only(bottomRight: Radius.circular(40)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar with status ring
                Obx(() {
                  bool safe = StatusService().isSafe.value;
                  return Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: safe ? Colors.greenAccent : Colors.redAccent,
                        width: 2.5,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 32,
                      backgroundColor:
                          Colors.white.withValues(alpha: 0.15),
                      child: Text(
                        _username.isNotEmpty
                            ? _username[0].toUpperCase()
                            : "?",
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 16),
                Text(
                  _username.isNotEmpty ? _username : "User",
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _email,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.white60,
                  ),
                ),
                const SizedBox(height: 12),
                // Status badge
                Obx(() {
                  bool safe = StatusService().isSafe.value;
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: safe
                          ? Colors.greenAccent.withValues(alpha: 0.2)
                          : Colors.redAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: safe
                            ? Colors.greenAccent.withValues(alpha: 0.5)
                            : Colors.redAccent.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          safe ? Icons.check_circle : Icons.warning_rounded,
                          size: 14,
                          color: safe ? Colors.greenAccent : Colors.redAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          safe ? "Safe" : "Not Safe",
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: safe ? Colors.greenAccent : Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ─── Menu Items ───
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _buildDrawerItem(
                  icon: Icons.wb_sunny_rounded,
                  iconColor: Colors.orange,
                  title: "Weather",
                  subtitle: "Check local forecast",
                  onTap: () {
                    Navigator.pop(context);
                    Get.to(
                      () => const WeatherPage(),
                      transition: Transition.rightToLeftWithFade,
                      duration: const Duration(milliseconds: 300),
                    );
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.people_rounded,
                  iconColor: Colors.blue,
                  title: "Contacts",
                  subtitle: "Friends & safety status",
                  onTap: () {
                    Navigator.pop(context);
                    Get.to(
                      () => const FriendList(),
                      transition: Transition.rightToLeftWithFade,
                      duration: const Duration(milliseconds: 300),
                    );
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.settings_rounded,
                  iconColor: Colors.grey,
                  title: "Settings",
                  subtitle: "Account & appearance",
                  onTap: () async {
                    Navigator.pop(context);
                    await Get.to(
                      () => const SettingsPage(),
                      transition: Transition.rightToLeftWithFade,
                      duration: const Duration(milliseconds: 300),
                    );
                    _loadUserData();
                  },
                ),
              ],
            ),
          ),

          // ─── Logout at Bottom ───
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 30),
            child: _buildDrawerItem(
              icon: Icons.logout_rounded,
              iconColor: Colors.red,
              title: "Logout",
              subtitle: "Sign out of your account",
              onTap: signout,
              isDestructive: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: isDestructive ? Colors.red : null,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
