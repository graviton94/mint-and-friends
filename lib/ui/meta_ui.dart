import 'package:material_ui/material_ui.dart';

import '../art/art.dart';
import '../game/config.dart';
import '../game/format.dart';
import '../game/game_state.dart';
import '../i18n/l10n.dart';
import '../i18n/names.dart';
import '../services/audio_service.dart';
import 'sheets.dart';
import 'theme.dart';
import 'widgets/frame_box.dart';
import 'widgets/icon_text.dart';

/// 보상 한 칸을 아이콘 문구로: "[[coin]]50 [[energy]]10 [[star]]1".
String rewardText(Reward r) => [
  if (r.coins > 0) '[[coin]]${fmt(r.coins.toDouble())}',
  if (r.energy > 0) '[[energy]]${r.energy}',
  if (r.stars > 0) '[[star]]${fmt(r.stars.toDouble())}',
  if (r.gems > 0) '[[diamond]]${r.gems}',
].join(' ');

// ---------------------------------------------------------------- 업적

Future<void> showAchievementsSheet(BuildContext context, GameState game) =>
    showGameSheet(context, game, () {
      final defs = [...Achievements.all]
        // 받을 수 있는 것 → 진행 중 → 다 끝난 것
        ..sort((a, b) {
          int rank(AchievementDef d) => game.achievementClaimable(d)
              ? 0
              : (game.achievementClaimedTiers(d) >= d.tiers.length ? 2 : 1);
          return rank(a).compareTo(rank(b));
        });
      return SheetFrame(
        title: tr('ach.title'),
        child: Column(
          children: [for (final d in defs) _AchRow(game: game, def: d)],
        ),
      );
    });

class _AchRow extends StatelessWidget {
  const _AchRow({required this.game, required this.def});
  final GameState game;
  final AchievementDef def;

