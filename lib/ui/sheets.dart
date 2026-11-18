import 'package:material_ui/material_ui.dart';

import '../game/config.dart';
import '../game/format.dart';
import '../game/game_state.dart';
import '../services/billing_service.dart';
import 'theme.dart';

Future<void> showUpgradesSheet(BuildContext context, GameState game) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.board,
    builder: (_) => ListenableBuilder(
      listenable: game,
      builder: (context, _) => _SheetFrame(
        title: '⬆️ 강화',
        child: Column(
          children: [
            for (final u in Upgrades.all) _UpgradeRow(game: game, def: u),
          ],
        ),
      ),
    ),
  );
}

class _UpgradeRow extends StatelessWidget {
  const _UpgradeRow({required this.game, required this.def});
  final GameState game;
  final UpgradeDef def;

  @override
  Widget build(BuildContext context) {
    final lv = game.lv(def.type);
    final maxed = game.upgradeMaxed(def.type);
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Text(def.icon, style: const TextStyle(fontSize: 30)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${def.title}  Lv.$lv', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    maxed
                        ? Upgrades.describe(def.type, lv)
                        : '${Upgrades.describe(def.type, lv)} → ${Upgrades.describe(def.type, lv + 1)}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: game.canBuyUpgrade(def.type) ? () => game.buyUpgrade(def.type) : null,
              child: Text(maxed ? 'MAX' : '🪙 ${fmt(game.upgradeCost(def.type))}'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showGardenSheet(BuildContext context, GameState game) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.board,
    builder: (_) => ListenableBuilder(
      listenable: game,
      builder: (context, _) {
        final area = Garden.areaAt(game.currentArea);
        final done = game.currentTaskInArea;
        return _SheetFrame(
          title: '${area.emoji} ${area.name}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 정원 미리보기 (아트 교체 예정: 영역별 배경 + 작업별 오브젝트 레이어)
              Container(
                height: 150,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFBFE3F5), Color(0xFFB5DDA4)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Center(
                  child: Wrap(
                    spacing: 14,
                    children: [
                      for (var i = 0; i < Garden.tasksPerArea; i++)
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 400),
                          opacity: i < done ? 1 : 0.18,
                          child: Text(area.tasks[i].emoji, style: const TextStyle(fontSize: 40)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: done / Garden.tasksPerArea,
                minHeight: 10,
                borderRadius: BorderRadius.circular(5),
              ),
              const SizedBox(height: 6),
              Text(
                '정원 보너스: 수익 x${game.gardenMultiplier.toStringAsFixed(2)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < Garden.tasksPerArea; i++)
                Card(
                  color: i < done ? const Color(0xFFE3F1DD) : Colors.white,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: Text(area.tasks[i].emoji, style: const TextStyle(fontSize: 28)),
                    title: Text(area.tasks[i].name,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    trailing: i < done
                        ? const Text('완료 ✅', style: TextStyle(fontSize: 15))
                        : i == done
                            ? FilledButton(
                                onPressed: game.canBuyGardenTask ? game.buyGardenTask : null,
                                child: Text('🪙 ${fmt(game.nextTaskCost)}'),
                              )
                            : const Text('🔒', style: TextStyle(fontSize: 20)),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

Future<void> showShopSheet(BuildContext context, BillingService billing) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Palette.board,
    builder: (_) => ListenableBuilder(
      listenable: billing,
      builder: (context, _) => _SheetFrame(
        title: '🚫 광고 제거 (1개월)',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('• 배너·전면 광고가 사라져요\n• 보상 광고 보상을 광고 없이 바로 받아요\n• 매월 자동 갱신, Play 스토어에서 언제든 해지',
                style: TextStyle(fontSize: 16, height: 1.6)),
            const SizedBox(height: 16),
            if (billing.adFree)
              const Text('✅ 광고 제거 이용 중', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))
            else
              FilledButton(
                onPressed: billing.product == null || billing.purchasing ? null : billing.buyRemoveAds,
                child: Text(billing.product == null ? '스토어 연결 중…' : '${billing.product!.price} / 월 구독하기'),
              ),
            TextButton(onPressed: billing.restore, child: const Text('구매 복원')),
          ],
        ),
      ),
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(3)),
                ),
              ),
              const SizedBox(height: 10),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
