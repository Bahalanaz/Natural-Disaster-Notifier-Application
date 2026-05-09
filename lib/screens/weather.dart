import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:undergrad_app/services/weather_service.dart';

class WeatherPage extends StatefulWidget {
  const WeatherPage({super.key});

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  Map<String, dynamic>? weatherData;
  bool loading = true;
  String? errorMsg;

  @override
  void initState() {
    super.initState();
    _loadWeather();
  }

  Future<void> _loadWeather() async {
    setState(() {
      loading = true;
      errorMsg = null;
    });

    try {
      final data = await WeatherService.fetchWeeklyWeather();
      if (!mounted) return;
      setState(() {
        weatherData = data;
        loading = false;
        if (data == null) errorMsg = "Failed to load weather data";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        errorMsg = "Could not get your location or weather data";
      });
    }
  }

  // Day label: Today / Tomorrow / Day name
  String getDayLabel(String dateString) {
    DateTime date = DateTime.parse(dateString);
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    DateTime tomorrow = today.add(const Duration(days: 1));

    if (date == today) return "Today";
    if (date == tomorrow) return "Tomorrow";
    return DateFormat('EEEE').format(date);
  }

  String getShortDate(String dateString) {
    DateTime date = DateTime.parse(dateString);
    return DateFormat('MMM d').format(date);
  }

  // WMO weather code to emoji + description
  Map<String, String> getWeatherInfo(int code) {
    if (code == 0) return {"emoji": "☀️", "desc": "Clear sky"};
    if (code <= 3) return {"emoji": "🌤️", "desc": "Partly cloudy"};
    if (code <= 48) return {"emoji": "🌫️", "desc": "Foggy"};
    if (code <= 55) return {"emoji": "🌦️", "desc": "Light drizzle"};
    if (code <= 57) return {"emoji": "🌧️", "desc": "Freezing drizzle"};
    if (code <= 65) return {"emoji": "🌧️", "desc": "Rain"};
    if (code <= 67) return {"emoji": "🌧️", "desc": "Freezing rain"};
    if (code <= 77) return {"emoji": "🌨️", "desc": "Snow"};
    if (code <= 82) return {"emoji": "🌧️", "desc": "Rain showers"};
    if (code <= 86) return {"emoji": "🌨️", "desc": "Snow showers"};
    if (code == 95) return {"emoji": "⛈️", "desc": "Thunderstorm"};
    if (code <= 99) return {"emoji": "⛈️", "desc": "Thunderstorm with hail"};
    return {"emoji": "🌡️", "desc": "Unknown"};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Weather", style: GoogleFonts.poppins()),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadWeather,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMsg != null || weatherData == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 60, color: Colors.grey),
            const SizedBox(height: 16),
            Text(errorMsg ?? "Something went wrong",
                style: const TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadWeather,
              icon: const Icon(Icons.refresh),
              label: const Text("Retry"),
            ),
          ],
        ),
      );
    }

    final daily = weatherData!['daily'];
    if (daily == null) {
      return const Center(child: Text("Weather data unavailable"));
    }
    final dates = (daily['time'] as List<dynamic>?) ?? [];
    final maxTemps = (daily['temperature_2m_max'] as List<dynamic>?) ?? [];
    final minTemps = (daily['temperature_2m_min'] as List<dynamic>?) ?? [];
    final precipitation = (daily['precipitation_sum'] as List<dynamic>?) ?? [];
    final weatherCodes = daily['weathercode'] as List<dynamic>?;
    final windSpeeds = daily['windspeed_10m_max'] as List<dynamic>?;

    // Current weather (if available)
    final current = weatherData!['current_weather'];

    return RefreshIndicator(
      onRefresh: _loadWeather,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── Current Weather Card ───
          if (current != null) _buildCurrentWeatherCard(current),

          const SizedBox(height: 20),

          Text(
            "7-Day Forecast",
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),

          // ─── Daily Forecast Cards ───
          ...List.generate(dates.length, (index) {
            final weatherCode = (weatherCodes != null && index < weatherCodes.length)
                ? weatherCodes[index] : 0;
            final info = getWeatherInfo(weatherCode is int ? weatherCode : 0);
            final wind = (windSpeeds != null && index < windSpeeds.length)
                ? windSpeeds[index] : 0;

            return _buildDayCard(
              dayLabel: getDayLabel(dates[index]),
              shortDate: getShortDate(dates[index]),
              emoji: info['emoji']!,
              description: info['desc']!,
              maxTemp: index < maxTemps.length ? maxTemps[index] : 0,
              minTemp: index < minTemps.length ? minTemps[index] : 0,
              rain: index < precipitation.length ? precipitation[index] : 0,
              wind: wind,
              isToday: getDayLabel(dates[index]) == "Today",
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCurrentWeatherCard(Map<String, dynamic> current) {
    final temp = current['temperature'];
    final windSpeed = current['windspeed'];
    final code = current['weathercode'] ?? 0;
    final info = getWeatherInfo(code is int ? code : 0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3C72), Color(0xFF2A5298)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            "Right Now",
            style: GoogleFonts.poppins(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            info['emoji']!,
            style: const TextStyle(fontSize: 50),
          ),
          const SizedBox(height: 8),
          Text(
            "${temp}°C",
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 42,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            info['desc']!,
            style: GoogleFonts.poppins(
              color: Colors.white70,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.air, color: Colors.white70, size: 18),
              const SizedBox(width: 4),
              Text(
                "${windSpeed} km/h",
                style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDayCard({
    required String dayLabel,
    required String shortDate,
    required String emoji,
    required String description,
    required dynamic maxTemp,
    required dynamic minTemp,
    required dynamic rain,
    required dynamic wind,
    required bool isToday,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: isToday ? 3 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Emoji
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 14),

            // Day + description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dayLabel,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  Text(
                    "$shortDate • $description",
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),

            // Temps + details
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "${maxTemp}° / ${minTemp}°",
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if ((rain ?? 0) > 0) ...[
                      const Icon(Icons.water_drop, size: 12, color: Colors.blue),
                      Text(
                        " ${rain}mm",
                        style: const TextStyle(fontSize: 11, color: Colors.blue),
                      ),
                      const SizedBox(width: 6),
                    ],
                    const Icon(Icons.air, size: 12, color: Colors.grey),
                    Text(
                      " ${wind}km/h",
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
