import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/rate_snapshot.dart';
import '../services/calculator.dart';
import '../utils/format.dart';

/// Gráfico comparativo de tasas (BCV, Binance USDT y Euro BCV) y evolución
/// de las últimas actualizaciones, renderizado con [CustomPainter] nativo y
/// soporte completo de accesibilidad ([Semantics]) para TalkBack.
class RatesBarChart extends StatelessWidget {
  const RatesBarChart({
    super.key,
    required this.bcvRate,
    required this.binanceRate,
    required this.euroRate,
    this.snapshots = const [],
  });

  final double bcvRate;
  final double binanceRate;
  final double euroRate;
  final List<RateSnapshot> snapshots;

  static const Color bcvColor = Color(0xFF22C55E);
  static const Color binanceColor = Color(0xFFF59E0B);
  static const Color euroColor = Color(0xFF3B82F6);

  String get semanticsLabel {
    final gap = MarginCalculator.exchangeGapPercent(
      bcvRate: bcvRate,
      binanceRate: binanceRate,
    );
    return 'BCV ${fmtRate(bcvRate)} · Binance ${fmtRate(binanceRate)} · Brecha ${gap.toStringAsFixed(2)}%';
  }

  @override
  Widget build(BuildContext context) {
    final count = snapshots.length;

    return Semantics(
      container: true,
      label: semanticsLabel,
      child: Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Comparativa Visual de Tasas (Bs)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Ventana registrada: últimas $count actualizaciones',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ExcludeSemantics(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  builder: (context, progress, _) {
                    return SizedBox(
                      height: 170,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _RatesBarPainter(
                          bcvRate: bcvRate,
                          binanceRate: binanceRate,
                          euroRate: euroRate,
                          progress: progress,
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (snapshots.length >= 2) ...[
                const Divider(height: 24),
                Text(
                  'Fluctuación reciente (últimas $count actualizaciones)',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                ExcludeSemantics(
                  child: SizedBox(
                    height: 80,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _SnapshotsSparklinePainter(snapshots: snapshots),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Row(
                  children: [
                    _LegendDot(color: bcvColor, label: 'BCV USD'),
                    SizedBox(width: 12),
                    _LegendDot(color: binanceColor, label: 'Binance USDT'),
                    SizedBox(width: 12),
                    _LegendDot(color: euroColor, label: 'Euro BCV'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}

class _RatesBarPainter extends CustomPainter {
  _RatesBarPainter({
    required this.bcvRate,
    required this.binanceRate,
    required this.euroRate,
    required this.progress,
  });

  final double bcvRate;
  final double binanceRate;
  final double euroRate;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final maxRate = math.max(bcvRate, math.max(binanceRate, euroRate));
    if (maxRate <= 0) return;

    final entries = [
      (label: 'BCV USD', value: bcvRate, color: RatesBarChart.bcvColor),
      (
        label: 'Binance USDT',
        value: binanceRate,
        color: RatesBarChart.binanceColor,
      ),
      (label: 'Euro BCV', value: euroRate, color: RatesBarChart.euroColor),
    ];

    const topPadding = 26.0;
    const bottomPadding = 28.0;
    final chartHeight = math.max(10.0, size.height - topPadding - bottomPadding);
    final slotWidth = size.width / entries.length;
    final barWidth = math.min(56.0, slotWidth * 0.52);

    // Línea base
    final baseLinePaint = Paint()
      ..color = const Color(0xFF2A3441)
      ..strokeWidth = 1.0;
    final baselineY = topPadding + chartHeight;
    canvas.drawLine(
      Offset(8, baselineY),
      Offset(size.width - 8, baselineY),
      baseLinePaint,
    );

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final normalized = (entry.value / maxRate).clamp(0.0, 1.0);
      final barHeight = chartHeight * normalized * progress;
      final centerX = slotWidth * i + slotWidth / 2;
      final left = centerX - barWidth / 2;
      final top = baselineY - barHeight;

      final barRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, top, barWidth, barHeight),
        topLeft: const Radius.circular(8),
        topRight: const Radius.circular(8),
      );

      final barPaint = Paint()
        ..color = entry.color
        ..style = PaintingStyle.fill;
      canvas.drawRRect(barRect, barPaint);

      // Valor encima de la barra
      final valuePainter = TextPainter(
        text: TextSpan(
          text: fmtBs(entry.value),
          style: TextStyle(
            color: entry.color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: slotWidth);

      valuePainter.paint(
        canvas,
        Offset(centerX - valuePainter.width / 2, math.max(0, top - 18)),
      );

      // Etiqueta debajo de la barra
      final labelPainter = TextPainter(
        text: TextSpan(
          text: entry.label,
          style: const TextStyle(
            color: Color(0xFFCBD5E1),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: slotWidth);

      labelPainter.paint(
        canvas,
        Offset(centerX - labelPainter.width / 2, baselineY + 6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RatesBarPainter oldDelegate) {
    return oldDelegate.bcvRate != bcvRate ||
        oldDelegate.binanceRate != binanceRate ||
        oldDelegate.euroRate != euroRate ||
        oldDelegate.progress != progress;
  }
}

class _SnapshotsSparklinePainter extends CustomPainter {
  _SnapshotsSparklinePainter({required this.snapshots});

  final List<RateSnapshot> snapshots;

  @override
  void paint(Canvas canvas, Size size) {
    if (snapshots.length < 2) return;

    double minVal = double.infinity;
    double maxVal = double.negativeInfinity;

    for (final s in snapshots) {
      minVal = math.min(minVal, math.min(s.bcvUsd, math.min(s.binanceUsdt, s.euroBcv)));
      maxVal = math.max(maxVal, math.max(s.bcvUsd, math.max(s.binanceUsdt, s.euroBcv)));
    }

    if (!minVal.isFinite || !maxVal.isFinite) return;
    final range = (maxVal - minVal) <= 0 ? 1.0 : (maxVal - minVal);

    void drawSeries(double Function(RateSnapshot) selector, Color color) {
      final path = Path();
      final pointPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      final linePaint = Paint()
        ..color = color
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      for (var i = 0; i < snapshots.length; i++) {
        final x = (i / (snapshots.length - 1)) * (size.width - 12) + 6;
        final val = selector(snapshots[i]);
        final norm = (val - minVal) / range;
        final y = size.height - 8 - norm * (size.height - 16);

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
        canvas.drawCircle(Offset(x, y), 2.8, pointPaint);
      }
      canvas.drawPath(path, linePaint);
    }

    drawSeries((s) => s.bcvUsd, RatesBarChart.bcvColor);
    drawSeries((s) => s.binanceUsdt, RatesBarChart.binanceColor);
    drawSeries((s) => s.euroBcv, RatesBarChart.euroColor);
  }

  @override
  bool shouldRepaint(covariant _SnapshotsSparklinePainter oldDelegate) {
    return oldDelegate.snapshots != snapshots;
  }
}

