import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:material_ui/material_ui.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../art/art.dart';
import '../game/config.dart';
import '../game/game_state.dart';
import '../i18n/l10n.dart';
import '../services/analytics_service.dart';
import '../services/audio_service.dart';
import 'share_card.dart';
import 'theme.dart';
import 'widgets/frame_box.dart';
import 'widgets/icon_text.dart';
import 'widgets/top_toast.dart';

/// 공유에 쓰는 내 정보 (친구 기능이 있으면 main 이 채운다).
class ShareInfo {
  static String? Function() code = () => null;
  static String? Function() name = () => null;
}

/// 자랑 카드 미리보기 + '자랑하기' (휴대폰 공유창). 하루 한 번 에너지.
Future<void> showShareDialog(
  BuildContext context,
  GameState game,
  ShareKind kind, {
  int? area,
  Chain? chain,
  int seeds = 0,
}) async {
  Analytics.instance.shareOpen(kind.name);
  final png = ShareCard.render(
    kind: kind,
    game: game,
    area: area,
    chain: chain,
    seeds: seeds,
    code: ShareInfo.code(),
    name: ShareInfo.name(),
  );
  var busy = false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => GameDialog(
      title: IconText(tr('share.dialogTitle'), textAlign: TextAlign.center),
      onClose: () => Navigator.pop(ctx),
      content: FutureBuilder<Uint8List>(
        future: png,
        builder: (_, snap) => AspectRatio(
          aspectRatio: ShareCard.w / ShareCard.h,
          child: snap.hasData
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(snap.data!, fit: BoxFit.contain),
                )
              : const Center(child: CircularProgressIndicator()),
        ),
      ),
      actions: [
        // 그림이 준비되기 전에는 누를 수 없고, 한 번만 눌린다
        // (두 번 누르면 아래 화면까지 닫히고 두 번 공유됐다)
        FutureBuilder<Uint8List>(
          future: png,
          builder: (_, snap) => FilledButton(
            style: framedButton(
              FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                backgroundColor: Palette.primary,
                foregroundColor: Colors.white,
              ),
              'button_green',
            ),
            onPressed: !snap.hasData
                ? null
                : () async {
                    if (busy || !ctx.mounted) return;
                    busy = true;
                    Navigator.pop(ctx);
                    await _share(context, game, kind, snap.data!);
                  },
            child: IconText(
              game.shareRewardReady
                  ? '${tr('share.button')}  [[energy]]+${Invite.shareEnergy}'
                  : tr('share.button'),
              style: const TextStyle(fontSize: 19),
            ),
          ),
        ),
        // 그림 없이 초대 글과 링크만 (메신저에서 링크가 바로 눌리게)
        TextButton(
          onPressed: () async {
            if (busy || !ctx.mounted) return;
            busy = true;
            Navigator.pop(ctx);
            await _shareText(context, game, kind);
          },
          child: IconText(tr('share.linkOnly')),
        ),
      ],
    ),
  );
}

Future<void> _share(
  BuildContext context,
  GameState game,
  ShareKind kind,
  Uint8List png,
) async {
  sfx(Sfx.tap);
  final code = ShareInfo.code();
  final text = tr(
    code == null || code.isEmpty ? 'share.textNoCode' : 'share.text',
    {'code': code ?? '', 'link': Invite.link(code)},
  );
  // 카카오톡 등은 그림을 붙이면 글을 버린다: 초대 글 · 링크를 미리 복사해 두고 알려 준다 (D-083)
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) TopToast.show(context, tr('share.copied'));
  try {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/mint_and_friends_${kind.name}.png');
    await f.writeAsBytes(png, flush: true);
    final r = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(f.path, mimeType: 'image/png')],
        text: text,
      ),
    );
    // 닫기만 하면 보상 없음. 보냈거나 (기기가 결과를 알려 주지 않는 경우 포함) 이면 하루 한 번 에너지.
    if (r.status == ShareResultStatus.dismissed) return;
    Analytics.instance.shareDone(kind.name, r.raw);
    final got = game.claimShareReward();
    if (got > 0 && context.mounted) {
      sfx(Sfx.coin);
      TopToast.show(context, tr('share.reward', {'n': got}));
    }
  } catch (e) {
    // 그림 첨부 공유가 안 되는 기기: 글과 링크만이라도 보낸다 (원인은 분석 · 화면에 남긴다)
    final why = '$e';
    debugPrint('share failed: $why');
    Analytics.instance.log('share_error', {
      'kind': kind.name,
      'why': why.length > 90 ? why.substring(0, 90) : why,
    });
    try {
      final r = await SharePlus.instance.share(ShareParams(text: text));
      if (r.status == ShareResultStatus.dismissed) return;
      Analytics.instance.shareDone(kind.name, 'text');
      final got = game.claimShareReward();
      if (got > 0 && context.mounted) {
        sfx(Sfx.coin);
        TopToast.show(context, tr('share.reward', {'n': got}));
      }
    } catch (e2) {
      if (context.mounted) {
        TopToast.show(
          context,
          '${tr('share.failed')}\n${'$e2'.length > 80 ? '$e2'.substring(0, 80) : e2}',
        );
      }
    }
  }
}

