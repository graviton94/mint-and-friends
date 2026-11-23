import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../art/art.dart';
import '../game/config.dart';
import '../game/game_state.dart';
import '../i18n/l10n.dart';
import '../i18n/names.dart';
import '../services/analytics_service.dart';
import '../services/audio_service.dart';
import '../services/social_service.dart';
import 'garden/garden_scene.dart';
import 'meta_ui.dart' show rewardText;
import 'share_card.dart';
import 'share_flow.dart';
import 'sheets.dart';
import 'theme.dart';
import 'widgets/frame_box.dart';
import 'widgets/icon_text.dart';
import 'widgets/top_toast.dart';

/// 친구 화면: 내 코드 · 닉네임, 코드로 친구 추가, 친구 목록 (선물 · 구경).
Future<void> showFriendsSheet(
  BuildContext context,
  SocialService social,
  GameState game,
) {
  sfx(Sfx.open);
  return showGameSheet(
    context,
    Listenable.merge([social, game]),
    () => Builder(
      builder: (context) => Padding(
        // 코드 입력 중 키보드가 시트를 가리지 않게
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SheetFrame(
          title: tr('social.title'),
          child: _FriendsBody(social: social, game: game),
        ),
      ),
    ),
  );
}

String socialErrorText(String code) => tr('social.err.$code', {
  'max': SocialConfig.maxFriends,
  'n': code == 'addLimit' ? SocialConfig.addsPerDay : SocialConfig.giftsPerDay,
});

const _sub = TextStyle(fontSize: 13, color: Color(0xFF5E6B5E));

BoxDecoration _card([Color color = Colors.white]) => BoxDecoration(
  color: color,
  borderRadius: BorderRadius.circular(14),
  border: Border.all(color: const Color(0xFFE5DCC8), width: 1.5),
);

class _FriendsBody extends StatefulWidget {
  const _FriendsBody({required this.social, required this.game});
  final SocialService social;
  final GameState game;

  @override
  State<_FriendsBody> createState() => _FriendsBodyState();
}

class _FriendsBodyState extends State<_FriendsBody> {
  final _code = TextEditingController();
  String? _note;
  bool _noteBad = false;
  Timer? _noteTimer;
  bool _starting = true;
  String? _startError;
  int _tab = 0; // 0 친구 목록 · 1 추가 · 초대

