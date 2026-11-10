import 'dart:math' as math;

import '../models/margin_mode.dart';

/// Calculadora de márgenes para comerciantes en Venezuela.
///
/// Soporta dos modalidades:
///
/// 1. [MarginMode.onCost] (Sobre costo / Markup):
///    El margen es un porcentaje directo del costo del producto:
///      Precio = (Costo en Bs × (1 + margen) + Gasto fijo) ÷ (1 − comisiones)
///    Ejemplo: Costo $0,66, tasa 964,20, margen 30 %:
///      Costo = 636,37 Bs -> Precio exacto = 636,37 × 1,30 = 827,28 Bs.
///
/// 2. [MarginMode.onSale] (Sobre venta / Financiero):
///    El margen representa qué fracción del precio final cobrado es ganancia líquida:
///      Precio = (Costo en Bs + Gasto fijo) ÷ (1 − comisiones − margen)
///    Ejemplo: Costo $10,00, tasa 897,54, margen 20 %, comisión 2 %:
///      Costo = 8.975,40 Bs -> Precio exacto = 8.975,40 ÷ 0,78 = 11.506,92 Bs.
class MarginCalculator {
  const MarginCalculator._();

  /// Costo en bolívares: costo en dólares × tasa.
  static double costInBs(double costUsd, double rate) => costUsd * rate;

  /// Precio de venta exacto (sin redondear).
  static double salePrice({
    required double costUsd,
    required double rate,
    required double margin, // tanto por uno, ej. 0.20 o 0.30
    required double commissionProvider,
    required double commissionGateway,
    required double commissionOther,
    double fixedExpenseBs = 0,
    MarginMode marginMode = MarginMode.onCost,
  }) {
    final totalCommission =
        commissionProvider + commissionGateway + commissionOther;

    if (marginMode == MarginMode.onCost) {
      final divisor = 1 - totalCommission;
      if (divisor <= 0) {
        throw ArgumentError(
          'Comisiones (${(totalCommission * 100).toStringAsFixed(1)} %) >= 100 %. '
          'Baja las comisiones.',
        );
      }
      final costBs = costInBs(costUsd, rate);
      return ((costBs * (1 + margin)) + fixedExpenseBs) / divisor;
    } else {
      final divisor = 1 - totalCommission - margin;
      if (divisor <= 0) {
        throw ArgumentError(
          'Comisiones (${(totalCommission * 100).toStringAsFixed(1)} %) + '
          'margen (${(margin * 100).toStringAsFixed(1)} %) >= 100 %. '
          'Baja el margen o las comisiones.',
        );
      }
      return (costInBs(costUsd, rate) + fixedExpenseBs) / divisor;
    }
  }

  /// Redondeo hacia arriba al múltiplo elegido (0 = exacto, 1 = Bs 1, 10, 50 o 100 Bs).
  ///
  /// Si [step] <= 0, redondea a 2 decimales estándar.
  static double roundUp(double value, int step) {
    if (step <= 0) {
      return (value * 100).round() / 100.0;
    }
    return (value / step).ceil() * step.toDouble();
  }

  /// Desglose completo de un precio ya calculado (exacto o redondeado).
  static Breakdown breakdown({
    required double costUsd,
    required double rate,
    required double margin,
    required double commissionProvider,
    required double commissionGateway,
    required double commissionOther,
    double fixedExpenseBs = 0,
    required double finalPriceBs,
    MarginMode marginMode = MarginMode.onCost,
  }) {
    final costBs = costInBs(costUsd, rate);
    final totalCommission =
        commissionProvider + commissionGateway + commissionOther;
    final commissionBs = finalPriceBs * totalCommission;

    final profitBs = marginMode == MarginMode.onCost
        ? costBs * margin
        : finalPriceBs * margin;

    final roundingExtraBs =
        finalPriceBs - (costBs + fixedExpenseBs) - commissionBs - profitBs;

    final realMarginOnSale = finalPriceBs > 0
        ? (finalPriceBs - costBs - fixedExpenseBs - commissionBs) / finalPriceBs
        : 0.0;
    final realMarginOnCost = costBs > 0
        ? (finalPriceBs - commissionBs - fixedExpenseBs - costBs) / costBs
        : 0.0;

    return Breakdown(
      costBs: costBs,
      fixedExpenseBs: fixedExpenseBs,
      commissionBs: commissionBs,
      commissionProviderBs: finalPriceBs * commissionProvider,
      commissionGatewayBs: finalPriceBs * commissionGateway,
      commissionOtherBs: finalPriceBs * commissionOther,
      profitBs: profitBs,
      roundingExtraBs: roundingExtraBs,
      finalPriceBs: finalPriceBs,
      realMargin: realMarginOnSale,
      realMarginOnCost: realMarginOnCost,
      marginMode: marginMode,
    );
  }

