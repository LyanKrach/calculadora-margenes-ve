import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/calculation_item.dart';
import '../models/rate.dart';
import '../services/history_service.dart';
import '../utils/format.dart';

/// Modal BottomSheet con dos pestañas (*Historial* y *Plantillas*) para
/// seleccionar y auto-rellenar la calculadora en un toque.
class HistoryPresetsSheet extends StatefulWidget {
  const HistoryPresetsSheet({
    super.key,
    required this.historyService,
    required this.ratesMap,
    required this.customRate,
    required this.onSelectHistory,
    required this.onSelectPreset,
    this.initialTabIndex = 0,
  });

  final HistoryService historyService;
  final Map<RateSource, Rate> ratesMap;
  final double customRate;
  final ValueChanged<HistoryEntry> onSelectHistory;
  final ValueChanged<Preset> onSelectPreset;
  final int initialTabIndex;

  @override
  State<HistoryPresetsSheet> createState() => _HistoryPresetsSheetState();
}

class _HistoryPresetsSheetState extends State<HistoryPresetsSheet> {
  List<HistoryEntry> _history = const [];
  List<Preset> _presets = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final history = await widget.historyService.getHistory();
    final presets = await widget.historyService.getPresets();
    if (mounted) {
      setState(() {
        _history = history;
        _presets = presets;
        _loading = false;
      });
    }
  }

  double _liveRateFor(RateSource source, {double? presetCustomRate}) {
    if (source == RateSource.custom) {
      return presetCustomRate ?? widget.customRate;
    }
    return widget.ratesMap[source]?.value ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm', 'es_VE');

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.68,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withAlpha(120),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.history), text: 'Historial'),
                  Tab(icon: Icon(Icons.bookmark_border), text: 'Plantillas'),
                ],
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        children: [
                          _buildHistoryTab(fmt),
                          _buildPresetsTab(fmt),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryTab(DateFormat fmt) {
    if (_history.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'El historial está vacío.\nSe guardan automáticamente los últimos 15 cálculos al copiar, compartir por WhatsApp o guardar una plantilla.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Últimos ${_history.length} de ${HistoryService.maxHistoryItems} cálculos',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              TextButton.icon(
                onPressed: () async {
                  await widget.historyService.clearHistory();
                  await _loadData();
                },
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Limpiar'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _history.length,
            itemBuilder: (context, index) {
              final item = _history[index];
              final totalCommPct = (item.commissionPlatform +
                      item.commissionPaymentMethod +
                      item.commissionOther) *
                  100;
              return ListTile(
                title: Text(
                  item.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Costo \$${fmtUsd(item.costUsd)} · Margen ${item.marginPercent.toStringAsFixed(1)}% (${item.marginMode.shortLabel}) · '
                  'Com. ${totalCommPct.toStringAsFixed(1)}%\n'
                  '${item.rateSource.label}: ${fmtRate(item.rateValue)} · ${fmt.format(item.timestamp)}',
                ),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${fmtBs(item.finalPriceBs)} Bs',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Eliminar del historial',
                      onPressed: () async {
                        await widget.historyService.deleteHistoryEntry(item.id);
                        await _loadData();
                      },
                    ),
                  ],
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onSelectHistory(item);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPresetsTab(DateFormat fmt) {
    if (_presets.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No tienes plantillas guardadas.\nUsa el botón "Guardar plantilla" junto al resultado de la calculadora para crear tus accesos rápidos.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _presets.length,
      itemBuilder: (context, index) {
        final preset = _presets[index];
        final liveRate = _liveRateFor(
          preset.rateSource,
          presetCustomRate: preset.customRateValue,
        );
        final livePriceBs = preset.recalculatePriceBs(liveRate);
        final totalCommPct = (preset.commissionPlatform +
                preset.commissionPaymentMethod +
                preset.commissionOther) *
            100;

        return ListTile(
          leading: const Icon(Icons.bookmark),
          title: Text(
            preset.title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            'Costo \$${fmtUsd(preset.costUsd)} · Margen ${preset.marginPercent.toStringAsFixed(1)}% (${preset.marginMode.shortLabel}) · '
            'Com. ${totalCommPct.toStringAsFixed(1)}%\n'
            'Tasa: ${preset.rateSource.label} (${liveRate > 0 ? fmtRate(liveRate) : "sin tasa"})',
          ),
          isThreeLine: true,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                livePriceBs != null ? '${fmtBs(livePriceBs)} Bs' : '—',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'Eliminar plantilla',
                onPressed: () async {
                  await widget.historyService.deletePreset(preset.id);
                  await _loadData();
                },
              ),
            ],
          ),
          onTap: () {
            Navigator.of(context).pop();
            widget.onSelectPreset(preset);
          },
        );
      },
    );
  }
}