  SocialService get social => widget.social;
  GameState get game => widget.game;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _noteTimer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!social.canUse) {
      setState(() => _starting = false);
      return;
    }
    setState(() {
      _starting = true;
      _startError = null;
    });
    try {
      await social.ensureProfile(game);
      await social.loadFriends();
      final n = await social.pullInbox(game);
      if (n > 0) _show(tr('social.giftsArrived', {'n': n}));
    } on SocialException catch (e) {
      _startError = e.code;
    }
    if (mounted) setState(() => _starting = false);
  }

  void _show(String text, {bool bad = false}) {
    if (!mounted) return;
    _noteTimer?.cancel();
    setState(() {
      _note = text;
      _noteBad = bad;
    });
    _noteTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _note = null);
    });
  }

  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
    } on SocialException catch (e) {
      sfx(Sfx.error);
      _show(socialErrorText(e.code), bad: true);
    }
  }

  Future<void> _add() => _guard(() async {
    FocusScope.of(context).unfocus();
    // 막 시작한 계정이 친구 코드를 넣으면 초대로 쳐서 환영 선물 (D-045)
    if (game.canBeInvited) {
      final before = social.friends.length;
      if (await social.applyInvite(_code.text, game)) {
        _code.clear();
        sfx(Sfx.unlock);
        Analytics.instance.inviteApplied('manual');
        final name = social.friends.length > before
            ? social.friends.last.profile.name
            : '';
        _show(tr('invite.accepted', {'name': name, 'n': Invite.welcomeGems}));
        return;
      }
    }
    final f = await social.addFriendByCode(_code.text);
    _code.clear();
    sfx(Sfx.unlock);
    _show(tr('social.added', {'name': f.profile.name}));
  });

  Future<void> _gift(SocialFriend f) => _guard(() async {
    await social.sendGift(f, game);
    sfx(Sfx.coin);
    _show(tr('social.giftSent', {'name': f.profile.name}));
  });

  Future<void> _addRec(SocialProfile p) => _guard(() async {
    final f = await social.addRecommended(p);
    sfx(Sfx.unlock);
    _show(tr('social.added', {'name': f.profile.name}));
  });

  Future<void> _rename() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: social.me?.name ?? ''),
    );
    if (name == null) return;
    await _guard(() => social.rename(name));
  }

  void _cycleAvatar() {
    final me = social.me;
    if (me == null) return;
    final owned = [
      for (final f in Friends.all)
        if (game.friends.contains(f.id)) f.id,
    ];
    if (owned.length < 2) return;
    final i = owned.indexOf(me.avatar);
    sfx(Sfx.tap);
    _guard(() => social.setAvatar(owned[(i + 1) % owned.length]));
  }

  Future<void> _remove(SocialFriend f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => GameDialog(
        content: IconText(
          tr('social.removeConfirm', {'name': f.profile.name}),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: IconText(tr('common.cancel')),
          ),
          FilledButton(
            style: plainButton(
              FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: IconText(tr('social.removeYes')),
          ),
        ],
      ),
    );
    if (ok == true) await _guard(() => social.removeFriend(f.uid));
  }

  @override
  Widget build(BuildContext context) {
    if (!social.canUse) {
      return _Message(
        icon: Art.friend(Friends.byId(Friends.starter)),
        text: tr('social.needSignIn'),
      );
    }
    final me = social.me;
    if (me == null) {
      if (_starting) return const _Loading();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Message(
            icon: Art.friend(Friends.byId(Friends.starter)),
            text: socialErrorText(_startError ?? 'failed'),
          ),
          Center(
            child: FilledButton(
              style: framedButton(FilledButton.styleFrom(), 'button_green'),
              onPressed: _start,
              child: IconText(tr('social.retry')),
            ),
          ),
        ],
      );
    }
    final note = AnimatedSize(
      duration: const Duration(milliseconds: 180),
      child: _note == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 8),
              child: IconText(
                _note!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: _noteBad ? const Color(0xFFB0640A) : Palette.primary,
                ),
              ),
            ),
    );
    final left = social.giftsLeft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Tabs(
          index: _tab,
          labels: [
            tr('social.tabFriends', {
              'n': social.friends.length,
              'max': SocialConfig.maxFriends,
            }),
            tr('social.tabAdd'),
          ],
          dots: [false, game.canBeInvited],
          onTap: (i) {
            if (i == _tab) return;
            sfx(Sfx.tap);
            FocusScope.of(context).unfocus();
            setState(() => _tab = i);
            if (i == 1) social.loadRecommended();
          },
        ),
        _TabPanel(
          child: _tab == 0
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 오늘 선물 · 모두 선물
                    Row(
                      children: [
                        ArtImage(Art.icon('gift'), size: 30),
                        const SizedBox(width: 6),
                        Expanded(
                          child: IconText(
                            social.friends.isEmpty
                                ? tr('social.giftHint')
                                : left > 0
                                ? tr('social.giftLeft', {
                                    'n': left,
                                    'max': SocialConfig.giftsPerDay,
                                    'e': SocialConfig.giftEnergy,
                                  })
                                : tr('social.giftAllSent', {
                                    'max': SocialConfig.giftsPerDay,
                                  }),
                            style: _sub,
                          ),
                        ),
                        if (social.loading)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                      ],
                    ),
                    note,
                    const _VineDivider(),
                    if (social.friends.isEmpty)
                      social.friendsLoaded
                          ? Column(
                              children: [
                                _Message(
                                  icon: Art.friend(Friends.byId('bori')),
                                  text: tr('social.empty'),
                                  small: true,
                                ),
                                FilledButton(
                                  style: framedButton(
                                    FilledButton.styleFrom(
                                      minimumSize: const Size(180, 46),
                                    ),
                                    'button_green',
                                  ),
                                  onPressed: () {
                                    setState(() => _tab = 1);
                                    social.loadRecommended();
                                  },
                                  child: IconText(tr('social.goAdd')),
                                ),
                                const SizedBox(height: 8),
                              ],
                            )
                          : const _Loading()
                    else
                      for (final f in _sorted())
                        _FriendRow(
                          friend: f,
                          sent: social.giftSentToday(f),
                          outOfGifts: left <= 0,
                          sending: social.isSending(f),
                          onGift: () => _gift(f),
                          onVisit: () =>
                              showVisitSheet(context, social, game, f),
                          onRemove: () => _remove(f),
                        ),
                    if (social.friends.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: IconText(
                          tr('social.removeHint'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black38,
                          ),
                        ),
                      ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MyCard(
                      me: me,
                      onCopy: () {
                        Clipboard.setData(ClipboardData(text: me.code));
                        sfx(Sfx.tap);
                        _show(tr('social.copied'));
                      },
                      onRename: _rename,
                      onAvatar: _cycleAvatar,
                    ),
                    const _VineDivider(),
                    IconText(
                      tr('social.addTitle'),
                      style: const TextStyle(fontSize: 17),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _code,
                            textCapitalization: TextCapitalization.characters,
                            maxLength: 9,
                            onSubmitted: (_) => _add(),
                            decoration: InputDecoration(
                              counterText: '',
                              isDense: true,
                              filled: true,
                              fillColor: Colors.white,
                              hintText: tr('social.codeHint'),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD9C9A8),
                                  width: 1.5,
                                ),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: framedButton(
                            FilledButton.styleFrom(
                              minimumSize: const Size(64, 44),
                            ),
                            'button_green',
                          ),
                          onPressed: social.busy ? null : _add,
                          child: IconText(tr('social.add')),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: IconText(
                        tr('social.addLeft', {
                          'n': social.addsLeft,
                          'max': SocialConfig.addsPerDay,
                        }),
                        style: _sub,
                      ),
                    ),
                    note,
                    const _VineDivider(),
                    IconText(
                      tr('social.recTitle'),
                      style: const TextStyle(fontSize: 17),
                    ),
                    IconText(tr('social.recNote'), style: _sub),
                    const SizedBox(height: 6),
                    if (social.recommended.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: IconText(
                          tr('social.recEmpty'),
                          textAlign: TextAlign.center,
                          style: _sub,
                        ),
                      )
                    else
                      for (final r in social.recommended)
                        _RecRow(
                          profile: r,
                          enabled: !social.busy && social.addsLeft > 0,
                          onAdd: () => _addRec(r),
                        ),
                    const _VineDivider(),
                    _InviteCard(
                      social: social,
                      game: game,
                      onInvite: () =>
                          showShareDialog(context, game, ShareKind.garden),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  /// 아직 선물 안 보낸 친구 먼저, 그다음 레벨 높은 순.
  List<SocialFriend> _sorted() {
    final l = [...social.friends];
    l.sort((a, b) {
      final sa = social.giftSentToday(a) ? 1 : 0;
      final sb = social.giftSentToday(b) ? 1 : 0;
      if (sa != sb) return sa - sb;
      return b.profile.level - a.profile.level;
    });
    return l;
  }
}

/// 잎 탭 두 개 (tab_body · tab_sprout · tab_idle). 고른 탭은 초록 + 새싹, 아래 판과 이어진다.
class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.index,
    required this.labels,
    required this.onTap,
    this.dots = const [],
  });
  final int index;
  final List<String> labels;
  final List<bool> dots;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: _Tab(
                  label: labels[i],
                  on: i == index,
                  dot: i < dots.length && dots[i],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.on, this.dot = false});
  final String label;
  final bool on;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final body = Art.frame(on ? 'tab_body' : 'tab_idle');
    final h = on ? 46.0 : 38.0;
    // 원본 → 화면 배율: 탭 몸통 높이 기준
    final k = h / (on ? 162 : 136);
    final text = IconText(
      label,
      maxLines: 1,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: on ? 17 : 15,
        color: on ? Colors.white : const Color(0xFF7A6A58),
        shadows: on
            ? const [Shadow(color: Color(0x88316B1C), offset: Offset(0, 1.5))]
            : null,
      ),
    );
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        SizedBox(
          height: h,
          child: body.available
              ? LayoutBuilder(
                  builder: (context, b) => FittedBox(
                    fit: BoxFit.fill,
                    child: Image.asset(
                      body.path,
                      width: (b.maxWidth / k).clamp(
                        on ? 260 : 200,
                        double.infinity,
                      ),
                      height: on ? 162 : 136,
                      centerSlice: on
                          ? const Rect.fromLTRB(70, 70, 190, 130)
                          : const Rect.fromLTRB(50, 50, 150, 100),
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                )
              : Container(
                  decoration: BoxDecoration(
                    color: on ? Palette.primary : const Color(0xFFF0E2D2),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                ),
        ),
        Positioned(
          left: 6,
          right: 6,
          bottom: on ? 10 : 8,
          child: FittedBox(fit: BoxFit.scaleDown, child: text),
        ),
        if (on && Art.frame('tab_sprout').available)
          Positioned(
            bottom: h - 12 * k,
            child: Image.asset(
              Art.frame('tab_sprout').path,
              width: 112 * k,
              height: 60 * k,
            ),
          ),
        if (dot)
          Positioned(
            top: on ? 4 : 18,
            right: 14,
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Color(0xFFE5533B),
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

/// 탭 아래 판: 크림색 카드, 위 테두리는 고른 탭과 이어지는 초록 줄.
class _TabPanel extends StatelessWidget {
  const _TabPanel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        height: 4,
        decoration: BoxDecoration(
          color: const Color(0xFF6DBB3A),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBF0),
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(18),
          ),
          border: Border.all(color: const Color(0xFFE5DCC8), width: 1.5),
        ),
        child: child,
      ),
    ],
  );
}

