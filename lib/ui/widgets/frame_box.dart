import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../art/art.dart';
import '../theme.dart';
import 'confetti.dart';
import 'icon_text.dart';

/// 프레임 그림(9-slice)이 있으면 그 그림을 배경으로, 없으면 [fallback] 장식으로 그린다.
class FrameBox extends StatelessWidget {
  const FrameBox({
    super.key,
    required this.frame,
    required this.fallback,
    this.child,
    this.padding,
    this.corner = 18,
  });

  final String frame;
  final BoxDecoration fallback;
  final Widget? child;
  final EdgeInsetsGeometry? padding;

  /// 화면에서 모서리가 차지할 크기 (논리 px).
  final double corner;

  /// [corner] = 화면에서 모서리(늘어나지 않는 가장자리)가 차지할 크기(논리 px).
  static Decoration decorationFor(
    String frame,
    BoxDecoration fallback, {
    double corner = 18,
  }) {
    final ref = Art.frame(frame);
    final center = Art.frameCenter(frame);
    if (!ref.available || center == null) return fallback;
    return NineSliceDecoration(
      ref.path,
      center,
      corner / Art.frameInset(frame),
      pill: frame.startsWith('button_') || frame.startsWith('capsule'),
      // 버튼은 둥근 끝 + 왼쪽 반짝이까지 끝 조각에 넣는다 (가운데 늘림에 반짝이가 뭉개지지 않게, D-093)
      capK: frame.startsWith('button_') ? 0.85 : 0.5,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: decorationFor(frame, fallback, corner: corner),
      padding: padding,
      child: child,
    );
  }
}

/// 게임 공통 대화상자: 패널 프레임 + 리본 제목. AlertDialog 와 같은 인자를 받는다.
class GameDialog extends StatelessWidget {
  const GameDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.actionsAlignment,
    this.banner = 'green',
    this.emblem,
    this.emblemText,
    this.onClose,
  });

  /// 오른쪽 위 X 버튼 (닫기 · 기다리기 · 괜찮아요 같은 선택지 대신).
  final VoidCallback? onClose;

  /// 엠블럼 가운데 글자 (예: 레벨 숫자).
  final String? emblemText;

  /// 제목 띠 색: 'green' (보통) · 'gold' (레벨업 · 보상).
  final String banner;

  /// 제목 띠 위에 얹는 그림 (예: 레벨업 별). 그림이 없으면 생략.
  final String? emblem;

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final MainAxisAlignment? actionsAlignment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 리본은 패널 위 테두리에 걸쳐 놓는다 (게임 팝업의 일반적인 모양). 패널 안은 리본 아래부터.
    final hasRibbon = title != null;
    final panel = FrameBox(
      frame: 'panel',
      fallback: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      corner: 30,
      // X 버튼 자리만큼 위를 띄운다 (첫 줄과 겹치지 않게)
      padding: EdgeInsets.fromLTRB(
        24,
        (hasRibbon ? 40 : 22) + (onClose != null ? 26 : 0),
        24,
        20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null && !hasRibbon)
            DefaultTextStyle.merge(
              style: const TextStyle(fontSize: 22),
              textAlign: TextAlign.center,
              child: title!,
            ),
          if (content != null) ...[
            const SizedBox(height: 12),
            Flexible(child: SingleChildScrollView(child: content!)),
          ],
          if (actions != null && actions!.isNotEmpty) ...[
            const SizedBox(height: 18),
            // 버튼은 한 줄에 하나씩, 같은 폭 · 같은 높이 (글자 버튼은 맨 아래 작게)
            for (final (i, a) in [
              ...actions!.where((a) => a is! TextButton),
              ...actions!.whereType<TextButton>(),
            ].indexed) ...[
              if (i > 0) const SizedBox(height: 10),
              if (a is TextButton)
                Center(child: a)
              else
                SizedBox(height: 56, child: a),
            ],
          ],
        ],
      ),
    );
    final closable = onClose == null
        ? panel
        : Stack(
            clipBehavior: Clip.none,
            children: [
              panel,
              Positioned(
                // 테두리 안쪽 오른쪽 위 (밖으로 튀어나가지 않게)
                right: 10,
                top: hasRibbon ? 30 : 10,
                child: GestureDetector(
                  onTap: onClose,
                  child: Art.icon('close').available
                      ? ArtImage(Art.icon('close'), size: 36)
                      : Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBF0),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF7A5230),
                              width: 2.5,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 24,
                            color: Color(0xFF7A5230),
                          ),
                        ),
                ),
              ),
            ],
          );
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.fromLTRB(28, emblem != null ? 160 : 52, 28, 24),
      clipBehavior: Clip.none,
      child: !hasRibbon
          ? closable
          : Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                closable,
                // 축하 꽃가루 + 레벨업 별: 팝업 위에만 (본문을 가리지 않게), 톡 튀어나온다
                if (banner == 'gold')
                  Positioned(
                    top: -150,
                    child: IgnorePointer(
                      child: _Pop(
                        delay: 0.15,
                        // 코드로 그린 꽃가루 (그림 확대 시 가장자리 노이즈 없음, D-097)
                        child: const ConfettiBurst(width: 230),
                      ),
                    ),
                  ),
                if (emblem != null && Art.frame(emblem!).available)
                  Positioned(
                    top: -130,
                    child: IgnorePointer(
                      child: _Pop(
                        child: SizedBox(
                          height: 114,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Image.asset(
                                Art.frame(emblem!).path,
                                height: 114,
                                filterQuality: FilterQuality.medium,
                              ),
                              if (emblemText != null)
                                // 별 몸통 가운데 (그림 높이의 64%)
                                Positioned(
                                  top: 114 * 0.64 - 26,
                                  child: _OutlinedNumber(emblemText!),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: -30,
                  child: _Ribbon(gold: banner == 'gold', child: title!),
                ),
              ],
            ),
    );
  }
}

