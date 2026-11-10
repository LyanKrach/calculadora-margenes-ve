import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/seller_profile.dart';

/// Servicio local para leer, guardar y eliminar el perfil del vendedor en
/// `SharedPreferences`. Nunca transmite datos fuera del dispositivo.
class SellerProfileService {
  static const String _storageKey = 'seller_profile_data';

  Future<SellerProfile> getProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return const SellerProfile.empty();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return SellerProfile.fromJson(decoded);
      } else if (decoded is Map) {
        return SellerProfile.fromJson(Map<String, dynamic>.from(decoded));
      }
      return const SellerProfile.empty();
    } catch (_) {
      return const SellerProfile.empty();
    }
  }

  Future<void> saveProfile(SellerProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(profile.toJson());
    await prefs.setString(_storageKey, encoded);
  }

  Future<void> clearProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}

