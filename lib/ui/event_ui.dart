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
          _Ladder(game: game, def: def),
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

/// 사다리 (D-113): 가로로 이어지는 진행 막대 + 칸 메달, 위 = 무료 보상, 아래 = 패스 보상.
/// 열면 지금 칸이 가운데 오게 스크롤한다.
class _Ladder extends StatefulWidget {
  const _Ladder({required this.game, required this.def});
  final GameState game;
  final EventDef def;

  @override
  State<_Ladder> createState() => _LadderState();
}

class _LadderState extends State<_Ladder> {
  static const col = 84.0;
  final _c = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_c.hasClients) return;
      final view = _c.position.viewportDimension;
      final at = (widget.game.eventStep - 0.5) * col - view / 2;
      _c.jumpTo(at.clamp(0.0, _c.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF0),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2D3B5), width: 1.5),
      ),
      child: Row(
        children: [
          // 왼쪽 고정 이름표: 무료(새싹) · 패스(왕관)
          SizedBox(
            width: 46,
            child: Column(
              children: [
                _side('event_sprout', tr('event.freeTrack')),
                const SizedBox(height: 44),
                _side('event_crown', tr('event.passTrack')),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _c,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < EventPass.steps; i++)
                    SizedBox(
                      width: col,
                      child: Column(
                        children: [
                          _RewardCell(
                            game: g,
                            def: widget.def,
                            i: i,
                            premium: false,
                          ),
                          _TrackNode(i: i, step: g.eventStep),
                          _RewardCell(
                            game: g,
                            def: widget.def,
                            i: i,
                            premium: true,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _side(String icon, String label) => SizedBox(
    height: 84,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ArtImage(Art.icon(icon), size: 32),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF5A3A22)),
          ),
        ),
      ],
    ),
  );
}

/// 진행 막대 한 칸: 가로 막대(지난 칸까지 초록으로 참) + 가운데 칸 메달.
class _TrackNode extends StatelessWidget {
  const _TrackNode({required this.i, required this.step});
  final int i;
  final int step;

  @override
  Widget build(BuildContext context) {
    final reached = i < step;
    final leftOn = i < step; // 이 칸까지 왔으면 왼쪽 반은 참
    final rightOn = i + 1 < step;
    Widget half(bool on, {required bool left}) => Expanded(
      child: Container(
        height: 14,
        decoration: BoxDecoration(
          color: on ? const Color(0xFF7CCB4E) : const Color(0xFFEDE2C8),
          border: Border(
            top: const BorderSide(color: Color(0xFF5A3A22), width: 2),
            bottom: const BorderSide(color: Color(0xFF5A3A22), width: 2),
            left: left && i == 0
                ? const BorderSide(color: Color(0xFF5A3A22), width: 2)
                : BorderSide.none,
            right: !left && i == EventPass.steps - 1
                ? const BorderSide(color: Color(0xFF5A3A22), width: 2)
                : BorderSide.none,
          ),
          borderRadius: BorderRadius.horizontal(
            left: left && i == 0 ? const Radius.circular(7) : Radius.zero,
            right: !left && i == EventPass.steps - 1
                ? const Radius.circular(7)
                : Radius.zero,
          ),
        ),
      ),
    );
    final medal = reached ? 'event_step_on' : 'event_step';
    return SizedBox(
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(children: [half(leftOn, left: true), half(rightOn, left: false)]),
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: Art.frame(medal).available
                ? BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage(Art.frame(medal).path),
                      fit: BoxFit.contain,
                    ),
                  )
                : BoxDecoration(
                    shape: BoxShape.circle,
                    color: reached
                        ? const Color(0xFF7CCB4E)
                        : const Color(0xFFFFF6E2),
                    border: Border.all(
                      color: const Color(0xFF5A3A22),
                      width: 2,
                    ),
                  ),
            child: Text(
              '${i + 1}',
              style: TextStyle(
                fontSize: 15,
                color: reached ? Colors.white : const Color(0xFF8A7660),
                shadows: reached
                    ? const [Shadow(color: Color(0xFF3E7A38), blurRadius: 2)]
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 보상 칸 하나 (무료 = 흰 카드, 패스 = 금빛 카드). 받을 수 있으면 반짝 테두리 + 빨간 점, 받았으면 흐리게 + 체크.
class _RewardCell extends StatelessWidget {
  const _RewardCell({
    required this.game,
    required this.def,
    required this.i,
    required this.premium,
  });
  final GameState game;
  final EventDef def;
  final int i;
  final bool premium;

  @override
  Widget build(BuildContext context) {
    final r = (premium ? EventPass.premium : EventPass.free)[i];
    final reached = i < game.eventStep;
    final claimed = (premium ? game.eventClaimedPrem : game.eventClaimedFree)
        .contains(i);
    final locked = premium && !game.hasEventPass;
    final can = reached && !claimed && !locked;
    final (art, label) = rewardShow(game, def, r, premium);
    final frame = premium ? 'event_slot_gold' : 'event_slot';
    final big = r.kind == RewardKind.finale || r.kind == RewardKind.badge;
    return GestureDetector(
      onTap: can
          ? () {
              final b = (game.gems, game.energy, game.stars, game.coins);
              if (game.claimEventStep(i, premium: premium) == null) return;
              sfx(Sfx.unlock);
              RewardPopup.show(
                context,
                Reward(
                  gems: game.gems - b.$1,
                  energy: game.energy - b.$2,
                  stars: game.stars - b.$3,
                  coins: (game.coins - b.$4).round(),
                ),
                title: tr('reward.got'),
                art: art,
                sub: big ? label : null,
              );
            }
          : null,
      child: Container(
        width: 76,
        height: 84,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Container(
                decoration: Art.frame(frame).available
                    ? BoxDecoration(
                        image: DecorationImage(
                          image: AssetImage(Art.frame(frame).path),
                          fit: BoxFit.fill,
                        ),
                        boxShadow: can
                            ? const [
                                BoxShadow(
                                  color: Color(0x99FFB938),
                                  blurRadius: 10,
                                ),
                              ]
                            : null,
                      )
                    : BoxDecoration(
                        color: premium ? const Color(0xFFFFF0C2) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF5A3A22),
                          width: 2,
                        ),
                      ),
              ),
            ),
            Positioned.fill(
              top: 14,
              child: Opacity(
                opacity: claimed ? 0.4 : (reached ? 1 : 0.85),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ArtImage(art, size: big ? 40 : 32),
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: IconText(
                          label,
                          maxLines: 1,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (claimed)
              Positioned(
                right: 2,
                top: 14,
                child: ArtImage(Art.icon('check'), size: 22),
              ),
            if (locked)
              Positioned(
                right: 0,
                top: 10,
                child: ArtImage(Art.icon('event_gold_lock'), size: 22),
              ),
            if (can) const Positioned(right: -2, top: 6, child: RedDot()),
          ],
        ),
      ),
    );
  }
}

/// 보상 그림 · 글자 (그때 진행도 기준 양).
(ArtRef, String) rewardShow(
  GameState game,
  EventDef def,
  StepReward r,
  bool premium,
) {
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
                  : Art.icon('event_souvenir_shelf'),
              tr('event.free.${def.id}'),
            ),
  };
}