/// 버튼 테마에 꽂는 프레임 배경. 프레임이 없으면 원래 색 배경을 그대로 쓴다.
/// 버튼 기본 글자 (테마와 같은 값).
// 굵게(fontWeight) 없이: Jua · Mochiy Pop 은 굵은 글꼴이 없어 억지로 두껍게 그려 다른 글씨체처럼 보였다 (D-088)
const buttonTextStyle = TextStyle(fontSize: 16);

/// 연두 · 보라 버튼의 흰 글자 테두리 (밝은 바탕에서 글자가 묻히지 않게).
List<Shadow> buttonTextOutline(String frame) {
  final c = switch (frame) {
    'button_green' => const Color(0xFF2E6410),
    'button_purple' => const Color(0xFF4A2A72),
    _ => null,
  };
  if (c == null) return const [];
  return [
    for (final o in const [
      Offset(1.3, 0),
      Offset(-1.3, 0),
      Offset(0, 1.3),
      Offset(0, -1.3),
      Offset(0.9, 0.9),
      Offset(-0.9, 0.9),
      Offset(0.9, -0.9),
      Offset(-0.9, -0.9),
    ])
      Shadow(color: c, offset: o),
    Shadow(color: c.withValues(alpha: 0.6), offset: const Offset(0, 2.2)),
  ];
}

