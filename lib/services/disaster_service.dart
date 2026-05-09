import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

const _cacheKey = 'cached_disasters';
const _cacheTimeKey = 'cached_disasters_time';
const _cacheMaxAge = 30; // minutes — cache expires after this

/// Fetch disasters from both USGS (earthquakes) and NASA EONET (all other types).
/// Returns a unified list of disaster maps with keys:
///   type, lat, lng, magnitude, title
Future<List<Map<String, dynamic>>> fetchDisasters() async {
  try {
    // Fetch both APIs in parallel
    final results = await Future.wait([
      _fetchUSGSEarthquakes(),
      _fetchEONETEvents(),
    ]).timeout(const Duration(seconds: 20));

    final allDisasters = <Map<String, dynamic>>[
      ...results[0],
      ...results[1],
    ];

    // Cache for offline use
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(allDisasters));
    await prefs.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);

    return allDisasters;
  } catch (e) {
    debugPrint('⚠️ Disaster fetch failed, using cache: $e');
    return await _getCachedDisasters();
  }
}

/// Fetch recent earthquakes from USGS FDSNWS API
/// Only gets M2.5+ from the last 24 hours
Future<List<Map<String, dynamic>>> _fetchUSGSEarthquakes() async {
  try {
    // Get earthquakes from the past 24 hours, magnitude 2.5+
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

      // USGS GeoJSON: [longitude, latitude, depth]
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

      // If USGS flagged a tsunami warning, also add a tsunami event
      if (props['tsunami'] == 1) {
        results.add({
          'type': 'tsunami',
          'lat': lat,
          'lng': lng,
          'magnitude': 90.0, // tsunami warnings are always high severity
          'title': 'Tsunami Warning — ${props['title'] ?? ''}',
        });
      }
    }

    return results;
  } catch (e) {
    debugPrint('USGS fetch error: $e');
    return [];
  }
}

/// Fetch active natural disaster events from NASA EONET v3 API
Future<List<Map<String, dynamic>>> _fetchEONETEvents() async {
  try {
    // Only fetch relevant natural disaster categories
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

      // Skip non-threatening categories
      if ({'manmade', 'seaLakeIce', 'snow', 'waterColor', 'dustHaze', 'tempExtremes'}
          .contains(categoryId)) {
        continue;
      }

      // Map EONET category to our normalized type
      final String type = _mapEONETCategory(categoryId, event['title'] ?? '');

      // Get the most recent geometry point (last in array = most recent)
      final List geometryList = event['geometry'] ?? [];
      if (geometryList.isEmpty) continue;

      final latestGeo = geometryList.last;
      final List coords = latestGeo['coordinates'] ?? [0.0, 0.0];

      // EONET GeoJSON: [longitude, latitude]
      final double lng = (coords[0] as num).toDouble();
      final double lat = (coords[1] as num).toDouble();

      // Get magnitude if available
      final double? magnitudeValue =
          (latestGeo['magnitudeValue'] as num?)?.toDouble();
      final String? magnitudeUnit = latestGeo['magnitudeUnit'];

      results.add({
        'type': type,
        'lat': lat,
        'lng': lng,
        'magnitude': _estimateEONETSeverity(type, magnitudeValue, magnitudeUnit),
        'title': event['title'] ?? type,
      });
    }

    return results;
  } catch (e) {
    debugPrint('EONET fetch error: $e');
    return [];
  }
}

/// Map EONET category IDs to our normalized disaster types
String _mapEONETCategory(String categoryId, String title) {
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
      // Differentiate storm sub-types from the title
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

/// Estimate a severity score (0-100) for EONET events based on type and magnitude.
/// This replaces the old API's "risk_score" field.
double _estimateEONETSeverity(String type, double? magValue, String? magUnit) {
  switch (type) {
    case 'wildfire':
      // Magnitude is in acres — bigger fire = higher severity
      if (magValue == null) return 70; // active fire with unknown size
      if (magValue > 10000) return 95;
      if (magValue > 1000) return 85;
      if (magValue > 100) return 75;
      return 60;

    case 'storm':
    case 'cyclone':
    case 'typhoon':
    case 'thunderstorm':
      // Magnitude is in kts (knots) for storms
      if (magValue == null) return 70;
      if (magValue >= 130) return 95; // Category 4+
      if (magValue >= 100) return 90; // Category 3
      if (magValue >= 64) return 80;  // Hurricane-force
      if (magValue >= 34) return 70;  // Tropical storm force
      return 50; // weak — won't trigger alert due to threshold

    case 'volcano':
      return 85; // active volcanoes are always serious

    case 'flood':
      return 80;

    case 'landslide':
      return 80;

    default:
      return 60;
  }
}

Future<List<Map<String, dynamic>>> _getCachedDisasters() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    final cachedTime = prefs.getInt(_cacheTimeKey) ?? 0;

    if (cached != null) {
      final age = DateTime.now().millisecondsSinceEpoch - cachedTime;
      if (age > _cacheMaxAge * 60 * 1000) {
        return [];
      }

      final list = jsonDecode(cached) as List;
      return list
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
          .toList();
    }
  } catch (_) {}
  return [];
}
