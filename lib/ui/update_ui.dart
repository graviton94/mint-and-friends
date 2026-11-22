import 'package:material_ui/material_ui.dart';

import '../art/art.dart';
import '../game/config.dart';
import '../i18n/l10n.dart';
import '../services/audio_service.dart';
import '../services/update_service.dart';
import 'theme.dart';
import 'widgets/frame_box.dart';
import 'widgets/icon_text.dart';

/// 새 버전 알림 창 (D-049): 업데이트 → 게임하는 동안 뒤에서 받는다 · 나중에 → 하루 뒤 다시.
Future<void> showUpdatePrompt(BuildContext context) => showDialog<void>(
  context: context,
  builder: (ctx) => GameDialog(
    banner: 'gold',
    title: IconText(tr('update.title'), textAlign: TextAlign.center),
    onClose: () {
      UpdateService.instance.snooze();
      Navigator.pop(ctx);
    },
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ArtImage(
          Art.friendPose(Friends.byId('bori'), 'camera') ??
              Art.friend(Friends.byId('bori'), happy: true),
          size: 120,
        ),
        const SizedBox(height: 8),
        IconText(
          tr('update.body'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, color: Color(0xFF6B5A44)),
        ),
      ],
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
        onPressed: () {
          sfx(Sfx.tap);
          Navigator.pop(ctx);
          UpdateService.instance.start();
        },
        child: IconText(tr('update.go'), style: const TextStyle(fontSize: 19)),
      ),
    ],
  ),
);

/// 다 받았을 때: 지금 다시 열기 · 나중에 (나중에 열면 다음 실행 때 적용된다).
Future<void> showUpdateReady(BuildContext context) => showDialog<void>(
  context: context,
  builder: (ctx) => GameDialog(
    banner: 'gold',
    title: IconText(tr('update.readyTitle'), textAlign: TextAlign.center),
    onClose: () => Navigator.pop(ctx),
    content: IconText(
      tr('update.readyBody'),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 16, color: Color(0xFF6B5A44)),
    ),
    actions: [
      FilledButton(
        style: framedButton(
          FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
            backgroundColor: const Color(0xFFF2C14E),
            foregroundColor: const Color(0xFF5A3A08),
          ),
          'button_gold',
        ),
        onPressed: () {
          Navigator.pop(ctx);
          UpdateService.instance.complete();
        },
        child: IconText(
          tr('update.restart'),
          style: const TextStyle(fontSize: 19),
        ),
      ),
    ],
  ),
);

/// 화면 위쪽의 작은 업데이트 알약: 받는 중이면 진행률, 다 받았으면 '다시 열기'.
class UpdatePill extends StatelessWidget {
  const UpdatePill({super.key, required this.onReadyTap});
  final VoidCallback onReadyTap;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: UpdateService.instance,
    builder: (context, _) {
      final u = UpdateService.instance;
      final show =
          u.phase == UpdatePhase.downloading ||
          u.phase == UpdatePhase.downloaded;
      if (!show) return const SizedBox.shrink();
      final ready = u.phase == UpdatePhase.downloaded;
      return SafeArea(
        child: Align(
          alignment: const Alignment(0, 0.74),
          child: GestureDetector(
            onTap: ready ? onReadyTap : null,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 250,
                padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
                decoration: BoxDecoration(
                  color: ready ? const Color(0xFFFFF1C9) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF7A5230), width: 2),
                  boxShadow: const [
                    BoxShadow(color: Color(0x33000000), blurRadius: 8),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconText(
                      ready
                          ? tr('update.pillReady')
                          : tr('update.pill', {
                              'pct': (u.progress * 100).round(),
                            }),
                      style: const TextStyle(fontSize: 14),
                    ),
                    if (!ready) ...[
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: LinearProgressIndicator(
                          value: u.total > 0 ? u.progress : null,
                          minHeight: 7,
                          backgroundColor: const Color(0xFFEDE3CC),
                          color: Palette.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
