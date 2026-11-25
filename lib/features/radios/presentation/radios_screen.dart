import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/playback/domain/radio_station.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/radios/presentation/radio_controller.dart';
import 'package:tachyon/features/radios/presentation/widgets/radio_filter_picker_dialog.dart';
import 'package:tachyon/features/radios/presentation/widgets/radio_logo_avatar.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

/// Screen displaying and managing online radio stations and continuous HLS livestreams.
/// Supports dual-mode navigation (offline SQLite stations vs live Radio Browser directory),
/// persistent card/list view modes, station searching, genre/country filtering,
/// and queue-based sequential playback.
class RadiosScreen extends StatefulWidget {
  const RadiosScreen({super.key});

  @override
  State<RadiosScreen> createState() => _RadiosScreenState();
}

class _RadiosScreenState extends State<RadiosScreen>
    with
        SingleTickerProviderStateMixin,
        AutomaticKeepAliveClientMixin<RadiosScreen> {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  bool _isCardView = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final initialTab = Provider.of<RadioController?>(
          context,
          listen: false,
        )?.currentTabIndex ??
        0;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: initialTab.clamp(0, 1),
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        Provider.of<RadioController?>(
          context,
          listen: false,
        )?.setTabIndex(_tabController.index);
      }
    });

    final repo = Provider.of<SettingsRepository?>(context, listen: false);
    if (repo != null) {
      _isCardView = repo.getCardView('radios', defaultValue: false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleCardView() {
    setState(() {
      _isCardView = !_isCardView;
    });
    Provider.of<SettingsRepository?>(context, listen: false)
        ?.setCardView('radios', _isCardView);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final strings = context.watch<LocaleController>().localeStrings;
    final store = context.watch<LibraryStore>();
    final playback = context.read<PlaybackController>();
    final radioCtrl = context.watch<RadioController>();

    final myStations = store.radioStations;
    final discoverStations = radioCtrl.discoverStations;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.rdTitle),
        actions: [
          IconButton(
            icon: Icon(
              _isCardView ? Icons.view_list_rounded : Icons.grid_view_rounded,
            ),
            tooltip: _isCardView
                ? strings.commonViewAsList
                : strings.commonViewAsCards,
            onPressed: _toggleCardView,
          ),
          IconButton(
            icon: radioCtrl.isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            tooltip: strings.rdRefresh,
            onPressed: radioCtrl.isRefreshing
                ? null
                : () => radioCtrl.refresh(),
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: strings.rdAddStation,
            onPressed: () =>
                _showAddEditStationDialog(context, null, strings, store),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.bookmark_rounded),
              text: strings.rdMyStations,
            ),
            Tab(
              icon: const Icon(Icons.explore_rounded),
              text: strings.rdDiscover,
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: My Stations (Local SQLite)
          _buildMyStationsTab(
            context,
            theme,
            strings,
            store,
            playback,
            myStations,
          ),

          // Tab 2: Discover (Radio Browser Online Directory)
          _buildDiscoverTab(
            context,
            theme,
            strings,
            playback,
            radioCtrl,
            discoverStations,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: My Stations
  // ---------------------------------------------------------------------------

  Widget _buildMyStationsTab(
    BuildContext context,
    ThemeData theme,
    AppStringKey strings,
    LibraryStore store,
    PlaybackController playback,
    List<RadioStation> stations,
  ) {
    if (stations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.radio_rounded,
                size: 72,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 16),
              Text(
                strings.rdEmptyTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                strings.rdEmptySubtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    onPressed: () => _showAddEditStationDialog(
                      context,
                      null,
                      strings,
                      store,
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(strings.rdAddStation),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () => _tabController.animateTo(1),
                    icon: const Icon(Icons.explore_rounded),
                    label: Text(strings.rdDiscover),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return _isCardView
        ? _buildStationsGrid(stations, playback, isSavedTab: true)
        : _buildStationsList(stations, playback, isSavedTab: true);
  }

  // ---------------------------------------------------------------------------
  // Tab 2: Discover (Radio Browser)
  // ---------------------------------------------------------------------------

  Widget _buildDiscoverTab(
    BuildContext context,
    ThemeData theme,
    AppStringKey strings,
    PlaybackController playback,
    RadioController radioCtrl,
    List<RadioStation> stations,
  ) {
    return Column(
      children: [
        // Search Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: strings.rdSearchHint,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchController.clear();
                        radioCtrl.search('');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 0.0,
                horizontal: 16.0,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28.0),
              ),
            ),
            onChanged: (val) => radioCtrl.search(val),
          ),
        ),

        // 2 Selectors: Genre & Country (Searchable modal pickers to prevent lag)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
          child: Row(
            children: [
              // 1. Genre Picker Button
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.style_rounded, size: 18),
                  label: Text(
                    radioCtrl.selectedTag == 'All' ||
                            radioCtrl.selectedTag.isEmpty
                        ? strings.rdAllGenres
                        : radioCtrl.selectedTag,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    alignment: Alignment.centerLeft,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    RadioFilterPickerDialog.show(
                      context,
                      title: strings.rdGenre,
                      currentSelectedValue: radioCtrl.selectedTag,
                      allLabel: strings.rdAllGenres,
                      items: radioCtrl.popularTags,
                      onSelected: (val) => radioCtrl.setTag(val),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),

              // 2. Country Picker Button
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.public_rounded, size: 18),
                  label: Text(
                    radioCtrl.selectedCountry == 'All' ||
                            radioCtrl.selectedCountry.isEmpty
                        ? strings.rdAllCountries
                        : radioCtrl.selectedCountry,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    alignment: Alignment.centerLeft,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    RadioFilterPickerDialog.show(
                      context,
                      title: strings.rdCountry,
                      currentSelectedValue: radioCtrl.selectedCountry,
                      allLabel: strings.rdAllCountries,
                      items: radioCtrl.popularCountries,
                      onSelected: (val) => radioCtrl.setCountry(val),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 6),

        // Station Results
        Expanded(
          child: radioCtrl.isLoading
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        strings.rdLoading,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : stations.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              size: 64,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              strings.rdNoResults,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              strings.rdNoResultsSubtitle,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton(
                              onPressed: () {
                                _searchController.clear();
                                radioCtrl.clearFilters();
                              },
                              child: Text(strings.rdAllGenres),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _isCardView
                      ? _buildStationsGrid(
                          stations,
                          playback,
                          isSavedTab: false,
                        )
                      : _buildStationsList(
                          stations,
                          playback,
                          isSavedTab: false,
                        ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // View Modes: List & Card Grid
  // ---------------------------------------------------------------------------

  Widget _buildStationsList(
    List<RadioStation> stations,
    PlaybackController playback, {
    required bool isSavedTab,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strings = context.read<LocaleController>().localeStrings;
    final store = context.read<LibraryStore>();
    final radioCtrl = context.read<RadioController>();

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4.0, bottom: 88.0),
      itemCount: stations.length,
      itemBuilder: (context, index) {
        final station = stations[index];
        final isSaved = radioCtrl.isStationSaved(station);

        final subtitleParts = <String>[];
        if (station.genre?.isNotEmpty == true) {
          subtitleParts.add(station.genre!);
        }
        if (station.country?.isNotEmpty == true) {
          subtitleParts.add(station.country!);
        }
        if (station.bitrateKbps != null && station.bitrateKbps! > 0) {
          subtitleParts.add('${station.bitrateKbps} kbps');
        }
        final subtitleText = subtitleParts.isNotEmpty
            ? subtitleParts.join(' • ')
            : 'Online Radio';

        return RepaintBoundary(
          child: Builder(
            builder: (context) {
              final (isCurrent, isPlaying) = context
                  .select<PlaybackController, (bool, bool)>((c) {
                    final cur =
                        c.currentPlayable?.filePath == station.streamUrl;
                    return (cur, cur && c.isPlaying);
                  });

              return ListTile(
                leading: RadioLogoAvatar(
                  faviconUrl: station.faviconUrl,
                  size: 46.0,
                  isCurrent: isCurrent,
                  isPlaying: isPlaying,
                ),
                title: Text(
                  station.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                    color: isCurrent
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                  ),
                ),
                subtitle: Text(
                  subtitleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSavedTab) ...[
                      IconButton(
                        icon: Icon(
                          station.isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: station.isFavorite
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        tooltip: station.isFavorite
                            ? 'Favorite'
                            : 'Add to favorites',
                        onPressed: station.id != null
                            ? () => store.toggleRadioStationFavoriteInStore(
                                station.id!,
                              )
                            : null,
                      ),
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        onSelected: (action) {
                          if (action == 'edit') {
                            _showAddEditStationDialog(
                              context,
                              station,
                              strings,
                              store,
                            );
                          } else if (action == 'delete' && station.id != null) {
                            _confirmDelete(context, station, strings, store);
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                const Icon(Icons.edit_outlined, size: 20),
                                const SizedBox(width: 12),
                                Text(strings.rdEditStation),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_outline_rounded,
                                  size: 20,
                                  color: colorScheme.error,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  strings.rdDeleteStation,
                                  style: TextStyle(color: colorScheme.error),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      IconButton(
                        icon: Icon(
                          isSaved
                              ? Icons.bookmark_added_rounded
                              : Icons.bookmark_add_outlined,
                          color: isSaved
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        tooltip: isSaved
                            ? strings.rdAlreadyInLibrary
                            : strings.rdSaveToLibrary,
                        onPressed: isSaved
                            ? null
                            : () async {
                                await radioCtrl.saveToLibrary(station);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${station.name}: ${strings.rdSavedToLibrary}',
                                      ),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                      ),
                    ],
                  ],
                ),
                onTap: () {
                  // Treat stations like tracks in a queue: loads all stations starting at index
                  playback.playTrack(station, contextTracks: stations);
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildStationsGrid(
    List<RadioStation> stations,
    PlaybackController playback, {
    required bool isSavedTab,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strings = context.read<LocaleController>().localeStrings;
    final store = context.read<LibraryStore>();
    final radioCtrl = context.read<RadioController>();

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 88.0),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 16.0,
        crossAxisSpacing: 16.0,
        childAspectRatio: 0.74,
      ),
      itemCount: stations.length,
      itemBuilder: (context, index) {
        final station = stations[index];
        final isSaved = radioCtrl.isStationSaved(station);

        return RepaintBoundary(
          child: Builder(
            builder: (context) {
              final (isCurrent, isPlaying) = context
                  .select<PlaybackController, (bool, bool)>((c) {
                    final cur =
                        c.currentPlayable?.filePath == station.streamUrl;
                    return (cur, cur && c.isPlaying);
                  });

              return Card(
                elevation: isCurrent ? 3 : 0,
                color: isCurrent
                    ? colorScheme.primaryContainer.withValues(alpha: 0.35)
                    : colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.4,
                      ),
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  side: isCurrent
                      ? BorderSide(color: colorScheme.primary, width: 1.5)
                      : BorderSide.none,
                ),
                child: InkWell(
                  onTap: () {
                    playback.playTrack(station, contextTracks: stations);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Station Cover / Logo
                        Expanded(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 1.0,
                              child: RadioLogoAvatar(
                                faviconUrl: station.faviconUrl,
                                size: 130.0,
                                isCurrent: isCurrent,
                                isPlaying: isPlaying,
                                borderRadius: BorderRadius.circular(10.0),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Station Title
                        Text(
                          station.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: isCurrent
                                ? FontWeight.bold
                                : FontWeight.w600,
                            fontSize: 13.5,
                            color: isCurrent
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),

                        // Metadata subtitle & action row
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                station.genre?.isNotEmpty == true
                                    ? station.genre!
                                    : (station.country?.isNotEmpty == true
                                          ? station.country!
                                          : 'Radio'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            if (isSavedTab) ...[
                              InkResponse(
                                onTap: station.id != null
                                    ? () =>
                                          store.toggleRadioStationFavoriteInStore(
                                            station.id!,
                                          )
                                    : null,
                                child: Icon(
                                  station.isFavorite
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  size: 18,
                                  color: station.isFavorite
                                      ? colorScheme.primary
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ] else ...[
                              InkResponse(
                                onTap: isSaved
                                    ? null
                                    : () async {
                                        await radioCtrl.saveToLibrary(station);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                '${station.name}: ${strings.rdSavedToLibrary}',
                                              ),
                                              duration: const Duration(
                                                seconds: 2,
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                child: Icon(
                                  isSaved
                                      ? Icons.bookmark_added_rounded
                                      : Icons.bookmark_add_outlined,
                                  size: 18,
                                  color: isSaved
                                      ? colorScheme.primary
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Dialogs: Manual Add / Edit with Image Preview & Delete
  // ---------------------------------------------------------------------------

  static Future<void> _showAddEditStationDialog(
    BuildContext context,
    RadioStation? existingStation,
    AppStringKey strings,
    LibraryStore store,
  ) async {
    final nameController =
        TextEditingController(text: existingStation?.name ?? '');
    final urlController =
        TextEditingController(text: existingStation?.streamUrl ?? '');
    final imageController =
        TextEditingController(text: existingStation?.faviconUrl ?? '');
    final genreController =
        TextEditingController(text: existingStation?.genre ?? '');
    final countryController =
        TextEditingController(text: existingStation?.country ?? '');
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final imageUrl = imageController.text.trim();
          final hasValidImage =
              imageUrl.isNotEmpty && Uri.tryParse(imageUrl)?.hasScheme == true;

          return AlertDialog(
            title: Text(
              existingStation == null
                  ? strings.rdAddStation
                  : strings.rdEditStation,
            ),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Optional Live Logo Preview
                    if (hasValidImage) ...[
                      Center(
                        child: RadioLogoAvatar(
                          faviconUrl: imageUrl,
                          size: 64.0,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    TextFormField(
                      controller: nameController,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: strings.rdStationName,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return strings.rdStationName;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: urlController,
                      decoration: InputDecoration(
                        labelText: strings.rdStreamUrl,
                        hintText: 'https://...',
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return strings.rdStreamUrl;
                        }
                        final uri = Uri.tryParse(val.trim());
                        if (uri == null || !uri.hasScheme) {
                          return strings.rdStreamUrl;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: imageController,
                      decoration: InputDecoration(
                        labelText: strings.rdImageUrl,
                        hintText: 'https://... (logo/favicon)',
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: genreController,
                      decoration: InputDecoration(
                        labelText: strings.rdGenre,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: countryController,
                      decoration: InputDecoration(
                        labelText: strings.rdCountry,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: Text(strings.rdCancel),
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState?.validate() == true) {
                    Navigator.of(dialogCtx).pop(true);
                  }
                },
                child: Text(strings.rdSave),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true && context.mounted) {
      final station = RadioStation(
        id: existingStation?.id,
        stationUuid: existingStation?.stationUuid,
        name: nameController.text.trim(),
        streamUrl: urlController.text.trim(),
        faviconUrl: imageController.text.trim().isNotEmpty
            ? imageController.text.trim()
            : null,
        genre: genreController.text.trim().isNotEmpty
            ? genreController.text.trim()
            : null,
        country: countryController.text.trim().isNotEmpty
            ? countryController.text.trim()
            : null,
        codec: existingStation?.codec,
        bitrateKbps: existingStation?.bitrateKbps,
        isFavorite: existingStation?.isFavorite ?? false,
        createdAt: existingStation?.createdAt ?? DateTime.now(),
      );
      await store.saveRadioStationInStore(station);
    }
  }

  static Future<void> _confirmDelete(
    BuildContext context,
    RadioStation station,
    AppStringKey strings,
    LibraryStore store,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(strings.rdDeleteStation),
        content: Text('${strings.rdDeleteConfirm}\n\n"${station.name}"'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(strings.rdCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogCtx).colorScheme.error,
              foregroundColor: Theme.of(dialogCtx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(strings.rdDelete),
          ),
        ],
      ),
    );

    if (confirmed == true && station.id != null) {
      await store.deleteRadioStationInStore(station.id!);
    }
  }
}