  @override
  Widget build(BuildContext context) {
    final claimed = game.achievementClaimedTiers(def);
    final done = claimed >= def.tiers.length;
    final claimable = game.achievementClaimable(def);
    final target = def.tiers[done ? def.tiers.length - 1 : claimed];
    final value = game.achievementValue(def);
    final reward = def.rewardFor(claimed);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: claimable ? const Color(0xFFFFF3C4) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: claimable ? Palette.accent : const Color(0xFFE5DCC8),
          width: claimable ? 2.5 : 1.5,
        ),
      ),
      child: Row(
        children: [
          Opacity(
            opacity: done ? 0.6 : 1,
            child: ArtImage(IconText.resolve(def.icon), size: 40),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        tr('ach.${def.id}'),
                        style: const TextStyle(fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tr('ach.tier', {'a': claimed, 'b': def.tiers.length}),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
                IconText(
                  tr('ach.${def.id}.desc', {'n': fmt(target.toDouble())}),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B5A44),
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: done ? 1 : (value / target).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: const Color(0xFFEDE3CC),
                    color: claimable
                        ? const Color(0xFFF2B33D)
                        : Palette.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (done)
            IconText(tr('ach.done'), style: const TextStyle(fontSize: 14))
          else
            FilledButton(
              style: framedButton(
                FilledButton.styleFrom(
                  minimumSize: const Size(78, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                'button_green',
              ),
              onPressed: claimable
                  ? () {
                      sfx(Sfx.coin);
                      game.claimAchievement(def);
                    }
                  : null,
              child: IconText(
                rewardText(reward),
                iconScale: 1.0,
                style: const TextStyle(fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 쪽지

Future<void> showMailSheet(BuildContext context, GameState game) =>
    showGameSheet(
      context,
      game,
      () => SheetFrame(
        title: tr('mail.title'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (game.unreadMail > 0)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    sfx(Sfx.coin);
                    game.claimAllMail();
                  },
                  child: Text(
                    tr('mail.claimAll'),
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ),
            if (game.mail.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  tr('mail.empty'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black45),
                ),
              ),
            for (final m in game.mail) _MailRow(game: game, mail: m),
          ],
        ),
      ),
    );

class _MailRow extends StatelessWidget {
  const _MailRow({required this.game, required this.mail});
  final GameState game;
  final Mail mail;

  @override
  Widget build(BuildContext context) {
    final fromFriend = Friends.all.any((f) => f.id == mail.from);
    final name = fromFriend
        ? friendName(mail.from)
        : mail.from == 'team'
        ? tr('mail.from.team')
        : mail.from;
    final title = mail.text ?? tr(mail.titleKey, {...mail.args, 'name': name});
    return Opacity(
      opacity: mail.claimed ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5DCC8), width: 1.5),
        ),
        child: Row(
          children: [
            fromFriend
                ? ArtImage(Art.friend(Friends.byId(mail.from)), size: 44)
                : ArtImage(
                    Art.icon(switch (mail.kind) {
                      MailKind.social => 'gift',
                      MailKind.notice
                          when mail.from == 'team' && mail.id != 'welcome' =>
                        'notice',
                      _ => 'letter',
                    }),
                    size: 40,
                  ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                  IconText(title, style: const TextStyle(fontSize: 15)),
                  if (mail.hasReward)
                    IconText(
                      rewardText(mail.reward),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF7A5A12),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            mail.claimed
                ? Text(
                    tr('mail.claimed'),
                    style: const TextStyle(fontSize: 13, color: Colors.black45),
                  )
                : FilledButton(
                    style: framedButton(
                      FilledButton.styleFrom(minimumSize: const Size(64, 40)),
                      'button_green',
                    ),
                    onPressed: () {
                      sfx(mail.hasReward ? Sfx.coin : Sfx.tap);
                      game.claimMail(mail.id);
                    },
                    child: Text(
                      tr('mail.claim'),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 메뉴

class MenuEntry {
  final String icon;
  final IconData? fallback;
  final String label;
  final int badge; // 0 = 없음, -1 = 점만
  final VoidCallback onTap;
  const MenuEntry(
    this.icon,
    this.label,
    this.onTap, {
    this.badge = 0,
    this.fallback,
  });
}

/// 메뉴: 업적 · 친구 · 쪽지 · 광고 제거 · 설정 (큰 타일).
Future<void> showMenuSheet(
  BuildContext context,
  Listenable listen,
  List<MenuEntry> Function() entries,
) => showGameSheet(
  context,
  listen,
  () => SheetFrame(
    title: tr('menu.title'),
    child: GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: [
        for (final e in entries())
          GestureDetector(
            onTap: () {
              sfx(Sfx.tap);
              Navigator.of(context).pop();
              e.onTap();
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFF7A5230),
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Art.icon(e.icon).available || e.fallback == null
                          ? ArtImage(Art.icon(e.icon), size: 44)
                          : Icon(
                              e.fallback,
                              size: 40,
                              color: const Color(0xFF7A5230),
                            ),
                      const SizedBox(height: 4),
                      Text(e.label, style: const TextStyle(fontSize: 15)),
                    ],
                  ),
                ),
                if (e.badge != 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: RedDot(count: e.badge > 0 ? e.badge : null),
                  ),
              ],
            ),
          ),
      ],
    ),
  ),
);

// 레벨 등 표시용 (사용하지 않으면 지워도 됨)
int get achievementGoalCount => Achievements.totalGoals;

// ---------------------------------------------------------------- 출석

/// 7일 출석판: 받은 날 · 오늘 · 남은 날. 빠진 날이 있어도 이어서 받는다.
Future<void> showCheckInSheet(BuildContext context, GameState game) =>
    showGameSheet(
      context,
      game,
      () => SheetFrame(
        title: tr('checkIn.title'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IconText(
              tr('checkIn.note'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, c) {
                final w = (c.maxWidth - 3 * 8) / 4;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (var d = 0; d < CheckIn.days; d++)
                      SizedBox(
                        width: d == CheckIn.days - 1 ? w * 2 + 8 : w,
                        child: _CheckInTile(game: game, day: d),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            FilledButton(
              style: framedButton(
                FilledButton.styleFrom(minimumSize: const Size(160, 52)),
                'button_green',
              ),
              onPressed: game.checkInReady
                  ? () {
                      sfx(Sfx.coin);
                      game.claimCheckIn();
                    }
                  : null,
              child: IconText(
                game.checkInReady ? tr('checkIn.claim') : tr('checkIn.done'),
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );

class _CheckInTile extends StatelessWidget {
  const _CheckInTile({required this.game, required this.day});
  final GameState game;
  final int day;

  @override
  Widget build(BuildContext context) {
    final next = game.checkInToday; // 다음에 받을 칸
    // 오늘 7일째를 받아 한 바퀴를 돌았으면(next 0) 오늘은 모두 받은 것으로 보인다
    final claimed = game.checkInReady ? day < next : (next == 0 || day < next);
    final isToday = game.checkInReady && day == next;
    final r = game.checkInReward(day);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: isToday
            ? const Color(0xFFFFF3C4)
            : claimed
            ? const Color(0xFFE6F2E0)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isToday ? const Color(0xFFE0A100) : const Color(0xFFE2D3B5),
          width: isToday ? 2.5 : 1.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            tr('checkIn.day', {'n': day + 1}),
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B5638)),
          ),
          const SizedBox(height: 4),
          Opacity(
            opacity: claimed ? 0.45 : 1,
            child: IconText(
              rewardText(r),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
          ),
          if (claimed)
            ArtImage(Art.icon('check'), size: 18)
          else
            const SizedBox(height: 18),
        ],
      ),
    );
  }
}
