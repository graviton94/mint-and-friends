import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../art/art.dart';
import '../../game/config.dart';
import '../../game/game_state.dart';
import '../../i18n/l10n.dart';
import '../../i18n/names.dart';
import '../../services/audio_service.dart';
import '../theme.dart';
import '../widgets/frame_box.dart';
import '../sheets.dart' show showStyleSheet;
import '../widgets/icon_text.dart';
import 'garden_scene.dart';

/// 정원 크게 보기: 화면 높이를 꽉 채운 씬을 옆으로 밀어 둘러보고, 아래 줄에서 바로 꾸민다.
///
/// 레이어: 씬(L0~L3, GardenScene) → 위 HUD(뒤로 · 구역 · 별) → 아래 장식 줄 → 알림.
class GardenScreen extends StatefulWidget {
  const GardenScreen({
    super.key,
    required this.game,
    required this.area,
    required this.onVisitorTap,
  });
  final GameState game;
  final int area;
  final VoidCallback onVisitorTap;

  @override
  State<GardenScreen> createState() => _GardenScreenState();
}

class _GardenScreenState extends State<GardenScreen> {
  late int _area = widget.area;
  String? _note;
  int _noteId = 0;

  GameState get game => widget.game;

  @override
  void dispose() {
    super.dispose();
  }

  void _say(String text) {
    final id = ++_noteId;
    setState(() => _note = text);
    Future.delayed(const Duration(milliseconds: 2400), () {
      if (mounted && _noteId == id) setState(() => _note = null);
    });
  }

  void _onSlot(int slot) {
    if (_area != game.currentArea) return;
    final d = Garden.areaAt(game.currentArea).decor[slot];
    if (game.isPlaced(game.currentArea, slot) &&
        Art.decorStyles(d).length > 1) {
      showStyleSheet(context, game, game.currentArea, slot);
      return;
    }
    if (game.areaLocked) {
      sfx(Sfx.error);
      _say(tr('toast.areaLocked', {'n': game.areaRequiredLevel}));
    } else if (game.canPlace(slot)) {
      game.placeDecor(slot);
    } else if (!game.isPlaced(game.currentArea, slot)) {
      sfx(Sfx.error);
      final d = Garden.areaAt(game.currentArea).decor[slot];
      _say(
        tr('toast.needStars', {
          'emoji': decorToken(d),
          'name': decorName(d),
          'cost': game.decorCost(slot),
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2E2418),
      body: ListenableBuilder(
        listenable: Listenable.merge([game, L10n.instance]),
        builder: (context, _) {
          if (_area > game.currentArea) _area = game.currentArea;
          final a = Garden.areaAt(_area);
          return Stack(
            children: [
              // 바탕: 같은 배경을 흐리게 꽉 채워 위아래 빈 곳을 자연스럽게 잇는다
              Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Image.asset(
                    Art.areaBackground(a).path,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => ColoredBox(color: Color(a.sky)),
                  ),
                ),
              ),
              const Positioned.fill(
                child: ColoredBox(color: Color(0x33FFFFFF)),
              ),
              // 씬: 가로 장면 전체를 화면 폭에 맞춰 (장식 8자리가 한눈에, 잘리지 않게).
              // 두 손가락으로 2.5배까지 확대 · 드래그로 둘러보기.
              Positioned.fill(
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: 64,
                      bottom: _area == game.currentArea ? _panelH : 16,
                    ),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: GardenScene.aspect,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: const Color(0xFF7A5230),
                              width: 3,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x40000000),
                                blurRadius: 14,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(19),
                            child: InteractiveViewer(
                              minScale: 1,
                              maxScale: 2.5,
                              child: GardenScene(
                                game: game,
                                area: _area,
                                radius: 0,
                                focusY: 1,
                                markerScale: 1.1,
                                onSlotTap: _onSlot,
                                onVisitorTap: widget.onVisitorTap,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 위 HUD (씬 위에 뜬다)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 위 HUD
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        child: Row(
                          children: [
                            _Circle(
                              icon: Icons.arrow_back_rounded,
                              onTap: () => Navigator.pop(context),
                            ),
                            const SizedBox(width: 8),
                            if (_area > 0)
                              _Circle(
                                icon: Icons.chevron_left_rounded,
                                onTap: () => setState(() => _area--),
                              ),
                            Expanded(
                              child: Center(
                                child: FrameBox(
                                  frame: 'capsule',
                                  fallback: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  corner: 14,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 6,
                                  ),
                                  child: FittedBox(
                                    child: IconText(
                                      areaLabel(game, _area),
                                      style: const TextStyle(fontSize: 17),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (_area < game.currentArea)
                              _Circle(
                                icon: Icons.chevron_right_rounded,
                                onTap: () => setState(() => _area++),
                              ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: const Color(0xFF7A5230),
                                  width: 2,
                                ),
                              ),
                              child: IconText(
                                '[[star]]${game.stars}',
                                style: const TextStyle(fontSize: 17),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 아래 장식 줄 (씬 위에 뜬다)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 아래 장식 줄 (지금 꾸미는 구역일 때)
                      if (_area == game.currentArea)
                        Container(
                          margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                          decoration: FrameBox.decorationFor(
                            'panel',
                            BoxDecoration(
                              color: const Color(0xF2FFF8E8),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            corner: 18,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 진행도: 막대 + n/8
                              Row(
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: LinearProgressIndicator(
                                        value:
                                            game.placed.length /
                                            Garden.slotsPerArea,
                                        minHeight: 10,
                                        backgroundColor: const Color(
                                          0xFFEDE3CC,
                                        ),
                                        color: const Color(0xFF7BC98F),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    '${game.placed.length}/${Garden.slotsPerArea}',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              // 장식 8자리를 한 번에 (4칸 × 2줄)
                              GridView.count(
                                crossAxisCount: 4,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                childAspectRatio: 0.82,
                                children: [
                                  for (var i = 0; i < a.decor.length; i++)
                                    _DecorCard(
                                      game: game,
                                      slot: i,
                                      onTap: () => _onSlot(i),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // 알림
              if (_note != null)
                Positioned(
                  left: 20,
                  right: 20,
                  top: MediaQuery.paddingOf(context).top + 64,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: FrameBox.decorationFor(
                        'toast',
                        BoxDecoration(
                          color: const Color(0xEE2F3B2F),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        corner: 16,
                      ),
                      child: IconText(
                        _note!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 아래 장식 판 높이 (씬이 그 위 공간에 맞춰 놓인다).
const double _panelH = 300;

class _DecorCard extends StatelessWidget {
  const _DecorCard({
    required this.game,
    required this.slot,
    required this.onTap,
  });
  final GameState game;
  final int slot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = Garden.areaAt(game.currentArea).decor[slot];
    final placed = game.isPlaced(game.currentArea, slot);
    final can = game.canPlace(slot);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: placed
              ? const Color(0xFFE6F2DC)
              : can
              ? const Color(0xFFFFF3C4)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: can ? Palette.accent : const Color(0xFFE5DCC8),
            width: can ? 2.5 : 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Opacity(
              opacity: placed || can ? 1 : 0.55,
              child: ArtImage(
                Art.decor(d, style: game.styleOf(game.currentArea, slot)),
                size: 46,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              child: IconText(
                placed ? '[[check]]' : '[[star]]${game.decorCost(slot)}',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      sfx(Sfx.tap);
      onTap();
    },
    child: Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF7A5230), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, color: const Color(0xFF7A5230), size: 24),
    ),
  );
}
