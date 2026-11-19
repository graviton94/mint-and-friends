import 'package:material_ui/material_ui.dart';

import '../game/config.dart';
import '../game/game_state.dart';
import 'theme.dart';

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
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: ready ? const Color(0xFFFFF3C4) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: ready ? Palette.accent : const Color(0xFFE5DCC8),
            width: ready ? 3 : 1.5,
          ),
        ),
        child: Row(
          children: [
            Text(friend.emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 2),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          o.item.emoji,
                          style: const TextStyle(fontSize: 22),
                        ),
                        Text(
                          ' Lv${o.level}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  FittedBox(
                    child: Text(
                      ready ? '탭해서 전달!' : '⭐${o.stars}',
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
              GestureDetector(
                onTap: onRefresh,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Text(
                    adFree ? '🔄' : '🔄\n📺',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
