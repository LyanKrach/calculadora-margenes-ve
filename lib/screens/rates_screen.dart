import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/rate.dart';
import '../models/rate_snapshot.dart';
import '../utils/format.dart';
import '../services/calculator.dart';
import '../services/rates_service.dart';
import '../theme/app_theme.dart';
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
      RateSource.bcvUsd => 'Tasa oficial Banco Central de Venezuela',
      RateSource.binanceUsdt => 'Mercado P2P en bolívares (referencia USDT)',
      RateSource.euroBcv => 'Tasa oficial Banco Central de Venezuela (Euro)',
      RateSource.custom => 'Tasa manual',
    };
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm', 'es_VE');
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Tasas del día'),
        actions: [
          IconButton(
            style: IconButton.styleFrom(
              backgroundColor: context.appColors.surface,
              foregroundColor: context.appColors.textPrimary,
              side: BorderSide(color: context.appColors.borderSubtle),
              shape: const CircleBorder(),
              minimumSize: const Size(40, 40),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _refresh,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  for (final source in [
                    RateSource.bcvUsd,
                    RateSource.binanceUsdt,
                    RateSource.euroBcv,
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      source.label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_sourceDetail(source)}\n'
                                      '${_rates[source]?.effectiveDate != null && _rates[source]!.effectiveDate!.isNotEmpty ? "${formatEffectiveDate(_rates[source]!.effectiveDate)}\n" : ""}'
                                      'Actualizada: ${_rates[source] == null ? '—' : fmt.format(_rates[source]!.fetchedAt)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: context.appColors.textSecondary,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _rates[source] == null
                                    ? '—'
                                    : '${fmtRate(_rates[source]!.value)} ${source.unit}',
                                textAlign: TextAlign.end,
                                style: AppTypography.rateValue(context),
                              ),
                            ],
                          ),
                        ),
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
                    const SizedBox(height: 20),
                    RatesBarChart(
                      bcvRate: _rates[RateSource.bcvUsd]!.value,
                      binanceRate: _rates[RateSource.binanceUsdt]!.value,
                      euroRate: _rates[RateSource.euroBcv]?.value ?? 0,
                      snapshots: _snapshots,
                    ),
                  ],
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: ListTile(
                        leading: Icon(
                          Icons.info_outline,
                          color: context.appColors.textSecondary,
                        ),
                        title: const Text(
                          'Modo sin conexión',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          'Si no hay internet, la app muestra la última tasa guardada '
                          'con su fecha y hora.',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.appColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
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
    final colors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isPositive ? colors.amber : colors.primary;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.65),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: isDark ? 0.18 : 0.10),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.swap_vert, color: accentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Brecha Cambiaria (Binance vs BCV)',
                    style: AppTypography.sectionTitle(
                      context,
                    ).copyWith(color: accentColor),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$sign${gapPercent.toStringAsFixed(2)} %',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Diferencia: $sign${fmtBs(diffBs)} Bs/USD',
              style: AppTypography.rateValue(context),
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
                color: colors.textSecondary,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
