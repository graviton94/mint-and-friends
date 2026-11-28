import 'package:material_ui/material_ui.dart';

import 'widgets/reward_popup.dart';

import '../art/art.dart';
import '../game/config.dart';
import '../game/format.dart';
import '../game/game_state.dart';
import '../i18n/l10n.dart';
import '../i18n/names.dart';
import '../services/analytics_service.dart';
import '../services/audio_service.dart';
import 'sheets.dart';
import 'theme.dart';
import 'widgets/frame_box.dart';
import 'widgets/icon_text.dart';
import 'widgets/sprout_scrollbar.dart';
import 'widgets/top_toast.dart';

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
          // 같은 줄 안에서는 다음 목표까지 많이 온 것부터
          return rank(a).compareTo(rank(b));
        });
      return SheetFrame(
        title: tr('ach.title'),
        child: Column(
          children: [
            if (game.claimableAchievements > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton(
                  style: framedButton(
                    FilledButton.styleFrom(minimumSize: const Size(160, 46)),
                    'button_green',
                  ),
                  onPressed: () {
                    sfx(Sfx.coin);
                    final r = game.claimAllAchievements();
                    RewardPopup.show(
                      context,
                      r,
                      title: tr('reward.achievement'),
                    );
                  },
                  child: Text(
                    tr('ach.claimAll', {'n': game.claimableAchievements}),
                    style: const TextStyle(fontSize: 17),
                  ),
                ),
              ),
            for (final d in defs) _AchRow(game: game, def: d),
          ],
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
    final reward = game.achievementReward(def, claimed);
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
                      def.endless
                          ? tr('ach.lv', {'n': claimed})
                          : tr('ach.tier', {
                              'a': claimed,
                              'b': def.tiers.length,
                            }),
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
                      {
                        final r = game.claimAchievement(def);
                        if (r != null && rewardText(r).isNotEmpty) {
                          RewardPopup.show(
                            context,
                            r,
                            title: tr('reward.achievement'),
                          );
                        }
                      }
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
        child: _MailBox(game: game),
      ),
    );

/// 보낸 이 이름 · 제목 · 본문 (번역 키 또는 원격 글).
String mailFrom(Mail m) => Friends.all.any((f) => f.id == m.from)
    ? friendName(m.from)
    : m.from == 'team'
    ? tr('mail.from.team')
    : m.from == 'gardener'
    ? tr('mail.from.gardener')
    : m.from;
String mailTitle(Mail m) =>
    m.text ?? tr(m.titleKey, {...m.args, 'name': mailFrom(m)});
String? mailBody(Mail m) {
  if (m.body != null && m.body!.trim().isNotEmpty) return m.body;
  final k = m.bodyKey;
  if (k == null) return null;
  return L10n.instance.has(k) ? tr(k, m.args) : tr('mail.updateBody');
}

ArtRef _mailIcon(Mail m) {
  if (Friends.all.any((f) => f.id == m.from)) {
    return Art.friend(Friends.byId(m.from));
  }
  if (m.from == 'gardener') {
    return Art.icon('diary').available ? Art.icon('diary') : Art.icon('letter');
  }
  return Art.icon(switch (m.kind) {
    MailKind.social => 'gift',
    MailKind.notice when m.id.startsWith('update-') => 'party',
    MailKind.notice when m.from == 'team' && m.id != 'welcome' => 'notice',
    _ => 'letter',
  });
}

/// 쪽지함: 모두 받기 · 선택 삭제 · 누르면 상세 · 읽은 쪽지는 14일 뒤 자동 삭제.
class _MailBox extends StatefulWidget {
  const _MailBox({required this.game});
  final GameState game;
  @override
  State<_MailBox> createState() => _MailBoxState();
}

class _MailBoxState extends State<_MailBox> {
  bool _select = false;
  final Set<String> _picked = {};

  GameState get game => widget.game;

  void _claimAll() {
    sfx(Sfx.coin);
    final r = game.claimAllMail();
    if (rewardText(r).isNotEmpty) {
      RewardPopup.show(context, r, title: tr('reward.mail'));
    }
  }