ButtonStyle framedButton(ButtonStyle base, String frame) {
  final outline = buttonTextOutline(frame);
  // 글자 테두리는 버튼마다 정한다: 연두 · 보라만 테두리, 나머지는 없음 (테마 값이 다른 버튼으로 새지 않게).
  // 원래 값을 잡아 둔다 (닫힘 안에서 base 를 읽으면 새 base = 자기 자신을 불러 끝없이 돈다)
  final ts = base.textStyle;
  base = base.copyWith(
    textStyle: WidgetStateProperty.resolveWith(
      (states) => (ts?.resolve(states) ?? buttonTextStyle).copyWith(
        // 비활성(반투명)일 때는 테두리를 빼야 글자가 뭉개지지 않는다
        shadows: states.contains(WidgetState.disabled) ? const [] : outline,
      ),
    ),
  );

  // 비활성 연두 · 보라 버튼: 흰 글자는 반투명 바탕에 묻히므로 진한 회녹색으로
  if (outline.isNotEmpty) {
    final fg = base.foregroundColor;
    base = base.copyWith(
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? const Color(0xFF4F5E3C)
            : fg?.resolve(states) ?? Colors.white,
      ),
    );
  }

  // 프레임 그림이 있으면 버튼 자체 배경·그림자는 투명하게 (둥근 모서리 밖으로 색이 비치지 않게)
  if (Art.frame(frame).available) {
    base = base.copyWith(
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(0),
      side: const WidgetStatePropertyAll(BorderSide.none),
    );
  }
  return base.copyWith(
    backgroundBuilder: (context, states, child) {
      final ref = Art.frame(frame);
      if (!ref.available || child == null) return child ?? const SizedBox();
      final disabled = states.contains(WidgetState.disabled);
      return Opacity(
        opacity: disabled ? 0.5 : 1,
        child: DecoratedBox(
          decoration: FrameBox.decorationFor(
            frame,
            const BoxDecoration(),
            corner: 16,
          ),
          child: child,
        ),
      );
    },
  );
}

/// 브랜드 색·경고 색처럼 직접 색을 지정한 버튼: 테마의 프레임을 쓰지 않는다.
ButtonStyle plainButton(ButtonStyle base) => base.copyWith(
  backgroundBuilder: (context, states, child) => child ?? const SizedBox(),
);

/// 9-slice 그리기: 원본을 9조각으로 나눠 모서리는 [k] 배율 고정 크기로, 가장자리·가운데만 늘린다.
/// (렌더러마다 결과가 다른 DecorationImage.centerSlice 대신 조각을 직접 그린다.)
class NineSliceDecoration extends Decoration {
  const NineSliceDecoration(
    this.path,
    this.center,
    this.k, {
    this.pill = false,
    this.capK = 0.5,
  });
  final String path;

  /// 알약 모양 버튼: 높이에 맞춰 그림을 통째로 줄이고 가로 가운데만 늘린다
  /// (둥근 끝이 잘려 늘어나지 않게, 9조각 대신 3조각).
  final bool pill;

  /// 알약 끝 조각 폭 = 높이 × capK.
  final double capK;
  final Rect center; // 원본 픽셀 기준 가운데(늘어나는) 영역
  final double k; // 원본 픽셀 → 화면 논리 px 배율 (모서리 크기 결정)

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _NineSlicePainter(this, onChanged);

  @override
  bool operator ==(Object other) =>
      other is NineSliceDecoration &&
      other.path == path &&
      other.center == center &&
      other.k == k &&
      other.pill == pill &&
      other.capK == capK;

  @override
  int get hashCode => Object.hash(path, center, k, pill, capK);
}

class _NineSlicePainter extends BoxPainter {
  _NineSlicePainter(this.d, VoidCallback? onChanged) : super(onChanged);
  final NineSliceDecoration d;

