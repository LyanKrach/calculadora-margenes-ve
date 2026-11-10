import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/rate.dart';
import '../models/rate_snapshot.dart';
import '../utils/format.dart';
import '../services/calculator.dart';
import '../services/rates_service.dart';
import '../widgets/rates_bar_chart.dart';

/// Pantalla de tasas: valores actuales, fuente, fecha de actualización
/// y estado sin conexión (muestra la última tasa guardada).
class RatesScreen extends StatefulWidget {
  const RatesScreen({super.key});

  @override
  State<RatesScreen> createState() => _RatesScreenState();
}

class _RatesScreenState extends State<RatesScreen> {
  final _service = RatesService();
  Map<RateSource, Rate> _rates = {};
  List<RateSnapshot> _snapshots = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    _rates = await _service.fetchAll();
    _snapshots = await _service.getSnapshots();
    if (mounted) setState(() => _loading = false);
  }

  String _sourceDetail(RateSource s) {
    return switch (s) {
      RateSource.bcvUsd => 'DolarApi · ve.dolarapi.com/v1/dolares/oficial · campo promedio',
      RateSource.binanceUsdt => 'Binance P2P · mediana de 10 anuncios (VES/USDT, BUY) · respaldo: quote-price y DolarApi paralelo',
      RateSource.euroBcv => 'DolarApi · ve.dolarapi.com/v1/euros/oficial · campo promedio',
      RateSource.custom => 'Manual: la escribes tú en la calculadora',
    };
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm', 'es_VE');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasas del día'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final source in [
                    RateSource.bcvUsd,
                    RateSource.binanceUsdt,
                    RateSource.euroBcv,
                  ])
                    Card(
                      child: ListTile(
                        title: Text(source.label),
                        subtitle: Text(
                          '${_sourceDetail(source)}\n'
                          'Actualizada: ${_rates[source] == null ? '—' : fmt.format(_rates[source]!.fetchedAt)}',
                        ),
                        trailing: Text(
                          _rates[source] == null
                              ? '—'
                              : '${fmtRate(_rates[source]!.value)} ${source.unit}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        isThreeLine: true,
                      ),
                    ),
                  if ((_rates[RateSource.bcvUsd]?.value ?? 0) > 0 &&
                      (_rates[RateSource.binanceUsdt]?.value ?? 0) > 0) ...[
                    const SizedBox(height: 8),
                    _buildGapCard(
                      context: context,
                      bcvRate: _rates[RateSource.bcvUsd]!.value,
                      binanceRate: _rates[RateSource.binanceUsdt]!.value,
                    ),
                    const SizedBox(height: 8),
                    RatesBarChart(
                      bcvRate: _rates[RateSource.bcvUsd]!.value,
                      binanceRate: _rates[RateSource.binanceUsdt]!.value,
                      euroRate: _rates[RateSource.euroBcv]?.value ?? 0,
                      snapshots: _snapshots,
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('Sin conexión'),
                      subtitle: Text(
                        'Si no hay internet, la app muestra la última tasa guardada '
                        'con su fecha, marcada como "guardada". '
                        'Nunca inventa una tasa: si no hay red ni caché, usa el '
                        'último valor verificado (BCV 897,5383 · Binance 1045,00 · Euro 1001,186, del 2026-11-09).',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Valores de referencia del 2026-11-09: BCV dólar 897,5383 Bs/\$ · '
                    'Binance USDT P2P mediana 1045,00 Bs/USDT · Euro BCV 1001,186 Bs/€.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildGapCard({
    required BuildContext context,
    required double bcvRate,
    required double binanceRate,
  }) {
    final gapPercent = MarginCalculator.exchangeGapPercent(
      bcvRate: bcvRate,
      binanceRate: binanceRate,
    );
    final diffBs = binanceRate - bcvRate;
    final isPositive = diffBs >= 0;
    final sign = isPositive ? '+' : '';
    final theme = Theme.of(context);
    final accentColor = isPositive ? Colors.amber : Colors.green;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: accentColor.withAlpha(180),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.swap_vert,
                  color: accentColor,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Brecha Cambiaria (Binance vs BCV)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: accentColor.withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$sign${gapPercent.toStringAsFixed(2)} %',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Diferencia: $sign${fmtBs(diffBs)} Bs/USD',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              gapPercent >= 0
                  ? 'Si repones mercancía o compras divisas a tasa Binance (${fmtRate(binanceRate)} Bs) '
                      'pero cobras a tasa oficial BCV (${fmtRate(bcvRate)} Bs), '
                      'tu costo de reposición es un ${gapPercent.toStringAsFixed(1)} % mayor. '
                      '¡Asegúrate de que tu margen cubra este diferencial!'
                  : 'La tasa Binance se encuentra por debajo de la tasa oficial BCV.',
              style: TextStyle(
                fontSize: 13,
                color: theme.textTheme.bodyMedium?.color?.withAlpha(200),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
