import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:tachyon/shared/theme/app_theme.dart';
import 'package:tachyon/features/library/presentation/albums_screen.dart';
import 'package:tachyon/features/library/presentation/artists_screen.dart';
import 'package:tachyon/features/library/presentation/folders_screen.dart';
import 'package:tachyon/features/library/presentation/genres_screen.dart';
import 'package:tachyon/features/library/presentation/tracks_screen.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playlists/presentation/playlists_screen.dart';
import 'package:tachyon/features/search/presentation/search_screen.dart';
import 'package:tachyon/features/settings/presentation/settings_screen.dart';
import 'package:tachyon/features/playback/presentation/now_playing_screen.dart';

import 'mini_player_bar.dart';

enum ShellDestination {
  tracks,
  albums,
  artists,
  playlists,
  genres,
  folders,
  search,
  settings,
}

class TachyonShell extends StatefulWidget {
  final VoidCallback? onOpenNowPlaying;

  const TachyonShell({super.key, this.onOpenNowPlaying});

  @override
  State<TachyonShell> createState() => _TachyonShellState();
}

class _TachyonShellState extends State<TachyonShell> {
  int _currentIndex = 0;

  static const List<Widget> _screens = [
    TracksScreen(key: PageStorageKey('tracks_screen')),
    AlbumsScreen(key: PageStorageKey('albums_screen')),
    ArtistsScreen(key: PageStorageKey('artists_screen')),
    PlaylistsScreen(key: PageStorageKey('playlists_screen')),
    GenresScreen(key: PageStorageKey('genres_screen')),
    FoldersScreen(key: PageStorageKey('folders_screen')),
    SearchScreen(key: PageStorageKey('search_screen')),
    SettingsScreen(key: PageStorageKey('settings_screen')),
  ];

  void _onDestinationSelected(int index) {
    if (_currentIndex != index) {
      setState(() => _currentIndex = index);
    }
  }

  void _openNowPlaying(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const NowPlayingScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;
          final tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final isDesktop = TachyonBreakpoints.isDesktop(context);
    final colorScheme = Theme.of(context).colorScheme;

    // Desktop Layout (>= 720dp)
    if (isDesktop) {
      final desktopSelectedIndex = _currentIndex <= 6 ? _currentIndex : null;
      return Scaffold(
        body: Row(
          children: [
            // Left NavigationRail
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 80),
              child: NavigationRail(
                selectedIndex: desktopSelectedIndex,
                onDestinationSelected: _onDestinationSelected,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: Column(
                    children: [
                      SizedBox(
                        width: 50,
                        height: 50,
                        child: const Image(
                          image: AssetImage('assets/icon/icon.png'),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                  ),
                ),
                trailing: Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: IconButton(
                        icon: Icon(
                          _currentIndex == 7
                              ? Icons.settings_rounded
                              : Icons.settings_outlined,
                          color: _currentIndex == 7
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        tooltip: strings.sTitle,
                        onPressed: () => _onDestinationSelected(7),
                      ),
                    ),
                  ),
                ),
                destinations: [
                  NavigationRailDestination(
                    icon: const Icon(Icons.music_note_outlined),
                    selectedIcon: const Icon(Icons.music_note_rounded),
                    label: Text(strings.trTitle),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.album_outlined),
                    selectedIcon: const Icon(Icons.album_rounded),
                    label: Text(strings.alTitle),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.person_outline),
                    selectedIcon: const Icon(Icons.person_rounded),
                    label: Text(strings.arTitle),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.playlist_play_outlined),
                    selectedIcon: const Icon(Icons.playlist_play_rounded),
                    label: Text(strings.plTitle),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.category_outlined),
                    selectedIcon: const Icon(Icons.category_rounded),
                    label: Text(strings.gTitle),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.folder_outlined),
                    selectedIcon: const Icon(Icons.folder_rounded),
                    label: Text(strings.fTitle),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.search_outlined),
                    selectedIcon: const Icon(Icons.search_rounded),
                    label: Text(strings.srTitle),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            // Main Content Area & Docked Desktop Mini Player
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: IndexedStack(
                      index: _currentIndex,
                      children: _screens,
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

    // Mobile Layout (< 720dp)
    final mobileSelectedIndex = _currentIndex <= 3 ? _currentIndex : 0;

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(index: _currentIndex, children: _screens),
          ),
          RepaintBoundary(
            child: MiniPlayerBar(
              isDesktop: false,
              onTap: widget.onOpenNowPlaying ?? () => _openNowPlaying(context),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: mobileSelectedIndex,
        onDestinationSelected: (index) => _onDestinationSelected(index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.music_note_outlined),
            selectedIcon: const Icon(Icons.music_note_rounded),
            label: strings.trTitle,
          ),
          NavigationDestination(
            icon: const Icon(Icons.album_outlined),
            selectedIcon: const Icon(Icons.album_rounded),
            label: strings.alTitle,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person_rounded),
            label: strings.arTitle,
          ),
          NavigationDestination(
            icon: const Icon(Icons.playlist_play_outlined),
            selectedIcon: const Icon(Icons.playlist_play_rounded),
            label: strings.plTitle,
          ),
          PopupMenuButton<int>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (index) => _onDestinationSelected(index),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 4,
                child: Row(
                  children: [
                    const Icon(Icons.category_rounded, size: 20),
                    const SizedBox(width: 12),
                    Text(strings.gTitle),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 5,
                child: Row(
                  children: [
                    const Icon(Icons.folder_rounded, size: 20),
                    const SizedBox(width: 12),
                    Text(strings.fTitle),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 6,
                child: Row(
                  children: [
                    const Icon(Icons.search_outlined, size: 20),
                    const SizedBox(width: 12),
                    Text(strings.srTitle),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 7,
                child: Row(
                  children: [
                    const Icon(Icons.settings_rounded, size: 20),
                    const SizedBox(width: 12),
                    Text(strings.sTitle),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