  static final Map<String, ui.Image> _cache = {};
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration config) {
    final img = _cache[d.path];
    final size = config.size;
    if (size == null) return;
    if (img == null) {
      if (_stream == null) {
        _stream = AssetImage(d.path).resolve(config);
        _listener = ImageStreamListener((info, sync) {
          _cache[d.path] = info.image;
          // 이미 캐시된 그림은 그리는 도중에 바로 알려 오므로, 다시 그리기는 다음 프레임으로 미룬다
          if (sync) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => onChanged?.call(),
            );
          } else {
            onChanged?.call();
          }
        });
        _stream!.addListener(_listener!);
      }
      return;
    }
    final w = img.width.toDouble(), h = img.height.toDouble();
    final paint0 = Paint()..filterQuality = FilterQuality.medium;
    if (d.pill) {
      // 둥근 끝 = 원본 높이의 절반. 화면에서는 버튼 높이의 절반 (폭이 모자라면 폭의 절반)
      final cap = h * d.capK;
      final capDst = (size.height * d.capK).clamp(0.0, size.width / 2);
      final sx = [0.0, cap, w - cap, w];
      final dx = [
        offset.dx,
        offset.dx + capDst,
        offset.dx + size.width - capDst,
        offset.dx + size.width,
      ];
      const inset = 0.5, overlap = 0.75;
      for (var j = 0; j < 3; j++) {
        final src = Rect.fromLTRB(
          sx[j] + (j > 0 ? inset : 0),
          0,
          sx[j + 1] - (j < 2 ? inset : 0),
          h,
        );
        final dst = Rect.fromLTRB(
          dx[j] - (j > 0 ? overlap : 0),
          offset.dy,
          dx[j + 1] + (j < 2 ? overlap : 0),
          offset.dy + size.height,
        );
        if (src.isEmpty || dst.isEmpty) continue;
        canvas.drawImageRect(img, src, dst, paint0);
      }
      return;
    }
    final c = d.center;
    // 원본 열/행 경계와 화면 열/행 경계
    final sx = [0.0, c.left, c.right, w];
    final sy = [0.0, c.top, c.bottom, h];
    var l = c.left * d.k,
        r = (w - c.right) * d.k,
        t = c.top * d.k,
        b = (h - c.bottom) * d.k;
    // 상자가 모서리 합보다 작으면 모서리를 함께 줄인다
    final fx = size.width < l + r ? size.width / (l + r) : 1.0;
    final fy = size.height < t + b ? size.height / (t + b) : 1.0;
    final f = fx < fy ? fx : fy;
    l *= f;
    r *= f;
    t *= f;
    b *= f;
    final dx = [
      offset.dx,
      offset.dx + l,
      offset.dx + size.width - r,
      offset.dx + size.width,
    ];
    final dy = [
      offset.dy,
      offset.dy + t,
      offset.dy + size.height - b,
      offset.dy + size.height,
    ];
    final paint = Paint()..filterQuality = FilterQuality.medium;
    // 이음새(얇은 선) 방지: 조각끼리 맞닿는 쪽은 원본을 0.5px 안에서 읽고(옆 조각 색이 번지지 않게),
    // 그리는 칸은 이웃 쪽으로 0.75px 겹친다(반올림 틈이 비지 않게).
    const inset = 0.5, overlap = 0.75;
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        final src = Rect.fromLTRB(
          sx[j] + (j > 0 ? inset : 0),
          sy[i] + (i > 0 ? inset : 0),
          sx[j + 1] - (j < 2 ? inset : 0),
          sy[i + 1] - (i < 2 ? inset : 0),
        );
        final dst = Rect.fromLTRB(
          dx[j] - (j > 0 ? overlap : 0),
          dy[i] - (i > 0 ? overlap : 0),
          dx[j + 1] + (j < 2 ? overlap : 0),
          dy[i + 1] + (i < 2 ? overlap : 0),
        );
        if (src.isEmpty || dst.isEmpty) continue;
        canvas.drawImageRect(img, src, dst, paint);
      }
    }
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    super.dispose();
  }
}

/// 대화상자 제목 띠: 패널 위 테두리에 걸친다. 글자는 띠 가운데에만.
/// 띠 그림(banner_green / banner_gold)이 들어오면 그 그림을, 없으면 코드로 그린 둥근 띠를 쓴다.
class _Ribbon extends StatelessWidget {
  const _Ribbon({required this.child, this.gold = false});
  final Widget child;
  final bool gold;

  static const double height = 52;

