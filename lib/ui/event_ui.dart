import 'package:material_ui/material_ui.dart';

import '../art/art.dart';
import '../game/config.dart';
import '../game/event_pass.dart';
import '../game/format.dart';
import '../game/game_state.dart';
import '../i18n/l10n.dart';
import '../i18n/names.dart';
import '../services/audio_service.dart';
import '../services/billing_service.dart';
import 'sheets.dart';
import 'theme.dart';
import 'widgets/frame_box.dart';
import 'widgets/icon_text.dart';
import 'widgets/reward_popup.dart';

/// 월간 이벤트 화면 (D-112): 배너 · 오늘의 퀘스트 · 패스 · 20칸 사다리 (무료 | 칸 | 패스).
Future<void> showEventSheet(
  BuildContext context,
  BillingService billing,
  GameState game,
) {
  final def = game.currentEvent;
  if (def == null) return Future.value();
  return showGameSheet(
    context,
    Listenable.merge([billing, game]),
    () => SheetFrame(
      title: tr('event.name.${def.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Banner(def: def, game: game),
          const SizedBox(height: 12),
          _Quests(game: game),
          const SizedBox(height: 12),
          if (!game.hasEventPass) ...[
            _PassBuy(billing: billing, game: game, def: def),
            const SizedBox(height: 12),
          ],
          if (game.eventClaimable > 0) ...[
            FilledButton(
              style: framedButton(
                FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                'button_green',
              ),
              onPressed: () => _claimAll(context, game),
              child: IconText(
                tr('event.claimAll', {'n': game.eventClaimable}),
                style: const TextStyle(fontSize: 17),
              ),
            ),
            const SizedBox(height: 10),
          ],
          _LadderHead(pass: game.hasEventPass),
          for (var i = 0; i < EventPass.steps; i++)
            _StepRow(game: game, def: def, i: i),
        ],
      ),
    ),
  );
}

void _claimAll(BuildContext context, GameState game) {
  var coins = 0, energy = 0, stars = 0, gems = 0;
  for (var i = 0; i < game.eventStep; i++) {
    for (final p in [false, true]) {
      final before = game.gems;
      final e0 = game.energy;
      final s0 = game.stars;
      final c0 = game.coins;
      if (game.claimEventStep(i, premium: p) != null) {
        gems += game.gems - before;
        energy += game.energy - e0;
        stars += game.stars - s0;
        coins += (game.coins - c0).round();
      }
    }
  }
  sfx(Sfx.unlock);
  RewardPopup.show(
    context,
    Reward(coins: coins, energy: energy, stars: stars, gems: gems),
    title: tr('reward.got'),
  );
}

