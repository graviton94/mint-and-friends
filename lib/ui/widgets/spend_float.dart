import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../../art/art.dart';
import '../../game/format.dart';
import '../../services/audio_service.dart';
import 'icon_text.dart';

/// 재화를 쓰면 (D-087): 누른 자리에서 작은 재화 그림 몇 개가 톡톡 튀어 흩어지고,
/// 작은 '-5' 글자가 통 튀어나와 살짝 떠오르며 사라진다. 알약 상자 없이 가볍게.
const _brown = Color(0xFF7A5230);

class SpendFloat {
  /// 마지막으로 화면을 누른 자리 (앱 전체 Listener 가 적는다).
  static Offset lastTap = Offset.zero;
  static final _rng = Random();

  static void show(OverlayState overlay, String token, double amount) {
    if (amount <= 0) return;
    sfx(Sfx.spend);
    final at = lastTap;
    // 튀는 조각: 위쪽 반원으로 4개, 방향 · 거리 · 회전은 조금씩 다르게
    final bits = [
      for (var i = 0; i < 4; i++)
        (
          -pi / 2 + (i - 1.5) * 0.55 + (_rng.nextDouble() - 0.5) * 0.3,
          46 + _rng.nextDouble() * 20,
          (_rng.nextDouble() - 0.5) * 2.4,
        ),
    ];
    late OverlayEntry e;
    e = OverlayEntry(
      builder: (_) => Positioned(
        left: at.dx - 70,
        top: at.dy - 90,
        width: 140,
        height: 120,
        // 앱 글씨체 · 글자 기본값이 오버레이에도 적용되게
        child: Material(
          type: MaterialType.transparency,
          child: IgnorePointer(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 850),
              onEnd: () {
                if (e.mounted) e.remove();
              },
              builder: (_, v, _) {
                const origin = Offset(70, 90);
                final out = Curves.easeOutCubic.transform(v);
                final fade = v < 0.55 ? 1.0 : (1 - v) / 0.45;
                final pop = Curves.elasticOut.transform(
                  (v / 0.45).clamp(0.0, 1.0),
                );
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final (ang, dist, spin) in bits)
                      Positioned(
                        left: origin.dx + cos(ang) * dist * out - 9,
                        // 포물선: 위로 튀었다가 조금 떨어진다
                        top: origin.dy + sin(ang) * dist * out + 26 * v * v - 9,
                        child: Opacity(
                          opacity: fade.clamp(0.0, 1.0),
                          child: Transform.rotate(
                            angle: spin * v,
                            child: Transform.scale(
                              scale: 1 - 0.35 * v,
                              child: ArtImage(
                                IconText.resolve(token),
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ),
                    // 글자: 통 튀어나와 살짝 떠오름
                    Positioned(
                      left: 0,
                      right: 0,
                      top: origin.dy - 30 - 18 * out,
                      child: Opacity(
                        opacity: fade.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: 0.5 + 0.5 * pop,
                          child: Center(
                            child: Text(
                              '-${fmt(amount)}',
                              // 게임 버튼 글자처럼: 흰 글자 + 갈색 외곽선
                              style: const TextStyle(
                                fontSize: 17,
                                height: 1,
                                color: Colors.white,
                                shadows: [
                                  Shadow(color: _brown, offset: Offset(1.5, 0)),
                                  Shadow(
                                    color: _brown,
                                    offset: Offset(-1.5, 0),
                                  ),
                                  Shadow(color: _brown, offset: Offset(0, 1.5)),
                                  Shadow(
                                    color: _brown,
                                    offset: Offset(0, -1.5),
                                  ),
                                  Shadow(color: _brown, offset: Offset(1, 1)),
                                  Shadow(color: _brown, offset: Offset(-1, -1)),
                                  Shadow(color: _brown, offset: Offset(1, -1)),
                                  Shadow(color: _brown, offset: Offset(-1, 1)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    overlay.insert(e);
  }
}
