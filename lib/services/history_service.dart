import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/calculation_item.dart';
import 'auth_service.dart';

/// Servicio para el historial de productos calculados (`calc_history_list`)
/// y la colección de plantillas / presets (`calc_presets_list`), con
/// sincronización automática en `Cloud Firestore` (`users/{uid}/history`)
/// cuando el usuario ha iniciado sesión.
class HistoryService {
  static const String _historyKey = 'calc_history_list';
  static const String _presetsKey = 'calc_presets_list';
  static const int maxHistoryItems = 15;

  FirebaseFirestore? get _firestore =>
      AuthService.isFirebaseInitialized ? FirebaseFirestore.instance : null;

  String? get _currentUid => AuthService().currentUser?.uid;

  CollectionReference<Map<String, dynamic>>? get _userHistoryCol {
    final db = _firestore;
    final uid = _currentUid;
    if (db == null || uid == null || uid.isEmpty) return null;
    return db.collection('users').doc(uid).collection('history');
  }

  // ------------------------------------------------------------------
  // Historial (máximo 15 elementos locales + respaldo en Firestore)
  // ------------------------------------------------------------------
  Future<List<HistoryEntry>> getHistory({bool syncRemote = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final local = List<HistoryEntry>.from(
      HistoryEntry.listFromJson(prefs.getString(_historyKey)),
    );

    final col = _userHistoryCol;
    if (!syncRemote || col == null) {
      return local;
    }

    try {
      final snap = await col.get();
      final byId = <String, HistoryEntry>{
        for (final e in local) e.id: e,
      };
      for (final doc in snap.docs) {
        final remoteEntry = HistoryEntry.fromJson(doc.data());
        if (remoteEntry.isValid) {
          byId[remoteEntry.id] = remoteEntry;
        }
      }

      // Subir entradas locales que falten en Firestore
      final remoteIds = snap.docs.map((d) => d.id).toSet();
      for (final localEntry in local) {
        if (!remoteIds.contains(localEntry.id)) {
          await col.doc(localEntry.id).set(localEntry.toJson());
        }
      }

      final merged = byId.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (merged.length > maxHistoryItems) {
        merged.removeRange(maxHistoryItems, merged.length);
      }

      final encoded = jsonEncode(merged.map((e) => e.toJson()).toList());
      await prefs.setString(_historyKey, encoded);
      return merged;
    } catch (_) {
      return local;
    }
  }

  Future<void> addHistoryEntry(HistoryEntry entry) async {
    if (!entry.isValid) return;
    final prefs = await SharedPreferences.getInstance();
    final current = List<HistoryEntry>.from(
      HistoryEntry.listFromJson(prefs.getString(_historyKey)),
    );

    // Insertar al inicio (más reciente primero) y podar a 15 elementos
    current.removeWhere((e) => e.id == entry.id);
    current.insert(0, entry);
    if (current.length > maxHistoryItems) {
      current.removeRange(maxHistoryItems, current.length);
    }

    final encoded = jsonEncode(current.map((e) => e.toJson()).toList());
    await prefs.setString(_historyKey, encoded);

    final col = _userHistoryCol;
    if (col != null) {
      try {
        await col.doc(entry.id).set(entry.toJson());
      } catch (_) {}
    }
  }

  Future<void> deleteHistoryEntry(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final current = List<HistoryEntry>.from(
      HistoryEntry.listFromJson(prefs.getString(_historyKey)),
    )..removeWhere((e) => e.id == id);

    final encoded = jsonEncode(current.map((e) => e.toJson()).toList());
    await prefs.setString(_historyKey, encoded);

    final col = _userHistoryCol;
    if (col != null) {
      try {
        await col.doc(id).delete();
      } catch (_) {}
    }
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final current = List<HistoryEntry>.from(
      HistoryEntry.listFromJson(prefs.getString(_historyKey)),
    );
    await prefs.remove(_historyKey);

    final col = _userHistoryCol;
    if (col != null) {
      try {
        for (final item in current) {
          await col.doc(item.id).delete();
        }
      } catch (_) {}
    }
  }

  // ------------------------------------------------------------------
  // Plantillas / Presets
  // ------------------------------------------------------------------
  Future<List<Preset>> getPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_presetsKey);
    return Preset.listFromJson(raw);
  }

  Future<void> savePreset(Preset preset) async {
    if (!preset.isValid) return;
    final prefs = await SharedPreferences.getInstance();
    final current = List<Preset>.from(
      Preset.listFromJson(prefs.getString(_presetsKey)),
    );

    final existingIdx = current.indexWhere((p) => p.id == preset.id);
    if (existingIdx >= 0) {
      current[existingIdx] = preset;
    } else {
      current.insert(0, preset);
    }

    final encoded = jsonEncode(current.map((p) => p.toJson()).toList());
    await prefs.setString(_presetsKey, encoded);
  }

  Future<void> deletePreset(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final current = List<Preset>.from(
      Preset.listFromJson(prefs.getString(_presetsKey)),
    )..removeWhere((p) => p.id == id);

    final encoded = jsonEncode(current.map((p) => p.toJson()).toList());
    await prefs.setString(_presetsKey, encoded);
  }

  Future<void> clearPresets() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_presetsKey);
  }
}
