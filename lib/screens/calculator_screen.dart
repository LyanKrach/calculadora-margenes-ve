import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/rate.dart';
import '../utils/format.dart';
import '../services/calculator.dart';
import '../services/rates_service.dart';

/// Pantalla principal: costo, tasa (4 tarjetas), margen, comisiones,
/// gasto fijo → precio de venta con desglose paso a paso, calculadora
/// inversa y tabla comparativa 10 %-40 %.
class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final _rates = RatesService();

  final _costCtrl = TextEditingController(text: '10');
  final _marginCtrl = TextEditingController(text: '20');
  final _provCtrl = TextEditingController(text: '2');
  final _gatewayCtrl = TextEditingController(text: '0');
  final _otherCtrl = TextEditingController(text: '0');
  final _fixedCtrl = TextEditingController(text: '0');
  final _customRateCtrl = TextEditingController();
  final _inversePriceCtrl = TextEditingController();

  RateSource _selectedSource = RateSource.bcvUsd;
  Map<RateSource, Rate> _ratesMap = {};
  bool _loadingRates = true;
  String? _ratesError;
  int _roundStep = 10;

  double get _costUsd => double.tryParse(_costCtrl.text.replaceAll(',', '.')) ?? 0;
  double get _margin => (double.tryParse(_marginCtrl.text.replaceAll(',', '.')) ?? 0) / 100;
  double get _prov => (double.tryParse(_provCtrl.text.replaceAll(',', '.')) ?? 0) / 100;
  double get _gateway => (double.tryParse(_gatewayCtrl.text.replaceAll(',', '.')) ?? 0) / 100;
  double get _other => (double.tryParse(_otherCtrl.text.replaceAll(',', '.')) ?? 0) / 100;
  double get _fixed => double.tryParse(_fixedCtrl.text.replaceAll(',', '.')) ?? 0;
  double get _totalCommission => _prov + _gateway + _other;

  double get _rate {
    if (_selectedSource == RateSource.custom) {
      return double.tryParse(_customRateCtrl.text.replaceAll(',', '.')) ?? 0;
    }
    return _ratesMap[_selectedSource]?.value ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _loadRates();
    _rates.getCustomRate().then((v) {
      if (v != null) _customRateCtrl.text = v.toStringAsFixed(2);
    });
    for (final c in [
      _costCtrl, _marginCtrl, _provCtrl, _gatewayCtrl, _otherCtrl,
      _fixedCtrl, _customRateCtrl, _inversePriceCtrl,
    ]) {
      c.addListener(() => setState(() {}));
    }
  }

  Future<void> _loadRates() async {
    setState(() => _loadingRates = true);
    try {
      _ratesMap = await _rates.fetchAll();
      _ratesError = null;
    } catch (e) {
      _ratesError = 'Sin conexión: se muestra la última tasa guardada.';
    }
    if (mounted) setState(() => _loadingRates = false);
  }

  @override
  void dispose() {
    for (final c in [
      _costCtrl, _marginCtrl, _provCtrl, _gatewayCtrl, _otherCtrl,
      _fixedCtrl, _customRateCtrl, _inversePriceCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copiado')),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool valid = _costUsd > 0 && _rate > 0 && _totalCommission + _margin < 1;
    double? exact;
    double? rounded;
    Breakdown? bd;
    if (valid) {
      try {
        exact = MarginCalculator.salePrice(
          costUsd: _costUsd,
          rate: _rate,
          margin: _margin,
          commissionProvider: _prov,
          commissionGateway: _gateway,
          commissionOther: _other,
          fixedExpenseBs: _fixed,
        );
        rounded = MarginCalculator.roundUp(exact, _roundStep);
        bd = MarginCalculator.breakdown(
          costUsd: _costUsd,
          rate: _rate,
          margin: _margin,
          commissionProvider: _prov,
          commissionGateway: _gateway,
          commissionOther: _other,
          fixedExpenseBs: _fixed,
          finalPriceBs: rounded,
        );
      } catch (_) {
        valid = false;
      }
    }

    final inversePrice =
        double.tryParse(_inversePriceCtrl.text.replaceAll(',', '.'));
    final inverseMargin = (valid && inversePrice != null && inversePrice > 0)
        ? MarginCalculator.realMargin(
            costUsd: _costUsd,
            rate: _rate,
            totalCommission: _totalCommission,
            fixedExpenseBs: _fixed,
            currentPriceBs: inversePrice,
          )
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calculadora de Márgenes VE'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar tasas',
            onPressed: _loadRates,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- 4 tarjetas de tasa ---
          const Text('Tasa del día', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_loadingRates)
            const LinearProgressIndicator()
          else
            ...RateSource.values.map((s) => _rateCard(s)),
          if (_ratesError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_ratesError!, style: const TextStyle(color: Colors.orange)),
            ),
          if (_selectedSource == RateSource.custom)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: _customRateCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Tasa personalizada (Bs/\$)',
                  hintText: 'Ej. 950,00',
                ),
                onChanged: (_) async {
                  final v = double.tryParse(_customRateCtrl.text.replaceAll(',', '.'));
                  if (v != null && v > 0) await _rates.setCustomRate(v);
                },
              ),
            ),
          const SizedBox(height: 16),

          // --- Inputs ---
          _numField(_costCtrl, 'Costo del producto (\$)'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _numField(_marginCtrl, 'Margen deseado (%)')),
            const SizedBox(width: 8),
            Expanded(child: _numField(_fixedCtrl, 'Gasto fijo (Bs)')),
          ]),
          const SizedBox(height: 8),
          const Text('Comisiones (%)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _numField(_provCtrl, 'Proveedor')),
            const SizedBox(width: 8),
            Expanded(child: _numField(_gatewayCtrl, 'Pasarela')),
            const SizedBox(width: 8),
            Expanded(child: _numField(_otherCtrl, 'Otra')),
          ]),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 10, label: Text('Bs 10')),
              ButtonSegment(value: 50, label: Text('Bs 50')),
              ButtonSegment(value: 100, label: Text('Bs 100')),
            ],
            selected: {_roundStep},
            onSelectionChanged: (s) => setState(() => _roundStep = s.first),
          ),
          const SizedBox(height: 16),

          // --- Resultado + desglose paso a paso ---
          if (!valid)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Revisa los datos: el costo y la tasa deben ser mayores que 0, '
                  'y comisiones + margen deben sumar menos del 100 %.',
                ),
              ),
            )
          else if (bd != null && rounded != null && exact != null) ...[
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Precio de venta', style: TextStyle(fontSize: 14)),
                    Text(
                      '${fmtBs(rounded)} Bs',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Precio exacto: ${fmtBs(exact)} Bs · redondeado hacia arriba a Bs $_roundStep',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      'Ganancia neta: ${fmtBs(bd.netProfitBs)} Bs '
                      '(≈ \$${fmtUsd(bd.netProfitBs / _rate)}) · '
                      'margen real ${(bd.realMargin * 100).toStringAsFixed(1)} %',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      FilledButton.icon(
                        onPressed: () => _copy('${fmtBs(rounded!)} Bs', 'Precio'),
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copiar precio'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _copy(
                          'Precio: ${fmtBs(rounded!)} Bs (tasa ${_selectedSource.label} ${fmtRate(_rate)} Bs/\$).',
                          'Mensaje',
                        ),
                        icon: const Icon(Icons.message_outlined, size: 18),
                        label: const Text('Mensaje cliente'),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Desglose paso a paso', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _step('1. Costo en Bs', 'Costo × tasa = \$${fmtUsd(_costUsd)} × ${fmtRate(_rate)} = ${fmtBs(bd.costBs)} Bs'),
            _step('2. Gasto fijo', '${fmtBs(bd.fixedExpenseBs)} Bs'),
            _step('3. Precio exacto',
                '(${fmtBs(bd.costBs)} + ${fmtBs(bd.fixedExpenseBs)}) ÷ (1 − ${(_totalCommission * 100).toStringAsFixed(1)} % − ${(_margin * 100).toStringAsFixed(1)} %) = ${fmtBs(exact)} Bs'),
            _step('4. Redondeo hacia arriba', '${fmtBs(exact)} → ${fmtBs(rounded)} Bs (a Bs $_roundStep)'),
            _step('5. Comisiones (${(_totalCommission * 100).toStringAsFixed(1)} %)',
                '${fmtBs(bd.commissionBs)} Bs (proveedor ${fmtBs(bd.commissionProviderBs)} · pasarela ${fmtBs(bd.commissionGatewayBs)} · otra ${fmtBs(bd.commissionOtherBs)})'),
            _step('6. Ganancia (${(_margin * 100).toStringAsFixed(1)} %)',
                '${fmtBs(bd.profitBs)} Bs + ${fmtBs(bd.roundingExtraBs)} Bs por redondeo = ${fmtBs(bd.netProfitBs)} Bs netos'),
            _step('Comprobación',
                '${fmtBs(bd.costBs)} + ${fmtBs(bd.fixedExpenseBs)} + ${fmtBs(bd.commissionBs)} + ${fmtBs(bd.netProfitBs)} = ${fmtBs(rounded)} Bs ✓'),
            const SizedBox(height: 16),

            // --- Tabla comparativa 10 %-40 % ---
            const Text('Tabla comparativa por margen', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: MarginCalculator.comparisonTable(
                  costUsd: _costUsd,
                  rate: _rate,
                  totalCommission: _totalCommission,
                  fixedExpenseBs: _fixed,
                  roundStep: _roundStep,
                ).map((row) => ListTile(
                      dense: true,
                      title: Text('${(row.margin * 100).toStringAsFixed(0)} %'),
                      trailing: Text(
                        '${fmtBs(row.roundedPriceBs)} Bs',
                        style: TextStyle(
                          fontWeight: row.margin == _margin ? FontWeight.bold : FontWeight.normal,
                          color: row.margin == _margin
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                      ),
                      subtitle: Text('Ganancia ${fmtBs(row.profitBs)} Bs'),
                    )).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // --- Calculadora inversa ---
            const Text('Calculadora inversa', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _inversePriceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Precio actual que cobras (Bs)',
                hintText: 'Ej. 12000',
              ),
            ),
            if (inverseMargin != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  inverseMargin < 0
                      ? 'Margen real: ${(inverseMargin * 100).toStringAsFixed(1)} % — ¡PIERDES DINERO con ese precio!'
                      : 'Margen real con ese precio: ${(inverseMargin * 100).toStringAsFixed(1)} %',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: inverseMargin < 0 ? Colors.red : Colors.green,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 24),
          const Text(
            'Fórmula: Precio = (Costo en Bs + Gasto fijo) ÷ (1 − comisiones − margen). '
            'El margen es sobre el precio de venta, no sobre el costo.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _rateCard(RateSource source) {
    final rate = _ratesMap[source];
    final selected = _selectedSource == source;
    final subtitle = source == RateSource.custom
        ? 'La escribes tú, sin internet'
        : rate == null
            ? 'Sin datos'
            : '${fmtRate(rate.value)} ${source.unit}'
                '${rate.isCached ? ' · guardada' : ''}';
    return Card(
      color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
      child: ListTile(
        title: Text(source.label),
        subtitle: Text(subtitle),
        trailing: selected ? const Icon(Icons.check_circle) : null,
        onTap: () => setState(() => _selectedSource = source),
      ),
    );
  }

  Widget _numField(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
    );
  }

  Widget _step(String title, String detail) {
    return Card(
      child: ListTile(title: Text(title), subtitle: Text(detail)),
    );
  }
}
