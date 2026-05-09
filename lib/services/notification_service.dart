import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._privateConstructor();
  static final NotificationService _instance =
      NotificationService._privateConstructor();
  factory NotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(settings: initSettings);
    _initialized = true;
  }

  Future<void> showDisasterAlert({
    required String disasterType,
    required double distance,
    required int riskScore,
    required String hotline,
    required String country,
  }) async {
    final safetyTip = getSafetyTip(disasterType);

    final androidDetails = AndroidNotificationDetails(
      'disaster_alerts',
      'Disaster Alerts',
      channelDescription: 'Notifications for nearby disaster alerts',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      ongoing: false,
      styleInformation: BigTextStyleInformation(
        '${distance.toStringAsFixed(1)} km away | Severity: $riskScore%\n\n'
        '$safetyTip\n\n'
        '$hotline',
        contentTitle: '🚨 ${disasterType.toUpperCase()} ALERT',
      ),
    );

    final details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      id: 0,
      title: '🚨 ${disasterType.toUpperCase()} ALERT — $country',
      body: '${distance.toStringAsFixed(1)} km away | $safetyTip',
      notificationDetails: details,
    );
  }

  /// Safety instructions based on disaster type
  static String getSafetyTip(String disasterType) {
    switch (disasterType.toLowerCase()) {
      case 'earthquake':
        return 'DROP, COVER, and HOLD ON. Stay away from windows and heavy objects. If indoors, stay inside. If outdoors, move to an open area.';
      case 'flood':
        return 'Move to higher ground immediately. Do NOT walk or drive through floodwater. 15cm of moving water can knock you down.';
      case 'wildfire':
        return 'Evacuate immediately if ordered. Close all windows and doors. Wear a mask or wet cloth over your nose and mouth.';
      case 'storm':
        return 'Stay indoors away from windows. Unplug electronics. If outdoors, avoid trees and metal structures. Do not use elevators.';
      case 'cyclone':
      case 'typhoon':
        return 'Move to the strongest part of the building. Stay away from windows and doors. Secure loose objects. Do NOT go outside until authorities say it is safe.';
      case 'thunderstorm':
        return 'Go indoors immediately. Stay away from windows, water, and metal objects. Unplug electronics. If caught outside, avoid open fields and tall trees.';
      case 'tsunami':
        return 'Move inland and to higher ground immediately. Do NOT wait to see the wave. Stay away from the coast until authorities say it is safe.';
      case 'volcano':
        return 'Evacuate immediately if ordered. Avoid river valleys and low-lying areas. Wear a mask to protect from ash. Stay indoors if possible.';
      case 'tornado':
        return 'Go to a basement or interior room on the lowest floor. Cover yourself with blankets or a mattress. Stay away from windows.';
      case 'landslide':
        return 'Move away from the path of the slide. Avoid river valleys and low areas. If near a stream, be alert for sudden changes in water level.';
      case 'drought':
        return 'Conserve water. Follow local water restrictions. Avoid outdoor burning. Check on elderly and vulnerable neighbors.';
      default:
        return 'Stay alert. Follow local authority instructions. Have an emergency kit ready. Move to safety if directed.';
    }
  }
}
