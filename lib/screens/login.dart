import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:undergrad_app/screens/askpermission.dart';
import 'package:undergrad_app/screens/forgot.dart';
import 'package:undergrad_app/screens/signup.dart';
import 'package:undergrad_app/screens/verifyemail.dart';

class login extends StatefulWidget {
  const login({super.key});

  @override
  State<login> createState() => _loginState();
}

class _loginState extends State<login> {
  TextEditingController email = TextEditingController();
  TextEditingController password = TextEditingController();
  bool isloading = false;

  LOGIN() async {
    setState(() {
      isloading = true;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.text.trim(),
        password: password.text.trim(),
      );

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Get.snackbar("Error", "Login failed. Please try again.");
        return;
      }

      if (user.emailVerified) {
        Get.offAll(() => const AskPermissionPage());
      } else {
        // Check if unverified account is older than 15 minutes
        final creationTime = user.metadata.creationTime;
        if (creationTime != null) {
          final age = DateTime.now().difference(creationTime);
          if (age.inMinutes >= 15) {
            // Auto-delete expired unverified account
            final uid = user.uid;
            try {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .delete();
            } catch (_) {}
            try {
              await user.delete();
            } catch (_) {
              await FirebaseAuth.instance.signOut();
            }
            Get.snackbar(
              "Account Expired",
              "This unverified account has expired. Please sign up again.",
              duration: const Duration(seconds: 5),
            );
            return;
          }
        }
        Get.to(() => const verify());
      }
    } on FirebaseAuthException catch (e) {
      Get.snackbar("Error", e.message ?? e.code);
    } catch (e) {
      Get.snackbar("Error", e.toString());
    }

    if (mounted) {
      setState(() {
        isloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return isloading
        ? const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          )
        : Scaffold(
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              automaticallyImplyLeading: false,
              elevation: 0,
              backgroundColor: Colors.transparent,
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
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      const SizedBox(height: 60),
                      Text("Disaster Alert",
                          style: GoogleFonts.poppins(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      const SizedBox(height: 10),
                      Text("Stay safe. Stay informed.",
                          style: GoogleFonts.poppins(
                              fontSize: 14, color: Colors.white70)),
                      const SizedBox(height: 50),
                      Container(
                        padding: const EdgeInsets.all(25),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 20,
                                offset: const Offset(0, 10))
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 35,
                              backgroundColor: Colors.orange[100],
                              child: const Icon(Icons.warning_amber_rounded,
                                  size: 40, color: Colors.orange),
                            ),
                            const SizedBox(height: 25),
                            TextField(
                              style: const TextStyle(color: Colors.black87),
                              controller: email,
                              decoration: InputDecoration(
                                hintText: "Email",
                                hintStyle: const TextStyle(color: Colors.black54),
                                prefixIcon: const Icon(Icons.email_outlined, color: Colors.black54),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              style: const TextStyle(color: Colors.black87),
                              controller: password,
                              obscureText: true,
                              decoration: InputDecoration(
                                hintText: "Password",
                                hintStyle: const TextStyle(color: Colors.black54),
                                prefixIcon: const Icon(Icons.lock_outline, color: Colors.black54),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                            ),
                            const SizedBox(height: 25),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: LOGIN,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                ),
                                child: Text("Login",
                                    style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white)),
                              ),
                            ),
                            const SizedBox(height: 15),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () => Get.to(const Signup()),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                ),
                                child: Text("Register",
                                    style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextButton(
                        onPressed: () => Get.to(const forgot()),
                        child: Text("Forgot password?",
                            style: GoogleFonts.poppins(color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
            ), 
          );
  }
}