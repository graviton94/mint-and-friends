import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../art/art.dart';
import '../game/config.dart';
import 'theme.dart';
import 'widgets/frame_box.dart' show framedButton;
import 'widgets/icon_text.dart';

/// 튜토리얼 한 단계를 그리는 덮개.
///
/// - 화면을 어둡게 하고 [hole] 만 뚫어 보여 준다 (둥근 사각형 + 맥박 고리).
/// - [action] 단계: 구멍 안만 누를 수 있고 바깥 터치는 막는다 (구멍 안의 버튼 · 보드를 직접 조작).
/// - 설명 단계: 어디를 눌러도 막고, 말풍선의 버튼으로 넘어간다.
/// - 말풍선은 구멍이 화면 위쪽이면 아래에, 아래쪽이면 위에 놓아 구멍을 가리지 않는다.
class CoachOverlay extends StatefulWidget {
  const CoachOverlay({
    super.key,
    required this.text,
    this.hole,
    this.action = false,
    this.buttonLabel,
    this.onNext,
    this.onSkip,
    this.skipLabel,
    this.pointAt,
    this.dragTo,
  });

  /// 손장갑이 가리킬 곳 (덮개 좌표). [dragTo] 가 있으면 그쪽으로 끌어 가는 모습을 되풀이한다.
  final Offset? pointAt;
  final Offset? dragTo;

  final String text;
  final Rect? hole;
  final bool action;
  final String? buttonLabel;
  final VoidCallback? onNext;
  final VoidCallback? onSkip;
  final String? skipLabel;

  @override
  State<CoachOverlay> createState() => _CoachOverlayState();
}

class _CoachOverlayState extends State<CoachOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        final hole = widget.hole?.inflate(6);
        final children = <Widget>[
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _DimPainter(hole)),
            ),
          ),
        ];
        // 터치 막기: 구멍이 있는 행동 단계면 구멍 바깥 네 조각만, 아니면 전체.
        if (hole != null && widget.action) {
          children.addAll([
            _block(0, 0, size.width, max(0, hole.top)),
            _block(
              0,
              hole.bottom,
              size.width,
              max(0, size.height - hole.bottom),
            ),
            _block(0, hole.top, max(0, hole.left), hole.height),
            _block(
              hole.right,
              hole.top,
              max(0, size.width - hole.right),
              hole.height,
            ),
          ]);
        } else {
          children.add(_block(0, 0, size.width, size.height));
        }
        if (hole != null) {
          children.add(
            Positioned.fromRect(
              rect: hole.inflate(10),
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, _) =>
                      CustomPaint(painter: _RingPainter(_pulse.value)),
                ),
              ),
            ),
          );
        }
        // 손장갑: 누르기(톡톡) 또는 끌기(가리킨 곳 → dragTo)
        if (widget.pointAt != null) {
          children.add(
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, _) {
                    // 화면 아래 끝 근처면 손을 뒤집어 위에서 가리킨다 (손이 화면 밖으로 잘리지 않게)
                    final flip =
                        widget.pointAt!.dy >
                        size.height - _GloveLayout.size - 8;
                    return CustomSingleChildLayout(
                      delegate: _GloveLayout(
                        widget.pointAt!,
                        widget.dragTo,
                        _pulse.value,
                        flip: flip,
                      ),
                      child: _Glove(
                        down: flip,
                        pressed: widget.dragTo == null
                            ? _pulse.value > 0.5
                            : _pulse.value > 0.15 && _pulse.value < 0.85,
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        }
        // 말풍선 위치
        final below = hole == null || hole.center.dy < size.height * 0.5;
        final bubble = _Bubble(
          text: widget.text,
          buttonLabel: widget.buttonLabel,
          onNext: widget.onNext,
          onSkip: widget.onSkip,
          skipLabel: widget.skipLabel,
        );
        if (hole == null) {
          children.add(
            Positioned(
              left: 16,
              right: 16,
              top: size.height * 0.3,
              child: bubble,
            ),
          );
        } else if (below) {
          children.add(
            Positioned(
              left: 12,
              right: 12,
              top: min(hole.bottom + 16, size.height - 200),
              child: bubble,
            ),
          );
        } else {
          children.add(
            Positioned(
              left: 12,
              right: 12,
              bottom: min(size.height - hole.top + 16, size.height - 200),
              child: bubble,
            ),
          );
        }
        return Stack(children: children);
      },
    );
  }

  Widget _block(double l, double t, double w, double h) => Positioned(
    left: l,
    top: t,
    width: w,
    height: h,
    child: const AbsorbPointer(child: SizedBox.expand()),
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    this.buttonLabel,
    this.onNext,
    this.onSkip,
    this.skipLabel,
  });
  final String text;
  final String? buttonLabel;
  final VoidCallback? onNext;
  final VoidCallback? onSkip;
  final String? skipLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 안내 캐릭터: 민트 (첫 친구)
        ArtImage(Art.friend(Friends.byId(Friends.starter)), size: 84),
        const SizedBox(width: 4),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBF0),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF7A5230), width: 3),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x44000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IconText(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.4,
                    color: Palette.text,
                  ),
                ),
                if (buttonLabel != null || onSkip != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (onSkip != null)
                        TextButton(
                          onPressed: onSkip,
                          child: Text(
                            skipLabel ?? '',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black45,
                            ),
                          ),
                        ),
                      if (onSkip != null) const Spacer(),
                      if (buttonLabel != null)
                        FilledButton(
                          style: framedButton(
                            FilledButton.styleFrom(
                              minimumSize: const Size(80, 38),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                            ),
                            'button_green',
                          ),
                          onPressed: onNext,
                          child: Text(
                            buttonLabel!,
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DimPainter extends CustomPainter {
  _DimPainter(this.hole);
  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final all = Path()..addRect(Offset.zero & size);
    final path = hole == null
        ? all
        : Path.combine(
            PathOperation.difference,
            all,
            Path()..addRRect(
              RRect.fromRectAndRadius(hole!, const Radius.circular(16)),
            ),
          );
    canvas.drawPath(path, Paint()..color = const Color(0xA6000000));
  }

  @override
  bool shouldRepaint(_DimPainter old) => old.hole != hole;
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(10 * (1 - t)),
      const Radius.circular(20),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0xFFFFE066).withValues(alpha: 1 - t),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t;
}