/// 배너 그림 + 왼쪽 1/3 에 이벤트 이름 · 남은 날.
class _Banner extends StatelessWidget {
  const _Banner({required this.def, required this.game});
  final EventDef def;
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final days = game.eventEnds.difference(game.now).inHours ~/ 24 + 1;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 2,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (Art.has(def.banner))
              Image.asset(def.banner, fit: BoxFit.cover)
            else
              const ColoredBox(color: Color(0xFFE6F2DC)),
            Positioned(
              left: 12,
              top: 12,
              bottom: 12,
              width: 150,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    tr('event.name.${def.id}'),
                    style: const TextStyle(
                      fontSize: 20,
                      height: 1.15,
                      color: Color(0xFF5A3A22),
                      shadows: [Shadow(color: Colors.white, blurRadius: 6)],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: IconText(
                      tr('event.daysLeft', {'n': days}),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFFC0442C),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 오늘의 퀘스트 4개 (3개를 끝내면 한 칸).
class _Quests extends StatelessWidget {
  const _Quests({required this.game});
  final GameState game;

  static const icons = {
    QuestKind.basket: 'basket',
    QuestKind.merge: 'sparkle',
    QuestKind.pat: 'heart',
    QuestKind.ad: 'ad',
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE2D3B5), width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IconText(
          tr('event.questsTitle', {
            'done': game.questsDone,
            'need': EventPass.questsNeeded,
          }),
          style: const TextStyle(fontSize: 16, color: Color(0xFF5A3A22)),
        ),
        const SizedBox(height: 2),
        IconText(
          game.eventStep >= EventPass.steps
              ? tr('event.allDone')
              : game.eventSteppedToday
              ? tr('event.todayDone')
              : tr('event.todayHint'),
          style: TextStyle(
            fontSize: 12.5,
            color: game.eventSteppedToday
                ? Palette.primary
                : const Color(0xFF8A7660),
          ),
        ),
        const SizedBox(height: 8),
        for (final k in QuestKind.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                ArtImage(IconText.resolve(icons[k]!), size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: IconText(
                    tr('event.quest.${k.name}', {'n': EventPass.target[k]}),
                    maxLines: 1,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                game.questDone(k)
                    ? ArtImage(Art.icon('check'), size: 22)
                    : Text(
                        '${game.questCount(k)}/${EventPass.target[k]}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF8A7660),
                        ),
                      ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// 패스 사기 (아직 안 샀을 때): 최종 의상 그림 + 받는 것 + 가격.
class _PassBuy extends StatelessWidget {
  const _PassBuy({
    required this.billing,
    required this.game,
    required this.def,
  });
  final BillingService billing;
  final GameState game;
  final EventDef def;

  @override
  Widget build(BuildContext context) {
    final d = billing.offerProducts[Offers.eventPass];
    final gems = EventPass.premium
        .where((r) => r.kind == RewardKind.gems)
        .fold<int>(0, (a, r) => a + r.amount);
    final outfit = Art.outfitArt(Friends.byId(def.friend), def.outfit);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF3C4), Color(0xFFFFE08A)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD9A21E), width: 2.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ArtImage(
                outfit.available ? outfit : Art.icon('outfit'),
                size: 72,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconText(
                      tr('event.passTitle'),
                      style: const TextStyle(
                        fontSize: 19,
                        color: Color(0xFF5A3A22),
                      ),
                    ),
                    IconText(
                      tr('event.passNote', {
                        'name': friendName(def.friend),
                        'outfit': tr('event.outfit.${def.id}'),
                        'gems': gems,
                      }),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF7A6146),
                      ),
                    ),
                  ],
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
            onPressed: d == null || billing.purchasing
                ? null
                : () => billing.buyOffer(Offers.eventPass),
            child: IconText(
              billing.purchasing
                  ? tr('shop.connecting')
                  : d?.price ?? '₩${fmtInt(EventPass.krw)}',
              style: const TextStyle(fontSize: 17),
            ),
          ),
        ],
      ),
    );
  }
}

class _LadderHead extends StatelessWidget {
  const _LadderHead({required this.pass});
  final bool pass;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Expanded(
          child: Center(
            child: IconText(
              tr('event.freeTrack'),
              style: const TextStyle(fontSize: 15, color: Color(0xFF3E7A38)),
            ),
          ),
        ),
        const SizedBox(width: 52),
        Expanded(
          child: Center(
            child: IconText(
              tr('event.passTrack'),
              style: const TextStyle(fontSize: 15, color: Color(0xFFB07A10)),
            ),
          ),
        ),
      ],
    ),
  );
}

/// 사다리 한 칸: [무료 보상] (칸 번호) [패스 보상].
class _StepRow extends StatelessWidget {
  const _StepRow({required this.game, required this.def, required this.i});
  final GameState game;
  final EventDef def;
  final int i;

