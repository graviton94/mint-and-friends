import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../art/art.dart';
import '../game/config.dart';
import '../game/format.dart';
import '../game/game_state.dart';
import '../i18n/l10n.dart';
import '../services/billing_service.dart';
import '../i18n/names.dart';
import 'widgets/frame_box.dart';
import 'widgets/icon_text.dart';

/// 결제 묶음 카드 (D-110): 저금통 · 에너지 묶음 · 단계 묶음이 같은 모양을 쓴다.
/// 위: 그림 + 제목 + 한 줄 설명 (+ 남은 시간), 가운데: 받는 것 칸들, 아래: 가격 버튼.
class OfferCard extends StatelessWidget {
  const OfferCard({
    super.key,
    required this.billing,
    required this.id,
    required this.art,
    required this.title,
    required this.items,
    this.note,
    this.timer,
    this.tag,
    this.progress,
    this.enabled = true,
    this.disabledLabel,
    this.colors = const [Color(0xFFFFF1D6), Color(0xFFFFE0C2)],
    this.border = const Color(0xFFE0903D),
  });

  final BillingService billing;
  final String id;
  final ArtRef art;
  final String title;
  final String? note;

  /// 받는 것: (아이콘 토큰 문구) 예: '[[diamond]] 250'.
  final List<String> items;
  final String? timer;

  /// 오른쪽 위 딱지 (예: '2배 가치').
  final String? tag;

  /// 저금통처럼 차오르는 막대 (받는 것 칸 대신).
  final Widget? progress;
  final bool enabled;
  final String? disabledLabel;
  final List<Color> colors;
  final Color border;

