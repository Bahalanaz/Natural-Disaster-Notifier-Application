import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:get/get.dart';

class LocationService {
  LocationService._privateConstructor();
  static final LocationService _instance = LocationService._privateConstructor();
  factory LocationService() => _instance;
  // Current location and permission state
  Position? currentPosition;
  RxBool hasPermission = false.obs;

  Stream<Position>? _positionStream;

  /// Request location permission from the OS
  Future<void> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      Get.snackbar("Error", "Please enable GPS");
      hasPermission.value = false;
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      // This triggers the OS native permission request dialog
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      Get.snackbar(
        "Permission Denied",
        "Enable location from phone settings manually",
      );
      hasPermission.value = false;
      return;
    }

    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      hasPermission.value = true;
      currentPosition = await getCurrentLocation();
    }
  }

  /// Get location once
  Future<Position> getCurrentLocation() async {
    if (!hasPermission.value) {
      await requestPermission();
      if (!hasPermission.value) throw Exception("Location permission denied");
    }

    currentPosition = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    return currentPosition!;
  }

  StreamSubscription<Position>? _streamSubscription;

  /// Start live location stream (auto-updates currentPosition)
  Future<Stream<Position>> startLocationStream({int distanceFilter = 10}) async {
    if (!hasPermission.value) {
      await requestPermission();
      if (!hasPermission.value) throw Exception("Location permission denied");
    }

    // Always create a fresh stream to avoid stale stream after logout/login
    stopLocationStream();

    LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilter,
    );

    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings);

    _streamSubscription = _positionStream!.listen((pos) {
      currentPosition = pos;
    });

    return _positionStream!;
  }

  /// Stop the location stream and clean up
  void stopLocationStream() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _positionStream = null;
  }

  /// Convert coordinates to country name
  Future<String> getCountry(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        return placemarks.first.country ?? "Unknown";
      }
    } catch (_) {}
    return "Unknown";
  }

  Future<String?> getCountryCode(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        return placemarks.first.isoCountryCode;
      }
    } catch (_) {}
    return null;
  }
}