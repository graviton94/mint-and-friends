import 'package:material_ui/material_ui.dart';

import '../art/art.dart';
import '../game/config.dart';
import '../game/event_pass.dart';
import '../game/game_state.dart';
import '../i18n/names.dart';
import '../i18n/l10n.dart';
import '../services/audio_service.dart';
import 'sheets.dart';
import 'widgets/frame_box.dart';
import 'widgets/icon_text.dart';
import 'widgets/prose_text.dart';

/// 정원사의 일기 (D-119): 구역을 완성할 때마다 한 장씩 찾는 이야기.

ArtRef get _diaryIcon =>
    Art.icon('diary').available ? Art.icon('diary') : Art.icon('book');

/// 종이 한 장: 제목 · 본문 · (마지막 장) 서명.
class DiaryPaper extends StatelessWidget {
  const DiaryPaper({super.key, required this.page});
  final int page;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF8E6),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFD9BE8F), width: 2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x22000000),
          blurRadius: 6,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IconText(
          tr('diary.p$page.t'),
          style: const TextStyle(fontSize: 18, color: Color(0xFF5A3A22)),
        ),
        const SizedBox(height: 8),
        ProseText(
          tr('diary.p$page'),
          style: const TextStyle(
            fontSize: 15,
            height: 1.6,
            color: Color(0xFF5E4A36),
          ),
        ),
        if (page == GameState.diaryPages - 1) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              tr('diary.sign'),
              style: const TextStyle(fontSize: 14, color: Color(0xFF8A6A48)),
            ),
          ),
        ],
      ],
    ),
  );
}

/// 찾은(또는 다시 읽는) 페이지 창.
Future<void> showDiaryPage(
  BuildContext context,
  int page, {
  bool found = false,
}) {
  if (found) sfx(Sfx.unlock);
  return showDialog<void>(
    context: context,
    builder: (ctx) => GameDialog(
      banner: 'gold',
      title: IconText(
        found ? tr('diary.found') : tr('diary.title'),
        textAlign: TextAlign.center,
      ),
      onClose: () => Navigator.pop(ctx),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ArtImage(_diaryIcon, size: 64),
          const SizedBox(height: 8),
          DiaryPaper(page: page),
          if (found) ...[
            const SizedBox(height: 10),
            IconText(
              '${tr('diary.reward')}  [[energy]] +${GameState.diaryReward(page).energy}'
              '${GameState.diaryReward(page).gems > 0 ? '  [[diamond]] +${GameState.diaryReward(page).gems}' : ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Color(0xFF5A3A22)),
            ),
          ],
        ],
      ),
    ),
  );
}

/// 일기장: 찾은 페이지는 제목 · 누르면 읽기, 못 찾은 페이지는 잠김.
Future<void> showDiarySheet(BuildContext context, GameState game) =>
    showGameSheet(
      context,
      game,
      () => SheetFrame(
        title: tr('diary.title'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(
                tr('diary.count', {
                  'n': game.diaryFound.length,
                  'all': GameState.diaryPages,
                }),
                style: const TextStyle(fontSize: 15, color: Color(0xFF8A7660)),
              ),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < GameState.diaryPages; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: game.diaryFound.contains(i)
                      ? () => showDiaryPage(context, i)
                      : null,
                  child: Container(
                    height: 58,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: game.diaryFound.contains(i)
                          ? const Color(0xFFFFF8E6)
                          : const Color(0xFFF1EBDD),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFD9BE8F),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${i + 1}',
                          style: const TextStyle(
                            fontSize: 18,
                            color: Color(0xFFB08A5E),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            game.diaryFound.contains(i)
                                ? tr('diary.p$i.t')
                                : tr('diary.locked'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              color: game.diaryFound.contains(i)
                                  ? const Color(0xFF5A3A22)
                                  : const Color(0xFFB0A28C),
                            ),
                          ),
                        ),
                        ArtImage(
                          game.diaryFound.contains(i)
                              ? Art.icon('letter')
                              : Art.lock,
                          size: 26,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

/// 이야기 한 장면 창: 친구 그림 + 말풍선처럼 한두 줄 + 버튼 (첫 만남 · 에피소드 · 이벤트 이야기 공용).
Future<void> showStoryScene(
  BuildContext context, {
  required String title,
  required ArtRef art,
  required String text,
  String? button,
  String? reward,
  Widget? extra,
}) => showDialog<void>(
  context: context,
  builder: (ctx) => GameDialog(
    banner: 'gold',
    title: IconText(title, textAlign: TextAlign.center),
    onClose: () => Navigator.pop(ctx),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ArtImage(art, size: 110),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD9BE8F), width: 2),
          ),
          child: ProseText(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              height: 1.55,
              color: Color(0xFF5E4A36),
            ),
          ),
        ),
        ?extra,
        if (reward != null) ...[
          const SizedBox(height: 10),
          IconText(
            reward,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Color(0xFF5A3A22)),
          ),
        ],
      ],
    ),
    actionsAlignment: MainAxisAlignment.center,
    actions: [
      if (button != null)
        FilledButton(
          style: framedButton(
            FilledButton.styleFrom(minimumSize: const Size(160, 48)),
            'button_green',
          ),
          onPressed: () => Navigator.pop(ctx),
          child: IconText(button, style: const TextStyle(fontSize: 17)),
        ),
    ],
  ),
);

/// 첫 만남 (D-122): 튜토리얼이 끝나면 민트가 찢어진 일기 조각을 보여 준다.
Future<void> showStoryIntro(BuildContext context, GameState game) {
  game.storyIntroSeen = true;
  sfx(Sfx.unlock);
  return showStoryScene(
    context,
    title: tr('diary.intro.t'),
    art: Art.friend(Friends.byId('bori'), happy: true),
    text: tr('diary.intro'),
    button: tr('diary.intro.go'),
    extra: Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ArtImage(
            Art.icon('diary_page').available
                ? Art.icon('diary_page')
                : Art.icon('letter'),
            size: 28,
          ),
          const SizedBox(width: 6),
          Text(
            tr('diary.count', {
              'n': game.diaryFound.length,
              'all': GameState.diaryPages,
            }),
            style: const TextStyle(fontSize: 15, color: Color(0xFF8A7660)),
          ),
        ],
      ),
    ),
  );
}

/// 친구 에피소드 시작 · 완성 창 (중간 단계는 위 알림으로).
Future<void> showEpisodeScene(
  BuildContext context,
  String friendId,
  int step, {
  bool done = false,
}) {
  sfx(done ? Sfx.levelup : Sfx.unlock);
  return showStoryScene(
    context,
    title: done
        ? tr('ep.done')
        : tr('ep.title', {'name': friendName(friendId)}),
    art: Art.friend(Friends.byId(friendId), happy: done),
    text: tr('ep.$friendId.${done ? 3 : 0}'),
    button: tr('common.ok'),
    reward: done
        ? '[[energy]] +${GameState.episodeReward.energy}'
        : tr('ep.hint', {'name': friendName(friendId)}),
  );
}

/// 월간 이벤트 이야기 (시작 · 10칸 · 20칸).
Future<void> showEventStory(
  BuildContext context,
  GameState game,
  EventDef def,
  int act,
) {
  game.eventStorySeen.add('${def.id}:$act');
  final outfit = Art.outfitArt(Friends.byId(def.friend), def.outfit);
  return showStoryScene(
    context,
    title: tr('event.name.${def.id}'),
    art: outfit.available ? outfit : Art.friend(Friends.byId(def.friend)),
    text: tr('event.story.${def.id}.$act'),
    button: tr('common.ok'),
  );
}
