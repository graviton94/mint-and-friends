import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
        FilledButton(
          style: framedButton(
            FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              backgroundColor: Palette.primary,
              foregroundColor: Colors.white,
            ),
            'button_green',
          ),
          onPressed: () async {
            final bytes = await png;
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            await _share(context, game, kind, bytes);
          },
          child: IconText(
            game.shareRewardReady
                ? '${tr('share.button')}  [[energy]]+${Invite.shareEnergy}'
                : tr('share.button'),
            style: const TextStyle(fontSize: 19),
          ),
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
