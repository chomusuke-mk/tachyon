import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:tachyon/core/lifecycle/app_lifecycle_controller.dart';
import 'package:tachyon/core/lifecycle/app_lifecycle_mode.dart';
import 'package:tachyon/shared/theme/app_theme.dart';
import 'package:tachyon/features/library/presentation/screens/albums_screen.dart';
import 'package:tachyon/features/library/presentation/screens/artists_screen.dart';
import 'package:tachyon/features/library/presentation/screens/folders_screen.dart';
import 'package:tachyon/features/library/presentation/screens/genres_screen.dart';
import 'package:tachyon/features/library/presentation/screens/tracks_screen.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/locales/presentation/controllers/locale_controller.dart';
import 'package:tachyon/features/playlists/presentation/screens/playlists_screen.dart';
import 'package:tachyon/features/radios/presentation/screens/radios_screen.dart';
import 'package:tachyon/features/settings/presentation/screens/settings_screen.dart';
import 'package:tachyon/features/playback/presentation/screens/now_playing_screen.dart';

import 'package:tachyon/features/shell/presentation/widgets/mini_player_bar.dart';
import 'package:tachyon/features/shell/presentation/widgets/scan_progress_overlay.dart';

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

/// Primary responsive shell hosting the library, radio, playlist, and settings tabs.
class TachyonShell extends StatefulWidget {
  /// Optional callback invoked when the user expands the Now Playing view.
  final VoidCallback? onOpenNowPlaying;

  /// Creates a [TachyonShell].
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
        // M3 pill shape prevents Expanded from stretching the overflow button in NavigationBar.
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

            // Insert a divider before Settings when earlier items appear in the overflow menu.
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
    AppStringKey strings,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final lifecycle = Provider.of<AppLifecycleController?>(
      context,
      listen: false,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight;
        final libraryCount = specs.length - 1; // Indices 0..specs.length-2 (Settings is last).
        final settingsIndex = specs.length - 1;

        // Height needed to display all library rail destinations plus Settings below.
        final fullRequiredHeight =
            _railLeadingHeight +
            (libraryCount * _railItemHeight) +
            _railSettingsHeight;

        int visibleLibraryCount;
        bool includeSettingsInOverflow = false;

        if (maxHeight >= fullRequiredHeight) {
          visibleLibraryCount = libraryCount;
        } else {
          // Compute how many library items fit alongside the overflow button and Settings.
          final availableWithSettings =
              maxHeight -
              _railLeadingHeight -
              _railSettingsHeight -
              _railOverflowButtonHeight;
          final fitCount = (availableWithSettings / _railItemHeight).floor();

          if (fitCount >= 2) {
            // NavigationRail requires at least 2 destinations; reserve 1 slot for overflow.
            visibleLibraryCount = fitCount.clamp(2, libraryCount - 1);
          } else {
            // At very small heights, move Settings into the overflow PopupMenu too.
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

        // Safety floor height preventing RenderFlex overflow on compact desktop windows.
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
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (lifecycle != null)
                      ValueListenableBuilder<DesktopWindowState>(
                        valueListenable:
                            lifecycle.windowBridge.windowStateListenable,
                        builder: (context, windowState, _) {
                          final needsFallbackButton =
                              lifecycle.windowBridge.hasNativeChannel &&
                              !windowState.hasNativeHeaderBar &&
                              windowState.hasSystemDecorations;
                          if (!needsFallbackButton) {
                            return const SizedBox.shrink();
                          }
                          final tooltip = strings.winSendToBackground.isNotEmpty
                              ? strings.winSendToBackground
                              : 'Send to background';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6.0),
                            child: IconButton(
                              key: const Key('shell_btn_background'),
                              icon: Icon(
                                Icons.vertical_align_bottom_rounded,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              tooltip: tooltip,
                              onPressed: lifecycle.enterBackground,
                            ),
                          );
                        },
                      ),
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

        // When every tab fits horizontally, show all destinations without a PopupMenu.
        final showAll = maxSlots >= totalItems;
        final visibleCount = showAll ? totalItems : maxSlots - 1;

        final overflowIndices = showAll
            ? const <int>[]
            : <int>[for (int i = visibleCount; i < totalItems; i++) i];

        // If the active tab lives in the overflow menu, highlight the overflow slot instead.
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
            RepaintBoundary(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 80),
                child: _buildDesktopRail(context, specs, strings),
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            // Main Content Area & Docked Desktop Mini Player
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        RepaintBoundary(child: _screens[_currentIndex]),
                        const Positioned(
                          right: 16,
                          bottom: 16,
                          child: RepaintBoundary(child: ScanProgressOverlay()),
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
                RepaintBoundary(child: _screens[_currentIndex]),
                const Positioned(
                  right: 16,
                  bottom: 16,
                  child: RepaintBoundary(child: ScanProgressOverlay()),
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
      bottomNavigationBar: RepaintBoundary(
        child: _buildMobileBottomBar(context, specs),
      ),
    );
  }
}
