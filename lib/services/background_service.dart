import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:undergrad_app/firebase_options.dart';

/// Initialize and configure the background service
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  const androidChannel = AndroidNotificationChannel(
    'disaster_foreground',
    'Disaster Monitoring',
    description: 'Keeps the disaster monitoring service running',
    importance: Importance.low,
  );

  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(androidChannel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      autoStartOnBoot: true,
      isForegroundMode: true,
      notificationChannelId: 'disaster_foreground',
      initialNotificationTitle: 'Disaster Alert',
      initialNotificationContent: 'Monitoring for nearby disasters...',
      foregroundServiceNotificationId: 888,
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

/// Save user UID so background isolate can access it
Future<void> saveUserUidForBackground(String uid) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('background_uid', uid);
}

/// Call when app comes to foreground — prevents background service sending duplicate alerts
Future<void> setAppForeground(bool isForeground) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('app_in_foreground', isForeground);
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {}

  final notificationsPlugin = FlutterLocalNotificationsPlugin();
  const androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidSettings);
  await notificationsPlugin.initialize(settings: initSettings);

  const alertChannel = AndroidNotificationChannel(
    'disaster_alerts',
    'Disaster Alerts',
    description: 'Notifications for nearby disaster alerts',
    importance: Importance.max,
  );
  await notificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(alertChannel);

  await _loadHotlines();

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  final lastAlertTimestamp = [0];

  Timer.periodic(const Duration(minutes: 10), (timer) async {
    await _performDisasterCheck(
      notificationsPlugin,
      lastAlertTimestamp,
      service,
    );
  });

  await _performDisasterCheck(
    notificationsPlugin,
    lastAlertTimestamp,
    service,
  );
}

Future<String?> _getCurrentUid() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getString('background_uid');
  } catch (_) {
    return null;
  }
}

Future<void> _updateFirestoreStatusBackground(String? uid, bool isSafe) async {
  if (uid == null || uid.isEmpty) return;
  try {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'isSafe': isSafe,
      'lastStatusUpdate': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  } catch (e) {
    debugPrint('Background Firestore update error: $e');
  }
}

void _updateForegroundNotification(ServiceInstance service, String status) {
  if (service is AndroidServiceInstance) {
    final now = DateTime.now();
    final time = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    service.setForegroundNotificationInfo(
      title: 'Disaster Alert',
      content: '$status | Last checked: $time',
    );
  }
}

/// The core disaster check — fetches from USGS + EONET APIs
Future<void> _performDisasterCheck(
  FlutterLocalNotificationsPlugin notificationsPlugin,
  List<int> lastAlertTimestamp,
  ServiceInstance service,
) async {
  try {
    final userUid = await _getCurrentUid();

    // Skip entire check if no user is logged in (saves battery)
    if (userUid == null || userUid.isEmpty) {
      debugPrint('Background: No user logged in, skipping check');
      _updateForegroundNotification(service, 'Waiting for login');
      return;
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('Background: Location services disabled');
      _updateForegroundNotification(service, 'GPS disabled');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      debugPrint('Background: Location permission revoked');
      _updateForegroundNotification(service, 'No location permission');
      return;
    }

    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 30));
    } catch (e) {
      debugPrint('Background: Could not get location: $e');
      _updateForegroundNotification(service, 'Location unavailable');
      return;
    }

    double userLat = position.latitude;
    double userLng = position.longitude;
    debugPrint('Background check at: $userLat, $userLng');

    // Fetch from both APIs in parallel — each has its own try/catch
    // so one failing won't block the other
    final usgsResult = await _bgFetchUSGS();
    final eonetResult = await _bgFetchEONET();
    final allDisasters = <Map<String, dynamic>>[...usgsResult, ...eonetResult];

    if (allDisasters.isEmpty) {
      // Both APIs returned nothing — could be offline or no events
      debugPrint('Background: No disaster data available');
      _updateForegroundNotification(service, 'All clear');
      await _updateFirestoreStatusBackground(userUid, true);
      return;
    }

    // Find nearby threats
    final nearby = allDisasters.where((d) {
      final double lat = (d['lat'] as num).toDouble();
      final double lng = (d['lng'] as num).toDouble();
      final String type = d['type'] ?? '';
      final double magnitude = (d['magnitude'] as num?)?.toDouble() ?? 0;

      double distance = _calculateDistance(userLat, userLng, lat, lng);
      double maxDistance = _getMaxDistance(type);

      if (type == 'earthquake') {
        return _isEarthquakeThreat(distance, magnitude);
      }

      if (distance < 5) return true;
      return distance <= maxDistance && magnitude >= 60;
    }).toList();

    if (nearby.isNotEmpty) {
      int now = DateTime.now().millisecondsSinceEpoch;

      // Skip notification if the app is currently in the foreground
      // (DisasterAlertService handles it there to avoid duplicate alerts)
      final prefs2 = await SharedPreferences.getInstance();
      await prefs2.reload();
      final appInForeground = prefs2.getBool('app_in_foreground') ?? false;

      if (now - lastAlertTimestamp[0] > 60000 && !appInForeground) {
        lastAlertTimestamp[0] = now;

        final disaster = nearby.first;
        final double dLat = (disaster['lat'] as num).toDouble();
        final double dLng = (disaster['lng'] as num).toDouble();
        double dist = _calculateDistance(userLat, userLng, dLat, dLng);

        String hotline = 'Emergency: 112';
        String country = 'Unknown';
        try {
          List<Placemark> placemarks =
              await placemarkFromCoordinates(userLat, userLng);
          if (placemarks.isNotEmpty) {
            country = placemarks.first.country ?? 'Unknown';
            final isoCode = placemarks.first.isoCountryCode;
            hotline = _getHotlineByCode(isoCode);
          }
        } catch (_) {}

        String safetyTip = _getSafetyTip(disaster['type'].toString());

        final int riskDisplay = disaster['type'] == 'earthquake'
            ? ((disaster['magnitude'] as num).toDouble() * 10).round().clamp(0, 100)
            : (disaster['magnitude'] as num).toInt();

        final androidDetails = AndroidNotificationDetails(
          'disaster_alerts',
          'Disaster Alerts',
          channelDescription: 'Notifications for nearby disaster alerts',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          styleInformation: BigTextStyleInformation(
            '${dist.toStringAsFixed(1)} km away | Severity: $riskDisplay%\n\n'
            '$safetyTip\n\n'
            '$hotline',
            contentTitle:
                '🚨 ${disaster['type'].toString().toUpperCase()} ALERT',
          ),
        );

        final details = NotificationDetails(android: androidDetails);

        await notificationsPlugin.show(
          id: 1,
          title:
              '🚨 ${disaster['type'].toString().toUpperCase()} ALERT — $country',
          body: '${dist.toStringAsFixed(1)} km away | $safetyTip',
          notificationDetails: details,
        );

        debugPrint(
            'BACKGROUND ALERT: ${disaster['type']} at ${dist.toStringAsFixed(1)} km');
      }

      await _updateFirestoreStatusBackground(userUid, false);
      _updateForegroundNotification(service, 'DANGER detected nearby');
    } else {
      debugPrint('Background check: No nearby disasters');
      await _updateFirestoreStatusBackground(userUid, true);
      _updateForegroundNotification(service, 'All clear');
    }
  } catch (e) {
    debugPrint('Background disaster check error: $e');
    _updateForegroundNotification(service, 'Check failed');
  }
}

