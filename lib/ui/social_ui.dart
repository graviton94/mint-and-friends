import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../art/art.dart';
import '../game/config.dart';
import '../game/game_state.dart';
import '../i18n/l10n.dart';
import '../i18n/names.dart';
import '../services/audio_service.dart';
import '../services/social_service.dart';
import 'garden/garden_scene.dart';
import 'meta_ui.dart' show rewardText;
import 'sheets.dart';
import 'theme.dart';
import 'widgets/frame_box.dart';
import 'widgets/icon_text.dart';

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

String socialErrorText(String code) =>
    tr('social.err.$code', {'max': SocialConfig.maxFriends});

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
    return Column(
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
        const SizedBox(height: 10),
        // 친구 추가
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
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: framedButton(
                FilledButton.styleFrom(minimumSize: const Size(64, 44)),
                'button_green',
              ),
              onPressed: social.busy ? null : _add,
              child: IconText(tr('social.add')),
            ),
          ],
        ),
        AnimatedSize(
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
                      color: _noteBad
                          ? const Color(0xFFB0640A)
                          : Palette.primary,
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: IconText(
                tr('social.list', {
                  'n': social.friends.length,
                  'max': SocialConfig.maxFriends,
                }),
                style: const TextStyle(fontSize: 18),
              ),
            ),
            if (social.loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 6),
          child: IconText(tr('social.giftHint'), style: _sub),
        ),
        if (social.friends.isEmpty)
          social.friendsLoaded
              ? _Message(
                  icon: Art.icon('gift'),
                  text: tr('social.empty'),
                  small: true,
                )
              : const _Loading()
        else
          for (final f in social.friends)
            _FriendRow(
              friend: f,
              sent: social.giftSentToday(f),
              sending: social.isSending(f),
              onGift: () => _gift(f),
              onVisit: () => showVisitSheet(context, social, game, f),
              onRemove: () => _remove(f),
            ),
      ],
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
            child: ArtImage(Art.friend(Friends.byId(me.avatar)), size: 56),
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
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          FriendCode.display(me.code),
                          style: const TextStyle(
                            fontSize: 20,
                            letterSpacing: 1.5,
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
    required this.sending,
    required this.onGift,
    required this.onVisit,
    required this.onRemove,
  });
  final SocialFriend friend;
  final bool sent;
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
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: _card(),
        child: Row(
          children: [
            ArtImage(Art.friend(Friends.byId(p.avatar)), size: 44),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16),
                  ),
                  IconText(
                    tr('social.levelArea', {
                      'n': p.level,
                      'area': areaName(Garden.areaAt(p.area)),
                    }),
                    maxLines: 1,
                    style: _sub,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 176),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  children: [
                    if (sent)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: IconText(
                          tr('social.giftDone'),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black45,
                          ),
                        ),
                      )
                    else
                      FilledButton(
                        style: framedButton(
                          FilledButton.styleFrom(
                            minimumSize: const Size(56, 38),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          'button_green',
                        ),
                        onPressed: sending ? null : onGift,
                        child: sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : IconText(tr('social.gift')),
                      ),
                    const SizedBox(width: 6),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(52, 38),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: onVisit,
                      child: IconText(tr('social.visit')),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
                  tr('social.levelArea', {
                    'n': p.level,
                    'area': areaName(Garden.areaAt(area)),
                  }),
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
        ],
      ),
    ),
  );
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