  @override
  Widget build(BuildContext context) {
    final reached = i < game.eventStep;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: _cell(context, premium: false, reached: reached)),
          SizedBox(
            width: 52,
            child: Center(
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: reached
                      ? const Color(0xFF7CCB4E)
                      : const Color(0xFFE8DCC4),
                  border: Border.all(color: const Color(0xFF5A3A22), width: 2),
                ),
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 16,
                    color: reached ? Colors.white : const Color(0xFF8A7660),
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: _cell(context, premium: true, reached: reached)),
        ],
      ),
    );
  }

  Widget _cell(
    BuildContext context, {
    required bool premium,
    required bool reached,
  }) {
    final r = (premium ? EventPass.premium : EventPass.free)[i];
    final claimed = (premium ? game.eventClaimedPrem : game.eventClaimedFree)
        .contains(i);
    final locked = premium && !game.hasEventPass;
    final can = reached && !claimed && !locked;
    final (ArtRef art, String label) = _show(r, premium);
    return GestureDetector(
      onTap: can
          ? () {
              final before = (game.gems, game.energy, game.stars, game.coins);
              if (game.claimEventStep(i, premium: premium) == null) return;
              sfx(Sfx.unlock);
              RewardPopup.show(
                context,
                Reward(
                  gems: game.gems - before.$1,
                  energy: game.energy - before.$2,
                  stars: game.stars - before.$3,
                  coins: (game.coins - before.$4).round(),
                ),
                title: tr('reward.got'),
                art: art,
                sub: r.kind == RewardKind.finale || r.kind == RewardKind.badge
                    ? label
                    : null,
              );
            }
          : null,
      child: Container(
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: can
              ? const Color(0xFFFFF6D6)
              : premium
              ? const Color(0xFFFFF9EA)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: can
                ? const Color(0xFFE0903D)
                : premium
                ? const Color(0xFFE8CF8A)
                : const Color(0xFFE2D3B5),
            width: can ? 2.5 : 1.5,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Opacity(
              opacity: claimed ? 0.45 : 1,
              child: Row(
                children: [
                  ArtImage(art, size: 36),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: IconText(
                        label,
                        maxLines: 1,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (claimed)
              Positioned(
                right: -2,
                top: 4,
                child: ArtImage(Art.icon('check'), size: 22),
              ),
            if (locked)
              Positioned(
                right: -2,
                top: 4,
                child: ArtImage(
                  Art.icon('event_gold_lock').available
                      ? Art.icon('event_gold_lock')
                      : Art.lock,
                  size: 20,
                ),
              ),
            if (can) const Positioned(right: -4, top: -4, child: RedDot()),
          ],
        ),
      ),
    );
  }

  (ArtRef, String) _show(StepReward r, bool premium) {
    final n = game.rewardAmount(r);
    return switch (r.kind) {
      RewardKind.energy => (Art.icon('energy'), '+$n'),
      RewardKind.coins => (Art.icon('coins_m'), '+${fmt(n.toDouble())}'),
      RewardKind.stars => (Art.star, '+$n'),
      RewardKind.gems => (Art.icon('diamond'), '+$n'),
      RewardKind.boostCoins => (
        Art.icon(boostIcon(BoostKind.coins)),
        tr('shop.boostTime', {'n': n}),
      ),
      RewardKind.boostEnergy => (
        Art.icon(boostIcon(BoostKind.energy)),
        tr('shop.boostTime', {'n': n}),
      ),
      RewardKind.boostLucky => (
        Art.icon(boostIcon(BoostKind.lucky)),
        tr('shop.boostTime', {'n': n}),
      ),
      RewardKind.badge => (
        Art.has(def.badge) ? ArtRef(def.badge, '') : Art.icon('trophy'),
        tr('event.badge'),
      ),
      RewardKind.finale =>
        premium
            ? (
                Art.outfitArt(Friends.byId(def.friend), def.outfit).available
                    ? Art.outfitArt(Friends.byId(def.friend), def.outfit)
                    : Art.icon('outfit'),
                tr('event.outfit.${def.id}'),
              )
            : (
                def.souvenir != null &&
                        Art.has('assets/art/souvenirs/${def.souvenir}.webp')
                    ? ArtRef('assets/art/souvenirs/${def.souvenir}.webp', '')
                    : Art.icon('event_souvenir_shelf').available
                    ? Art.icon('event_souvenir_shelf')
                    : Art.icon('season_fx'),
                tr('event.free.${def.id}'),
              ),
    };
  }
}