  void _delete() {
    final d = game.deleteMail(_picked);
    setState(() {
      _picked.clear();
      _select = false;
    });
    if (rewardText(d.reward).isNotEmpty) {
      // 안 받은 선물은 받고 지웠다
      sfx(Sfx.coin);
      RewardPopup.show(context, d.reward, title: tr('mail.deletedClaimed'));
    } else {
      sfx(Sfx.tap);
      if (d.count > 0) {
        TopToast.show(context, tr('mail.deleted', {'n': d.count}));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mails = game.mail;
    final small = const TextStyle(fontSize: 15);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 위 도구 줄
        Row(
          children: [
            if (!_select && game.unreadMail > 0)
              TextButton(
                onPressed: _claimAll,
                child: Text(tr('mail.claimAll'), style: small),
              ),
            const Spacer(),
            if (_select) ...[
              TextButton(
                onPressed: () => setState(() {
                  _picked
                    ..clear()
                    ..addAll([for (final m in mails) m.id]);
                }),
                child: Text(tr('mail.pickAll'), style: small),
              ),
              TextButton(
                onPressed: _picked.isEmpty ? null : _delete,
                child: Text(
                  tr('mail.deleteN', {'n': _picked.length}),
                  style: small.copyWith(
                    color: _picked.isEmpty ? null : const Color(0xFFC0392B),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _select = false;
                  _picked.clear();
                }),
                child: Text(tr('common.cancel'), style: small),
              ),
            ] else if (mails.isNotEmpty)
              TextButton(
                onPressed: () => setState(() => _select = true),
                child: Text(tr('mail.select'), style: small),
              ),
          ],
        ),
        if (mails.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              tr('mail.empty'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black45),
            ),
          ),
        for (final m in mails)
          _MailRow(
            game: game,
            mail: m,
            selecting: _select,
            picked: _picked.contains(m.id),
            onPick: () => setState(() {
              if (!_picked.remove(m.id)) _picked.add(m.id);
            }),
          ),
        const SizedBox(height: 6),
        IconText(
          tr('mail.autoDelete', {'d': MailConfig.keepRead.inDays}),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: Colors.black45),
        ),
      ],
    );
  }
}

class _MailRow extends StatelessWidget {
  const _MailRow({
    required this.game,
    required this.mail,
    required this.selecting,
    required this.picked,
    required this.onPick,
  });
  final GameState game;
  final Mail mail;
  final bool selecting;
  final bool picked;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final isUpdate = mail.id.startsWith('update-');
    final isNotice =
        mail.kind == MailKind.notice &&
        mail.from == 'team' &&
        mail.id != 'welcome';
    return GestureDetector(
      onTap: selecting ? onPick : () => showMailDetail(context, game, mail),
      child: Opacity(
        opacity: mail.claimed ? 0.6 : 1,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: picked ? const Color(0xFFFFF1C9) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: picked ? const Color(0xFFF2B33D) : const Color(0xFFE5DCC8),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              if (selecting) ...[
                _PickBox(on: picked, enabled: onPick != null),
                const SizedBox(width: 8),
              ],
              ArtImage(_mailIcon(mail), size: 42),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isNotice)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: isUpdate
                                  ? const Color(0xFF5BAE6A)
                                  : const Color(0xFFE5793B),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              tr(
                                isUpdate ? 'mail.tagUpdate' : 'mail.tagNotice',
                              ),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        Flexible(
                          child: Text(
                            mailFrom(mail),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black45,
                            ),
                          ),
                        ),
                      ],
                    ),
                    IconText(
                      mailTitle(mail),
                      maxLines: 2,
                      style: const TextStyle(fontSize: 15),
                    ),
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
              if (!mail.claimed)
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE5533B),
                    shape: BoxShape.circle,
                  ),
                )
              else
                Text(
                  tr(mail.hasReward ? 'mail.claimed' : 'mail.read'),
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 선택 상자 (체크 표시).
class _PickBox extends StatelessWidget {
  const _PickBox({required this.on, required this.enabled});
  final bool on;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : 0.3,
    child: Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: on ? const Color(0xFF6CC58A) : const Color(0xFFFFFBF0),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFF7A5230), width: 2),
      ),
      child: on
          ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
          : null,
    ),
  );
}

