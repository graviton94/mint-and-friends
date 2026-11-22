import 'package:material_ui/material_ui.dart';

import '../../art/art.dart';

/// 새싹 스크롤 손잡이 (scroll_thumb): 내용이 넘칠 때만 오른쪽에 보이고, 끌어서 움직일 수도 있다.
/// [builder] 는 받은 컨트롤러를 스크롤 뷰에 붙여 돌려준다.
class SproutScrollbar extends StatefulWidget {
  const SproutScrollbar({
    super.key,
    required this.builder,
    this.width = 16,
    this.inset = 2,
  });
  final Widget Function(ScrollController controller) builder;
  final double width;
  final double inset;

  @override
  State<SproutScrollbar> createState() => _SproutScrollbarState();
}

class _SproutScrollbarState extends State<SproutScrollbar> {
  final _c = ScrollController();

  @override
  void initState() {
    super.initState();
    _c.addListener(_tick);
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
        return false;
      },
      child: LayoutBuilder(
        builder: (context, box) {
          final view = widget.builder(_c);
          // 손잡이가 있든 없든 같은 모양의 트리를 돌려준다 (안쪽 상태가 초기화되지 않게)
          Widget? bar;
          if (_c.hasClients && _c.position.hasContentDimensions) {
            final p = _c.position;
            final max = p.maxScrollExtent;
            if (max > 0) {
              final track = p.viewportDimension - widget.inset * 2;
              final thumb =
                  (track * p.viewportDimension / (max + p.viewportDimension))
                      .clamp(widget.width * 3.2, track);
              final top =
                  widget.inset +
                  (track - thumb) * (p.pixels / max).clamp(0.0, 1.0);
              bar = Positioned(
                right: 0,
                top: top,
                width: widget.width + 8,
                height: thumb,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (d) {
                    final per =
                        max / (track - thumb).clamp(1.0, double.infinity);
                    _c.jumpTo((p.pixels + d.delta.dy * per).clamp(0.0, max));
                  },
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _Thumb(width: widget.width, height: thumb),
                  ),
                ),
              );
            }
          }
          return Stack(
            fit: StackFit.passthrough,
            children: [
              view,
              bar ?? const Positioned(width: 0, height: 0, child: SizedBox()),
            ],
          );
        },
      ),
    );
  }
}

/// 잎은 그대로, 줄기만 늘린다: 원본 크기로 9조각 늘이기를 한 뒤 줄여서 그린다.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.width, required this.height});
  final double width, height;
  static const _w = 179.0, _h = 509.0;

  @override
  Widget build(BuildContext context) {
    final ref = Art.frame('scroll_thumb');
    if (!ref.available) {
      return Container(
        width: width * 0.6,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF9BD46A),
          borderRadius: BorderRadius.circular(width),
        ),
      );
    }
    final k = _w / width;
    return SizedBox(
      width: width,
      height: height,
      child: FittedBox(
        fit: BoxFit.fill,
        child: Image.asset(
          ref.path,
          width: _w,
          height: (height * k).clamp(_h, double.infinity),
          centerSlice: const Rect.fromLTRB(40, 175, 130, 450),
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
