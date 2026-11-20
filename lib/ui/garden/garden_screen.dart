import 'dart:math';

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
  final _scroll = ScrollController();
  String? _note;
  bool _centered = false;
  int _noteId = 0;

  GameState get game => widget.game;

  @override
  void dispose() {
    _scroll.dispose();
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
              // 씬: 화면 높이를 꽉 채운 3:2 캔버스, 옆으로 밀어 둘러본다
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final h = c.maxHeight;
                    final w = max(c.maxWidth, h * GardenScene.aspect);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_scroll.hasClients && !_centered && w > c.maxWidth) {
                        _centered = true;
                        _scroll.jumpTo((w - c.maxWidth) / 2);
                      }
                    });
                    return SingleChildScrollView(
                      controller: _scroll,
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: SizedBox(
                        width: w,
                        height: h,
                        child: GardenScene(
                          game: game,
                          area: _area,
                          radius: 0,
                          focusY: 1,
                          onSlotTap: _onSlot,
                          onVisitorTap: widget.onVisitorTap,
                        ),
                      ),
                    );
                  },
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
                          height: 112,
                          margin: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                          decoration: FrameBox.decorationFor(
                            'panel',
                            BoxDecoration(
                              color: const Color(0xF2FFF8E8),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            corner: 18,
                          ),
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            itemCount: a.decor.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, i) => _DecorCard(
                              game: game,
                              slot: i,
                              onTap: () => _onSlot(i),
                            ),
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
        width: 76,
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