/// 덩굴 구분선 (divider).
class _VineDivider extends StatelessWidget {
  const _VineDivider();
  @override
  Widget build(BuildContext context) {
    final d = Art.frame('divider');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: d.available
          ? Image.asset(d.path, height: 22, fit: BoxFit.contain)
          : const Divider(),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(24),
    child: Center(child: CircularProgressIndicator()),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.small = false});
  final ArtRef icon;
  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: small ? 10 : 20, horizontal: 8),
    child: Column(
      children: [
        ArtImage(icon, size: small ? 48 : 72),
        const SizedBox(height: 10),
        IconText(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: small ? 15 : 17),
        ),
      ],
    ),
  );
}

class _MyCard extends StatelessWidget {
  const _MyCard({
    required this.me,
    required this.onCopy,
    required this.onRename,
    required this.onAvatar,
  });
  final SocialProfile me;
  final VoidCallback onCopy;
  final VoidCallback onRename;
  final VoidCallback onAvatar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: _card(const Color(0xFFF3FAEF)),
      child: Row(
        children: [
          GestureDetector(
            onTap: onAvatar,
            child: _Avatar(id: safeAvatar(me.avatar), size: 60),
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
                        me.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(6),
                      tooltip: tr('social.rename'),
                      icon: Art.icon('edit').available
                          ? ArtImage(Art.icon('edit'), size: 22)
                          : const Icon(Icons.edit_rounded, size: 18),
                      onPressed: onRename,
                    ),
                  ],
                ),
                IconText(tr('social.myCode'), style: _sub),
                Row(
                  children: [
                    Flexible(
                      child: _Plaque(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            FriendCode.display(me.code),
                            style: const TextStyle(
                              fontSize: 19,
                              letterSpacing: 1.5,
                              color: Color(0xFF5C402C),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: FilledButton(
                          style: framedButton(
                            FilledButton.styleFrom(
                              minimumSize: const Size(56, 34),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                            ),
                            'button_green',
                          ),
                          onPressed: onCopy,
                          child: IconText(tr('social.copy')),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.friend,
    required this.sent,
    this.outOfGifts = false,
    required this.sending,
    required this.onGift,
    required this.onVisit,
    required this.onRemove,
  });
  final SocialFriend friend;
  final bool sent;
  final bool outOfGifts;
  final bool sending;
  final VoidCallback onGift;
  final VoidCallback onVisit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = friend.profile;
    return GestureDetector(
      onLongPress: onRemove,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
        decoration: _card(sent ? const Color(0xFFFAF6EC) : Colors.white),
        child: Row(
          children: [
            _Avatar(id: safeAvatar(p.avatar), size: 50),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _LevelChip(level: p.level),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          p.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  IconText(
                    areaName(Garden.areaAt(p.area)),
                    maxLines: 1,
                    style: _sub,
                  ),
                  if (p.score > 0)
                    IconText(
                      tr('social.scoreLine', {
                        'score': (p.score / 10).toStringAsFixed(1),
                      }),
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9A7A3A),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _RoundButton(
              icon: Art.icon('visit'),
              label: tr('social.visitShort'),
              color: const Color(0xFFFFF1C9),
              onTap: onVisit,
            ),
            const SizedBox(width: 6),
            sent
                ? _RoundButton(
                    icon: Art.icon('check'),
                    label: tr('social.sentShort'),
                    color: const Color(0xFFEDE6D6),
                  )
                : outOfGifts
                ? _RoundButton(
                    icon: Art.icon('gift'),
                    label: tr('social.tomorrow'),
                    color: const Color(0xFFEDE6D6),
                  )
                : _RoundButton(
                    icon: Art.icon('gift'),
                    label: tr('social.giftShort'),
                    color: const Color(0xFFD8F0C4),
                    busy: sending,
                    onTap: onGift,
                  ),
          ],
        ),
      ),
    );
  }
}

/// 추천 친구 한 줄: 얼굴 · Lv · 이름 · 구역 · 추가.
class _RecRow extends StatelessWidget {
  const _RecRow({
    required this.profile,
    required this.enabled,
    required this.onAdd,
  });
  final SocialProfile profile;
  final bool enabled;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
    decoration: _card(),
    child: Row(
      children: [
        _Avatar(id: safeAvatar(profile.avatar), size: 42),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _LevelChip(level: profile.level),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      profile.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ],
              ),
              IconText(
                areaName(Garden.areaAt(profile.area)),
                maxLines: 1,
                style: _sub,
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        FilledButton(
          style: framedButton(
            FilledButton.styleFrom(
              minimumSize: const Size(60, 38),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            'button_green',
          ),
          onPressed: enabled ? onAdd : null,
          child: IconText(tr('social.add')),
        ),
      ],
    ),
  );
}

/// 친구 얼굴: 민트 동그라미 위에.
/// 나무 이름판 (title_plaque): 꽃 장식 · 테두리는 그대로, 가운데만 늘린다.
class _Plaque extends StatelessWidget {
  const _Plaque({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final img = Art.frame('title_plaque');
    const h = 48.0, k = h / 189;
    return SizedBox(
      height: h,
      child: Stack(
        children: [
          if (img.available)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, b) => FittedBox(
                  fit: BoxFit.fill,
                  child: Image.asset(
                    img.path,
                    width: (b.maxWidth / k).clamp(450, double.infinity),
                    height: 189,
                    centerSlice: const Rect.fromLTRB(110, 60, 340, 130),
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 8),
            child: Center(child: child),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.id, required this.size});
  final String id;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFFE3F4DA),
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0xFFB9DDA4), width: 2),
    ),
    alignment: Alignment.center,
    child: ArtImage(Art.friend(Friends.byId(id)), size: size * 0.86),
  );
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.level});
  final int level;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
    decoration: BoxDecoration(
      color: const Color(0xFF6DBB3A),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: const Color(0xFF4E8A2A), width: 1.2),
    ),
    child: Text(
      'Lv.$level',
      style: const TextStyle(fontSize: 12, color: Colors.white, height: 1.2),
    ),
  );
}

