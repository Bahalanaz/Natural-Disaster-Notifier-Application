import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:undergrad_app/services/theme_controller.dart';
import 'package:undergrad_app/screens/login.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final user = FirebaseAuth.instance.currentUser;
  final themeController = ThemeController.to;

  String _username = '';
  String _email = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
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

  // ─── Change Username ───
  void _showChangeUsernameDialog() {
    final controller = TextEditingController(text: _username);

    Get.dialog(
      AlertDialog(
        title: const Text("Change Username"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: "Enter new username",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => _updateUsername(controller.text.trim()),
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _updateUsername(String newUsername) async {
    if (newUsername.isEmpty) {
      Get.snackbar("Error", "Username cannot be empty");
      return;
    }

    if (newUsername == _username) {
      Get.back();
      return;
    }

    // Check if username is already taken (case-insensitive)
    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('usernameLower', isEqualTo: newUsername.toLowerCase())
        .get();

    if (query.docs.isNotEmpty) {
      Get.snackbar("Error", "Username already taken");
      return;
    }

    await FirebaseFirestore.instance.collection('users').doc(user!.uid).update({
      'username': newUsername,
      'usernameLower': newUsername.toLowerCase(),
    });

    setState(() => _username = newUsername);
    Get.back();
    Get.snackbar("Success", "Username updated to $newUsername");
  }

  // ─── Change Password ───
  void _showChangePasswordDialog() {
    final currentPassController = TextEditingController();
    final newPassController = TextEditingController();
    final confirmPassController = TextEditingController();

    Get.dialog(
      AlertDialog(
        title: const Text("Change Password"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentPassController,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: "Current password",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newPassController,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: "New password",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPassController,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: "Confirm new password",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => _updatePassword(
              currentPassController.text,
              newPassController.text,
              confirmPassController.text,
            ),
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _updatePassword(String current, String newPass, String confirm) async {
    if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
      Get.snackbar("Error", "Please fill all fields");
      return;
    }

    if (newPass != confirm) {
      Get.snackbar("Error", "New passwords don't match");
      return;
    }

    if (newPass.length < 6) {
      Get.snackbar("Error", "Password must be at least 6 characters");
      return;
    }

    final email = user?.email;
    if (user == null || email == null) {
      Get.snackbar("Error", "No user session found");
      return;
    }

    try {
      // Re-authenticate first
      final credential = EmailAuthProvider.credential(
        email: email,
        password: current,
      );
      await user!.reauthenticateWithCredential(credential);

      // Update password
      await user!.updatePassword(newPass);
      Get.back();
      Get.snackbar("Success", "Password updated successfully");
    } on FirebaseAuthException catch (e) {
      Get.snackbar("Error", e.message ?? "Failed to update password");
    } catch (e) {
      Get.snackbar("Error", e.toString());
    }
  }

  // ─── Delete Account ───
  void _showDeleteAccountDialog() {
    final passController = TextEditingController();

    Get.dialog(
      AlertDialog(
        title: const Text("Delete Account"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "This will permanently delete your account and all your data. This action cannot be undone.",
              style: TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passController,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: "Enter your password to confirm",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => _deleteAccount(passController.text),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _deleteAccount(String password) async {
    if (password.isEmpty) {
      Get.snackbar("Error", "Please enter your password");
      return;
    }

    final email = user?.email;
    if (user == null || email == null) {
      Get.snackbar("Error", "No user session found");
      return;
    }

    try {
      // Re-authenticate
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await user!.reauthenticateWithCredential(credential);

      final uid = user!.uid;

      // 1. Remove from all friends' connections
      final friendsDoc = await FirebaseFirestore.instance
          .collection('friends')
          .doc(uid)
          .get();

      if (friendsDoc.exists) {
        List connections = friendsDoc.data()?['connections'] ?? [];
        for (String friendUid in connections) {
          try {
            await FirebaseFirestore.instance
                .collection('friends')
                .doc(friendUid)
                .update({
              'connections': FieldValue.arrayRemove([uid])
            });
          } catch (_) {}
        }

        // Delete own friends doc
        await FirebaseFirestore.instance.collection('friends').doc(uid).delete();
      }

      // 2. Delete all friend requests sent or received
      final sentRequests = await FirebaseFirestore.instance
          .collection('friend_requests')
          .where('from', isEqualTo: uid)
          .get();
      final receivedRequests = await FirebaseFirestore.instance
          .collection('friend_requests')
          .where('to', isEqualTo: uid)
          .get();

      for (var doc in sentRequests.docs) {
        await doc.reference.delete();
      }
      for (var doc in receivedRequests.docs) {
        await doc.reference.delete();
      }

      // 3. Delete user document
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();

      // 4. Delete Firebase Auth account
      await user!.delete();

      Get.offAll(() => const login());
      Get.snackbar("Account Deleted", "Your account has been permanently deleted");
    } on FirebaseAuthException catch (e) {
      Get.snackbar("Error", e.message ?? "Failed to delete account");
    } catch (e) {
      Get.snackbar("Error", e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Settings", style: GoogleFonts.poppins()),
      ),
      body: ListView(
        children: [
          // ─── Profile Section ───
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              "PROFILE",
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text("Username"),
            subtitle: Text(_username),
            trailing: const Icon(Icons.edit, size: 20),
            onTap: _showChangeUsernameDialog,
          ),
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text("Email"),
            subtitle: Text(_email),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text("Change Password"),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showChangePasswordDialog,
          ),

          const Divider(),

          // ─── Appearance Section ───
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              "APPEARANCE",
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          Obx(() => SwitchListTile(
                secondary: Icon(
                  themeController.isDarkMode.value
                      ? Icons.dark_mode
                      : Icons.light_mode,
                ),
                title: const Text("Dark Mode"),
                subtitle: Text(
                  themeController.isDarkMode.value ? "On" : "Off",
                ),
                value: themeController.isDarkMode.value,
                onChanged: (_) => themeController.toggleTheme(),
              )),

          const Divider(),

          // ─── About Section ───
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              "ABOUT",
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text("App Version"),
            subtitle: const Text("1.0.0"),
          ),

          const Divider(),

          // ─── Danger Zone ───
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              "DANGER ZONE",
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.red,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text(
              "Delete Account",
              style: TextStyle(color: Colors.red),
            ),
            subtitle: const Text("Permanently delete your account and data"),
            onTap: _showDeleteAccountDialog,
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