/// 손장갑 위치: 손가락 끝이 목표에 오도록. 누르기는 위아래로 톡톡, 끌기는 목표 사이를 오간다.
class _GloveLayout extends SingleChildLayoutDelegate {
  _GloveLayout(this.from, this.to, this.t, {this.flip = false});
  final Offset from;
  final Offset? to;
  final double t;
  final bool flip;

  static const double size = 72;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) =>
      BoxConstraints.tight(const Size(size, size));

  @override
  Offset getPositionForChild(Size area, Size child) {
    Offset tip;
    if (to == null) {
      final bob = 10 * (1 - (2 * t - 1).abs());
      tip = from + Offset(0, flip ? -bob : bob);
    } else {
      // 0~0.15 집기, 0.15~0.75 끌기, 0.75~1 놓고 잠깐 쉼
      final m = ((t - 0.15) / 0.6).clamp(0.0, 1.0);
      final e = Curves.easeInOut.transform(m);
      tip = Offset.lerp(from, to!, e)!;
    }
    // 손가락 끝: 위를 가리키는 손(hand_point)은 그림 위쪽, 아래로 누르는 손(hand_press)은 아래쪽.
    final f = _Glove.tip(flip);
    return Offset(tip.dx - size * f.dx, tip.dy - size * f.dy);
  }

  @override
  bool shouldRelayout(_GloveLayout o) =>
      o.t != t || o.from != from || o.to != to || o.flip != flip;
}

/// 흰 손장갑. 목표 아래에서는 위를 가리키는 손(hand_point), 화면 아래 끝이라 위에서
/// 가리켜야 하면 아래로 누르는 손(hand_press)을 쓴다. 누르는 순간은 살짝 작아진다.
class _Glove extends StatelessWidget {
  const _Glove({required this.pressed, this.down = false});
  final bool pressed;
  final bool down;

  /// 그림 안 손가락 끝의 비율 위치 (그림 크기 대비).
  static Offset tip(bool down) {
    final art = Art.icon(down ? 'hand_press' : 'hand_point');
    if (!art.available)
      return down ? const Offset(0.32, 0.96) : const Offset(0.32, 0.04);
    return down ? const Offset(0.34, 0.80) : const Offset(0.38, 0.20);
  }

  @override
  Widget build(BuildContext context) {
    final art = Art.icon(down ? 'hand_press' : 'hand_point');
    final scale = pressed ? 0.9 : 1.0;
    final origin = Alignment(tip(down).dx * 2 - 1, tip(down).dy * 2 - 1);
    if (art.available) {
      return Transform.scale(
        scale: scale,
        alignment: origin,
        child: ArtImage(art, size: _GloveLayout.size),
      );
    }
    return Transform.flip(
      flipY: down,
      child: Transform.scale(
        scale: scale,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.touch_app_rounded,
              size: _GloveLayout.size,
              color: const Color(0xFF5A3A1E),
            ),
            Icon(
              Icons.touch_app_rounded,
              size: _GloveLayout.size - 8,
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}
