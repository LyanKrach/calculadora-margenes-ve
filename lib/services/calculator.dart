import 'dart:math' as math;

/// Calculadora de márgenes para vendedores en Venezuela.
///
/// FÓRMULA (el margen es sobre el precio de venta, no sobre el costo):
///
///   Costo en Bs = costo (USD) × tasa (Bs/$)
///   Precio de venta en Bs = (Costo en Bs + Gasto fijo) ÷ (1 − comisiones − margen)
///
/// donde `comisiones` es la suma proveedor + pasarela + otra, y `margen`
/// es el margen deseado, ambos en tanto por uno (20 % = 0.20).
///
/// Ejemplo verificado (2026-11-09, tasa BCV 897,54):
///   costo \$10,00 · tasa 897,54 · margen 20 % · comisión 2 % · gasto fijo 0
///   Costo en Bs = 10 × 897,54 = 8.975,40 Bs
///   Precio = 8.975,40 ÷ (1 − 0,02 − 0,20) = 8.975,40 ÷ 0,78 = 11.506,92 Bs
///   Comisión (2 %) = 11.506,92 × 0,02 = 230,14 Bs
///   Ganancia (20 %) = 11.506,92 × 0,20 = 2.301,38 Bs
///   Comprobación: 8.975,40 + 230,14 + 2.301,38 = 11.506,92 Bs ✓
class MarginCalculator {
  const MarginCalculator._();

  /// Costo en bolívares: costo en dólares × tasa.
  static double costInBs(double costUsd, double rate) => costUsd * rate;

  /// Precio de venta exacto (sin redondear).
  ///
  /// Lanza [ArgumentError] si comisiones + margen ≥ 1 (el divisor sería
  /// cero o negativo: el precio sería infinito o negativo, es decir,
  /// la operación pierde dinero con cualquier precio).
  static double salePrice({
    required double costUsd,
    required double rate,
    required double margin, // tanto por uno, ej. 0.20
    required double commissionProvider,
    required double commissionGateway,
    required double commissionOther,
    double fixedExpenseBs = 0,
  }) {
    final totalCommission =
        commissionProvider + commissionGateway + commissionOther;
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

  /// Redondeo SIEMPRE hacia arriba al múltiplo elegido (10, 50 o 100 Bs).
  /// Nunca hacia abajo: redondear hacia abajo podría dejar el precio
  /// por debajo del punto de equilibrio.
  ///
  /// Ejemplos: 11.506,92 → 11.510 (a 10), 11.550 (a 50), 11.600 (a 100).
  static double roundUp(double value, int step) {
    if (step <= 0) return value;
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
  }) {
    final costBs = costInBs(costUsd, rate);
    final totalCommission =
        commissionProvider + commissionGateway + commissionOther;
    return Breakdown(
      costBs: costBs,
      fixedExpenseBs: fixedExpenseBs,
      commissionBs: finalPriceBs * totalCommission,
      commissionProviderBs: finalPriceBs * commissionProvider,
      commissionGatewayBs: finalPriceBs * commissionGateway,
      commissionOtherBs: finalPriceBs * commissionOther,
      profitBs: finalPriceBs * margin,
      // Lo que sobra (o falta) por el redondeo hacia arriba:
      roundingExtraBs: finalPriceBs - (costBs + fixedExpenseBs) -
          (finalPriceBs * totalCommission) - (finalPriceBs * margin),
      finalPriceBs: finalPriceBs,
      realMargin: (finalPriceBs - costBs - fixedExpenseBs -
              finalPriceBs * totalCommission) /
          finalPriceBs,
    );
  }

  /// Calculadora inversa: con un precio actual, ¿cuál es el margen real?
  ///
  ///   Margen real = 1 − comisiones − (Costo en Bs + Gasto fijo) ÷ Precio
  ///
  /// Resultado negativo = se pierde dinero con ese precio.
  /// Ejemplo: costo \$10, tasa 897,54, comisión 2 %, precio 11.506,92 Bs
  /// → margen real = 1 − 0,02 − 8.975,40 ÷ 11.506,92 = 0,20 (20,0 %).
  static double realMargin({
    required double costUsd,
    required double rate,
    required double totalCommission,
    double fixedExpenseBs = 0,
    required double currentPriceBs,
  }) {
    if (currentPriceBs <= 0) return double.negativeInfinity;
    return 1 -
        totalCommission -
        (costInBs(costUsd, rate) + fixedExpenseBs) / currentPriceBs;
  }

  /// Tabla comparativa: precio (redondeado hacia arriba a [roundStep])
  /// para márgenes del 10 % al 40 % en pasos de 5 puntos.
  static List<MarginRow> comparisonTable({
    required double costUsd,
    required double rate,
    required double totalCommission,
    double fixedExpenseBs = 0,
    int roundStep = 10,
  }) {
    const margins = [0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40];
    return margins.map((margin) {
      final exact = salePrice(
        costUsd: costUsd,
        rate: rate,
        margin: margin,
        commissionProvider: totalCommission,
        commissionGateway: 0,
        commissionOther: 0,
        fixedExpenseBs: fixedExpenseBs,
      );
      return MarginRow(
        margin: margin,
        exactPriceBs: exact,
        roundedPriceBs: roundUp(exact, roundStep),
        profitBs: exact * margin,
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

  /// Margen real sobre el precio final (sube un poco con el redondeo).
  final double realMargin;

  /// Ganancia neta en Bs = ganancia por margen + extra del redondeo.
  double get netProfitBs => profitBs + roundingExtraBs;
}

class MarginRow {
  const MarginRow({
    required this.margin,
    required this.exactPriceBs,
    required this.roundedPriceBs,
    required this.profitBs,
  });

  final double margin;
  final double exactPriceBs;
  final double roundedPriceBs;
  final double profitBs;
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