/// 동그란 아이콘 버튼 + 아래 작은 글자 (구경 · 선물 · 보냄).
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.busy = false,
  });
  final ArtRef icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: busy ? null : onTap,
    child: SizedBox(
      width: 52,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF7A5230), width: 2),
              boxShadow: onTap == null
                  ? null
                  : const [
                      BoxShadow(color: Color(0x33000000), offset: Offset(0, 2)),
                    ],
            ),
            alignment: Alignment.center,
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Opacity(
                    opacity: onTap == null ? 0.6 : 1,
                    child: ArtImage(icon, size: 28),
                  ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: onTap == null ? Colors.black38 : const Color(0xFF5C402C),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------- 친구 정원 구경

/// 친구의 공개 프로필로 만든 읽기 전용 정원 (누를 수 없음) + 하루 한 번 답례.
Future<void> showVisitSheet(
  BuildContext context,
  SocialService social,
  GameState game,
  SocialFriend friend,
) {
  sfx(Sfx.open);
  final p = friend.profile;
  final visit = p.toVisitGame(); // 시트가 열려 있는 동안만 쓰는 일회용
  final area = p.showcaseArea;
  return showGameSheet(
    context,
    social,
    () => SheetFrame(
      title: tr('social.visitTitle', {'name': p.name}),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ArtImage(Art.friend(Friends.byId(p.avatar)), size: 36),
              const SizedBox(width: 8),
              Flexible(
                child: IconText(
                  tr(
                    p.score > 0 ? 'social.levelAreaScore' : 'social.levelArea',
                    {
                      'n': p.level,
                      'area': areaName(Garden.areaAt(area)),
                      'score': (p.score / 10).toStringAsFixed(1),
                    },
                  ),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: GardenScene.aspect,
            child: IgnorePointer(
              child: GardenScene(
                game: visit,
                area: area,
                radius: 16,
                showEmptySlots: false,
                onSlotTap: (_) {},
                onVisitorTap: () {},
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (social.visitThanksReady)
            Center(
              child: FilledButton(
                style: framedButton(
                  FilledButton.styleFrom(minimumSize: const Size(160, 46)),
                  'button_green',
                ),
                onPressed: () {
                  final r = social.claimVisitThanks(game, p.name);
                  if (r != null) sfx(Sfx.coin);
                },
                child: IconText(
                  tr('social.visitThanks', {
                    'r': rewardText(SocialConfig.visitThanks),
                  }),
                ),
              ),
            )
          else
            IconText(
              tr('social.visitThanked'),
              textAlign: TextAlign.center,
              style: _sub,
            ),
          const SizedBox(height: 4),
          // 신고: 정원 이름이 불쾌하거나 괴롭힘 · 사칭이면 (Play 사용자 제작 콘텐츠 정책)
          Center(
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.black45),
              onPressed: () => _report(context, social, friend),
              child: IconText(
                tr('social.report'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _report(
  BuildContext context,
  SocialService social,
  SocialFriend friend,
) async {
  final pick = await showDialog<(String, bool)>(
    context: context,
    builder: (_) => _ReportDialog(name: friend.profile.name),
  );
  if (pick == null || !context.mounted) return;
  try {
    await social.reportFriend(friend, pick.$1, alsoRemove: pick.$2);
    if (!context.mounted) return;
    TopToast.show(context, tr('social.reportDone'));
    if (pick.$2) Navigator.of(context).maybePop();
  } catch (_) {
    if (context.mounted) TopToast.show(context, tr('social.reportFail'));
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.name});
  final String name;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  String _reason = SocialService.reportReasons.first;
  bool _remove = true;

  @override
  Widget build(BuildContext context) {
    return GameDialog(
      title: IconText(tr('social.report'), textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IconText(
            tr('social.reportAbout', {'name': widget.name}),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 6),
          RadioGroup<String>(
            groupValue: _reason,
            onChanged: (v) => setState(() => _reason = v ?? _reason),
            child: Column(
              children: [
                for (final r in SocialService.reportReasons)
                  RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: r,
                    title: IconText(tr('social.reportReason.$r')),
                  ),
              ],
            ),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _remove,
            onChanged: (v) => setState(() => _remove = v ?? true),
            title: IconText(tr('social.reportRemove')),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: IconText(tr('common.cancel')),
        ),
        FilledButton(
          style: plainButton(
            FilledButton.styleFrom(backgroundColor: Colors.redAccent),
          ),
          onPressed: () => Navigator.pop(context, (_reason, _remove)),
          child: IconText(tr('social.reportSend')),
        ),
      ],
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});
  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _ok() {
    final name = cleanName(_c.text);
    if (name.isEmpty) return;
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return GameDialog(
      title: IconText(tr('social.rename'), textAlign: TextAlign.center),
      content: TextField(
        controller: _c,
        autofocus: true,
        maxLength: SocialConfig.nameMax,
        onSubmitted: (_) => _ok(),
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: IconText(tr('common.cancel')),
        ),
        FilledButton(
          style: framedButton(FilledButton.styleFrom(), 'button_green'),
          onPressed: _ok,
          child: IconText(tr('common.ok')),
        ),
      ],
    );
  }
}

/// 친구 초대 칸 (D-045): 초대하기 버튼 + 받은 보상 n/5 + 초대한 친구들의 진행 (Lv · 접속한 날 · 남은 날).
class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.social,
    required this.game,
    required this.onInvite,
  });
  final SocialService social;
  final GameState game;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2C48E), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ArtImage(Art.icon('invite'), size: 52),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconText(
                      tr('invite.title'),
                      style: const TextStyle(fontSize: 17),
                    ),
                    IconText(
                      tr('invite.note', {
                        'gems': Invite.rewardGems,
                        'welcome': Invite.welcomeGems,
                        'done': game.inviteRewarded.length,
                        'max': Invite.maxRewards,
                      }),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF7A6248),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: FilledButton(
                    style: framedButton(
                      FilledButton.styleFrom(minimumSize: const Size(72, 44)),
                      'button_green',
                    ),
                    onPressed: onInvite,
                    child: IconText(tr('invite.button')),
                  ),
                ),
              ),
            ],
          ),
          for (final f in social.invitees)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  ArtImage(
                    Art.friend(Friends.byId(safeAvatar(f.profile.avatar))),
                    size: 30,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      f.profile.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                  IconText(
                    game.inviteRewarded.contains(f.uid)
                        ? tr('invite.rewarded')
                        : tr('invite.progress', {
                            'lv': f.profile.level,
                            'needLv': Invite.needLevel,
                            'days': f.profile.days,
                            'needDays': Invite.needDays,
                            'left': f.profile.inviteDaysLeft(now),
                          }),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF7A6248),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
