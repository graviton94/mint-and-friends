import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../art/art.dart';

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
  });

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
      padding: EdgeInsets.fromLTRB(24, hasRibbon ? 40 : 22, 24, 20),
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
            const SizedBox(height: 16),
            Wrap(
              alignment: switch (actionsAlignment) {
                MainAxisAlignment.center => WrapAlignment.center,
                MainAxisAlignment.start => WrapAlignment.start,
                _ => WrapAlignment.end,
              },
              spacing: 8,
              runSpacing: 8,
              children: actions!,
            ),
          ],
        ],
      ),
    );
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.fromLTRB(28, emblem != null ? 150 : 52, 28, 24),
      clipBehavior: Clip.none,
      child: !hasRibbon
          ? panel
          : Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                panel,
                // 축하 꽃가루 + 레벨업 별: 팝업 위에만 (본문을 가리지 않게), 톡 튀어나온다
                if (banner == 'gold' && Art.frame('confetti').available)
                  Positioned(
                    top: -150,
                    child: IgnorePointer(
                      child: _Pop(
                        delay: 0.15,
                        child: Image.asset(
                          Art.frame('confetti').path,
                          width: 230,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ),
                  ),
                if (emblem != null && Art.frame(emblem!).available)
                  Positioned(
                    top: -112,
                    child: IgnorePointer(
                      child: _Pop(
                        child: Image.asset(
                          Art.frame(emblem!).path,
                          height: 96,
                          filterQuality: FilterQuality.medium,
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
ButtonStyle framedButton(ButtonStyle base, String frame) {
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
  const NineSliceDecoration(this.path, this.center, this.k);
  final String path;
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
      other.k == k;

  @override
  int get hashCode => Object.hash(path, center, k);
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
        _listener = ImageStreamListener((info, _) {
          _cache[d.path] = info.image;
          onChanged?.call();
        });
        _stream!.addListener(_listener!);
      }
      return;
    }
    final w = img.width.toDouble(), h = img.height.toDouble();
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