/// 정원 화면 등에 붙이는 작은 '자랑하기' 버튼 (카메라 아이콘).
class ShareButton extends StatelessWidget {
  const ShareButton({super.key, required this.onTap, this.size = 44});
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Semantics(
      button: true,
      label: tr('share.button'),
      child: ArtImage(Art.icon('share'), size: size),
    ),
  );
}

/// 진단용 (빌드 옵션 SHARE_PROBE): 화면 없이 자랑 카드를 그려 공유를 단계별로 실행하고 결과를 로그에 남긴다.
/// 에뮬레이터 워크플로(share-probe.yml)가 'SHAREPROBE' 줄을 모아 보여 준다.
Future<void> runShareProbe(GameState game) async {
  void log(String s) => print('SHAREPROBE $s'); // ignore: avoid_print
  try {
    // 같은 원인(JNI 플러그인)을 쓰는 저장 · 소리 캐시도 함께 확인
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('probe', 'ok');
      log('prefs ${prefs.getString('probe')}');
    } catch (e) {
      log('prefs ERROR $e');
    }
    try {
      final u = await AudioCache.instance.load('audio/bgm_garden.ogg');
      log('audio cache ok ${u.path.split('/').last}');
    } catch (e) {
      log('audio cache ERROR $e');
    }
    log('render start');
    final png = await ShareCard.render(kind: ShareKind.garden, game: game);
    log('render ok ${png.length} bytes');
    final dir = await getTemporaryDirectory();
    log('temp ${dir.path}');
    final f = File('${dir.path}/mint_and_friends_probe.png');
    await f.writeAsBytes(png, flush: true);
    log('file ok ${await f.length()}');
    try {
      final r = await SharePlus.instance
          .share(
            ShareParams(
              files: [XFile(f.path, mimeType: 'image/png')],
              text: 'probe text',
            ),
          )
          .timeout(const Duration(seconds: 6));
      log('share files result ${r.status} ${r.raw}');
    } catch (e, st) {
      log('share files ERROR $e');
      log('stack ${st.toString().split('\n').take(6).join(' | ')}');
    }
    try {
      final r = await SharePlus.instance
          .share(ShareParams(text: 'probe text only'))
          .timeout(const Duration(seconds: 6));
      log('share text result ${r.status} ${r.raw}');
    } catch (e) {
      log('share text ERROR $e');
    }
  } catch (e, st) {
    log('probe ERROR $e');
    log('stack ${st.toString().split('\n').take(6).join(' | ')}');
  }
  log('done');
}

/// 글과 링크만 공유 (그림 없이).
Future<void> _shareText(
  BuildContext context,
  GameState game,
  ShareKind kind,
) async {
  sfx(Sfx.tap);
  final code = ShareInfo.code();
  final text = tr(
    code == null || code.isEmpty ? 'share.textNoCode' : 'share.text',
    {'code': code ?? '', 'link': Invite.link(code)},
  );
  try {
    final r = await SharePlus.instance.share(ShareParams(text: text));
    if (r.status == ShareResultStatus.dismissed) return;
    Analytics.instance.shareDone(kind.name, 'text');
    final got = game.claimShareReward();
    if (got > 0 && context.mounted) {
      sfx(Sfx.coin);
      TopToast.show(context, tr('share.reward', {'n': got}));
    }
  } catch (_) {
    if (context.mounted) TopToast.show(context, tr('share.failed'));
  }
}
