import 'dart:math';

import 'package:material_ui/material_ui.dart';

/// 축하 꽃가루 (D-097): 그림 대신 코드로 그려 어떤 크기에서도 가장자리가 깨끗하다.
/// 꽃 · 잎 · 리본 조각 · 네모 사탕이 아래 가운데에서 부채꼴로 톡 터져 나와 자리를 잡고,
/// 그 뒤로는 살랑살랑 조금씩 흔들린다. 조각마다 같은 색의 진한 외곽선 (게임 그림체).
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key, this.width = 230, this.seed = 7});
  final double width;
  final int seed;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();
  final Stopwatch _clock = Stopwatch()..start();
  late final List<_Piece> _pieces = _layout(widget.seed);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static List<_Piece> _layout(int seed) {
    final rng = Random(seed);
    const kinds = [
      _Kind.square,
      _Kind.flower,
      _Kind.ribbon,
      _Kind.square,
      _Kind.leaf,
      _Kind.pill,
      _Kind.square,
      _Kind.ribbon,
      _Kind.flower,
      _Kind.square,
      _Kind.leaf,
      _Kind.pill,
      _Kind.square,
      _Kind.ribbon,
      _Kind.square,
      _Kind.leaf,
      _Kind.flower,
      _Kind.square,
    ];
    const colors = [
      Color(0xFFF59BC0),
      Color(0xFFFFD34D),
      Color(0xFFB79BF2),
      Color(0xFF9DD84F),
      Color(0xFF7FD0F2),
      Color(0xFFF4A0B0),
    ];
    final out = <_Piece>[];
    for (var i = 0; i < kinds.length; i++) {
      // 부채꼴: 가운데 아래(0.5, 1.0)에서 위쪽 160도 안으로
      final ang =
          -pi / 2 +
          (i / (kinds.length - 1) - 0.5) * pi * 0.95 +
          (rng.nextDouble() - 0.5) * 0.25;
      final dist = 0.62 + rng.nextDouble() * 0.38; // 가운데(별 · 리본 자리)는 비운다
      final k = kinds[i];
      out.add(
        _Piece(
          kind: k,
          color: k == _Kind.leaf
              ? const Color(0xFF9DD84F)
              : k == _Kind.flower
              ? const Color(0xFFF59BC0)
              : colors[rng.nextInt(colors.length)],
          ang: ang,
          dist: dist,
          size: switch (k) {
            _Kind.flower => 0.14,
            _Kind.ribbon => 0.12,
            _Kind.leaf => 0.12,
            _Kind.pill => 0.09,
            _Kind.square => 0.06,
          },
          rot: rng.nextDouble() * pi * 2,
          spin: (rng.nextDouble() - 0.5) * 1.2,
          delay: rng.nextDouble() * 0.12,
          phase: rng.nextDouble() * pi * 2,
        ),
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    return SizedBox(
      width: w,
      height: w * 0.62,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(
          painter: _ConfettiPainter(
            _pieces,
            _clock.elapsedMilliseconds / 1000.0,
          ),
        ),
      ),
    );
  }
}

enum _Kind { flower, ribbon, square, leaf, pill }

class _Piece {
  const _Piece({
    required this.kind,
    required this.color,
    required this.ang,
    required this.dist,
    required this.size,
    required this.rot,
    required this.spin,
    required this.delay,
    required this.phase,
  });
  final _Kind kind;
  final Color color;
  final double ang, dist, size, rot, spin, delay, phase;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t);
  final List<_Piece> pieces;
  final double t; // 초

  static Color _dark(Color c) => Color.lerp(c, const Color(0xFF6B3A22), 0.55)!;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final origin = Offset(w / 2, size.height * 0.98);
    for (final p in pieces) {
      // 0.55초 동안 톡 터져 나와 자리를 잡는다 (조금 넘쳤다가 돌아옴)
      final k = ((t - p.delay) / 0.55).clamp(0.0, 1.0);
      final out = Curves.easeOutBack.transform(k);
      final sway = sin(t * 1.6 + p.phase) * 0.012 * w * (k >= 1 ? 1 : 0);
      // 위쪽 반타원으로 넓게: 가로는 폭의 절반, 세로는 높이만큼
      final pos =
          origin +
          Offset(cos(p.ang) * w * 0.48, sin(p.ang) * size.height * 0.92) *
              (p.dist * out) +
          Offset(sway, cos(t * 1.3 + p.phase) * 0.006 * w);
      final s = p.size * w * (0.4 + 0.6 * Curves.easeOut.transform(k));
      final rot = p.rot + p.spin * (k * 2 + sin(t * 0.9 + p.phase) * 0.15);
      if (k <= 0) continue;
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(rot);
      _draw(canvas, p, s);
      canvas.restore();
    }
  }

  void _draw(Canvas c, _Piece p, double s) {
    final fill = Paint()..color = p.color;
    final line = Paint()
      ..color = _dark(p.color)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.6, s * 0.11)
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final shine = Paint()..color = Colors.white.withValues(alpha: 0.55);
    switch (p.kind) {
      case _Kind.square:
        final r = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: s, height: s),
          Radius.circular(s * 0.22),
        );
        c.drawRRect(r, fill);
      case _Kind.pill:
        final r = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: s * 1.8, height: s * 0.7),
          Radius.circular(s),
        );
        c.drawRRect(r, fill);
        c.drawRRect(r, line..strokeWidth = max(1.4, s * 0.12));
      case _Kind.ribbon:
        // 두꺼운 호: 진한 테두리 호 위에 색 호, 위쪽에 가는 광택
        final rect = Rect.fromCircle(
          center: Offset(0, s * 0.6),
          radius: s * 0.75,
        );
        c.drawArc(
          rect,
          -pi * 0.78,
          pi * 0.56,
          false,
          Paint()
            ..color = _dark(p.color)
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.34
            ..strokeCap = StrokeCap.round,
        );
        c.drawArc(
          rect,
          -pi * 0.78,
          pi * 0.56,
          false,
          Paint()
            ..color = p.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.22
            ..strokeCap = StrokeCap.round,
        );
        c.drawArc(
          rect.deflate(s * 0.06),
          -pi * 0.78,
          pi * 0.5,
          false,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.06
            ..strokeCap = StrokeCap.round,
        );
      case _Kind.leaf:
        final path = Path()
          ..moveTo(-s * 0.55, 0)
          ..quadraticBezierTo(0, -s * 0.55, s * 0.55, 0)
          ..quadraticBezierTo(0, s * 0.55, -s * 0.55, 0)
          ..close();
        c.drawPath(path, fill);
        c.drawPath(path, line);
        c.drawLine(
          Offset(-s * 0.35, 0),
          Offset(s * 0.3, -s * 0.05),
          line..strokeWidth = max(1.2, s * 0.06),
        );
      case _Kind.flower:
        final petals = Path();
        for (var i = 0; i < 5; i++) {
          final a = -pi / 2 + i * 2 * pi / 5;
          petals.addOval(
            Rect.fromCircle(
              center: Offset(cos(a), sin(a)) * s * 0.3,
              radius: s * 0.24,
            ),
          );
        }
        c.drawPath(petals, line..strokeWidth = max(2.4, s * 0.2));
        c.drawPath(petals, fill);
        c.drawCircle(
          Offset.zero,
          s * 0.16,
          Paint()..color = const Color(0xFFFFD34D),
        );
        c.drawCircle(Offset(-s * 0.05, -s * 0.05), s * 0.06, shine);
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
