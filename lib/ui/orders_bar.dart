import 'package:material_ui/material_ui.dart';

import '../art/art.dart';
import '../game/config.dart';
import '../game/format.dart';
import '../game/game_state.dart';
import '../i18n/l10n.dart';
import 'theme.dart';
import 'widgets/icon_text.dart';
import 'widgets/frame_box.dart';

/// 친구들의 부탁 3개. 보드에 아이템이 있으면 탭 한 번으로 전달된다.
class OrdersBar extends StatelessWidget {
  const OrdersBar({
    super.key,
    required this.game,
    required this.onRefresh,
    required this.onQuota,
    required this.adFree,
  });
  final GameState game;
  final void Function(int index) onRefresh;
  final void Function(String friendId) onQuota;
  final bool adFree;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < game.orders.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _OrderCard(
              game: game,
              index: i,
              onRefresh: () => onRefresh(i),
              onQuota: () => onQuota(game.orders[i].friendId),
              adFree: adFree,
            ),
          ),
        ],
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.game,
    required this.index,
    required this.onRefresh,
    required this.onQuota,
    required this.adFree,
  });
  final GameState game;
  final int index;
  final VoidCallback onRefresh;
  final VoidCallback onQuota;
  final bool adFree;

  @override
  Widget build(BuildContext context) {
    final o = game.orders[index];
    final friend = Friends.byId(o.friendId);
    final ready = game.canDeliver(index);
    return GestureDetector(
      onTap: ready ? () => game.deliver(index) : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _card(context, o, friend, ready),
          // 전달할 수 있으면 빨간 점
          if (ready) const Positioned(right: -4, top: -4, child: RedDot()),
        ],
      ),
    );
  }

  /// 친구 얼굴 + (한도가 걸린 뒤) 오늘 남은 별 부탁 수.
  Widget _avatar(Order o) {
    final friend = Friends.byId(o.friendId);
    final face = ArtImage(Art.friend(friend), size: 28);
    if (!game.quotaActive) return face;
    final left = game.starOrdersLeft(o.friendId);
    return SizedBox(
      width: 30,
      height: 34,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          face,
          Positioned(
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: left > 0 ? Palette.primary : Colors.black38,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$left/${game.starOrderLimit(o.friendId)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  height: 1.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, Order o, FriendDef friend, bool ready) {
    final stars = game.orderGivesStars(o);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: FrameBox.decorationFor(
        ready ? 'card_ready' : 'card',
        BoxDecoration(
          color: ready ? const Color(0xFFFFF3C4) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: ready ? Palette.accent : const Color(0xFFE5DCC8),
            width: ready ? 3 : 1.5,
          ),
        ),
        corner: 14,
      ),
      child: Row(
        children: [
          _avatar(o),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ArtImage(Art.item(o.chain, o.level), size: 26),
                      Text(
                        ' Lv${o.level}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                FittedBox(
                  child: IconText(
                    ready
                        ? tr('order.deliver')
                        : stars
                        ? '[[star]]${o.stars}'
                        : '[[coin]]${fmt(game.orderCoins(o))}',
                    style: TextStyle(
                      fontSize: 13,
                      color: ready ? const Color(0xFFB0640A) : Palette.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!ready && !stars)
            Tooltip(
              message: tr('order.quotaMore'),
              child: GestureDetector(
                onTap: onQuota,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ArtImage(Art.star, size: 16),
                      if (!adFree) ArtImage(Art.icon('ad'), size: 14),
                    ],
                  ),
                ),
              ),
            )
          else if (!ready)
            Tooltip(
              message: tr('order.refresh'),
              child: GestureDetector(
                onTap: onRefresh,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ArtImage(
                        Art.icon('swap').available
                            ? Art.icon('swap')
                            : Art.icon('refresh'),
                        size: 16,
                      ),
                      if (!adFree && game.freeRerollsLeft == 0)
                        ArtImage(Art.icon('ad'), size: 14),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
