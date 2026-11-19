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
    this.scale = 0.5,
  });

  final String frame;
  final BoxDecoration fallback;
  final Widget? child;
  final EdgeInsetsGeometry? padding;

  /// 프레임 테두리 두께 배율 (384px 원본 기준, 0.5 = 모서리가 화면에서 약 58px).
  final double scale;

  static Decoration decorationFor(
    String frame,
    BoxDecoration fallback, {
    double scale = 0.5,
  }) {
    final ref = Art.frame(frame);
    if (!ref.available) return fallback;
    return BoxDecoration(
      image: DecorationImage(
        image: AssetImage(ref.path),
        centerSlice: Art.frameCenter,
        scale: 1 / scale,
        fit: BoxFit.fill,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: decorationFor(frame, fallback, scale: scale),
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
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: FrameBox(
        frame: 'panel',
        fallback: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(28),
        ),
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              FrameBox(
                frame: 'ribbon',
                fallback: const BoxDecoration(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                child: DefaultTextStyle.merge(
                  style: const TextStyle(fontSize: 22),
                  textAlign: TextAlign.center,
                  child: title!,
                ),
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
      ),
    );
  }
}

/// 버튼 테마에 꽂는 프레임 배경. 프레임이 없으면 원래 색 배경을 그대로 쓴다.
ButtonStyle framedButton(ButtonStyle base, String frame) {
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
            scale: 0.35,
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
