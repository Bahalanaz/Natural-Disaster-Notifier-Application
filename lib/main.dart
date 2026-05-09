import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:undergrad_app/Wrapper.dart';
import 'firebase_options.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:undergrad_app/services/background_service.dart';
import 'package:undergrad_app/services/notification_service.dart';
import 'package:undergrad_app/services/theme_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize notifications channel and background service config
  // (service only starts monitoring once a user UID is stored in SharedPreferences)
  await NotificationService().initialize();
  await initializeBackgroundService();

  // Only start the service if a user was previously logged in
  // (avoids showing the foreground notification on the login screen)
  final prefs = await SharedPreferences.getInstance();
  final savedUid = prefs.getString('background_uid') ?? '';
  if (savedUid.isNotEmpty) {
    await FlutterBackgroundService().startService();
  }

  // Initialize theme controller
  Get.put(ThemeController());

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Disaster Alert',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: const Wrapper(), // main entry point
    );
  }
}