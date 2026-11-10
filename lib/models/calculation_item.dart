import 'dart:convert';

import '../services/calculator.dart';
import 'margin_mode.dart';
import 'rate.dart';

/// Mixin con los parámetros base de un cálculo de margen.
mixin CalculationParamsMixin {
  String get id;
  String get title;
  double get costUsd;
  double get marginPercent;
  double get fixedExpenseBs;

  /// Comisión de plataforma / proveedor en tanto por uno (ej. 0.015 = 1.5 %).
  double get commissionPlatform;

  /// Comisión por método de pago / pasarela en tanto por uno (ej. 0.003 = 0.3 %).
  double get commissionPaymentMethod;

  /// Otra comisión en tanto por uno.
  double get commissionOther;

  int get roundStep;
  RateSource get rateSource;
  MarginMode get marginMode;
  int get version;

  bool get isValid =>
      id.isNotEmpty &&
      costUsd > 0 &&
      (commissionPlatform + commissionPaymentMethod + commissionOther) < 1.0;

  Map<String, dynamic> baseParamsToJson() => {
        'v': version,
        'id': id,
        'title': title,
        'costUsd': costUsd,
        'marginPercent': marginPercent,
        'fixedExpenseBs': fixedExpenseBs,
        'commissionPlatform': commissionPlatform,
        'commissionPaymentMethod': commissionPaymentMethod,
        'commissionOther': commissionOther,
        'roundStep': roundStep,
        'rateSourceName': rateSource.name,
        'marginMode': marginMode.name,
      };
}

RateSource _parseRateSource(String? name) {
  if (name == null) return RateSource.bcvUsd;
  for (final s in RateSource.values) {
    if (s.name == name) return s;
  }
  return RateSource.bcvUsd;
}

/// Entrada del historial de cálculos (congela `rateValue` y `finalPriceBs`).
///
/// Se almacena en `calc_history_list` (separado de [Preset]), sin flag `isPreset`.
class HistoryEntry with CalculationParamsMixin {
  const HistoryEntry({
    required this.id,
    required this.title,
    required this.costUsd,
    required this.marginPercent,
    required this.fixedExpenseBs,
    required this.commissionPlatform,
    required this.commissionPaymentMethod,
    required this.commissionOther,
    required this.roundStep,
    required this.rateSource,
    this.marginMode = MarginMode.onCost,
    required this.rateValue,
    required this.finalPriceBs,
    required this.timestamp,
    this.version = currentVersion,
  });

  static const int currentVersion = 1;

  @override
  final String id;
  @override
  final String title;
  @override
  final double costUsd;
  @override
  final double marginPercent;
  @override
  final double fixedExpenseBs;
  @override
  final double commissionPlatform;
  @override
  final double commissionPaymentMethod;
  @override
  final double commissionOther;
  @override
  final int roundStep;
  @override
  final RateSource rateSource;
  @override
  final MarginMode marginMode;
  @override
  final int version;

  final double rateValue;
  final double finalPriceBs;
  final DateTime timestamp;

  @override
  bool get isValid => super.isValid && rateValue > 0 && finalPriceBs > 0;

  Map<String, dynamic> toJson() => {
        ...baseParamsToJson(),
        'rateValue': rateValue,
        'finalPriceBs': finalPriceBs,
        'timestamp': timestamp.toIso8601String(),
      };

  /// Deserializa con `try/catch` y fallback a estado vacío.
  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    try {
      final v = (json['v'] as num?)?.toInt() ?? 1;
      final id = json['id']?.toString() ?? '';
      final title = json['title']?.toString() ?? '';
      final costUsd = (json['costUsd'] as num?)?.toDouble() ?? 0.0;
      final marginPercent = (json['marginPercent'] as num?)?.toDouble() ?? 0.0;
      final fixedExpenseBs = (json['fixedExpenseBs'] as num?)?.toDouble() ?? 0.0;
      final commissionPlatform = (json['commissionPlatform'] as num?)?.toDouble() ??
          (json['commissionProvider'] as num?)?.toDouble() ??
          0.0;
      final commissionPaymentMethod =
          (json['commissionPaymentMethod'] as num?)?.toDouble() ??
              (json['commissionGateway'] as num?)?.toDouble() ??
              0.0;
      final commissionOther = (json['commissionOther'] as num?)?.toDouble() ?? 0.0;
      final roundStep = (json['roundStep'] as num?)?.toInt() ?? 10;
      final rateSource = _parseRateSource(json['rateSourceName']?.toString());
      final marginMode = MarginMode.fromName(json['marginMode']?.toString());
      final rateValue = (json['rateValue'] as num?)?.toDouble() ?? 0.0;
      final finalPriceBs = (json['finalPriceBs'] as num?)?.toDouble() ?? 0.0;
      final parsedTs = DateTime.tryParse(json['timestamp']?.toString() ?? '');

      if (id.isEmpty || costUsd <= 0 || rateValue <= 0 || finalPriceBs <= 0 || parsedTs == null) {
        return HistoryEntry.empty();
      }

      return HistoryEntry(
        version: v,
        id: id,
        title: title,
        costUsd: costUsd,
        marginPercent: marginPercent,
        fixedExpenseBs: fixedExpenseBs,
        commissionPlatform: commissionPlatform,
        commissionPaymentMethod: commissionPaymentMethod,
        commissionOther: commissionOther,
        roundStep: roundStep,
        rateSource: rateSource,
        marginMode: marginMode,
        rateValue: rateValue,
        finalPriceBs: finalPriceBs,
        timestamp: parsedTs,
      );
    } catch (_) {
      return HistoryEntry.empty();
    }
  }

  factory HistoryEntry.empty() => HistoryEntry(
        id: '',
        title: '',
        costUsd: 0,
        marginPercent: 0,
        fixedExpenseBs: 0,
        commissionPlatform: 0,
        commissionPaymentMethod: 0,
        commissionOther: 0,
        roundStep: 10,
        rateSource: RateSource.bcvUsd,
        marginMode: MarginMode.onCost,
        rateValue: 0,
        finalPriceBs: 0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      );

  static List<HistoryEntry> listFromJson(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! List) return const [];
      final list = <HistoryEntry>[];
      for (final item in decoded) {
        if (item is Map) {
          final entry = HistoryEntry.fromJson(Map<String, dynamic>.from(item));
          if (entry.isValid) list.add(entry);
        }
      }
      return list;
    } catch (_) {
      return const [];
    }
  }
}