  @override
  Widget build(BuildContext context) {
    final d = billing.offerProducts[id];
    final price = d?.price ?? '₩${fmtInt(Offers.krw[id] ?? 0)}';
    final can = enabled && d != null && !billing.purchasing;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border, width: 2.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ArtImage(art, size: 54),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: IconText(
                        title,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 19,
                          color: Color(0xFF5A3A22),
                        ),
                      ),
                    ),
                    if (note != null)
                      IconText(
                        note!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF7A6146),
                        ),
                      ),
                  ],
                ),
              ),
              if (tag != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0533D),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    tag!,
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                  ),
                ),
            ],
          ),
          if (timer != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: IconText(
                '[[timer]] $timer',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFFC0442C)),
              ),
            ),
          if (progress != null) ...[const SizedBox(height: 10), progress!],
          if (items.isNotEmpty) const SizedBox(height: 8),
          if (items.isNotEmpty)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in items)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE8D2AE)),
                    ),
                    child: IconText(
                      t,
                      maxLines: 1,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 10),
          FilledButton(
            style: framedButton(
              FilledButton.styleFrom(minimumSize: const Size(0, 46)),
              'button_green',
            ),
            onPressed: can ? () => billing.buyOffer(id) : null,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: IconText(
                !enabled && disabledLabel != null
                    ? disabledLabel!
                    : billing.purchasing
                    ? tr('shop.connecting')
                    : price,
                maxLines: 1,
                style: const TextStyle(fontSize: 17),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 저금통 막대 (D-113): 둥근 홈 막대 그림 안에 파란 다이아 물이 차오르고, 가운데에 모은 수,
/// 깰 수 있는 자리에 눈금 + 아래 '450부터 깨기'.
class _PiggyBar extends StatelessWidget {
  const _PiggyBar({
    required this.value,
    required this.mark,
    required this.label,
    required this.markLabel,
  });
  final double value;
  final double mark;
  final String label;
  final String markLabel;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      const h = 30.0, inset = 6.0;
      final w = c.maxWidth;
      final inner = w - inset * 2;
      final mx = inset + inner * mark;
      final ready = value >= mark;
      return SizedBox(
        height: h + 18,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: h,
              child: DecoratedBox(
                decoration: FrameBox.decorationFor(
                  'event_track',
                  BoxDecoration(
                    color: const Color(0xFFF3E4C8),
                    borderRadius: BorderRadius.circular(h / 2),
                    border: Border.all(
                      color: const Color(0xFF5A3A22),
                      width: 2,
                    ),
                  ),
                  corner: h / 2,
                ),
              ),
            ),
            Positioned(
              left: inset,
              top: inset,
              height: h - inset * 2,
              width: max(h - inset * 2, inner * value.clamp(0.0, 1.0)),
              child: Opacity(
                opacity: value <= 0 ? 0 : 1,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF9FE2FF), Color(0xFF3F9AD6)],
                    ),
                    borderRadius: BorderRadius.circular(h),
                  ),
                  alignment: Alignment.topCenter,
                  padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            // 깰 수 있는 자리 눈금
            Positioned(
              left: mx - 1.5,
              top: 2,
              height: h - 4,
              width: 3,
              child: Container(
                decoration: BoxDecoration(
                  color: ready
                      ? Colors.white.withValues(alpha: 0.9)
                      : const Color(0xFF5A3A22),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: h,
              child: Center(
                child: IconText(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                    shadows: [
                      Shadow(color: Color(0xFF2F4F6B), blurRadius: 3),
                      Shadow(color: Color(0xFF2F4F6B), offset: Offset(0, 1)),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: mx - 60,
              width: 120,
              top: h + 1,
              child: Text(
                markLabel,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11.5,
                  color: ready
                      ? const Color(0xFF3F9AD6)
                      : const Color(0xFF8A7660),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// 다이아 저금통 카드.
Widget piggyCard(BillingService billing, GameState game) => OfferCard(
  billing: billing,
  id: Offers.piggy,
  art: Art.icon('piggy').available ? Art.icon('piggy') : Art.icon('dia_basket'),
  title: tr('piggy.title'),
  note: game.piggyFull
      ? tr('piggy.full')
      : tr('piggy.note', {'n': Piggy.perOrder}),
  items: const [],
  tag: tr('piggy.tag'),
  progress: _PiggyBar(
    value: game.piggyGems / Piggy.cap,
    mark: Piggy.minBreak / Piggy.cap,
    label: '[[diamond]] ${fmtInt(game.piggyGems)} / ${fmtInt(Piggy.cap)}',
    markLabel: tr('piggy.breakAt', {'n': fmtInt(Piggy.minBreak)}),
  ),
  enabled: game.piggyBreakable,
  disabledLabel: tr('piggy.locked', {'n': fmtInt(Piggy.minBreak)}),
  colors: const [Color(0xFFE4F4FF), Color(0xFFCDE8F8)],
  border: const Color(0xFF4AA3D8),
);

/// 에너지 묶음 카드 (하루 한 번).
Widget energyBundleCard(BillingService billing) => OfferCard(
  billing: billing,
  id: Offers.energy,
  art: Art.icon('energy_bundle').available
      ? Art.icon('energy_bundle')
      : Art.icon('energy_crate'),
  title: tr('energyBundle.title'),
  note: tr('energyBundle.note'),
  tag: tr('offer.daily'),
  items: [
    '[[energy]] ${EnergyBundle.energy}',
    '[[diamond]] ${EnergyBundle.gems}',
    '[[boost]] ${tr('boost.energy')} ${tr('shop.boostTime', {'n': EnergyBundle.boost.inMinutes})}',
  ],
);

/// 단계 묶음 카드 (24시간 한정).
Widget milestoneCard(BillingService billing, GameState game) => OfferCard(
  billing: billing,
  id: Offers.milestone,
  art: Art.icon('milestone_gift').available
      ? Art.icon('milestone_gift')
      : Art.icon('welcome_gift'),
  title: tr('msOffer.title'),
  note: milestoneReason(game.milestoneKey),
  timer: tr('msOffer.left', {'time': fmtDuration(game.milestoneLeft)}),
  tag: tr('offer.limited'),
  items: [
    '[[diamond]] ${MilestoneBundle.gems}',
    '[[energy]] ${MilestoneBundle.energy}',
    '[[coin]] ${fmt(game.milestoneCoins)}',
    '[[boost]] ${tr('boost.coins')} ${tr('unit.hour', {'n': MilestoneBundle.boost.inMinutes ~/ 60})}',
  ],
  colors: const [Color(0xFFFFF3C4), Color(0xFFFFE08A)],
  border: const Color(0xFFD9A21E),
);

/// 단계 묶음이 열린 이유 한 줄 ('새 구역 기념' · '레벨 20 기념').
String milestoneReason(String? key) {
  if (key == null) return '';
  if (key.startsWith('lv:')) {
    return tr('msOffer.level', {'n': key.substring(3)});
  }
  return tr('msOffer.area');
}

/// 단계 묶음이 열렸을 때 한 번 띄우는 창 (레벨 10 · 20 … · 새 구역).
Future<void> showMilestoneOffer(
  BuildContext context,
  BillingService billing,
  GameState game,
) {
  if (!game.milestoneActive) return Future.value();
  return showDialog<void>(
    context: context,
    builder: (ctx) => ListenableBuilder(
      listenable: Listenable.merge([billing, game]),
      builder: (ctx, _) => GameDialog(
        banner: 'gold',
        title: IconText(tr('msOffer.popTitle'), textAlign: TextAlign.center),
        onClose: () => Navigator.pop(ctx),
        content: game.milestoneActive
            ? milestoneCard(billing, game)
            : IconText(tr('reward.purchase'), textAlign: TextAlign.center),
      ),
    ),
  );
}
