import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:undergrad_app/services/get_location_service.dart';
import 'package:flutter/foundation.dart';

const _weatherCacheKey = 'cached_weather';
const _weatherCacheTimeKey = 'cached_weather_time';
const _weatherCacheMaxAgeMinutes = 60; // cache weather for 1 hour

class WeatherService {
  /// Fetch weekly weather using the user's actual GPS location
  static Future<Map<String, dynamic>?> fetchWeeklyWeather() async {
    try {
      final locationService = LocationService();
      final position = await locationService.getCurrentLocation();

      final lat = position.latitude;
      final lng = position.longitude;

      final url =
          'https://api.open-meteo.com/v1/forecast'
          '?latitude=$lat&longitude=$lng'
          '&daily=temperature_2m_max,temperature_2m_min,'
          'precipitation_sum,weathercode,windspeed_10m_max'
          '&current_weather=true'
          '&timezone=auto';

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Cache for offline use
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_weatherCacheKey, response.body);
        await prefs.setInt(_weatherCacheTimeKey, DateTime.now().millisecondsSinceEpoch);

        return data;
      } else {
        debugPrint("Failed to fetch weather: ${response.statusCode}");
        return await _getCachedWeather();
      }
    } catch (e) {
      debugPrint("Error fetching weather, using cache: $e");
      return await _getCachedWeather();
    }
  }

  static Future<Map<String, dynamic>?> _getCachedWeather() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_weatherCacheKey);
      final cachedTime = prefs.getInt(_weatherCacheTimeKey) ?? 0;

      if (cached != null) {
        final ageMinutes = (DateTime.now().millisecondsSinceEpoch - cachedTime) ~/ 60000;
        if (ageMinutes <= _weatherCacheMaxAgeMinutes) {
          return json.decode(cached);
        }
      }
    } catch (_) {}
    return null;
  }
}
