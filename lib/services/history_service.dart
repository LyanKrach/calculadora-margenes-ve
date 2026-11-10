import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/calculation_item.dart';
import 'auth_service.dart';

/// Servicio para el historial de productos calculados (`calc_history_list`)
/// y la colección de plantillas / presets (`calc_presets_list`), con
/// sincronización por cuenta en `Cloud Firestore` (`users/{uid}/history`)
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

  String _historyCacheKey() {
    final uid = _currentUid;
    return (uid != null && uid.isNotEmpty) ? '${_historyKey}_$uid' : _historyKey;
  }

  String _presetsCacheKey() {
    final uid = _currentUid;
    return (uid != null && uid.isNotEmpty) ? '${_presetsKey}_$uid' : _presetsKey;
  }

  // ------------------------------------------------------------------
  // Historial (máximo 15 elementos locales aislados por cuenta + Firestore)
  // ------------------------------------------------------------------
  Future<List<HistoryEntry>> getHistory({bool syncRemote = true}) async {
    final prefs = await SharedPreferences.getInstance();

    if (!AuthService.isFirebaseInitialized) {
      return List<HistoryEntry>.from(
        HistoryEntry.listFromJson(prefs.getString(_historyKey)),
      );
    }

    final uid = _currentUid;
    if (uid == null || uid.isEmpty) {
      return const [];
    }

    final userKey = _historyCacheKey();
    final local = List<HistoryEntry>.from(
      HistoryEntry.listFromJson(prefs.getString(userKey)),
    );

    final col = _userHistoryCol;
    if (!syncRemote || col == null) {
      return local;
    }

    try {
      final snap = await col.get().timeout(const Duration(seconds: 8));
      final remoteList = <HistoryEntry>[];
      for (final doc in snap.docs) {
        final remoteEntry = HistoryEntry.fromJson(doc.data());
        if (remoteEntry.isValid) {
          remoteList.add(remoteEntry);
        }
      }

      remoteList.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (remoteList.length > maxHistoryItems) {
        remoteList.removeRange(maxHistoryItems, remoteList.length);
      }

      final encoded = jsonEncode(remoteList.map((e) => e.toJson()).toList());
      await prefs.setString(userKey, encoded);
      return remoteList;
    } catch (_) {
      return local;
    }
  }

  Future<void> addHistoryEntry(HistoryEntry entry) async {
    if (!entry.isValid) return;
    final prefs = await SharedPreferences.getInstance();

    if (!AuthService.isFirebaseInitialized) {
      final current = List<HistoryEntry>.from(
        HistoryEntry.listFromJson(prefs.getString(_historyKey)),
      );
      current.removeWhere((e) => e.id == entry.id);
      current.insert(0, entry);
      if (current.length > maxHistoryItems) {
        current.removeRange(maxHistoryItems, current.length);
      }
      final encoded = jsonEncode(current.map((e) => e.toJson()).toList());
      await prefs.setString(_historyKey, encoded);
      return;
    }

    final col = _userHistoryCol;
    final uid = _currentUid;
    if (col == null || uid == null || uid.isEmpty) {
      return;
    }

    final userKey = _historyCacheKey();
    final current = List<HistoryEntry>.from(
      HistoryEntry.listFromJson(prefs.getString(userKey)),
    );

    current.removeWhere((e) => e.id == entry.id);
    current.insert(0, entry);
    if (current.length > maxHistoryItems) {
      current.removeRange(maxHistoryItems, current.length);
    }

    final encoded = jsonEncode(current.map((e) => e.toJson()).toList());
    await prefs.setString(userKey, encoded);

    try {
      await col.doc(entry.id).set(entry.toJson()).timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  Future<void> deleteHistoryEntry(String id) async {
    final prefs = await SharedPreferences.getInstance();

    if (!AuthService.isFirebaseInitialized) {
      final current = List<HistoryEntry>.from(
        HistoryEntry.listFromJson(prefs.getString(_historyKey)),
      )..removeWhere((e) => e.id == id);
      final encoded = jsonEncode(current.map((e) => e.toJson()).toList());
      await prefs.setString(_historyKey, encoded);
      return;
    }

    final userKey = _historyCacheKey();
    final current = List<HistoryEntry>.from(
      HistoryEntry.listFromJson(prefs.getString(userKey)),
    )..removeWhere((e) => e.id == id);

    final encoded = jsonEncode(current.map((e) => e.toJson()).toList());
    await prefs.setString(userKey, encoded);

    final col = _userHistoryCol;
    if (col != null) {
      try {
        await col.doc(id).delete().timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();

    if (!AuthService.isFirebaseInitialized) {
      await prefs.remove(_historyKey);
      return;
    }

    final userKey = _historyCacheKey();
    await prefs.remove(userKey);

    final col = _userHistoryCol;
    if (col != null) {
      try {
        final snap = await col.get().timeout(const Duration(seconds: 8));
        for (final doc in snap.docs) {
          await doc.reference.delete();
        }
      } catch (_) {}
    }
  }

  // ------------------------------------------------------------------
  // Plantillas / Presets (aislados por cuenta en producción)
  // ------------------------------------------------------------------
  Future<List<Preset>> getPresets() async {
    final prefs = await SharedPreferences.getInstance();
    if (!AuthService.isFirebaseInitialized) {
      return Preset.listFromJson(prefs.getString(_presetsKey));
    }
    if (_currentUid == null || _currentUid!.isEmpty) {
      return const [];
    }
    return Preset.listFromJson(prefs.getString(_presetsCacheKey()));
  }

  Future<void> savePreset(Preset preset) async {
    if (!preset.isValid) return;
    final prefs = await SharedPreferences.getInstance();
    final key = AuthService.isFirebaseInitialized
        ? _presetsCacheKey()
        : _presetsKey;
    final current = List<Preset>.from(
      Preset.listFromJson(prefs.getString(key)),
    );

    final existingIdx = current.indexWhere((p) => p.id == preset.id);
    if (existingIdx >= 0) {
      current[existingIdx] = preset;
    } else {
      current.insert(0, preset);
    }

    final encoded = jsonEncode(current.map((p) => p.toJson()).toList());
    await prefs.setString(key, encoded);
  }

  Future<void> deletePreset(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final key = AuthService.isFirebaseInitialized
        ? _presetsCacheKey()
        : _presetsKey;
    final current = List<Preset>.from(
      Preset.listFromJson(prefs.getString(key)),
    )..removeWhere((p) => p.id == id);

    final encoded = jsonEncode(current.map((p) => p.toJson()).toList());
    await prefs.setString(key, encoded);
  }

  Future<void> clearPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final key = AuthService.isFirebaseInitialized
        ? _presetsCacheKey()
        : _presetsKey;
    await prefs.remove(key);
  }
}
