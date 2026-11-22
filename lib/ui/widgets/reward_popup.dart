import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../art/art.dart';
import '../../game/format.dart';
import '../../game/meta.dart' show Reward;
import '../../i18n/l10n.dart';
import '../../services/audio_service.dart';
import 'frame_box.dart';
import 'icon_text.dart';

/// 보상 받기 축하 창 (출석 · 쪽지 · 업적 · 선물 등 공용).
/// 화면을 살짝 어둡게 하고 가운데에 금색 리본 + 보상 아이콘(빛) + 수량이 통통 튀어 나온다.
/// 아무 데나 누르거나 2.8초 지나면 닫힌다. 창 · 시트 위에도 보인다.
class RewardPopup {
  static OverlayEntry? _live;

  static void show(
    BuildContext context,
    Reward r, {
    String? title,
    ArtRef? art,
    String? sub,
    Duration stay = const Duration(milliseconds: 2800),
  }) {
    if (r.isEmpty && art == null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _live?.remove();
    sfx(Sfx.coin);
    final items = <(ArtRef, String)>[
      if (r.coins > 0) (Art.coin, fmt(r.coins.toDouble())),
      if (r.energy > 0) (Art.icon('energy'), '${r.energy}'),
      if (r.stars > 0) (Art.icon('star'), fmt(r.stars.toDouble())),
      if (r.gems > 0) (Art.icon('diamond'), '${r.gems}'),
    ];
    late OverlayEntry e;
    Timer? t;
    void close() {
      t?.cancel();
      if (_live == e) _live = null;
      if (e.mounted) e.remove();
    }

    e = OverlayEntry(
      builder: (ctx) => _RewardView(
        title: title ?? tr('reward.got'),
        art: art,
        sub: sub,
        items: items,
        onClose: close,
      ),
    );
    _live = e;
    overlay.insert(e);
    // 광고 · 결제 화면에서 돌아오는 중이면 앱이 다시 보일 때부터 시간을 잰다
    // (안 그러면 보이기도 전에 저절로 닫혀 '받았다' 창을 못 본다)
    void arm() {
      if (!e.mounted) return;
      final st = WidgetsBinding.instance.lifecycleState;
      if (st == null || st == AppLifecycleState.resumed) {
        t = Timer(stay, close);
      } else {
        t = Timer(const Duration(milliseconds: 300), arm);
      }
    }

    arm();
  }
}

class _RewardView extends StatelessWidget {
  const _RewardView({
    required this.title,
    required this.items,
    required this.onClose,
    this.art,
    this.sub,
  });
  final String title;
  final ArtRef? art;
  final String? sub;
  final List<(ArtRef, String)> items;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final big = items.length <= 2;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutBack,
        builder: (_, v, child) => ColoredBox(
          color: Color.fromRGBO(30, 22, 12, 0.45 * v.clamp(0.0, 1.0)),
          child: Center(
            child: Transform.scale(
              scale: 0.6 + 0.4 * v,
              child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
            ),
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            width: 300,
            padding: const EdgeInsets.fromLTRB(18, 40, 18, 18),
            margin: const EdgeInsets.only(top: 30),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8EA),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0xFF7A5230), width: 3),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x44000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (art != null)
                      GlowHalo(size: 150, child: ArtImage(art!, size: 110)),
                    if (sub != null) ...[
                      IconText(
                        sub!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 17,
                          color: Color(0xFF4A3A22),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < items.length; i++)
                            _Pop(
                              delay: 120 + i * 110,
                              child: _Chip(
                                icon: items[i].$1,
                                value: items[i].$2,
                                big: big && art == null,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      tr('reward.tap'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black38,
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: -10,
                  right: -10,
                  top: -72,
                  child: Center(
                    child: FrameBox(
                      frame: 'banner_gold',
                      fallback: BoxDecoration(
                        color: const Color(0xFFF2C14E),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SizedBox(
                        width: 240,
                        height: 60,
                        child: Center(
                          child: IconText(
                            title,
                            style: const TextStyle(
                              fontSize: 21,
                              color: Color(0xFF5A3A08),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 보상 하나: 빛 + 큰 아이콘 + 수량.
class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.value, required this.big});
  final ArtRef icon;
  final String value;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final s = big ? 76.0 : 52.0;
    return Container(
      width: big ? 118 : 120,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEAD9B5), width: 2),
      ),
      child: Column(
        children: [
          GlowHalo(
            size: s * 1.5,
            child: ArtImage(icon, size: s),
          ),
          Text(
            '+$value',
            style: TextStyle(
              fontSize: big ? 24 : 20,
              color: const Color(0xFFB0640A),
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// 차례로 통통 튀어 나오기.
class _Pop extends StatefulWidget {
  const _Pop({required this.delay, required this.child});
  final int delay;
  final Widget child;

  @override
  State<_Pop> createState() => _PopState();
}

class _PopState extends State<_Pop> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: CurvedAnimation(parent: _c, curve: Curves.elasticOut),
    child: widget.child,
  );
}