  @override
  Widget build(BuildContext context) {
    final art = Art.frame(gold ? 'banner_gold' : 'banner_green');
    final text = DefaultTextStyle.merge(
      style: const TextStyle(
        fontSize: 21,
        color: Colors.white,
        shadows: [
          Shadow(color: Color(0xFF5A3A1E), offset: Offset(0, 1.5)),
          Shadow(color: Color(0xFF5A3A1E), offset: Offset(1.2, 0)),
          Shadow(color: Color(0xFF5A3A1E), offset: Offset(-1.2, 0)),
          Shadow(color: Color(0xFF5A3A1E), offset: Offset(0, -1.2)),
        ],
      ),
      textAlign: TextAlign.center,
      child: child,
    );
    // 새 리본 (D-092): 꼬리 + 가운데 띠(글자 길이만큼 늘어남) + 뒤집은 꼬리
    final color = gold ? 'gold' : 'green';
    final mid = Art.frame('ribbon_mid_$color');
    final tail = Art.frame('ribbon_tail_$color');
    if (mid.available && tail.available) {
      const band = 44.0;
      const tailSize =
          band / 0.7067; // 꼬리 그림에서 띠는 위쪽 70.7% (가운데 띠는 그 부분을 떠 온 것)
      Widget tailImg({bool flip = false}) => Transform.flip(
        flipX: flip,
        child: Image.asset(
          tail.path,
          width: tailSize * 295 / 300, // 꼬리 그림 비율 (잘린 끝 1.5% 제외)
          height: tailSize,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.medium,
        ),
      );
      return SizedBox(
        height: tailSize,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            tailImg(),
            Transform.translate(
              offset: const Offset(-1.5, 0),
              child: Container(
                height: band,
                constraints: const BoxConstraints(minWidth: 80, maxWidth: 220),
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage(mid.path),
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                // 글자 폭만큼만 (Container 에 alignment 를 주면 최대 폭까지 늘어난다)
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: FittedBox(fit: BoxFit.scaleDown, child: text),
                    ),
                  ],
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(-2.5, 0), // 이음매에 실선이 비치지 않게 겹쳐 붙인다
              child: tailImg(flip: true),
            ),
          ],
        ),
      );
    }
    if (art.available) {
      final sz =
          Art.frameSize(art.path.split('/').last.split('.').first) ??
          const Size(384, 126);
      const ah = 70.0; // 띠 그림 높이 (비율 3:1 → 폭 약 210)
      final w = ah * sz.width / sz.height;
      return SizedBox(
        width: w,
        height: ah,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                art.path,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
              ),
            ),
            // 가운데 띠만 (양 끝 접힌 꼬리 · 아래 접힘 제외)
            Positioned(
              left: w * 0.2,
              right: w * 0.2,
              top: ah * 0.14,
              bottom: ah * 0.4,
              child: FittedBox(fit: BoxFit.scaleDown, child: text),
            ),
          ],
        ),
      );
    }
    // 띠 그림이 오기 전: 단색 둥근 띠 (두꺼운 갈색 테두리 + 위쪽 광택)
    final base = gold ? const Color(0xFFF2B33D) : const Color(0xFF7CC04A);
    final top = gold ? const Color(0xFFFFD873) : const Color(0xFFA4DB72);
    return Container(
      height: height,
      constraints: const BoxConstraints(minWidth: 200),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(color: const Color(0xFF5A3A1E), width: 3),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, base],
          stops: const [0.45, 0.46],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: FittedBox(fit: BoxFit.scaleDown, child: text),
    );
  }
}

/// 팝업 장식이 톡 튀어나오는 등장 (크기 0.4 → 1, 살짝 튕김).
class _Pop extends StatelessWidget {
  const _Pop({required this.child, this.delay = 0});
  final Widget child;
  final double delay; // 0~1 (전체 600ms 중 늦게 시작할 비율)

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 650),
      builder: (_, t, c) {
        final v = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
        final scale = 0.4 + 0.6 * Curves.elasticOut.transform(v);
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.scale(scale: scale, child: c),
        );
      },
      child: child,
    );
  }
}

/// 굵은 숫자: 흰 글자 + 두꺼운 갈색 외곽선 (별 · 배지 위에 얹는 용).
class _OutlinedNumber extends StatelessWidget {
  const _OutlinedNumber(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final size = text.length >= 3 ? 32.0 : 42.0;
    return SizedBox(
      height: 52,
      child: Stack(
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: size,
              height: 1.2,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 6
                ..strokeJoin = StrokeJoin.round
                ..color = const Color(0xFF7A4A12),
            ),
          ),
          Text(
            text,
            style: TextStyle(fontSize: size, height: 1.2, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/// 팝업 본문 공통 모양: 큰 그림 → 큰 숫자 한 줄 → 짧은 설명 한 줄 → (선택) 추가 위젯.
/// 글은 최소로, 핵심 값은 크게 (모바일 게임 팝업 가독성).
class PopupHero extends StatelessWidget {
  const PopupHero({
    super.key,
    required this.art,
    required this.big,
    this.note,
    this.extra,
  });
  final Widget art;
  final String big;
  final String? note;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        art,
        const SizedBox(height: 6),
        IconText(
          big,
          textAlign: TextAlign.center,
          iconScale: 1.1,
          style: const TextStyle(
            fontSize: 32,
            height: 1.15,
            color: Color(0xFF3A2E22),
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 4),
          IconText(
            note!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Color(0xFF6B5A44)),
          ),
        ],
        if (extra != null) ...[const SizedBox(height: 10), extra!],
      ],
    );
  }
}

