import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'homepage.dart';

class AskPermissionPage extends StatefulWidget {
  const AskPermissionPage({super.key});

  @override
  State<AskPermissionPage> createState() => _AskPermissionPageState();
}

class _AskPermissionPageState extends State<AskPermissionPage>
    with WidgetsBindingObserver {
  bool _locationGranted = false;
  bool _backgroundGranted = false;
  bool _notificationGranted = false;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  Future<void> _refreshStatus() async {
    final locationPerm = await Geolocator.checkPermission();
    final notifPerm = await Permission.notification.status;

    if (!mounted) return;

    setState(() {
      _locationGranted = locationPerm == LocationPermission.whileInUse ||
          locationPerm == LocationPermission.always;
      _backgroundGranted = locationPerm == LocationPermission.always;
      _notificationGranted = notifPerm.isGranted;
    });

    // All granted — go to homepage
    if (_backgroundGranted && _notificationGranted) {
      Get.offAll(() => const Homepage());
    }
  }

  Future<void> _requestAllPermissions() async {
    setState(() => _requesting = true);

    // GPS check
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      Get.snackbar("GPS Disabled", "Please turn on your GPS first",
          snackPosition: SnackPosition.TOP);
      setState(() => _requesting = false);
      return;
    }

    //  Location "while using"
    LocationPermission locationPerm = await Geolocator.checkPermission();
    if (locationPerm == LocationPermission.denied) {
      locationPerm = await Geolocator.requestPermission();
    }
    if (locationPerm == LocationPermission.deniedForever) {
      _showSettingsSnackbar("Location");
      setState(() => _requesting = false);
      await _refreshStatus();
      return;
    }

    // Background location "all the time"
    if (locationPerm != LocationPermission.always) {
      final bgStatus = await Permission.locationAlways.request();
      if (!bgStatus.isGranted) {
        setState(() => _requesting = false);
        await _refreshStatus();
        return;
      }
    }

    //  Notifications
    final notifStatus = await Permission.notification.request();
    if (!notifStatus.isGranted) {
      setState(() => _requesting = false);
      await _refreshStatus();
      return;
    }

    setState(() => _requesting = false);
    Get.offAll(() => const Homepage());
  }

  void _showSettingsSnackbar(String permission) {
    Get.snackbar(
      "$permission Blocked",
      "Tap 'Open Settings' to enable it manually",
      snackPosition: SnackPosition.TOP,
      duration: const Duration(seconds: 3),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E3C72), Color(0xFF2A5298)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Shield icon
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    size: 50,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),

                Text(
                  "Stay Protected",
                  style: GoogleFonts.poppins(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "We need a few permissions to keep you safe from nearby disasters.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),

                const Spacer(),

                // Permission status cards
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      _buildPermissionRow(
                        icon: Icons.location_on_outlined,
                        title: "Location Access",
                        subtitle: "Detect your position",
                        granted: _locationGranted,
                      ),
                      const Divider(height: 24),
                      _buildPermissionRow(
                        icon: Icons.all_inclusive,
                        title: "Background Location",
                        subtitle: "Monitor even when app is closed",
                        granted: _backgroundGranted,
                      ),
                      const Divider(height: 24),
                      _buildPermissionRow(
                        icon: Icons.notifications_outlined,
                        title: "Notifications",
                        subtitle: "Receive disaster alerts",
                        granted: _notificationGranted,
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Grant button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _requesting ? null : _requestAllPermissions,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1E3C72),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _requesting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            "Grant Permissions",
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),

                // Open settings link
                TextButton.icon(
                  onPressed: () => openAppSettings(),
                  icon: const Icon(Icons.settings, size: 18, color: Colors.white54),
                  label: Text(
                    "Open Settings",
                    style: GoogleFonts.poppins(
                      color: Colors.white54,
                      fontSize: 13,
                    ),
                  ),
                ),

                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool granted,
  }) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: granted
                ? Colors.green.withOpacity(0.1)
                : Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: granted ? Colors.green : Colors.grey,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
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
        Icon(
          granted ? Icons.check_circle : Icons.circle_outlined,
          color: granted ? Colors.green : Colors.grey.shade300,
          size: 24,
        ),
      ],
    );
  }
}
