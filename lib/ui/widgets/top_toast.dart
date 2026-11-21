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
                decoration: BoxDecoration(
                  color: const Color(0xF7FFF8EA),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF7A5230),
                    width: 2.5,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: IconText(
                    text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF3A2E22),
                      fontSize: 15,
                    ),
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

  /// 새 아이템 발견처럼 축하할 일: 그림 + 제목 + 설명이 든 큰 카드가 위에서 내려온다.
  static void celebrate(
    BuildContext context, {
    required Widget art,
    required String title,
    required String sub,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    late OverlayEntry e;
    e = OverlayEntry(
      builder: (ctx) => Positioned(
        left: 24,
        right: 24,
        top: MediaQuery.paddingOf(ctx).top + 70,
        child: IgnorePointer(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 420),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.translate(
              offset: Offset(0, (1 - v) * -60),
              child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
            ),
            child: Center(
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 20, 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFFF9E6), Color(0xFFFFEBB8)],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFD9A441), width: 3),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x44000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GlowHalo(size: 84, child: art),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            IconText(
                              title,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFFB07A1C),
                              ),
                            ),
                            IconText(
                              sub,
                              style: const TextStyle(
                                fontSize: 19,
                                color: Color(0xFF3A2E22),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(e);
    Future.delayed(const Duration(milliseconds: 2800), e.remove);
  }
}
