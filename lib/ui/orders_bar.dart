import 'package:material_ui/material_ui.dart';

import '../art/art.dart';
import '../game/config.dart';
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
    required this.adFree,
  });
  final GameState game;
  final void Function(int index) onRefresh;
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
    required this.adFree,
  });
  final GameState game;
  final int index;
  final VoidCallback onRefresh;
  final bool adFree;

  @override
  Widget build(BuildContext context) {
    final o = game.orders[index];
    final friend = Friends.byId(o.friendId);
    final ready = game.canDeliver(index);
    return GestureDetector(
      onTap: ready ? () => game.deliver(index) : null,
      child: AnimatedContainer(
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
          scale: 0.3,
        ),
        child: Row(
          children: [
            ArtImage(Art.friend(friend), size: 28),
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
                      ready ? tr('order.deliver') : '[[star]]${o.stars}',
                      style: TextStyle(
                        fontSize: 13,
                        color: ready ? const Color(0xFFB0640A) : Palette.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!ready)
              Tooltip(
                message: tr('order.refresh'),
                child: GestureDetector(
                  onTap: onRefresh,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ArtImage(Art.icon('refresh'), size: 16),
                        if (!adFree) ArtImage(Art.icon('ad'), size: 14),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
