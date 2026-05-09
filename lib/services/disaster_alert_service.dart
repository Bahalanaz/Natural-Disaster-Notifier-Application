import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:undergrad_app/services/status_service.dart';
import 'package:undergrad_app/services/notification_service.dart';
import 'package:undergrad_app/services/hotline_service.dart';
import 'get_location_service.dart';
import 'disaster_service.dart';
import 'package:flutter/foundation.dart';

class DisasterAlertService {
  // Singleton — prevents duplicate streams/timers when Homepage rebuilds
  DisasterAlertService._privateConstructor();
  static final DisasterAlertService _instance = DisasterAlertService._privateConstructor();
  factory DisasterAlertService() => _instance;

  final LocationService _locationService = LocationService();
  StreamSubscription<Position>? _positionSubscription;
  Timer? _periodicTimer;

  int _lastApiCall = 0;
  int _lastAlertTimestamp = 0;
  bool _isCheckRunning = false;

  /// Update the user's safety status in Firestore so friends can see it
  Future<void> _updateFirestoreStatus(bool isSafe) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'isSafe': isSafe,
        'lastStatusUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Firestore status update error: $e");
    }
  }

  void start() async {
    // Cancel any previous subscription before starting fresh
    stop();
    _lastApiCall = 0; // reset rate limit so first check runs immediately

    try {
      final stream =
          await _locationService.startLocationStream(distanceFilter: 10);

      // Listen for location changes (triggers on movement)
      _positionSubscription = stream.listen((position) {
        debugPrint("Location: ${position.latitude}, ${position.longitude}");
        _safeCheck(position.latitude, position.longitude);
      });

      // Also run a periodic timer every 10 minutes for stationary users
      _periodicTimer = Timer.periodic(const Duration(minutes: 10), (_) async {
        final pos = _locationService.currentPosition;
        if (pos != null) {
          debugPrint("Periodic check at: ${pos.latitude}, ${pos.longitude}");
          _forceCheck(pos.latitude, pos.longitude);
        } else {
          try {
            final freshPos = await _locationService.getCurrentLocation();
            debugPrint("Periodic check (fresh) at: ${freshPos.latitude}, ${freshPos.longitude}");
            _forceCheck(freshPos.latitude, freshPos.longitude);
          } catch (e) {
            debugPrint("Periodic check: could not get location: $e");
          }
        }
      });

      // Run an immediate check on start
      _runImmediateCheck();
    } catch (e) {
      debugPrint("Start error: $e");
    }
  }

  void _runImmediateCheck() async {
    try {
      final pos = _locationService.currentPosition ??
          await _locationService.getCurrentLocation();
      _forceCheck(pos.latitude, pos.longitude);
    } catch (e) {
      debugPrint("Immediate check failed: $e");
    }
  }

  void stop() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _locationService.stopLocationStream();
  }

  /// Rate-limited check — skips if called within 10 min of last check
  void _safeCheck(double lat, double lng) {
    int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastApiCall > 10 * 60 * 1000) {
      _lastApiCall = now;
      _checkDisasters(lat, lng);
    }
  }

  /// Forced check — bypasses rate limit (used by periodic timer)
  void _forceCheck(double lat, double lng) {
    _lastApiCall = DateTime.now().millisecondsSinceEpoch;
    _checkDisasters(lat, lng);
  }

  void _checkDisasters(double userLat, double userLng) async {
    if (_isCheckRunning) return;
    _isCheckRunning = true;

    try {
      final disasters = await fetchDisasters();

      final nearby = disasters.where((d) {
        final double lat = (d['lat'] as num).toDouble();
        final double lng = (d['lng'] as num).toDouble();
        final String type = d['type'] ?? '';
        final double magnitude = (d['magnitude'] as num?)?.toDouble() ?? 0;

        double distance = _calculateDistance(userLat, userLng, lat, lng);
        double maxDistance = _getMaxDistance(type);

        // For earthquakes, use magnitude-based filtering
        if (type == 'earthquake') {
          return _isEarthquakeThreat(distance, magnitude);
        }

        // For EONET events
        // magnitude here is our estimated severity score (0-100)
        if (distance < 5) return true; // very close — always alert
        return distance <= maxDistance && magnitude >= 60;
      }).toList();

      if (nearby.isNotEmpty) {
        StatusService().setDanger();
        await _updateFirestoreStatus(false);

        int now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastAlertTimestamp > 60000) {
          _lastAlertTimestamp = now;

          final disaster = nearby.first;
          final double dLat = (disaster['lat'] as num).toDouble();
          final double dLng = (disaster['lng'] as num).toDouble();
          double dist = _calculateDistance(userLat, userLng, dLat, dLng);

          debugPrint("🚨 DISASTER ALERT");
          debugPrint("Type: ${disaster['type']}");
          debugPrint("Title: ${disaster['title']}");
          debugPrint("Magnitude: ${disaster['magnitude']}");
          debugPrint("Distance: ${dist.toStringAsFixed(2)} km");

          String country = 'Unknown';
          String? countryCode;
          try {
            country = await _locationService.getCountry(userLat, userLng);
            countryCode = await _locationService.getCountryCode(userLat, userLng);
          } catch (_) {}

          await HotlineService().load();
          String hotline = HotlineService().getHotline(countryCode);

          debugPrint("Country: $country");
          debugPrint("Hotline: $hotline");

          // Build risk display: for earthquakes show magnitude, for others show severity
          final int riskDisplay = disaster['type'] == 'earthquake'
              ? ((disaster['magnitude'] as num).toDouble() * 10).round().clamp(0, 100)
              : (disaster['magnitude'] as num).toInt();

          await NotificationService().showDisasterAlert(
            disasterType: disaster['type'],
            distance: dist,
            riskScore: riskDisplay,
            hotline: hotline,
            country: country,
          );
        }
      } else {
        StatusService().setSafe();
        await _updateFirestoreStatus(true);
        debugPrint("No nearby disasters");
      }
    } catch (e) {
      debugPrint("Error checking disasters: $e");
    } finally {
      _isCheckRunning = false;
    }
  }

  /// Determine if an earthquake is a threat based on distance and magnitude.
  /// Larger earthquakes can be felt much further away.
  bool _isEarthquakeThreat(double distanceKm, double magnitude) {
    if (magnitude >= 7.0) return distanceKm <= 300; // major — felt 300km+
    if (magnitude >= 6.0) return distanceKm <= 200; // strong
    if (magnitude >= 5.0) return distanceKm <= 100; // moderate
    if (magnitude >= 4.0) return distanceKm <= 50;  // light — felt nearby
    if (magnitude >= 3.0) return distanceKm <= 20;  // minor — very close only
    return false; // < 3.0 not alertable
  }

  /// Get maximum alert distance by disaster type (for EONET events)
  double _getMaxDistance(String? type) {
    switch (type) {
      case 'earthquake':
        return 300; // handled by _isEarthquakeThreat instead
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

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
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
}
