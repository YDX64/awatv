import 'dart:math' as math;

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';

/// Compact donut chart for the Live / Filmler / Diziler ratio.
///
/// Pure CustomPaint — no chart package — so the binary stays small
/// and the visual matches the AWAtv brand exactly. The donut leaves
/// a transparent inner ring so the surrounding card colour shows
/// through (matches the IPTV reference apps' pie-card look).
///
/// Three slices are precomputed from a `Map<HistoryKind, Duration>`
/// because passing the full summary would force the widget to know
/// how the rest of the screen interprets "byKind" — keeping the
/// dependency surface tight makes it easy to drop the same chart
/// into other surfaces (e.g. weekly digest) later.
class StatsPieChart extends StatelessWidget {
  const StatsPieChart({
    required this.byKind,
    super.key,
  });

  final Map<HistoryKind, Duration> byKind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final liveSec = byKind[HistoryKind.live]?.inSeconds ?? 0;
    final vodSec = byKind[HistoryKind.vod]?.inSeconds ?? 0;
    final seriesSec = byKind[HistoryKind.series]?.inSeconds ?? 0;
    final total = liveSec + vodSec + seriesSec;

    return AspectRatio(
      aspectRatio: 1.6,
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spaceM),
        child: Row(
          children: <Widget>[
            Expanded(
              flex: 3,
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: total == 0
                      ? _emptyDonut(scheme)
                      : CustomPaint(
                          painter: _DonutPainter(
                            slices: <_Slice>[
                              _Slice(
                                value: liveSec.toDouble(),
                                color: scheme.primary,
                              ),
                              _Slice(
                                value: vodSec.toDouble(),
                                color: scheme.secondary,
                              ),
                              _Slice(
                                value: seriesSec.toDouble(),
                                color: scheme.tertiary,
                              ),
                            ],
                            stroke: 18,
                            background:
                                scheme.surfaceContainerHighest,
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  _formatHours(total),
                                  style:
                                      theme.textTheme.titleLarge,
                                ),
                                Text(
                                  'Toplam',
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(
                                    color: scheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: DesignTokens.spaceM),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _LegendRow(
                    color: scheme.primary,
                    label: 'Canli TV',
                    value: liveSec,
                    total: total,
                  ),
                  const SizedBox(height: DesignTokens.spaceS),
                  _LegendRow(
                    color: scheme.secondary,
                    label: 'Filmler',
                    value: vodSec,
                    total: total,
                  ),
                  const SizedBox(height: DesignTokens.spaceS),
                  _LegendRow(
                    color: scheme.tertiary,
                    label: 'Diziler',
                    value: seriesSec,
                    total: total,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyDonut(ColorScheme scheme) {
    return CustomPaint(
      painter: _EmptyDonutPainter(
        color: scheme.surfaceContainerHighest,
        stroke: 18,
      ),
      child: Center(
        child: Text(
          'Veri yok',
          style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    required this.value,
    required this.total,
  });

  final Color color;
  final String label;
  final int value;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = total == 0 ? 0 : (value * 100 / total).round();
    return Row(
      children: <Widget>[
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: DesignTokens.spaceS),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          '%$pct',
          style: theme.textTheme.labelLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _Slice {
  const _Slice({required this.value, required this.color});
  final double value;
  final Color color;
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.stroke,
    required this.background,
  });

  final List<_Slice> slices;
  final double stroke;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );

    // Background ring — keeps the donut visible even if a single
    // slice owns 99% of the value.
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = background.withValues(alpha: 0.55);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2, false, bg);

    final total = slices.fold<double>(0, (a, s) => a + s.value);
    if (total <= 0) return;

    // Start at the top (-pi/2 in Flutter's clockwise convention).
    var start = -math.pi / 2;
    for (final slice in slices) {
      if (slice.value <= 0) continue;
      final sweep = (slice.value / total) * math.pi * 2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..color = slice.color;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) {
    if (old.slices.length != slices.length) return true;
    for (var i = 0; i < slices.length; i++) {
      if (old.slices[i].value != slices[i].value) return true;
      if (old.slices[i].color != slices[i].color) return true;
    }
    return old.stroke != stroke || old.background != background;
  }
}

class _EmptyDonutPainter extends CustomPainter {
  _EmptyDonutPainter({required this.color, required this.stroke});

  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color.withValues(alpha: 0.45);
    canvas.drawArc(rect, 0, math.pi * 2, false, paint);
  }

  @override
  bool shouldRepaint(covariant _EmptyDonutPainter old) =>
      old.color != color || old.stroke != stroke;
}

String _formatHours(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours == 0) return '${minutes}dk';
  if (minutes == 0) return '${hours}sa';
  return '${hours}sa ${minutes}dk';
}