/// Plantilla / Preset guardada por el vendedor.
///
/// Guarda `rateSourceName` y recalcula el precio final en Bs con la tasa vigente
/// al momento de aplicarse o visualizarse.
class Preset with CalculationParamsMixin {
  const Preset({
    required this.id,
    required this.title,
    required this.costUsd,
    required this.marginPercent,
    required this.fixedExpenseBs,
    required this.commissionPlatform,
    required this.commissionPaymentMethod,
    required this.commissionOther,
    required this.roundStep,
    required this.rateSource,
    this.marginMode = MarginMode.onCost,
    required this.createdAt,
    this.customRateValue,
    this.version = currentVersion,
  });

  static const int currentVersion = 1;

  @override
  final String id;
  @override
  final String title;
  @override
  final double costUsd;
  @override
  final double marginPercent;
  @override
  final double fixedExpenseBs;
  @override
  final double commissionPlatform;
  @override
  final double commissionPaymentMethod;
  @override
  final double commissionOther;
  @override
  final int roundStep;
  @override
  final RateSource rateSource;
  @override
  final MarginMode marginMode;
  @override
  final int version;

  /// Valor de tasa manual solo cuando [rateSource] es [RateSource.custom].
  final double? customRateValue;
  final DateTime createdAt;

  /// Recalcula el precio final en Bs (redondeado hacia arriba) usando [liveRate].
  double? recalculatePriceBs(double liveRate) {
    final effectiveRate =
        rateSource == RateSource.custom ? (customRateValue ?? liveRate) : liveRate;
    if (effectiveRate <= 0 || !isValid) return null;
    try {
      final exact = MarginCalculator.salePrice(
        costUsd: costUsd,
        rate: effectiveRate,
        margin: marginPercent / 100.0,
        commissionProvider: commissionPlatform,
        commissionGateway: commissionPaymentMethod,
        commissionOther: commissionOther,
        fixedExpenseBs: fixedExpenseBs,
        marginMode: marginMode,
      );
      return MarginCalculator.roundUp(exact, roundStep);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        ...baseParamsToJson(),
        if (customRateValue != null) 'customRateValue': customRateValue,
        'createdAt': createdAt.toIso8601String(),
      };

  /// Deserializa con `try/catch` y fallback a estado vacío.
  factory Preset.fromJson(Map<String, dynamic> json) {
    try {
      final v = (json['v'] as num?)?.toInt() ?? 1;
      final id = json['id']?.toString() ?? '';
      final title = json['title']?.toString() ?? '';
      final costUsd = (json['costUsd'] as num?)?.toDouble() ?? 0.0;
      final marginPercent = (json['marginPercent'] as num?)?.toDouble() ?? 0.0;
      final fixedExpenseBs = (json['fixedExpenseBs'] as num?)?.toDouble() ?? 0.0;
      final commissionPlatform = (json['commissionPlatform'] as num?)?.toDouble() ??
          (json['commissionProvider'] as num?)?.toDouble() ??
          0.0;
      final commissionPaymentMethod =
          (json['commissionPaymentMethod'] as num?)?.toDouble() ??
              (json['commissionGateway'] as num?)?.toDouble() ??
              0.0;
      final commissionOther = (json['commissionOther'] as num?)?.toDouble() ?? 0.0;
      final roundStep = (json['roundStep'] as num?)?.toInt() ?? 10;
      final rateSource = _parseRateSource(json['rateSourceName']?.toString());
      final marginMode = MarginMode.fromName(json['marginMode']?.toString());
      final customRateValue = (json['customRateValue'] as num?)?.toDouble();
      final parsedTs = DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.tryParse(json['timestamp']?.toString() ?? '');

      if (id.isEmpty || title.isEmpty || costUsd <= 0 || parsedTs == null) {
        return Preset.empty();
      }

      return Preset(
        version: v,
        id: id,
        title: title,
        costUsd: costUsd,
        marginPercent: marginPercent,
        fixedExpenseBs: fixedExpenseBs,
        commissionPlatform: commissionPlatform,
        commissionPaymentMethod: commissionPaymentMethod,
        commissionOther: commissionOther,
        roundStep: roundStep,
        rateSource: rateSource,
        marginMode: marginMode,
        customRateValue: customRateValue,
        createdAt: parsedTs,
      );
    } catch (_) {
      return Preset.empty();
    }
  }

  factory Preset.empty() => Preset(
        id: '',
        title: '',
        costUsd: 0,
        marginPercent: 0,
        fixedExpenseBs: 0,
        commissionPlatform: 0,
        commissionPaymentMethod: 0,
        commissionOther: 0,
        roundStep: 10,
        rateSource: RateSource.bcvUsd,
        marginMode: MarginMode.onCost,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  static List<Preset> listFromJson(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! List) return const [];
      final list = <Preset>[];
      for (final item in decoded) {
        if (item is Map) {
          final preset = Preset.fromJson(Map<String, dynamic>.from(item));
          if (preset.isValid) list.add(preset);
        }
      }
      return list;
    } catch (_) {
      return const [];
    }
  }
}

