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
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final MainAxisAlignment? actionsAlignment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 리본은 패널 위 테두리에 걸쳐 놓는다 (게임 팝업의 일반적인 모양). 패널 안은 리본 아래부터.
    final hasRibbon = title != null && Art.frame('ribbon').available;
    final panel = FrameBox(
      frame: 'panel',
      fallback: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      corner: 30,
      padding: EdgeInsets.fromLTRB(24, hasRibbon ? 58 : 22, 24, 20),
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
      insetPadding: const EdgeInsets.fromLTRB(28, 52, 28, 24),
      clipBehavior: Clip.none,
      child: !hasRibbon
          ? panel
          : Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                panel,
                Positioned(top: -40, child: _Ribbon(child: title!)),
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

/// 대화상자 제목 리본: 폭 240 고정(비율 그대로). 글자는 띠 부분(아래 꼬리 제외)에만 놓는다.
class _Ribbon extends StatelessWidget {
  const _Ribbon({required this.child});
  final Widget child;

  static const double width = 240;

  @override
  Widget build(BuildContext context) {
    final art = Art.frame('ribbon');
    const h = width * 174 / 384;
    return SizedBox(
      width: width,
      height: h,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              art.path,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
            ),
          ),
          Positioned(
            left: width * 0.2,
            right: width * 0.2,
            top: h * 0.31,
            height: h * 0.32,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: DefaultTextStyle.merge(
                style: const TextStyle(
                  fontSize: 20,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: Color(0xFF3F6A12),
                      offset: Offset(0, 1.5),
                      blurRadius: 0,
                    ),
                    Shadow(
                      color: Color(0xFF3F6A12),
                      offset: Offset(1.2, 0),
                      blurRadius: 0,
                    ),
                    Shadow(
                      color: Color(0xFF3F6A12),
                      offset: Offset(-1.2, 0),
                      blurRadius: 0,
                    ),
                    Shadow(
                      color: Color(0xFF3F6A12),
                      offset: Offset(0, -1.2),
                      blurRadius: 0,
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