// ─── Background API fetchers (self-contained, no shared imports) ───

Future<List<Map<String, dynamic>>> _bgFetchUSGS() async {
  try {
    final now = DateTime.now().toUtc();
    final oneDayAgo = now.subtract(const Duration(hours: 24));
    final startTime = oneDayAgo.toIso8601String().split('.').first;

    final url = 'https://earthquake.usgs.gov/fdsnws/event/1/query'
        '?format=geojson'
        '&starttime=$startTime'
        '&minmagnitude=2.5'
        '&orderby=time'
        '&limit=100';

    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body);
    final List features = data['features'] ?? [];

    final results = <Map<String, dynamic>>[];

    for (final f in features) {
      final props = f['properties'] ?? {};
      final coords = f['geometry']?['coordinates'] ?? [0.0, 0.0, 0.0];

      final double lng = (coords[0] as num).toDouble();
      final double lat = (coords[1] as num).toDouble();
      final double mag = (props['mag'] as num?)?.toDouble() ?? 0.0;

      results.add({
        'type': 'earthquake',
        'lat': lat,
        'lng': lng,
        'magnitude': mag,
        'title': props['title'] ?? 'Earthquake M${mag.toStringAsFixed(1)}',
      });

      if (props['tsunami'] == 1) {
        results.add({
          'type': 'tsunami',
          'lat': lat,
          'lng': lng,
          'magnitude': 90.0,
          'title': 'Tsunami Warning — ${props['title'] ?? ''}',
        });
      }
    }

    return results;
  } catch (e) {
    debugPrint('Background USGS error: $e');
    return [];
  }
}

Future<List<Map<String, dynamic>>> _bgFetchEONET() async {
  try {
    final url = 'https://eonet.gsfc.nasa.gov/api/v3/events'
        '?status=open'
        '&limit=100';

    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body);
    final List events = data['events'] ?? [];

    final results = <Map<String, dynamic>>[];

    for (final event in events) {
      final List categories = event['categories'] ?? [];
      if (categories.isEmpty) continue;

      final String categoryId = categories[0]['id'] ?? '';

      if ({'manmade', 'seaLakeIce', 'snow', 'waterColor', 'dustHaze', 'tempExtremes'}
          .contains(categoryId)) {
        continue;
      }

      final String type = _bgMapEONETCategory(categoryId, event['title'] ?? '');

      final List geometryList = event['geometry'] ?? [];
      if (geometryList.isEmpty) continue;

      final latestGeo = geometryList.last;
      final List coords = latestGeo['coordinates'] ?? [0.0, 0.0];

      final double lng = (coords[0] as num).toDouble();
      final double lat = (coords[1] as num).toDouble();

      final double? magnitudeValue =
          (latestGeo['magnitudeValue'] as num?)?.toDouble();
      final String? magnitudeUnit = latestGeo['magnitudeUnit'];

      results.add({
        'type': type,
        'lat': lat,
        'lng': lng,
        'magnitude': _bgEstimateSeverity(type, magnitudeValue, magnitudeUnit),
        'title': event['title'] ?? type,
      });
    }

    return results;
  } catch (e) {
    debugPrint('Background EONET error: $e');
    return [];
  }
}