/// 쪽지 상세: 보낸 이 · 날짜 · 제목 · 본문 · 보상 → 받기 / 확인.
Future<void> showMailDetail(BuildContext context, GameState game, Mail m) {
  final body = mailBody(m);
  final isUpdate = m.id.startsWith('update-');
  final isNotice =
      m.kind == MailKind.notice && m.from == 'team' && m.id != 'welcome';
  final d = m.at;
  final date =
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
  return showDialog<void>(
    context: context,
    builder: (ctx) => GameDialog(
      banner: isNotice ? 'gold' : 'green',
      title: IconText(
        isUpdate
            ? tr('mail.tagUpdate')
            : isNotice
            ? tr('mail.tagNotice')
            : tr('mail.letter'),
        textAlign: TextAlign.center,
      ),
      onClose: () {
        game.readMail(m.id);
        Navigator.pop(ctx);
      },
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 운영 쪽지는 큰 그림 (업데이트: 선물 상자 · 공지: 알림판), 나머지는 보낸 친구
          if (isNotice)
            Center(
              child: ArtImage(
                Art.frame(isUpdate ? 'mail_update' : 'mail_notice'),
                size: 132,
              ),
            ),
          Row(
            children: [
              if (!isNotice) ...[
                ArtImage(_mailIcon(m), size: 52),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: isNotice
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.start,
                  children: [
                    IconText(
                      mailTitle(m),
                      textAlign: isNotice ? TextAlign.center : TextAlign.start,
                      style: const TextStyle(fontSize: 18),
                    ),
                    Text(
                      '${mailFrom(m)} · $date',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (body != null) ...[
            const SizedBox(height: 8),
            _LetterPaper(body: body),
          ],
          if (m.hasReward) ...[
            const SizedBox(height: 10),
            IconText(
              rewardText(m.reward),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, color: Color(0xFF7A5A12)),
            ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          style: framedButton(
            FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              backgroundColor: Palette.primary,
              foregroundColor: Colors.white,
            ),
            'button_green',
          ),
          onPressed: () {
            Navigator.pop(ctx);
            if (m.hasReward && !m.claimed) {
              sfx(Sfx.coin);
              final r = game.claimMail(m.id);
              if (r != null && rewardText(r).isNotEmpty) {
                RewardPopup.show(context, r, title: tr('reward.mail'));
              }
            } else {
              sfx(Sfx.tap);
              game.readMail(m.id);
            }
          },
          child: IconText(
            tr(m.hasReward && !m.claimed ? 'mail.claim' : 'common.ok'),
            style: const TextStyle(fontSize: 18),
          ),
        ),
      ],
    ),
  );
}

/// 쪽지 본문: 단순한 둥근 상자. 넘치면 새싹 손잡이로 스크롤.
class _LetterPaper extends StatelessWidget {
  const _LetterPaper({required this.body});
  final String body;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxHeight: 260),
    padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFBF0),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE5DCC8), width: 1.5),
    ),
    child: SproutScrollbar(
      builder: (c) => SingleChildScrollView(
        controller: c,
        padding: const EdgeInsets.only(right: 18),
        child: IconText(
          body,
          style: const TextStyle(
            fontSize: 15,
            height: 1.5,
            color: Color(0xFF5C402C),
          ),
        ),
      ),
    ),
  );
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
  List<MenuEntry> Function() entries, {
  String? title,
}) => showGameSheet(
  context,
  listen,
  () => SheetFrame(
    title: title ?? tr('menu.title'),
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
              Analytics.instance.menuTap(e.icon);
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
                      {
                        final r = game.claimCheckIn();
                        if (r != null && rewardText(r).isNotEmpty) {
                          RewardPopup.show(
                            context,
                            r,
                            title: tr('reward.checkIn'),
                          );
                        }
                      }
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
      height: 96,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            tr('checkIn.day', {'n': day + 1}),
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B5638)),
          ),
          const SizedBox(height: 4),
          Opacity(
            opacity: claimed ? 0.45 : 1,
            // 보상은 한 줄로: 길면 칸 너비에 맞춰 줄인다 (칸 높이는 모두 같게)
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: IconText(
                rewardText(r),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ),
          if (claimed) ...[
            const SizedBox(height: 2),
            ArtImage(Art.icon('check'), size: 18),
          ],
        ],
      ),
    );
  }
}
