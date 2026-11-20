import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../services/panels_store.dart';
import '../services/weather_service.dart';

/// Movement 69 — the ONE panel renderer, shared by the Home feed and the
/// Panels screen: flat bordered tiles, no card-in-card nesting. The kind
/// picks the body — stat, sparkline graph, progress bar or list — and the
/// data is whatever the AI authored in its ```gork-panel block.
class PanelTile extends StatelessWidget {
  const PanelTile({
    super.key,
    required this.panel,
    this.weather,
    this.onWeatherRefresh,
    this.onDelete,
    this.compact = false,
  });

  final PanelSpec panel;
  final WeatherNow? weather;
  final VoidCallback? onWeatherRefresh;
  final VoidCallback? onDelete;

  /// Compact rendering for the Home feed (slightly tighter paddings).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return Container(
      margin: EdgeInsets.only(
          left: Spacing.md,
          right: Spacing.md,
          bottom: compact ? Spacing.sm : Spacing.md),
      padding: EdgeInsets.all(compact ? 14 : 16),
      decoration: BoxDecoration(
        color: GlassColors.fill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GlassColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(panel.title,
                    style: TypeScale.heading(color: palette.textPrimary)),
              ),
              if (onDelete != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onDelete,
                  child: Icon(Icons.close, size: 20, color: palette.textTertiary),
                ),
            ],
          ),
          if (panel.note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(panel.note,
                style: TypeScale.caption(color: palette.textTertiary)),
          ],
          const SizedBox(height: Spacing.sm),
          _content(palette),
        ],
      ),
    );
  }

  Widget _content(Palette palette) {
    if (weather != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('${weather!.tempC.toStringAsFixed(0)}°C',
              style: TypeScale.display(color: palette.primary)),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(weather!.label,
                    style: TypeScale.body(color: palette.textPrimary)),
                Text('wind ${weather!.windKmh.toStringAsFixed(0)} km/h',
                    style: TypeScale.caption(color: palette.textTertiary)),
              ],
            ),
          ),
          if (onWeatherRefresh != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onWeatherRefresh,
              child:
                  Icon(Icons.refresh, size: 22, color: palette.textSecondary),
            ),
        ],
      );
    }
    switch (panel.kind) {
      case PanelKind.graph:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Sparkline(series: panel.series, color: palette.primary),
            const SizedBox(height: 6),
            if (panel.manualValue.isNotEmpty)
              Text(panel.manualValue,
                  style: TypeScale.bodySmall(color: palette.textSecondary)),
          ],
        );
      case PanelKind.progress:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: panel.progress,
                minHeight: 10,
                backgroundColor: palette.surfaceElevated,
                valueColor: AlwaysStoppedAnimation(palette.primary),
              ),
            ),
            const SizedBox(height: 6),
            Text(
                '${((panel.progress ?? 0) * 100).round()}%'
                '${panel.manualValue.isEmpty ? '' : ' · ${panel.manualValue}'}',
                style: TypeScale.bodySmall(color: palette.textSecondary)),
          ],
        );
      case PanelKind.list:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, item) in panel.items.take(8).indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${i + 1}.',
                        style:
                            TypeScale.bodySmall(color: palette.textTertiary)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(item,
                          style:
                              TypeScale.bodySmall(color: palette.textPrimary)),
                    ),
                  ],
                ),
              ),
          ],
        );
      case PanelKind.metric:
        return Text(
          panel.manualValue.isEmpty ? '—' : panel.manualValue,
          style: TypeScale.display(color: palette.primary),
        );
    }
  }
}

/// A tiny inline sparkline — the graph renderer for AI panels. Pure
/// CustomPainter, no chart dependency, theme-aware ink.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.series, required this.color});

  final List<double> series;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      width: double.infinity,
      child:
          CustomPaint(painter: _SparklinePainter(series: series, color: color)),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.series, required this.color});

  final List<double> series;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.length < 2) {
      // One point — a dot, honest about having no trend yet.
      canvas.drawCircle(
          Offset(size.width / 2, size.height / 2), 4, Paint()..color = color);
      return;
    }
    final double maxV = series.reduce(math.max);
    final double minV = series.reduce(math.min);
    final double span = (maxV - minV).abs() < 0.001 ? 1 : maxV - minV;
    final path = Path();
    for (final (i, v) in series.indexed) {
      final double x = i / (series.length - 1) * size.width;
      final double y =
          size.height - 6 - ((v - minV) / span) * (size.height - 12);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
    final lastX = size.width - 1;
    final lastY =
        size.height - 6 - ((series.last - minV) / span) * (size.height - 12);
    canvas.drawCircle(Offset(lastX, lastY), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.series != series || old.color != color;
}
