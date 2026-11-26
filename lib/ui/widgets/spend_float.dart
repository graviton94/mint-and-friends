import 'package:material_ui/material_ui.dart';

import '../../game/format.dart';
import '../../services/audio_service.dart';
import '../../art/art.dart';
import 'icon_text.dart';

/// 재화를 쓰면 누른 자리에서 [재화 그림 -쓴 양] 알약이 통 튀어나와 위로 떠오르며 사라진다 (D-081).
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
        left: at.dx - 90,
        top: at.dy - 58,
        width: 180,
        child: IgnorePointer(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1100),
            onEnd: () {
              if (e.mounted) e.remove();
            },
            builder: (_, v, child) {
              // 통 튀어나와(0~0.2) 잠깐 머물고(~0.45) 위로 떠오르며 사라짐
              final pop = v < 0.2 ? Curves.elasticOut.transform(v / 0.2) : 1.0;
              final rise = v < 0.4
                  ? 0.0
                  : Curves.easeInCubic.transform((v - 0.4) / 0.6);
              return Transform.translate(
                offset: Offset(0, -44 * rise),
                child: Opacity(
                  opacity: (1 - rise).clamp(0.0, 1.0),
                  child: Transform.scale(scale: 0.4 + 0.6 * pop, child: child),
                ),
              );
            },
            child: Center(
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 3, 12, 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBF0),
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(color: const Color(0xFF7A5230), width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ArtImage(IconText.resolve(token), size: 26),
                    const SizedBox(width: 4),
                    Text(
                      '-${fmt(amount)}',
                      style: const TextStyle(
                        fontSize: 20,
                        height: 1.1,
                        color: Color(0xFFD9483B),
                      ),
                    ),
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
