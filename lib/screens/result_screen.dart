import 'package:flutter/material.dart';

import '../models/margin_mode.dart';
import '../models/rate.dart';
import '../services/calculator.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// Pantalla independiente de resultados estilo ArbiCalc:
/// - AppBar con flecha atrás + título "Resultado" + switch "Detalles" apagado por defecto.
/// - Resumen arriba: héroe verde con el precio (44px w800), chip de ganancia y 4 acciones.
/// - Con Detalles activado: desglose paso a paso numerado, tabla comparativa 10%–40% y calculadora inversa.
/// - Botón "Volver" fijo abajo que regresa a la Calculadora conservando todos los datos.
class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.costUsd,
    required this.rate,
    required this.rateSource,
    required this.margin,
    required this.marginMode,
    required this.commissionProvider,
    required this.commissionGateway,
    required this.commissionOther,
    required this.fixedExpenseBs,
    required this.roundStep,
    required this.exactPriceBs,
    required this.roundedPriceBs,
    required this.breakdown,
    this.inversePriceController,
    this.onCopyPrice,
    this.onCopyClientMessage,
    this.onShareWhatsApp,
    this.onSavePreset,
  });

  final double costUsd;
  final double rate;
  final RateSource rateSource;
  final double margin;
  final MarginMode marginMode;
  final double commissionProvider;
  final double commissionGateway;
  final double commissionOther;
  final double fixedExpenseBs;
  final int roundStep;
  final double exactPriceBs;
  final double roundedPriceBs;
  final Breakdown breakdown;
  final TextEditingController? inversePriceController;
  final Future<void> Function(BuildContext context, double roundedPriceBs)?
      onCopyPrice;
  final Future<void> Function(BuildContext context, double roundedPriceBs)?
      onCopyClientMessage;
  final Future<void> Function(BuildContext context, double roundedPriceBs)?
      onShareWhatsApp;
  final Future<void> Function(BuildContext context, double roundedPriceBs)?
      onSavePreset;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  bool _showDetails = false;
  late final TextEditingController _inverseCtrl;
  late final bool _ownsInverseCtrl;

  double get _totalCommission =>
      widget.commissionProvider +
      widget.commissionGateway +
      widget.commissionOther;

  @override
  void initState() {
    super.initState();
    if (widget.inversePriceController != null) {
      _inverseCtrl = widget.inversePriceController!;
      _ownsInverseCtrl = false;
    } else {
      _inverseCtrl = TextEditingController();
      _ownsInverseCtrl = true;
    }
    _inverseCtrl.addListener(_onInverseChanged);
  }

  void _onInverseChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _inverseCtrl.removeListener(_onInverseChanged);
    if (_ownsInverseCtrl) {
      _inverseCtrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final bd = widget.breakdown;
    final exact = widget.exactPriceBs;
    final rounded = widget.roundedPriceBs;

    final inversePrice = double.tryParse(
      _inverseCtrl.text.replaceAll(',', '.'),
    );
    final inverseMargin = (inversePrice != null && inversePrice > 0)
        ? MarginCalculator.realMargin(
            costUsd: widget.costUsd,
            rate: widget.rate,
            totalCommission: _totalCommission,
            fixedExpenseBs: widget.fixedExpenseBs,
            currentPriceBs: inversePrice,
            marginMode: widget.marginMode,
          )
        : null;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        leading: IconButton(
          tooltip: 'Volver',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Resultado',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _showDetails = !_showDetails),
                  child: Text(
                    'Detalles',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  height: 30,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Switch(
                      key: const Key('result_details_switch'),
                      value: _showDetails,
                      activeThumbColor: colors.primary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (val) => setState(() => _showDetails = val),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _showDetails
                    ? SingleChildScrollView(
                        key: const ValueKey('breakdown_visible'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildHeroPriceCard(
                              context: context,
                              rounded: rounded,
                              exact: exact,
                              bd: bd,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Desglose paso a paso',
                              style: AppTypography.sectionTitle(context),
                            ),
                            const SizedBox(height: 8),
                            _buildTimelineBreakdown(
                              context: context,
                              bd: bd,
                              exact: exact,
                              rounded: rounded,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Tabla comparativa por margen (${widget.marginMode.shortLabel})',
                              style: AppTypography.sectionTitle(context),
                            ),
                            const SizedBox(height: 8),
                            Card(
                              child: Column(
                                children: MarginCalculator.comparisonTable(
                                  costUsd: widget.costUsd,
                                  rate: widget.rate,
                                  totalCommission: _totalCommission,
                                  fixedExpenseBs: widget.fixedExpenseBs,
                                  roundStep: widget.roundStep,
                                  marginMode: widget.marginMode,
                                ).map((row) {
                                  final isCurrent =
                                      (row.margin - widget.margin).abs() <
                                      0.0001;
                                  return Container(
                                    decoration: isCurrent
                                        ? BoxDecoration(
                                            color: colors.primary.withValues(
                                              alpha: 0.10,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          )
                                        : null,
                                    child: ListTile(
                                      dense: true,
                                      title: Text(
                                        '${(row.margin * 100).toStringAsFixed(0)} %',
                                        style: TextStyle(
                                          fontWeight: isCurrent
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                        ),
                                      ),
                                      trailing: Text(
                                        '${fmtBs(row.roundedPriceBs)} Bs',
                                        style: TextStyle(
                                          fontWeight: isCurrent
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                          color: isCurrent
                                              ? colors.primary
                                              : colors.textPrimary,
                                        ),
                                      ),
                                      subtitle: Text(
                                        'Ganancia neta ${fmtBs(row.netProfitBs)} Bs',
                                        style: TextStyle(
                                          color: colors.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Calculadora inversa',
                              style: AppTypography.sectionTitle(context),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _inverseCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Precio actual que cobras (Bs)',
                                hintText: 'Ej. 12000',
                                suffixText: 'Bs',
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
                                    fontWeight: FontWeight.w800,
                                    color: inverseMargin < 0
                                        ? colors.danger
                                        : colors.primary,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 14),
                            Text(
                              'Fórmula: Precio = (Costo en Bs + Gasto fijo) ÷ (1 − comisiones − margen). '
                              'El margen es sobre el precio de venta, no sobre el costo.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colors.textMuted,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      )
                    : Column(
                        key: const ValueKey('breakdown_hidden'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeroPriceCard(
                            context: context,
                            rounded: rounded,
                            exact: exact,
                            bd: bd,
                          ),
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: colors.borderSubtle),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.receipt_long_rounded,
                                  size: 16,
                                  color: colors.textMuted,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Activa "Detalles" arriba para ver el desglose paso a paso, tabla comparativa y calculadora inversa.',
                                    style: TextStyle(
                                      color: colors.textMuted,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _showDetails = true),
                                  style: TextButton.styleFrom(
                                    foregroundColor: colors.primary,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    'Ver',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 46,
                child: OutlinedButton.icon(
                  key: const Key('result_back_button'),
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: colors.surface,
                    foregroundColor: colors.textPrimary,
                    side: BorderSide(color: colors.borderStrong),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text(
                    'Volver',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroPriceCard({
    required BuildContext context,
    required double rounded,
    required double exact,
    required Breakdown bd,
  }) {
    final colors = context.appColors;
    final heroButtonStyle = OutlinedButton.styleFrom(
      backgroundColor: const Color(0xFF052E16).withValues(alpha: 0.45),
      foregroundColor: Colors.white,
      side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      minimumSize: const Size(0, 36),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.heroGradientStart, colors.heroGradientEnd],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.heroBorder, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF22C55E).withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'PRECIO DE VENTA',
                    style: AppTypography.overlineLabel(
                      context,
                    ).copyWith(color: Colors.white.withValues(alpha: 0.92)),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Text(
                          '${widget.rateSource.label} · ${fmtRate(widget.rate)}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.30),
                          ),
                        ),
                        child: Text(
                          widget.marginMode.shortLabel,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '${fmtBs(rounded)} Bs',
                  style: AppTypography.heroPrice(
                    context,
                  ).copyWith(color: Colors.white),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.roundStep == 0
                    ? 'Precio exacto · sin redondeo (≈ \$${fmtUsd(rounded / widget.rate)} USD)'
                    : 'Precio exacto: ${fmtBs(exact)} Bs · redondeado a Bs ${widget.roundStep} (≈ \$${fmtUsd(rounded / widget.rate)} USD)',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.90),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.28),
                  ),
                ),
                child: Text(
                  widget.marginMode == MarginMode.onCost
                      ? 'Ganancia neta: ${fmtBs(bd.netProfitBs)} Bs (≈ \$${fmtUsd(bd.netProfitBs / widget.rate)}) · '
                            'margen s/costo: ${(bd.realMarginOnCost * 100).toStringAsFixed(1)} % (s/venta: ${(bd.realMargin * 100).toStringAsFixed(1)} %)'
                      : 'Ganancia neta: ${fmtBs(bd.netProfitBs)} Bs (≈ \$${fmtUsd(bd.netProfitBs / widget.rate)}) · '
                            'margen real: ${(bd.realMargin * 100).toStringAsFixed(1)} %',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: widget.onCopyPrice == null
                        ? null
                        : () => widget.onCopyPrice!(context, rounded),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copiar precio'),
                  ),
                  OutlinedButton.icon(
                    onPressed: widget.onCopyClientMessage == null
                        ? null
                        : () => widget.onCopyClientMessage!(context, rounded),
                    style: heroButtonStyle,
                    icon: const Icon(Icons.message_outlined, size: 16),
                    label: const Text('Mensaje cliente'),
                  ),
                  OutlinedButton.icon(
                    onPressed: widget.onShareWhatsApp == null
                        ? null
                        : () => widget.onShareWhatsApp!(context, rounded),
                    style: heroButtonStyle,
                    icon: const Icon(Icons.send_outlined, size: 16),
                    label: const Text('WhatsApp'),
                  ),
                  OutlinedButton.icon(
                    onPressed: widget.onSavePreset == null
                        ? null
                        : () => widget.onSavePreset!(context, rounded),
                    style: heroButtonStyle,
                    icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                    label: const Text('Guardar como preset'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineBreakdown({
    required BuildContext context,
    required Breakdown bd,
    required double exact,
    required double rounded,
  }) {
    final steps = <(String, String, String)>[
      (
        '1',
        '1. Costo en Bs',
        'Costo × tasa = \$${fmtUsd(widget.costUsd)} × ${fmtRate(widget.rate)} = ${fmtBs(bd.costBs)} Bs',
      ),
      ('2', '2. Gasto fijo', '${fmtBs(bd.fixedExpenseBs)} Bs'),
      (
        '3',
        '3. Precio exacto (${widget.marginMode.shortLabel})',
        widget.marginMode == MarginMode.onCost
            ? '(${fmtBs(bd.costBs)} × (1 + ${(widget.margin * 100).toStringAsFixed(1)} %) + ${fmtBs(bd.fixedExpenseBs)}) ÷ (1 − ${(_totalCommission * 100).toStringAsFixed(1)} %) = ${fmtBs(exact)} Bs'
            : '(${fmtBs(bd.costBs)} + ${fmtBs(bd.fixedExpenseBs)}) ÷ (1 − ${(_totalCommission * 100).toStringAsFixed(1)} % − ${(widget.margin * 100).toStringAsFixed(1)} %) = ${fmtBs(exact)} Bs',
      ),
      (
        '4',
        '4. Redondeo',
        widget.roundStep == 0
            ? '${fmtBs(exact)} Bs (Exacto sin redondeo)'
            : '${fmtBs(exact)} → ${fmtBs(rounded)} Bs (a Bs ${widget.roundStep})',
      ),
      (
        '5',
        '5. Comisiones (${(_totalCommission * 100).toStringAsFixed(1)} %)',
        '${fmtBs(bd.commissionBs)} Bs (plataforma ${fmtBs(bd.commissionProviderBs)} · pago móvil/pasarela ${fmtBs(bd.commissionGatewayBs)} · otra ${fmtBs(bd.commissionOtherBs)})',
      ),
      (
        '6',
        '6. Ganancia',
        widget.marginMode == MarginMode.onCost
            ? '${fmtBs(bd.profitBs)} Bs (${(widget.margin * 100).toStringAsFixed(1)} % del costo) + ${fmtBs(bd.roundingExtraBs)} Bs por redondeo = ${fmtBs(bd.netProfitBs)} Bs netos'
            : '${fmtBs(bd.profitBs)} Bs (${(widget.margin * 100).toStringAsFixed(1)} % de venta) + ${fmtBs(bd.roundingExtraBs)} Bs por redondeo = ${fmtBs(bd.netProfitBs)} Bs netos',
      ),
      (
        '✓',
        'Comprobación',
        '${fmtBs(bd.costBs)} + ${fmtBs(bd.fixedExpenseBs)} + ${fmtBs(bd.commissionBs)} + ${fmtBs(bd.netProfitBs)} = ${fmtBs(rounded)} Bs ✓',
      ),
    ];

    final colors = context.appColors;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            for (var i = 0; i < steps.length; i++)
              _timelineStep(
                context: context,
                badge: steps[i].$1,
                title: steps[i].$2,
                detail: steps[i].$3,
                isLast: i == steps.length - 1,
                isCheck: steps[i].$1 == '✓',
                colors: colors,
              ),
          ],
        ),
      ),
    );
  }

  Widget _timelineStep({
    required BuildContext context,
    required String badge,
    required String title,
    required String detail,
    required bool isLast,
    required bool isCheck,
    required AppColors colors,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 26,
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCheck
                        ? colors.primary
                        : colors.primary.withValues(alpha: 0.14),
                    border: Border.all(
                      color: colors.primary.withValues(
                        alpha: isCheck ? 1 : 0.6,
                      ),
                      width: 1.4,
                    ),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: isCheck
                          ? (isDark ? const Color(0xFF04140A) : Colors.white)
                          : colors.primary,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: colors.borderStrong,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
