import 'dart:convert';
import 'package:flutter/services.dart';

class HotlineService {
  HotlineService._privateConstructor();
  static final HotlineService _instance = HotlineService._privateConstructor();
  factory HotlineService() => _instance;

  Map<String, dynamic>? _hotlines;

  /// Load the hotlines JSON from assets (caches after first load)
  Future<void> load() async {
    if (_hotlines != null) return;
    final jsonString =
        await rootBundle.loadString('assets/emergency_hotlines.json');
    _hotlines = jsonDecode(jsonString) as Map<String, dynamic>;
  }

  /// Load from a raw JSON string (for background isolate where rootBundle may not work)
  void loadFromString(String jsonString) {
    if (_hotlines != null) return;
    _hotlines = jsonDecode(jsonString) as Map<String, dynamic>;
  }

  /// Get formatted hotline string by ISO 3166-1 alpha-2 country code
  String getHotline(String? isoCode) {
    if (_hotlines == null) return 'Emergency: 112';

    final code = (isoCode ?? 'DEFAULT').toUpperCase();
    final entry = _hotlines![code] ?? _hotlines!['DEFAULT'];

    if (entry == null) return 'Emergency: 112';

    final police = entry['police'] ?? '112';
    final ambulance = entry['ambulance'] ?? '112';
    final fire = entry['fire'] ?? '112';

    // If all three are the same, show a single line
    if (police == ambulance && ambulance == fire) {
      return 'Emergency: $police';
    }

    return 'Police: $police | Ambulance: $ambulance | Fire: $fire';
  }
}
