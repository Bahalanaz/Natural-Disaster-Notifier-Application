import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:undergrad_app/screens/login.dart';

class forgot extends StatefulWidget {
  const forgot({super.key});

  @override
  State<forgot> createState() => _forgotState();
}

class _forgotState extends State<forgot> {
  TextEditingController email = TextEditingController();

  bool isLoading = false;

  reset() async {
    String mail = email.text.trim();

    if (mail.isEmpty) {
      Get.snackbar("Error", "Please enter your email",
          snackPosition: SnackPosition.TOP,
          margin: const EdgeInsets.all(20));
      return;
    }

    setState(() => isLoading = true);

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: mail)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        Get.snackbar(
          "Error",
          "No account found with this email address",
          snackPosition: SnackPosition.TOP,
          margin: const EdgeInsets.all(20),
          backgroundColor: Colors.red[100],
          colorText: Colors.red[900],
        );
        setState(() => isLoading = false);
        return;
      }

      await FirebaseAuth.instance.sendPasswordResetEmail(email: mail);
      Get.snackbar(
        "Email Sent",
        "Password reset link has been sent",
        snackPosition: SnackPosition.TOP,
        margin: const EdgeInsets.all(20),
        backgroundColor: Colors.green[100],
        colorText: Colors.green[900],
      );
    } on FirebaseAuthException catch (e) {
      Get.snackbar("Error", e.message ?? "Failed to send reset email",
          snackPosition: SnackPosition.TOP,
          margin: const EdgeInsets.all(20));
    } catch (e) {
      Get.snackbar("Error", e.toString(),
          snackPosition: SnackPosition.TOP,
          margin: const EdgeInsets.all(20));
    }

    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF2A5298),
              Color(0xFF2A5298),
            ],
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

                // TITLE
                Text(
                  "Reset Password",
                  style: GoogleFonts.poppins(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "We’ll send you a reset link",
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 50),

                // CARD
                Container(
                  padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ICON
                      CircleAvatar(
                        radius: 35,
                        backgroundColor: Colors.orange[100],
                        child: const Icon(
                          Icons.email_outlined,
                          size: 35,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(height: 25),

                      // EMAIL FIELD
                      TextField(
                        controller: email,
                        style: GoogleFonts.poppins(color: Colors.black87),
                        decoration: InputDecoration(
                          hintText: "Enter your email",
                          hintStyle: GoogleFonts.poppins(color: Colors.black54),
                          prefixIcon: const Icon(Icons.email_outlined, color: Colors.black54),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: const BorderSide(
                              color: Colors.grey,
                              width: 2,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: const BorderSide(
                              color: Colors.grey,
                              width: 2,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: const BorderSide(
                              color: Colors.orange, // purple highlight
                              width: 2.5,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 15, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 25),

                      // SEND LINK BUTTON
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: isLoading ? null : () => reset(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            textStyle: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text("Send Reset Link",
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  )),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // BACK TO LOGIN BUTTON
                TextButton(
                  onPressed: () => Get.offAll(() => const login()),
                  child: Text(
                    "Back to Login",
                    style: GoogleFonts.poppins(color: Colors.white),
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