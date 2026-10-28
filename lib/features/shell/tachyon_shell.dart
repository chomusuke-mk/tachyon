import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:tachyon/shared/theme/app_theme.dart';
import 'package:tachyon/features/library/presentation/albums_screen.dart';
import 'package:tachyon/features/library/presentation/artists_screen.dart';
import 'package:tachyon/features/library/presentation/folders_screen.dart';
import 'package:tachyon/features/library/presentation/genres_screen.dart';
import 'package:tachyon/features/library/presentation/tracks_screen.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playlists/presentation/playlists_screen.dart';
import 'package:tachyon/features/radios/presentation/radios_screen.dart';
import 'package:tachyon/features/settings/presentation/settings_screen.dart';
import 'package:tachyon/features/playback/presentation/now_playing_screen.dart';

import 'mini_player_bar.dart';
import 'scan_progress_overlay.dart';

enum ShellDestination {
  tracks,
  albums,
  artists,
  playlists,
  genres,
  folders,
  radios,
  settings,
}

class _DestinationSpec {
  final int index;
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _DestinationSpec({
    required this.index,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

class TachyonShell extends StatefulWidget {
  final VoidCallback? onOpenNowPlaying;

  const TachyonShell({super.key, this.onOpenNowPlaying});

  @override
  State<TachyonShell> createState() => _TachyonShellState();
}

class _TachyonShellState extends State<TachyonShell> {
  int _currentIndex = 0;

  static const double _minMobileItemWidth = 62.0;
  static const double _railLeadingHeight = 76.0;
  static const double _railItemHeight = 66.0;
  static const double _railSettingsHeight = 64.0;
  static const double _railOverflowButtonHeight = 56.0;

  static const List<Widget> _screens = [
    TracksScreen(key: PageStorageKey('tracks_screen')),
    AlbumsScreen(key: PageStorageKey('albums_screen')),
    ArtistsScreen(key: PageStorageKey('artists_screen')),
    PlaylistsScreen(key: PageStorageKey('playlists_screen')),
    GenresScreen(key: PageStorageKey('genres_screen')),
    FoldersScreen(key: PageStorageKey('folders_screen')),
    RadiosScreen(key: PageStorageKey('radios_screen')),
    SettingsScreen(key: PageStorageKey('settings_screen')),
  ];

  void _onDestinationSelected(int index) {
    if (_currentIndex != index) {
      setState(() => _currentIndex = index);
    }
  }

  void _openNowPlaying(BuildContext context) {
    NowPlayingScreen.open(context);
  }

  List<_DestinationSpec> _getDestinations(AppStringKey strings) {
    return [
      _DestinationSpec(
        index: 0,
        icon: Icons.music_note_outlined,
        selectedIcon: Icons.music_note_rounded,
        label: strings.trTitle,
      ),
      _DestinationSpec(
        index: 1,
        icon: Icons.album_outlined,
        selectedIcon: Icons.album_rounded,
        label: strings.alTitle,
      ),
      _DestinationSpec(
        index: 2,
        icon: Icons.person_outline,
        selectedIcon: Icons.person_rounded,
        label: strings.arTitle,
      ),
      _DestinationSpec(
        index: 3,
        icon: Icons.playlist_play_outlined,
        selectedIcon: Icons.playlist_play_rounded,
        label: strings.plTitle,
      ),
      _DestinationSpec(
        index: 4,
        icon: Icons.category_outlined,
        selectedIcon: Icons.category_rounded,
        label: strings.gTitle,
      ),
      _DestinationSpec(
        index: 5,
        icon: Icons.folder_outlined,
        selectedIcon: Icons.folder_rounded,
        label: strings.fTitle,
      ),
      _DestinationSpec(
        index: 6,
        icon: Icons.radio_outlined,
        selectedIcon: Icons.radio_rounded,
        label: strings.rdTitle,
      ),
      _DestinationSpec(
        index: 7,
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
        label: strings.sTitle,
      ),
    ];
  }

  Widget _buildOverflowPopupButton({
    required BuildContext context,
    required List<_DestinationSpec> allSpecs,
    required List<int> overflowIndices,
    required bool isDesktopRail,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isOverflowSelected = overflowIndices.contains(_currentIndex);

    return Center(
      child: PopupMenuButton<int>(
        tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
        position: PopupMenuPosition.over,
        offset: isDesktopRail ? const Offset(60, 0) : const Offset(0, -48),
        constraints: const BoxConstraints(minWidth: 150, maxWidth: 210),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        onSelected: _onDestinationSelected,
        // Diseño tipo píldora M3 para evitar que Expanded lo estire en NavigationBar
        icon: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: isDesktopRail ? 56 : 64,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isOverflowSelected
                ? colorScheme.secondaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Icons.more_vert_rounded,
            color: isOverflowSelected
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurfaceVariant,
          ),
        ),
        itemBuilder: (context) {
          final entries = <PopupMenuEntry<int>>[];

          for (int i = 0; i < overflowIndices.length; i++) {
            final itemIndex = overflowIndices[i];
            final spec = allSpecs[itemIndex];
            final isSelected = _currentIndex == itemIndex;

            // Separador antes de Settings si hay otros elementos antes en el menú
            if (itemIndex == allSpecs.length - 1 && i > 0) {
              entries.add(const PopupMenuDivider(height: 8));
            }

            entries.add(
              PopupMenuItem<int>(
                value: itemIndex,
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isSelected ? spec.selectedIcon : spec.icon,
                      size: 20,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        spec.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return entries;
        },
      ),
    );
  }

  Widget _buildDesktopRail(
    BuildContext context,
    List<_DestinationSpec> specs,
    dynamic strings,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight;
        final libraryCount = specs.length - 1; // Índices 0..specs.length-2 (Settings es el último)
        final settingsIndex = specs.length - 1;

        // Altura necesaria para mostrar los iconos de biblioteca + Settings abajo
        final fullRequiredHeight =
            _railLeadingHeight +
            (libraryCount * _railItemHeight) +
            _railSettingsHeight;

        int visibleLibraryCount;
        bool includeSettingsInOverflow = false;

        if (maxHeight >= fullRequiredHeight) {
          visibleLibraryCount = libraryCount;
        } else {
          // Calculamos cuántos caben dejando espacio para el botón de overflow y Settings
          final availableWithSettings =
              maxHeight -
              _railLeadingHeight -
              _railSettingsHeight -
              _railOverflowButtonHeight;
          final fitCount = (availableWithSettings / _railItemHeight).floor();

          if (fitCount >= 2) {
            // NavigationRail requiere al menos 2 destinos; máximo libraryCount - 1 porque 1 slot es el menú
            visibleLibraryCount = fitCount.clamp(2, libraryCount - 1);
          } else {
            // Si la altura es muy reducida, movemos también Settings dentro del PopupMenu
            includeSettingsInOverflow = true;
            final availableWithoutSettings =
                maxHeight - _railLeadingHeight - _railOverflowButtonHeight;
            visibleLibraryCount = (availableWithoutSettings / _railItemHeight)
                .floor()
                .clamp(2, libraryCount - 1);
          }
        }

        final overflowIndices = <int>[
          for (int i = visibleLibraryCount; i < libraryCount; i++) i,
          if (includeSettingsInOverflow) settingsIndex,
        ];

        final desktopSelectedIndex = _currentIndex < visibleLibraryCount
            ? _currentIndex
            : null;

        // Altura mínima de seguridad para que nunca ocurra RenderFlex overflow en ventanas diminutas
        final minSafeHeight =
            _railLeadingHeight +
            (visibleLibraryCount * _railItemHeight) +
            (overflowIndices.isNotEmpty ? _railOverflowButtonHeight : 0) +
            (!includeSettingsInOverflow ? _railSettingsHeight : 0);

        final needsScrollFallback = maxHeight < minSafeHeight;

        final rail = NavigationRail(
          selectedIndex: desktopSelectedIndex,
          onDestinationSelected: _onDestinationSelected,
          leading: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: Image.asset(
                  'assets/icon/icon_small.webp',
                  cacheHeight: 100,
                  cacheWidth: 100,
                  width: 50,
                  height: 50,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
          destinations: [
            for (int i = 0; i < visibleLibraryCount; i++)
              NavigationRailDestination(
                icon: Icon(specs[i].icon),
                selectedIcon: Icon(specs[i].selectedIcon),
                label: Text(
                  specs[i].label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          trailing: Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (overflowIndices.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: _buildOverflowPopupButton(
                      context: context,
                      allSpecs: specs,
                      overflowIndices: overflowIndices,
                      isDesktopRail: true,
                    ),
                  )
                else
                  const SizedBox.shrink(),
                if (!includeSettingsInOverflow)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: IconButton(
                      icon: Icon(
                        _currentIndex == settingsIndex
                            ? Icons.settings_rounded
                            : Icons.settings_outlined,
                        color: _currentIndex == settingsIndex
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                      tooltip: strings.sTitle,
                      onPressed: () => _onDestinationSelected(settingsIndex),
                    ),
                  ),
              ],
            ),
          ),
        );

        if (needsScrollFallback) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(maxHeight, minSafeHeight),
              ),
              child: IntrinsicHeight(child: rail),
            ),
          );
        }

        return rail;
      },
    );
  }