/// 보상 팝업의 광고 버튼: 위에 [[ad]] 큰 글씨, 아래에 받을 양.
class DialogAdButton extends StatelessWidget {
  const DialogAdButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.adFree,
    this.sub,
  });
  final String label;
  final String? sub;
  final bool adFree;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: framedButton(
        FilledButton.styleFrom(
          backgroundColor: Palette.ad,
          minimumSize: const Size(double.infinity, 58),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        ),
        'button_purple',
      ),
      onPressed: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconText(
            adFree ? label : '[[ad]] $label',
            style: const TextStyle(fontSize: 19, color: Colors.white),
          ),
          if (sub != null)
            IconText(
              sub!,
              style: const TextStyle(fontSize: 13, color: Color(0xF2FFFFFF)),
            ),
        ],
      ),
    );
  }
}

/// 보상 팝업의 기본 버튼: 흰 프레임, 광고 버튼과 같은 높이.
class DialogPlainButton extends StatelessWidget {
  const DialogPlainButton({
    super.key,
    required this.label,
    required this.onTap,
  });
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilledButton(
    style: framedButton(
      FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Palette.text,
        minimumSize: const Size(double.infinity, 58),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      ),
      'button_white',
    ),
    onPressed: onTap,
    child: IconText(label, style: const TextStyle(fontSize: 18)),
  );
}

/// 보상 그림 뒤의 은은한 햇살: 따뜻한 원형 빛 + 천천히 도는 빛줄기.
class GlowHalo extends StatefulWidget {
  const GlowHalo({super.key, required this.child, this.size = 150});
  final Widget child;
  final double size;

  @override
  State<GlowHalo> createState() => _GlowHaloState();
}

class _GlowHaloState extends State<GlowHalo>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final rays = Art.frame('rays');
    final burst = rays.available ? rays : Art.frame('levelup_burst');
    return SizedBox(
      width: s,
      height: s * 0.8,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            width: s,
            height: s,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Color(0x66FFE08A),
                  Color(0x22FFE9B0),
                  Color(0x00FFF4D6),
                ],
                stops: [0, 0.6, 1],
              ),
            ),
          ),
          if (burst.available)
            RotationTransition(
              turns: _spin,
              child: Opacity(
                opacity: rays.available ? 0.9 : 0.35,
                child: Image.asset(burst.path, width: s, height: s),
              ),
            ),
          widget.child,
        ],
      ),
    );
  }
}

/// 비용 버튼: 숫자 길이와 상관없이 같은 크기 (글자는 줄여 맞춤).
class CostButton extends StatelessWidget {
  const CostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.width = 108,
    this.height = 44,
    this.frame = 'button_green',
  });
  final String label;
  final VoidCallback? onPressed;

  /// 'button_green'(사기 · 올리기) · 'button_white'(보조: 디자인 바꾸기 등) · 'button_gold'.
  final String frame;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: FilledButton(
      style: framedButton(
        FilledButton.styleFrom(
          minimumSize: Size(width, height),
          maximumSize: Size(width, height),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: frame == 'button_white' ? Colors.white : null,
          foregroundColor: frame == 'button_white'
              ? Palette.text
              : frame == 'button_gold'
              ? const Color(0xFF5A3A08)
              : null,
        ),
        frame,
      ),
      onPressed: onPressed,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: IconText(
          label,
          maxLines: 1,
          style: const TextStyle(fontSize: 15),
        ),
      ),
    ),
  );
}
