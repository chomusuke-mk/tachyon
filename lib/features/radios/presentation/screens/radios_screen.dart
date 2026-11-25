import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/playback/domain/radio_station.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/locales/presentation/controllers/locale_controller.dart';
import 'package:tachyon/features/radios/presentation/controllers/radio_controller.dart';
import 'package:tachyon/features/radios/presentation/widgets/radio_filter_picker_dialog.dart';
import 'package:tachyon/features/radios/presentation/widgets/radio_station_dialog.dart';
import 'package:tachyon/features/radios/presentation/widgets/radio_station_tile.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

/// Screen displaying and managing online radio stations and continuous HLS livestreams.
///
/// Supports dual-mode navigation (offline SQLite stations vs live Radio Browser directory),
/// persistent card/list view modes, station searching, genre/country filtering,
/// and queue-based sequential playback.
class RadiosScreen extends StatefulWidget {
  /// Creates a [RadiosScreen].
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
            onPressed: () => showAddEditRadioStationDialog(
              context,
              strings: strings,
              store: store,
            ),
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
                    onPressed: () => showAddEditRadioStationDialog(
                      context,
                      strings: strings,
                      store: store,
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
    final strings = context.read<LocaleController>().localeStrings;
    final store = context.read<LibraryStore>();
    final radioCtrl = context.read<RadioController>();

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4.0, bottom: 88.0),
      itemCount: stations.length,
      itemBuilder: (context, index) {
        final station = stations[index];
        return RadioStationListTile(
          station: station,
          strings: strings,
          store: store,
          radioController: radioCtrl,
          isSavedTab: isSavedTab,
          onTap: () => playback.playTrack(station, contextTracks: stations),
          onEdit: () => showAddEditRadioStationDialog(
            context,
            existingStation: station,
            strings: strings,
            store: store,
          ),
          onDelete: () => showDeleteRadioStationDialog(
            context,
            station: station,
            strings: strings,
            store: store,
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
        return RadioStationGridCard(
          station: station,
          strings: strings,
          store: store,
          radioController: radioCtrl,
          isSavedTab: isSavedTab,
          onTap: () => playback.playTrack(station, contextTracks: stations),
        );
      },
    );
  }
}
