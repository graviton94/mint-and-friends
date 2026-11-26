import 'package:material_ui/material_ui.dart';

import '../../game/format.dart';
import '../../services/audio_service.dart';
import 'icon_text.dart';

/// 재화를 쓰면 누른 자리에서 '-[[star]]5' 가 위로 떠오르며 사라진다 (D-080).
class SpendFloat {
  /// 마지막으로 화면을 누른 자리 (앱 전체 Listener 가 적는다).
  static Offset lastTap = Offset.zero;

  static void show(OverlayState overlay, String token, double amount) {
    if (amount <= 0) return;
    sfx(Sfx.spend);
    late OverlayEntry e;
    final at = lastTap;
    e = OverlayEntry(
      builder: (_) => Positioned(
        left: at.dx - 80,
        top: at.dy - 40,
        width: 160,
        child: IgnorePointer(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            onEnd: () {
              if (e.mounted) e.remove();
            },
            builder: (_, v, child) => Transform.translate(
              offset: Offset(0, -56 * v),
              child: Opacity(
                opacity: v < 0.55 ? 1 : (1 - v) / 0.45,
                child: Transform.scale(
                  scale: v < 0.15 ? 0.7 + 2 * v : 1,
                  child: child,
                ),
              ),
            ),
            child: Center(
              child: IconText(
                '-[[$token]]${fmt(amount)}',
                style: const TextStyle(
                  fontSize: 22,
                  color: Color(0xFFE0533D),
                  shadows: [
                    Shadow(color: Colors.white, offset: Offset(1.5, 0)),
                    Shadow(color: Colors.white, offset: Offset(-1.5, 0)),
                    Shadow(color: Colors.white, offset: Offset(0, 1.5)),
                    Shadow(color: Colors.white, offset: Offset(0, -1.5)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(e);
  }
}