  Widget _buildMobileBottomBar(
    BuildContext context,
    List<_DestinationSpec> specs,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalItems = specs.length;
        final maxSlots = (constraints.maxWidth / _minMobileItemWidth)
            .floor()
            .clamp(2, totalItems);

        // Si caben todos los iconos, los colocamos todos sin PopupMenu
        final showAll = maxSlots >= totalItems;
        final visibleCount = showAll ? totalItems : maxSlots - 1;

        final overflowIndices = showAll
            ? const <int>[]
            : <int>[for (int i = visibleCount; i < totalItems; i++) i];

        // Si el ítem activo está en el menú, apuntamos al slot del menú para no marcar otro icono por error
        final mobileSelectedIndex = _currentIndex < visibleCount
            ? _currentIndex
            : visibleCount;

        final navBarTheme = NavigationBarTheme.of(context);

        return NavigationBarTheme(
          data: navBarTheme.copyWith(
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final baseStyle =
                  navBarTheme.labelTextStyle?.resolve(states) ??
                  Theme.of(context).textTheme.labelMedium ??
                  const TextStyle();
              return baseStyle.copyWith(overflow: TextOverflow.ellipsis);
            }),
          ),
          child: DefaultTextStyle.merge(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: NavigationBar(
              selectedIndex: mobileSelectedIndex,
              onDestinationSelected: (index) {
                if (index < visibleCount) {
                  _onDestinationSelected(index);
                }
              },
              destinations: [
                for (int i = 0; i < visibleCount; i++)
                  NavigationDestination(
                    icon: Icon(specs[i].icon),
                    selectedIcon: Icon(specs[i].selectedIcon),
                    label: specs[i].label,
                  ),
                if (!showAll)
                  _buildOverflowPopupButton(
                    context: context,
                    allSpecs: specs,
                    overflowIndices: overflowIndices,
                    isDesktopRail: false,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final isDesktop = TachyonBreakpoints.isDesktop(context);
    final specs = _getDestinations(strings);

    // Desktop Layout (>= 720dp)
    if (isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            // Left NavigationRail
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 80),
              child: _buildDesktopRail(context, specs, strings),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            // Main Content Area & Docked Desktop Mini Player
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        _screens[_currentIndex],
                        const Positioned(
                          right: 16,
                          bottom: 16,
                          child: ScanProgressOverlay(),
                        ),
                      ],
                    ),
                  ),
                  RepaintBoundary(
                    child: MiniPlayerBar(
                      isDesktop: true,
                      onTap:
                          widget.onOpenNowPlaying ??
                          () => _openNowPlaying(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                _screens[_currentIndex],
                const Positioned(
                  right: 16,
                  bottom: 16,
                  child: ScanProgressOverlay(),
                ),
              ],
            ),
          ),
          RepaintBoundary(
            child: MiniPlayerBar(
              isDesktop: false,
              onTap: widget.onOpenNowPlaying ?? () => _openNowPlaying(context),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildMobileBottomBar(context, specs),
    );
  }
}
