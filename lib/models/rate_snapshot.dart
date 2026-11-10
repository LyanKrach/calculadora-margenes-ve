import 'dart:convert';

/// Instantánea histórica de las 3 tasas principales para graficar fluctuación.
///
/// Incluye versionado de esquema `"v": 1` y deserialización tolerante a fallos.
class RateSnapshot {
  const RateSnapshot({
    required this.timestamp,
    required this.bcvUsd,
    required this.binanceUsdt,
    required this.euroBcv,
    this.version = currentVersion,
  });

  static const int currentVersion = 1;

  final DateTime timestamp;
  final double bcvUsd;
  final double binanceUsdt;
  final double euroBcv;
  final int version;

  bool get isValid => bcvUsd > 0 && binanceUsdt > 0 && euroBcv > 0;

  Map<String, dynamic> toJson() => {
        'v': version,
        'timestamp': timestamp.toIso8601String(),
        'bcvUsd': bcvUsd,
        'binanceUsdt': binanceUsdt,
        'euroBcv': euroBcv,
      };

  /// Deserializa un objeto JSON con `try/catch` y fallback seguro a estado vacío.
  factory RateSnapshot.fromJson(Map<String, dynamic> json) {
    try {
      final v = (json['v'] as num?)?.toInt() ?? 1;
      final tsRaw = json['timestamp']?.toString() ?? '';
      final parsedTs = DateTime.tryParse(tsRaw);
      final bcv = (json['bcvUsd'] as num?)?.toDouble() ?? 0.0;
      final binance = (json['binanceUsdt'] as num?)?.toDouble() ?? 0.0;
      final euro = (json['euroBcv'] as num?)?.toDouble() ?? 0.0;

      if (parsedTs == null || bcv <= 0 || binance <= 0 || euro <= 0) {
        return RateSnapshot.empty();
      }

      return RateSnapshot(
        version: v,
        timestamp: parsedTs,
        bcvUsd: bcv,
        binanceUsdt: binance,
        euroBcv: euro,
      );
    } catch (_) {
      return RateSnapshot.empty();
    }
  }

  /// Estado vacío de respaldo ante datos corruptos.
  factory RateSnapshot.empty() => RateSnapshot(
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
        bcvUsd: 0,
        binanceUsdt: 0,
        euroBcv: 0,
      );

  /// Decodifica una lista JSON serializada con `try/catch` y fallback a `[]`.
  static List<RateSnapshot> listFromJson(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! List) return const [];
      final result = <RateSnapshot>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final snap = RateSnapshot.fromJson(item);
          if (snap.isValid) {
            result.add(snap);
          }
        } else if (item is Map) {
          final snap = RateSnapshot.fromJson(Map<String, dynamic>.from(item));
          if (snap.isValid) {
            result.add(snap);
          }
        }
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  /// Determina si [candidate] debe agregarse después de [last].
  ///
  /// Regla cerrada:
  /// (a) Variación respecto al último snapshot > 0.5 % en BCV, Binance o Euro, o
  /// (b) Pasó ≥ 1 hora desde [last.timestamp].
  static bool shouldAppend({
    required RateSnapshot? last,
    required RateSnapshot candidate,
  }) {
    if (!candidate.isValid) return false;
    if (last == null || !last.isValid) return true;

    final elapsed = candidate.timestamp.difference(last.timestamp);
    if (elapsed >= const Duration(hours: 1)) {
      return true;
    }

    if (_variationPercent(last.bcvUsd, candidate.bcvUsd) > 0.5) return true;
    if (_variationPercent(last.binanceUsdt, candidate.binanceUsdt) > 0.5) {
      return true;
    }
    if (_variationPercent(last.euroBcv, candidate.euroBcv) > 0.5) return true;

    return false;
  }

  static double _variationPercent(double previous, double current) {
    if (previous <= 0) return current > 0 ? 100.0 : 0.0;
    return ((current - previous).abs() / previous) * 100.0;
  }
}

