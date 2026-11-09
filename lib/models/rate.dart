/// Una tasa de cambio con su origen y fecha de obtención.
///
/// Fuentes posibles (valores reales observados el 2026-11-09):
/// - BCV dólar: 897,5383 Bs/$ (DolarApi, campo `promedio`)
/// - Euro BCV: 1001,186 Bs/€ (DolarApi)
/// - Binance USDT P2P (mediana): 1045,00 Bs/USDT
/// - Personalizada: la escribe el usuario, no se consulta a ninguna API.
enum RateSource {
  bcvUsd('BCV dólar', 'Bs/\$'),
  binanceUsdt('Binance USDT', 'Bs/USDT'),
  euroBcv('Euro BCV', 'Bs/€'),
  custom('Personalizada', 'Bs/\$');

  const RateSource(this.label, this.unit);
  final String label;
  final String unit;
}

class Rate {
  const Rate({
    required this.source,
    required this.value,
    required this.fetchedAt,
    this.isCached = false,
  });

  final RateSource source;
  final double value;
  final DateTime fetchedAt;

  /// true cuando el valor viene de la caché offline (no de la red).
  final bool isCached;

  Map<String, dynamic> toJson() => {
        'source': source.name,
        'value': value,
        'fetchedAt': fetchedAt.toIso8601String(),
      };

  factory Rate.fromJson(Map<String, dynamic> json) {
    return Rate(
      source: RateSource.values.firstWhere(
        (s) => s.name == json['source'],
        orElse: () => RateSource.bcvUsd,
      ),
      value: (json['value'] as num).toDouble(),
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
      isCached: true,
    );
  }
}