  /// Calculadora inversa: con un precio actual, ¿cuál es el margen real?
  ///
  /// En [MarginMode.onCost]: margen sobre costo = (Neto recibido − Costo) ÷ Costo.
  /// En [MarginMode.onSale]: margen sobre venta = (Neto recibido − Costo) ÷ Precio.
  static double realMargin({
    required double costUsd,
    required double rate,
    required double totalCommission,
    double fixedExpenseBs = 0,
    required double currentPriceBs,
    MarginMode marginMode = MarginMode.onCost,
  }) {
    if (currentPriceBs <= 0) return double.negativeInfinity;
    final costBs = costInBs(costUsd, rate);
    final netReceived = currentPriceBs * (1 - totalCommission) - fixedExpenseBs;

    if (marginMode == MarginMode.onCost) {
      if (costBs <= 0) return 0.0;
      return (netReceived - costBs) / costBs;
    } else {
      return (netReceived - costBs) / currentPriceBs;
    }
  }

  /// Brecha cambiaria entre dos tasas (típicamente Binance USDT vs BCV USD) en porcentaje:
  ///   ((binanceRate - bcvRate) / bcvRate) * 100
  static double exchangeGapPercent({
    required double bcvRate,
    required double binanceRate,
  }) {
    if (bcvRate <= 0) return 0.0;
    return ((binanceRate - bcvRate) / bcvRate) * 100;
  }

  /// Tabla comparativa: precio para márgenes del 10 % al 40 % en pasos de 5 puntos.
  static List<MarginRow> comparisonTable({
    required double costUsd,
    required double rate,
    required double totalCommission,
    double fixedExpenseBs = 0,
    int roundStep = 10,
    MarginMode marginMode = MarginMode.onCost,
  }) {
    const margins = [0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40];
    final costBs = costInBs(costUsd, rate);

    final validMargins = marginMode == MarginMode.onCost
        ? margins.where((_) => totalCommission < 1.0)
        : margins.where((m) => totalCommission + m < 1.0);

    return validMargins.map((margin) {
      final exact = salePrice(
        costUsd: costUsd,
        rate: rate,
        margin: margin,
        commissionProvider: totalCommission,
        commissionGateway: 0,
        commissionOther: 0,
        fixedExpenseBs: fixedExpenseBs,
        marginMode: marginMode,
      );
      final rounded = roundUp(exact, roundStep);
      final netProfit =
          rounded - costBs - fixedExpenseBs - (rounded * totalCommission);
      return MarginRow(
        margin: margin,
        exactPriceBs: exact,
        roundedPriceBs: rounded,
        profitBs: marginMode == MarginMode.onCost ? costBs * margin : exact * margin,
        netProfitBs: netProfit,
      );
    }).toList();
  }
}

class Breakdown {
  const Breakdown({
    required this.costBs,
    required this.fixedExpenseBs,
    required this.commissionBs,
    required this.commissionProviderBs,
    required this.commissionGatewayBs,
    required this.commissionOtherBs,
    required this.profitBs,
    required this.roundingExtraBs,
    required this.finalPriceBs,
    required this.realMargin,
    required this.realMarginOnCost,
    required this.marginMode,
  });

  final double costBs;
  final double fixedExpenseBs;
  final double commissionBs;
  final double commissionProviderBs;
  final double commissionGatewayBs;
  final double commissionOtherBs;
  final double profitBs;
  final double roundingExtraBs;
  final double finalPriceBs;

  /// Margen real sobre el precio final de venta.
  final double realMargin;

  /// Margen real sobre el costo (markup).
  final double realMarginOnCost;

  final MarginMode marginMode;

  /// Ganancia neta en Bs = ganancia por margen + extra del redondeo.
  double get netProfitBs => profitBs + roundingExtraBs;
}

class MarginRow {
  const MarginRow({
    required this.margin,
    required this.exactPriceBs,
    required this.roundedPriceBs,
    required this.profitBs,
    double? netProfitBs,
  }) : netProfitBs = netProfitBs ?? profitBs;

  final double margin;
  final double exactPriceBs;
  final double roundedPriceBs;
  final double profitBs;

  /// Ganancia neta real en Bs al cobrar [roundedPriceBs] (incluye extra por redondeo).
  final double netProfitBs;
}

/// Mediana de una lista de precios (la usa el fetch de Binance P2P).
/// Con un número par de valores se promedian los dos centrales.
double median(List<double> values) {
  if (values.isEmpty) throw ArgumentError('Lista vacía');
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Redondeo hacia arriba expuesto para pruebas rápidas.
double roundUpTo(double value, int step) =>
    math.max(0, (value / step).ceil() * step).toDouble();
