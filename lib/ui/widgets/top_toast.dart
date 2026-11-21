import 'package:material_ui/material_ui.dart';

import 'frame_box.dart';
import 'icon_text.dart';

/// 화면 위에서 내려오는 알림 (창 · 시트 위에도 보인다). 보상 받기 · 안내 문구 공용.
class TopToast {
  static final List<OverlayEntry> _live = [];

  static void show(BuildContext context, String text) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    late OverlayEntry e;
    final slot = _live.length;
    e = OverlayEntry(
      builder: (ctx) => Positioned(
        left: 20,
        right: 20,
        top: MediaQuery.paddingOf(ctx).top + 62 + slot * 52,
        child: IgnorePointer(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            builder: (_, v, child) => Opacity(
              opacity: v.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, (1 - v) * -28),
                child: child,
              ),
            ),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 11,
                ),
                decoration: FrameBox.decorationFor(
                  'toast',
                  BoxDecoration(
                    color: const Color(0xEE2F3B2F),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  corner: 16,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: IconText(
                    text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _live.add(e);
    overlay.insert(e);
    Future.delayed(const Duration(milliseconds: 2400), () {
      e.remove();
      _live.remove(e);
    });
  }
}