String _bgMapEONETCategory(String categoryId, String title) {
  final t = title.toLowerCase();
  switch (categoryId) {
    case 'earthquakes':
      return 'earthquake';
    case 'volcanoes':
      return 'volcano';
    case 'wildfires':
      return 'wildfire';
    case 'floods':
      return 'flood';
    case 'landslides':
      return 'landslide';
    case 'drought':
      return 'drought';
    case 'severeStorms':
      if (t.contains('typhoon')) return 'typhoon';
      if (t.contains('hurricane')) return 'cyclone';
      if (t.contains('cyclone')) return 'cyclone';
      if (t.contains('tornado')) return 'tornado';
      if (t.contains('thunderstorm')) return 'thunderstorm';
      return 'storm';
    default:
      return categoryId;
  }
}

double _bgEstimateSeverity(String type, double? magValue, String? magUnit) {
  switch (type) {
    case 'wildfire':
      if (magValue == null) return 70;
      if (magValue > 10000) return 95;
      if (magValue > 1000) return 85;
      if (magValue > 100) return 75;
      return 60;
    case 'storm':
    case 'cyclone':
    case 'typhoon':
    case 'thunderstorm':
      if (magValue == null) return 70;
      if (magValue >= 130) return 95;
      if (magValue >= 100) return 90;
      if (magValue >= 64) return 80;
      if (magValue >= 34) return 70;
      return 50;
    case 'volcano':
      return 85;
    case 'flood':
      return 80;
    case 'landslide':
      return 80;
    default:
      return 60;
  }
}

bool _isEarthquakeThreat(double distanceKm, double magnitude) {
  if (magnitude >= 7.0) return distanceKm <= 300;
  if (magnitude >= 6.0) return distanceKm <= 200;
  if (magnitude >= 5.0) return distanceKm <= 100;
  if (magnitude >= 4.0) return distanceKm <= 50;
  if (magnitude >= 3.0) return distanceKm <= 20;
  return false;
}

double _getMaxDistance(String? type) {
  switch (type) {
    case 'earthquake':
      return 300;
    case 'tsunami':
      return 100;
    case 'cyclone':
    case 'typhoon':
    case 'storm':
      return 80;
    case 'thunderstorm':
      return 50;
    case 'tornado':
      return 50;
    case 'wildfire':
      return 40;
    case 'volcano':
      return 60;
    case 'flood':
      return 25;
    case 'landslide':
      return 15;
    default:
      return 30;
  }
}

double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371;
  double dLat = (lat2 - lat1) * pi / 180;
  double dLon = (lon2 - lon1) * pi / 180;

  double a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) *
          cos(lat2 * pi / 180) *
          sin(dLon / 2) *
          sin(dLon / 2);

  double c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return R * c;
}

// ─── Hotline helpers ───

Map<String, dynamic>? _cachedHotlines;

Future<void> _loadHotlines() async {
  if (_cachedHotlines != null) return;
  try {
    // Ensure Flutter binding is initialized before accessing rootBundle
    // (required in background Dart isolates)
    WidgetsFlutterBinding.ensureInitialized();
    final jsonString =
        await rootBundle.loadString('assets/emergency_hotlines.json');
    _cachedHotlines = jsonDecode(jsonString) as Map<String, dynamic>;
  } catch (e) {
    debugPrint('Background: Failed to load hotlines JSON: $e');
  }
}

String _getHotlineByCode(String? isoCode) {
  if (_cachedHotlines == null) return 'Emergency: 112';

  final code = (isoCode ?? 'DEFAULT').toUpperCase();
  final entry = _cachedHotlines![code] ?? _cachedHotlines!['DEFAULT'];
  if (entry == null) return 'Emergency: 112';

  final police = entry['police'] ?? '112';
  final ambulance = entry['ambulance'] ?? '112';
  final fire = entry['fire'] ?? '112';

  if (police == ambulance && ambulance == fire) {
    return 'Emergency: $police';
  }
  return 'Police: $police | Ambulance: $ambulance | Fire: $fire';
}

// ─── Safety tips ───

String _getSafetyTip(String disasterType) {
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
    default:
      return 'Stay alert. Follow local authority instructions. Have an emergency kit ready. Move to safety if directed.';
  }
}
