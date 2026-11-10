import 'dart:convert';

import '../services/calculator.dart';
import 'calculation_item.dart';
import 'margin_mode.dart';
import 'rate.dart';

/// Producto del catálogo del vendedor.
///
/// Calcula su precio de venta en bolívares y su ganancia neta al instante
/// en función de la tasa vigente sin necesidad de volver a calcular manualmente.
class ProductItem with CalculationParamsMixin {
  const ProductItem({
    required this.id,
    required this.name,
    this.category = '',
    required this.costUsd,
    required this.marginPercent,
    required this.fixedExpenseBs,
    required this.commissionPlatform,
    required this.commissionPaymentMethod,
    required this.commissionOther,
    required this.roundStep,
    required this.rateSource,
    this.marginMode = MarginMode.onCost,
    this.customRateValue,
    required this.createdAt,
    required this.updatedAt,
    this.version = currentVersion,
  });

  static const int currentVersion = 1;

  @override
  final String id;

  final String name;
  final String category;

  @override
  String get title => name;

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

  final double? customRateValue;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  bool get isValid => super.isValid && name.trim().isNotEmpty;

  /// Tasa efectiva según la fuente configurada para el producto.
  double effectiveRate(Map<RateSource, Rate> ratesMap, double globalCustomRate) {
    if (rateSource == RateSource.custom) {
      return (customRateValue != null && customRateValue! > 0)
          ? customRateValue!
          : globalCustomRate;
    }
    return ratesMap[rateSource]?.value ?? 0.0;
  }

  /// Calcula al instante el precio de venta redondeado en Bs con [rate].
  double? livePriceBs(double rate) {
    if (rate <= 0 || !isValid) return null;
    try {
      final exact = MarginCalculator.salePrice(
        costUsd: costUsd,
        rate: rate,
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

  /// Calcula al instante el desglose completo (ganancia neta, comisiones, etc.) con [rate].
  Breakdown? liveBreakdown(double rate) {
    final rounded = livePriceBs(rate);
    if (rounded == null || rate <= 0) return null;
    try {
      return MarginCalculator.breakdown(
        costUsd: costUsd,
        rate: rate,
        margin: marginPercent / 100.0,
        commissionProvider: commissionPlatform,
        commissionGateway: commissionPaymentMethod,
        commissionOther: commissionOther,
        fixedExpenseBs: fixedExpenseBs,
        finalPriceBs: rounded,
        marginMode: marginMode,
      );
    } catch (_) {
      return null;
    }
  }

  /// Convierte a mapa JSON compatible tanto con `SharedPreferences` como con `Firestore`.
  Map<String, dynamic> toJson() => {
        'v': version,
        'id': id,
        'name': name.trim(),
        if (category.trim().isNotEmpty) 'category': category.trim(),
        'costUsd': costUsd,
        'marginPercent': marginPercent,
        'fixedExpenseBs': fixedExpenseBs,
        'commissionPlatform': commissionPlatform,
        'commissionPaymentMethod': commissionPaymentMethod,
        'commissionOther': commissionOther,
        'roundStep': roundStep,
        'rateSourceName': rateSource.name,
        'marginMode': marginMode.name,
        if (customRateValue != null && customRateValue! >= 0)
          'customRateValue': customRateValue,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ProductItem.fromJson(Map<String, dynamic> json) {
    try {
      final v = (json['v'] as num?)?.toInt() ?? 1;
      final id = json['id']?.toString() ?? '';
      final name =
          json['name']?.toString().trim() ?? json['title']?.toString().trim() ?? '';
      final category = json['category']?.toString().trim() ?? '';
      final costUsd = (json['costUsd'] as num?)?.toDouble() ?? 0.0;
      final marginPercent = (json['marginPercent'] as num?)?.toDouble() ?? 0.0;
      final fixedExpenseBs = (json['fixedExpenseBs'] as num?)?.toDouble() ?? 0.0;
      final commissionPlatform =
          (json['commissionPlatform'] as num?)?.toDouble() ??
              (json['commissionProvider'] as num?)?.toDouble() ??
              0.0;
      final commissionPaymentMethod =
          (json['commissionPaymentMethod'] as num?)?.toDouble() ??
              (json['commissionGateway'] as num?)?.toDouble() ??
              0.0;
      final commissionOther =
          (json['commissionOther'] as num?)?.toDouble() ?? 0.0;
      final roundStep = (json['roundStep'] as num?)?.toInt() ?? 10;
      final rateSourceName = json['rateSourceName']?.toString();
      final marginMode = MarginMode.fromName(json['marginMode']?.toString());
      RateSource rateSource = RateSource.bcvUsd;
      if (rateSourceName != null) {
        for (final s in RateSource.values) {
          if (s.name == rateSourceName) {
            rateSource = s;
            break;
          }
        }
      }
      final customRateValue = (json['customRateValue'] as num?)?.toDouble();
      final createdAt =
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
      final updatedAt =
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? createdAt;

      if (id.isEmpty || name.isEmpty || costUsd <= 0) {
        return ProductItem.empty();
      }

      return ProductItem(
        version: v,
        id: id,
        name: name,
        category: category,
        costUsd: costUsd,
        marginPercent: marginPercent,
        fixedExpenseBs: fixedExpenseBs,
        commissionPlatform: commissionPlatform,
        commissionPaymentMethod: commissionPaymentMethod,
        commissionOther: commissionOther,
        roundStep: [0, 1, 10, 50, 100].contains(roundStep) ? roundStep : 10,
        rateSource: rateSource,
        marginMode: marginMode,
        customRateValue: customRateValue,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    } catch (_) {
      return ProductItem.empty();
    }
  }

  factory ProductItem.empty() => ProductItem(
        id: '',
        name: '',
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
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  static List<ProductItem> listFromJson(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! List) return const [];
      final list = <ProductItem>[];
      for (final item in decoded) {
        if (item is Map) {
          final prod = ProductItem.fromJson(Map<String, dynamic>.from(item));
          if (prod.isValid) list.add(prod);
        }
      }
      return list;
    } catch (_) {
      return const [];
    }
  }
}

