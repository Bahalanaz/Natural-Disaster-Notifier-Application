import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:undergrad_app/screens/verifyemail.dart';
import 'package:undergrad_app/screens/login.dart';

class Signup extends StatefulWidget {
  const Signup({super.key});

  @override
  State<Signup> createState() => _SigninState();
}

class _SigninState extends State<Signup> {
  TextEditingController username = TextEditingController();
  TextEditingController email = TextEditingController();
  TextEditingController password = TextEditingController();
  bool isloading = false;

  signup() async {
    if (isloading) return;

    String uname = username.text.trim();
    String mail = email.text.trim();
    String pass = password.text.trim();

    if (uname.isEmpty || mail.isEmpty || pass.isEmpty) {
      Get.snackbar("Error", "Please fill all fields");
      return;
    }

    if (pass.length < 6) {
      Get.snackbar("Error", "Password must be at least 6 characters");
      return;
    }

    setState(() => isloading = true);

    try {
      // Check if username is already taken (case-insensitive)
      final usernameQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('usernameLower', isEqualTo: uname.toLowerCase())
          .get();

      if (usernameQuery.docs.isNotEmpty) {
        Get.snackbar("Error", "Username already taken");
        return;
      }

      // Try to create the Auth account
      UserCredential userCred;
      try {
        userCred = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: mail, password: pass);
      } on FirebaseAuthException catch (e) {
        // If email is taken, check if it's an old unverified account we can recycle
        if (e.code == 'email-already-in-use') {
          final cleaned = await _tryCleanUnverifiedAccount(mail, pass);
          if (cleaned) {
            // Old unverified account deleted — retry signup
            userCred = await FirebaseAuth.instance
                .createUserWithEmailAndPassword(email: mail, password: pass);
          } else {
            Get.snackbar("Error", "Email is already in use by a verified account");
            return;
          }
        } else {
          Get.snackbar("Signup error", e.message ?? e.code);
          return;
        }
      }

      String uid = userCred.user!.uid;

      // Store user info in Firestore
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'username': uname,
          'usernameLower': uname.toLowerCase(),
          'email': mail,
          'isSafe': true,
          'lastStatusUpdate': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        // Firestore write failed — delete the Auth account so email isn't stuck
        await userCred.user?.delete();
        Get.snackbar("Error", "Account creation failed. Please try again.");
        return;
      }

      Get.offAll(() => const verify());
    } on FirebaseAuthException catch (e) {
      Get.snackbar("Signup error", e.message ?? e.code);
    } catch (e) {
      Get.snackbar("Error", e.toString());
    } finally {
      if (mounted) setState(() => isloading = false);
    }
  }

  /// Try to sign into an existing account with the same email.
  /// If it's unverified and old (>15 min), delete it so the email can be reused.
  Future<bool> _tryCleanUnverifiedAccount(String mail, String pass) async {
    try {
      // Try signing in with the same credentials
      final cred = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: mail, password: pass);
      final user = cred.user;

      if (user != null && !user.emailVerified) {
        // Check how old the account is
        final creationTime = user.metadata.creationTime;
        if (creationTime != null) {
          final age = DateTime.now().difference(creationTime);
          if (age.inMinutes >= 15) {
            // Old unverified account — delete it
            final uid = user.uid;
            try {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .delete();
            } catch (_) {}
            await user.delete();
            return true;
          }
        }
      }

      // Either verified or too new — sign out and don't delete
      await FirebaseAuth.instance.signOut();
      return false;
    } catch (_) {
      // Can't sign in (wrong password or other error) — can't clean it up
      return false;
    }
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
                  "Create Account",
                  style: GoogleFonts.poppins(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "Register to receive alerts",
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
                          Icons.person_add_alt_1,
                          size: 35,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(height: 25),

                      // USERNAME
                      TextField(
                        controller: username,
                        style: GoogleFonts.poppins(color: Colors.black87),
                        decoration: InputDecoration(
                          hintText: "Username",
                          hintStyle: GoogleFonts.poppins(color: Colors.black54),
                          prefixIcon: const Icon(Icons.person, color: Colors.black54),
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
                              color: Colors.orange,
                              width: 2.5,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 15, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // EMAIL
                      TextField(
                        controller: email,
                        style: GoogleFonts.poppins(color: Colors.black87),
                        decoration: InputDecoration(
                          hintText: "Email",
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
                              color: Colors.orange,
                              width: 2.5,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 15, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // PASSWORD
                      TextField(
                        controller: password,
                        obscureText: true,
                        style: GoogleFonts.poppins(color: Colors.black87),
                        decoration: InputDecoration(
                          hintText: "Password",
                          hintStyle: GoogleFonts.poppins(color: Colors.black54),
                          prefixIcon: const Icon(Icons.lock_outline, color: Colors.black54),
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
                              color: Colors.orange,
                              width: 2.5,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 15, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 25),

                      // SIGNUP BUTTON
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: isloading ? null : () => signup(),
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
                          child: isloading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  "Sign Up",
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // BACK TO LOGIN
                TextButton(
                  onPressed: () => Get.offAll(() => const login()),
                  child: Text(
                    "Already have an account? Login",
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
