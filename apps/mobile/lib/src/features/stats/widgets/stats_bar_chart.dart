import 'dart:ui' as ui;

import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';

/// Last-7-days bar chart.
///
/// Index 0 = "today minus 6 days", index 6 = today. Each bar is one
/// rounded rectangle, height proportional to the busiest day so even
/// short viewing weeks read clearly. Day labels are short Turkish
/// weekday abbreviations rendered below the axis.
class StatsBarChart extends StatelessWidget {
  const StatsBarChart({
    required this.daySeconds,
    super.key,
  })  : assert(daySeconds.length == 7, 'expects 7 days of buckets');

  final List<int> daySeconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AspectRatio(
      aspectRatio: 2.4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          DesignTokens.spaceM,
          DesignTokens.spaceM,
          DesignTokens.spaceM,
          DesignTokens.spaceM,
        ),
        child: CustomPaint(
          painter: _BarChartPainter(
            buckets: daySeconds,
            barColor: scheme.primary,
            mutedColor: scheme.surfaceContainerHighest,
            labelColor: scheme.onSurface.withValues(alpha: 0.7),
            labels: _last7Labels(DateTime.now()),
            textStyle: theme.textTheme.labelSmall ?? const TextStyle(),
          ),
        ),
      ),
    );
  }

  /// Build the last seven Turkish weekday labels ending today.
  /// Order matches [daySeconds] — index 0 is "today - 6", index 6 is
  /// today.
  static List<String> _last7Labels(DateTime today) {
    const tr = <String>['Pzt', 'Sal', 'Car', 'Per', 'Cum', 'Cts', 'Paz'];
    final out = <String>[];
    final start = DateTime(today.year, today.month, today.day)
        .subtract(const Duration(days: 6));
    for (var i = 0; i < 7; i++) {
      final d = start.add(Duration(days: i));
      // Dart's weekday is Monday=1..Sunday=7 — re-map onto our 0-indexed
      // list so the label aligns with the actual weekday of the bucket.
      out.add(tr[(d.weekday - 1) % 7]);
    }
    return out;
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.buckets,
    required this.barColor,
    required this.mutedColor,
    required this.labelColor,
    required this.labels,
    required this.textStyle,
  });

  final List<int> buckets;
  final Color barColor;
  final Color mutedColor;
  final Color labelColor;
  final List<String> labels;
  final TextStyle textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    const labelLane = 18.0;
    final chartHeight = size.height - labelLane;
    if (chartHeight <= 0) return;
    final maxVal = buckets.fold<int>(0, (a, b) => b > a ? b : a);
    final hasData = maxVal > 0;
    // Always reserve a non-zero "ceiling" so empty weeks still draw a
    // baseline track instead of crashing on a divide-by-zero.
    final ceiling = hasData ? maxVal.toDouble() : 1.0;

    final slot = size.width / 7;
    const gap = 6.0;
    final barWidth = slot - gap * 2;
    final radius = Radius.circular(barWidth.clamp(2, 8) / 2 + 2);

    final emptyPaint = Paint()
      ..color = mutedColor.withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;
    final fillPaint = Paint()
      ..color = barColor
      ..style = PaintingStyle.fill;

    for (var i = 0; i < 7; i++) {
      final v = buckets[i].toDouble();
      final x = slot * i + gap;
      final ratio = v / ceiling;
      final h = ratio * chartHeight;
      // Background track — full-height muted bar. Always painted so an
      // empty day still has a placeholder column.
      canvas.drawRRect(
        RRect.fromLTRBAndCorners(
          x,
          0,
          x + barWidth,
          chartHeight,
          topLeft: radius,
          topRight: radius,
        ),
        emptyPaint,
      );
      if (h > 0) {
        canvas.drawRRect(
          RRect.fromLTRBAndCorners(
            x,
            chartHeight - h,
            x + barWidth,
            chartHeight,
            topLeft: radius,
            topRight: radius,
          ),
          fillPaint,
        );
      }
      // Day label
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: textStyle.copyWith(color: labelColor),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: slot);
      tp.paint(
        canvas,
        Offset(
          x + barWidth / 2 - tp.width / 2,
          chartHeight + (labelLane - tp.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter old) {
    if (old.buckets.length != buckets.length) return true;
    for (var i = 0; i < buckets.length; i++) {
      if (old.buckets[i] != buckets[i]) return true;
    }
    return old.barColor != barColor ||
        old.mutedColor != mutedColor ||
        old.labelColor != labelColor;
  }
}
