import 'package:flutter/foundation.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';

/// Central domain class managing localized string lookups for Tachyon.
///
/// Exposes strictly-typed camelCase getters for all keys cataloged in
/// `i18n/en.jsonc` and `i18n/es.jsonc`. All getters guarantee a null-safe
/// empty string fallback.
class AppStringKey {
  final Map<String, String> _cadenasLocalizadas = <String, String>{};

  // ---------------------------------------------------------------------------
  // np_: Now Playing & Transport Controls
  // ---------------------------------------------------------------------------
  String get npTitle => _cadenasLocalizadas['np_title'] ?? '';
  String get npPlay => _cadenasLocalizadas['np_play'] ?? '';
  String get npPause => _cadenasLocalizadas['np_pause'] ?? '';
  String get npPrevious => _cadenasLocalizadas['np_previous'] ?? '';
  String get npNext => _cadenasLocalizadas['np_next'] ?? '';
  String get npStop => _cadenasLocalizadas['np_stop'] ?? '';
  String get npMute => _cadenasLocalizadas['np_mute'] ?? '';
  String get npUnmute => _cadenasLocalizadas['np_unmute'] ?? '';
  String get npVolume => _cadenasLocalizadas['np_volume'] ?? '';
  String get npShuffleOff => _cadenasLocalizadas['np_shuffle_off'] ?? '';
  String get npShuffleOn => _cadenasLocalizadas['np_shuffle_on'] ?? '';
  String get npRepeatOff => _cadenasLocalizadas['np_repeat_off'] ?? '';
  String get npRepeatAll => _cadenasLocalizadas['np_repeat_all'] ?? '';
  String get npRepeatOne => _cadenasLocalizadas['np_repeat_one'] ?? '';
  String get npElapsed => _cadenasLocalizadas['np_elapsed'] ?? '';
  String get npRemaining => _cadenasLocalizadas['np_remaining'] ?? '';
  String get npDuration => _cadenasLocalizadas['np_duration'] ?? '';
  String get npSeekForward => _cadenasLocalizadas['np_seek_forward'] ?? '';
  String get npSeekBackward => _cadenasLocalizadas['np_seek_backward'] ?? '';
  String get npQueue => _cadenasLocalizadas['np_queue'] ?? '';
  String get npQueueClear => _cadenasLocalizadas['np_queue_clear'] ?? '';
  String get npQueueClearConfirm =>
      _cadenasLocalizadas['np_queue_clear_confirm'] ?? '';
  String get npQueueEmpty => _cadenasLocalizadas['np_queue_empty'] ?? '';
  String get npQueueReorder => _cadenasLocalizadas['np_queue_reorder'] ?? '';
  String get npLyrics => _cadenasLocalizadas['np_lyrics'] ?? '';
  String get npLyricsEmpty => _cadenasLocalizadas['np_lyrics_empty'] ?? '';
  String get npLyricsSync => _cadenasLocalizadas['np_lyrics_sync'] ?? '';
  String get npLyricsUnsync => _cadenasLocalizadas['np_lyrics_unsync'] ?? '';
  String get npLyricsTranslate =>
      _cadenasLocalizadas['np_lyrics_translate'] ?? '';
  String get npLyricsTranslating =>
      _cadenasLocalizadas['np_lyrics_translating'] ?? '';
  String get npLyricsTranslationMode =>
      _cadenasLocalizadas['np_lyrics_translation_mode'] ?? '';
  String get npLyricsOriginal =>
      _cadenasLocalizadas['np_lyrics_original'] ?? '';
  String get npLyricsTranslated =>
      _cadenasLocalizadas['np_lyrics_translated'] ?? '';
  String get npLyricsInterleaved =>
      _cadenasLocalizadas['np_lyrics_interleaved'] ?? '';
  String get npLyricsSources => _cadenasLocalizadas['np_lyrics_sources'] ?? '';
  String get npLyricsResearch =>
      _cadenasLocalizadas['np_lyrics_research'] ?? '';
  String get npLyricsResumeSync =>
      _cadenasLocalizadas['np_lyrics_resume_sync'] ?? '';
  String get npLyricsSourcesTitle =>
      _cadenasLocalizadas['np_lyrics_sources_title'] ?? '';
  String get npLyricsSourceLocal =>
      _cadenasLocalizadas['np_lyrics_source_local'] ?? '';
  String get npLyricsSourceLocalDesc =>
      _cadenasLocalizadas['np_lyrics_source_local_desc'] ?? '';
  String get npLyricsSourceLrclib =>
      _cadenasLocalizadas['np_lyrics_source_lrclib'] ?? '';
  String get npLyricsSourceLrclibDesc =>
      _cadenasLocalizadas['np_lyrics_source_lrclib_desc'] ?? '';
  String get npLyricsSourceOvh =>
      _cadenasLocalizadas['np_lyrics_source_ovh'] ?? '';
  String get npLyricsSourceOvhDesc =>
      _cadenasLocalizadas['np_lyrics_source_ovh_desc'] ?? '';
  String get npLyricsSourcesResearch =>
      _cadenasLocalizadas['np_lyrics_sources_research'] ?? '';
  String get npLyricsSourcesResearchBtn =>
      _cadenasLocalizadas['np_lyrics_sources_research_btn'] ?? '';
  String get npLyricsRetranslateBtn =>
      _cadenasLocalizadas['np_lyrics_retranslate_btn'] ?? '';
  String get npLyricsSourcesClose =>
      _cadenasLocalizadas['np_lyrics_sources_close'] ?? '';
  String get npLyricsSourcesCloseBtn =>
      _cadenasLocalizadas['np_lyrics_sources_close_btn'] ?? '';
  String get npLyricsTabSources =>
      _cadenasLocalizadas['np_lyrics_tab_sources'] ?? '';
  String get npLyricsTabTranslation =>
      _cadenasLocalizadas['np_lyrics_tab_translation'] ?? '';
  String get npLyricsSourceLang =>
      _cadenasLocalizadas['np_lyrics_source_lang'] ?? '';
  String get npLyricsTargetLang =>
      _cadenasLocalizadas['np_lyrics_target_lang'] ?? '';
  String get npLyricsLangAuto =>
      _cadenasLocalizadas['np_lyrics_lang_auto'] ?? '';
  String get npLyricsLangAutoTarget =>
      _cadenasLocalizadas['np_lyrics_lang_auto_target'] ?? '';
  String get npLyricsRateLimitError =>
      _cadenasLocalizadas['np_lyrics_rate_limit_error'] ?? '';
  String get npLyricsThresholdWaiting =>
      _cadenasLocalizadas['np_lyrics_threshold_waiting'] ?? '';
  String get npLyricsBannerDismiss =>
      _cadenasLocalizadas['np_lyrics_banner_dismiss'] ?? '';
  String get npLyricsSourceEmbedded =>
      _cadenasLocalizadas['np_lyrics_source_embedded'] ?? '';
  String get npLyricsSourceFile =>
      _cadenasLocalizadas['np_lyrics_source_file'] ?? '';
  String get npLyricsSourceNone =>
      _cadenasLocalizadas['np_lyrics_source_none'] ?? '';
  String get npLyricsLoading => _cadenasLocalizadas['np_lyrics_loading'] ?? '';
  String get npLyricsError => _cadenasLocalizadas['np_lyrics_error'] ?? '';
  String get npLyricsTranslateError =>
      _cadenasLocalizadas['np_lyrics_translate_error'] ?? '';
  String get npAudioControls => _cadenasLocalizadas['np_audio_controls'] ?? '';
  String get npSpeed => _cadenasLocalizadas['np_speed'] ?? '';
  String get npPitch => _cadenasLocalizadas['np_pitch'] ?? '';
  String get npVolumeBoost => _cadenasLocalizadas['np_volume_boost'] ?? '';
  String get npReplayGain => _cadenasLocalizadas['np_replay_gain'] ?? '';
  String get npReplayGainOff => _cadenasLocalizadas['np_replay_gain_off'] ?? '';
  String get npReplayGainTrack =>
      _cadenasLocalizadas['np_replay_gain_track'] ?? '';
  String get npReplayGainAlbum =>
      _cadenasLocalizadas['np_replay_gain_album'] ?? '';
  String get npPreamp => _cadenasLocalizadas['np_preamp'] ?? '';
  String get npCrossfade => _cadenasLocalizadas['np_crossfade'] ?? '';
  String get npCrossfadeDuration =>
      _cadenasLocalizadas['np_crossfade_duration'] ?? '';
  String get npAudioDevices => _cadenasLocalizadas['np_audio_devices'] ?? '';
  String get npAudioDeviceDefault =>
      _cadenasLocalizadas['np_audio_device_default'] ?? '';
  String get npCrossfadeAuto => _cadenasLocalizadas['np_crossfade_auto'] ?? '';
  String get npCrossfadeManual =>
      _cadenasLocalizadas['np_crossfade_manual'] ?? '';
  String get npExclusiveAudio =>
      _cadenasLocalizadas['np_exclusive_audio'] ?? '';
  String get npFullscreen => _cadenasLocalizadas['np_fullscreen'] ?? '';
  String get npExitFullscreen =>
      _cadenasLocalizadas['np_exit_fullscreen'] ?? '';
  String get npVisualizer => _cadenasLocalizadas['np_visualizer'] ?? '';
  String get npBackgroundArtwork =>
      _cadenasLocalizadas['np_background_artwork'] ?? '';
  String get npBackgroundGradient =>
      _cadenasLocalizadas['np_background_gradient'] ?? '';
  String get npAddToPlaylist => _cadenasLocalizadas['np_add_to_playlist'] ?? '';
  String get npLike => _cadenasLocalizadas['np_like'] ?? '';
  String get npUnlike => _cadenasLocalizadas['np_unlike'] ?? '';
  String get npTechnicalInfo => _cadenasLocalizadas['np_technical_info'] ?? '';
  String get npBitrate => _cadenasLocalizadas['np_bitrate'] ?? '';
  String get npSampleRate => _cadenasLocalizadas['np_sample_rate'] ?? '';
  String get npChannels => _cadenasLocalizadas['np_channels'] ?? '';
  String get npFormat => _cadenasLocalizadas['np_format'] ?? '';

  // ---------------------------------------------------------------------------
  // tr_: Tracks Screen & Actions
  // ---------------------------------------------------------------------------
  String get trTitle => _cadenasLocalizadas['tr_title'] ?? '';
  String get trSearchHint => _cadenasLocalizadas['tr_search_hint'] ?? '';
  String get trPlay => _cadenasLocalizadas['tr_play'] ?? '';
  String get trPlayNext => _cadenasLocalizadas['tr_play_next'] ?? '';
  String get trAddQueue => _cadenasLocalizadas['tr_add_queue'] ?? '';
  String get trAddPlaylist => _cadenasLocalizadas['tr_add_playlist'] ?? '';
  String get trViewAlbum => _cadenasLocalizadas['tr_view_album'] ?? '';
  String get trViewArtist => _cadenasLocalizadas['tr_view_artist'] ?? '';
  String get trEditTags => _cadenasLocalizadas['tr_edit_tags'] ?? '';
  String get trFileInfo => _cadenasLocalizadas['tr_file_info'] ?? '';
  String get trShare => _cadenasLocalizadas['tr_share'] ?? '';
  String get trDelete => _cadenasLocalizadas['tr_delete'] ?? '';
  String get trDeleteConfirm => _cadenasLocalizadas['tr_delete_confirm'] ?? '';
  String get trDeletedSuccess =>
      _cadenasLocalizadas['tr_deleted_success'] ?? '';
  String get trNoTracks => _cadenasLocalizadas['tr_no_tracks'] ?? '';
  String get trNoTracksDesc => _cadenasLocalizadas['tr_no_tracks_desc'] ?? '';
  String get trLoadingTracks => _cadenasLocalizadas['tr_loading_tracks'] ?? '';
  String get trCount => _cadenasLocalizadas['tr_count'] ?? '';
  String get trSort => _cadenasLocalizadas['tr_sort'] ?? '';
  String get trSortTitle => _cadenasLocalizadas['tr_sort_title'] ?? '';
  String get trSortArtist => _cadenasLocalizadas['tr_sort_artist'] ?? '';
  String get trSortAlbum => _cadenasLocalizadas['tr_sort_album'] ?? '';
  String get trSortDateAdded => _cadenasLocalizadas['tr_sort_date_added'] ?? '';
  String get trSortDuration => _cadenasLocalizadas['tr_sort_duration'] ?? '';
  String get trSortAscending => _cadenasLocalizadas['tr_sort_ascending'] ?? '';
  String get trSortDescending =>
      _cadenasLocalizadas['tr_sort_descending'] ?? '';
  String get trFilePath => _cadenasLocalizadas['tr_file_path'] ?? '';
  String get trCodec => _cadenasLocalizadas['tr_codec'] ?? '';
  String get trFileSize => _cadenasLocalizadas['tr_file_size'] ?? '';
  String get trUnknownArtist => _cadenasLocalizadas['tr_unknown_artist'] ?? '';
  String get trAddedToPlaylist =>
      _cadenasLocalizadas['tr_added_to_playlist'] ?? '';
  String get trMoreActions => _cadenasLocalizadas['tr_more_actions'] ?? '';

  // ---------------------------------------------------------------------------
  // al_: Albums Screen & Detail
  // ---------------------------------------------------------------------------
  String get alTitle => _cadenasLocalizadas['al_title'] ?? '';
  String get alSearchHint => _cadenasLocalizadas['al_search_hint'] ?? '';
  String get alTracksCount => _cadenasLocalizadas['al_tracks_count'] ?? '';
  String get alReleaseYear => _cadenasLocalizadas['al_release_year'] ?? '';
  String get alPlayAll => _cadenasLocalizadas['al_play_all'] ?? '';
  String get alShuffleAll => _cadenasLocalizadas['al_shuffle_all'] ?? '';
  String get alAddQueue => _cadenasLocalizadas['al_add_queue'] ?? '';
  String get alAddPlaylist => _cadenasLocalizadas['al_add_playlist'] ?? '';
  String get alViewArtist => _cadenasLocalizadas['al_view_artist'] ?? '';
  String get alNoAlbums => _cadenasLocalizadas['al_no_albums'] ?? '';
  String get alNoAlbumsDesc => _cadenasLocalizadas['al_no_albums_desc'] ?? '';
  String get alSort => _cadenasLocalizadas['al_sort'] ?? '';
  String get alSortTitle => _cadenasLocalizadas['al_sort_title'] ?? '';
  String get alSortArtist => _cadenasLocalizadas['al_sort_artist'] ?? '';
  String get alSortYear => _cadenasLocalizadas['al_sort_year'] ?? '';
  String get alSortTrackCount =>
      _cadenasLocalizadas['al_sort_track_count'] ?? '';
  String get alTotalDuration => _cadenasLocalizadas['al_total_duration'] ?? '';

  // ---------------------------------------------------------------------------
  // ar_: Artists Screen & Discography
  // ---------------------------------------------------------------------------
  String get arTitle => _cadenasLocalizadas['ar_title'] ?? '';
  String get arSearchHint => _cadenasLocalizadas['ar_search_hint'] ?? '';
  String get arAlbumsCount => _cadenasLocalizadas['ar_albums_count'] ?? '';
  String get arTracksCount => _cadenasLocalizadas['ar_tracks_count'] ?? '';
  String get arPlayAll => _cadenasLocalizadas['ar_play_all'] ?? '';
  String get arShuffleAll => _cadenasLocalizadas['ar_shuffle_all'] ?? '';
  String get arDiscography => _cadenasLocalizadas['ar_discography'] ?? '';
  String get arAllTracks => _cadenasLocalizadas['ar_all_tracks'] ?? '';
  String get arBiography => _cadenasLocalizadas['ar_biography'] ?? '';
  String get arNoArtists => _cadenasLocalizadas['ar_no_artists'] ?? '';
  String get arNoArtistsDesc => _cadenasLocalizadas['ar_no_artists_desc'] ?? '';
  String get arSort => _cadenasLocalizadas['ar_sort'] ?? '';
  String get arSortName => _cadenasLocalizadas['ar_sort_name'] ?? '';
  String get arSortAlbums => _cadenasLocalizadas['ar_sort_albums'] ?? '';
  String get arSortTracks => _cadenasLocalizadas['ar_sort_tracks'] ?? '';

  // ---------------------------------------------------------------------------
  // pl_: Playlists Management
  // ---------------------------------------------------------------------------
  String get plTitle => _cadenasLocalizadas['pl_title'] ?? '';
  String get plCreateNew => _cadenasLocalizadas['pl_create_new'] ?? '';
  String get plNewNameHint => _cadenasLocalizadas['pl_new_name_hint'] ?? '';
  String get plCreateButton => _cadenasLocalizadas['pl_create_button'] ?? '';
  String get plCancelButton => _cadenasLocalizadas['pl_cancel_button'] ?? '';
  String get plDelete => _cadenasLocalizadas['pl_delete'] ?? '';
  String get plDeleteConfirm => _cadenasLocalizadas['pl_delete_confirm'] ?? '';
  String get plRename => _cadenasLocalizadas['pl_rename'] ?? '';
  String get plEdit => _cadenasLocalizadas['pl_edit'] ?? '';
  String get plEmpty => _cadenasLocalizadas['pl_empty'] ?? '';
  String get plEmptyDesc => _cadenasLocalizadas['pl_empty_desc'] ?? '';
  String get plAddTracks => _cadenasLocalizadas['pl_add_tracks'] ?? '';
  String get plRemoveTrack => _cadenasLocalizadas['pl_remove_track'] ?? '';
  String get plPlayAll => _cadenasLocalizadas['pl_play_all'] ?? '';
  String get plShuffleAll => _cadenasLocalizadas['pl_shuffle_all'] ?? '';
  String get plLikedSongs => _cadenasLocalizadas['pl_liked_songs'] ?? '';
  String get plHistory => _cadenasLocalizadas['pl_history'] ?? '';
  String get plRecentlyAdded => _cadenasLocalizadas['pl_recently_added'] ?? '';
  String get plTracksCount => _cadenasLocalizadas['pl_tracks_count'] ?? '';
  String get plReorderHint => _cadenasLocalizadas['pl_reorder_hint'] ?? '';
  String get plNoPlaylists => _cadenasLocalizadas['pl_no_playlists'] ?? '';

  // ---------------------------------------------------------------------------
  // g_: Genres Screen
  // ---------------------------------------------------------------------------
  String get gTitle => _cadenasLocalizadas['g_title'] ?? '';
  String get gSearchHint => _cadenasLocalizadas['g_search_hint'] ?? '';
  String get gUnknown => _cadenasLocalizadas['g_unknown'] ?? '';
  String get gTracksCount => _cadenasLocalizadas['g_tracks_count'] ?? '';
  String get gAlbumsCount => _cadenasLocalizadas['g_albums_count'] ?? '';
  String get gPlayAll => _cadenasLocalizadas['g_play_all'] ?? '';
  String get gShuffleAll => _cadenasLocalizadas['g_shuffle_all'] ?? '';
  String get gNoGenres => _cadenasLocalizadas['g_no_genres'] ?? '';
  String get gNoGenresDesc => _cadenasLocalizadas['g_no_genres_desc'] ?? '';

  // ---------------------------------------------------------------------------
  // f_: Folders & Filesystem Browser
  // ---------------------------------------------------------------------------
  String get fTitle => _cadenasLocalizadas['f_title'] ?? '';
  String get fNavigateUp => _cadenasLocalizadas['f_navigate_up'] ?? '';
  String get fCurrentFolder => _cadenasLocalizadas['f_current_folder'] ?? '';
  String get fEmptyFolder => _cadenasLocalizadas['f_empty_folder'] ?? '';
  String get fScanFolder => _cadenasLocalizadas['f_scan_folder'] ?? '';
  String get fAddToLibrary => _cadenasLocalizadas['f_add_to_library'] ?? '';
  String get fItemsCount => _cadenasLocalizadas['f_items_count'] ?? '';
  String get fInaccessible => _cadenasLocalizadas['f_inaccessible'] ?? '';
  String get fInaccessibleDesc =>
      _cadenasLocalizadas['f_inaccessible_desc'] ?? '';
  String get fBreadcrumbRoot => _cadenasLocalizadas['f_breadcrumb_root'] ?? '';
  String get fViewAsGrid => _cadenasLocalizadas['f_view_as_grid'] ?? '';
  String get fViewAsList => _cadenasLocalizadas['f_view_as_list'] ?? '';
  String get fRescanAll => _cadenasLocalizadas['f_rescan_all'] ?? '';

  // ---------------------------------------------------------------------------
  // sr_: Global Search
  // ---------------------------------------------------------------------------
  String get srTitle => _cadenasLocalizadas['sr_title'] ?? '';
  String get srHint => _cadenasLocalizadas['sr_hint'] ?? '';
  String get srFilterAll => _cadenasLocalizadas['sr_filter_all'] ?? '';
  String get srNoResults => _cadenasLocalizadas['sr_no_results'] ?? '';
  String get srNoResultsDesc => _cadenasLocalizadas['sr_no_results_desc'] ?? '';
  String get srTracksFound => _cadenasLocalizadas['sr_tracks_found'] ?? '';
  String get srAlbumsFound => _cadenasLocalizadas['sr_albums_found'] ?? '';
  String get srArtistsFound => _cadenasLocalizadas['sr_artists_found'] ?? '';
  String get srGenresFound => _cadenasLocalizadas['sr_genres_found'] ?? '';
  String get srPlaylistsFound =>
      _cadenasLocalizadas['sr_playlists_found'] ?? '';
  String get srViewMore => _cadenasLocalizadas['sr_view_more'] ?? '';
  String get srRecentSearches =>
      _cadenasLocalizadas['sr_recent_searches'] ?? '';
  String get srClearHistory => _cadenasLocalizadas['sr_clear_history'] ?? '';

  // ---------------------------------------------------------------------------
  // s_: Settings Screen
  // ---------------------------------------------------------------------------
  String get sTitle => _cadenasLocalizadas['s_title'] ?? '';
  String get sMusicFolders => _cadenasLocalizadas['s_music_folders'] ?? '';
  String get sMusicFoldersDesc =>
      _cadenasLocalizadas['s_music_folders_desc'] ?? '';
  String get sAddFolder => _cadenasLocalizadas['s_add_folder'] ?? '';
  String get sAddFolderTitle => _cadenasLocalizadas['s_add_folder_title'] ?? '';
  String get sFolderPathHint => _cadenasLocalizadas['s_folder_path_hint'] ?? '';
  String get sFolderPathLabel =>
      _cadenasLocalizadas['s_folder_path_label'] ?? '';
  String get sBrowseFolder => _cadenasLocalizadas['s_browse_folder'] ?? '';
  String get sFolderErrorInvalid =>
      _cadenasLocalizadas['s_folder_error_invalid'] ?? '';
  String get sNoFoldersYet => _cadenasLocalizadas['s_no_folders_yet'] ?? '';
  String get sBrowseFoldersDesc =>
      _cadenasLocalizadas['s_browse_folders_desc'] ?? '';
  String get sCancel => _cadenasLocalizadas['s_cancel'] ?? '';
  String get sAdd => _cadenasLocalizadas['s_add'] ?? '';
  String get sClear => _cadenasLocalizadas['s_clear'] ?? '';
  String get sTranslationTargetLang =>
      _cadenasLocalizadas['s_translation_target_lang'] ?? '';
  String get sTranslationTargetLangDesc =>
      _cadenasLocalizadas['s_translation_target_lang_desc'] ?? '';
  String get sTranslationLangDefault =>
      _cadenasLocalizadas['s_translation_lang_default'] ?? '';
  String get sAudioDevicesTitle =>
      _cadenasLocalizadas['s_audio_devices_title'] ?? '';
  String get sEqualizerTitle => _cadenasLocalizadas['s_equalizer_title'] ?? '';
  String get sEqualizerEnabled =>
      _cadenasLocalizadas['s_equalizer_enabled'] ?? '';
  String get sEqualizerPreset =>
      _cadenasLocalizadas['s_equalizer_preset'] ?? '';
  String get sEqPresetFlat => _cadenasLocalizadas['s_eq_preset_flat'] ?? '';
  String get sEqPresetRock => _cadenasLocalizadas['s_eq_preset_rock'] ?? '';
  String get sEqPresetPop => _cadenasLocalizadas['s_eq_preset_pop'] ?? '';
  String get sEqPresetJazz => _cadenasLocalizadas['s_eq_preset_jazz'] ?? '';
  String get sEqPresetClassical =>
      _cadenasLocalizadas['s_eq_preset_classical'] ?? '';
  String get sEqPresetBassBoost =>
      _cadenasLocalizadas['s_eq_preset_bass_boost'] ?? '';
  String get sEqPresetCustom => _cadenasLocalizadas['s_eq_preset_custom'] ?? '';
  String get sRemoveFolder => _cadenasLocalizadas['s_remove_folder'] ?? '';
  String get sRescanLibrary => _cadenasLocalizadas['s_rescan_library'] ?? '';
  String get sRescanLibraryDesc =>
      _cadenasLocalizadas['s_rescan_library_desc'] ?? '';
  String get sScanningProgress =>
      _cadenasLocalizadas['s_scanning_progress'] ?? '';
  String get sCleanMissingTracks =>
      _cadenasLocalizadas['s_clean_missing_tracks'] ?? '';
  String get sCleanMissingTracksDesc =>
      _cadenasLocalizadas['s_clean_missing_tracks_desc'] ?? '';
  String get sAudioSection => _cadenasLocalizadas['s_audio_section'] ?? '';
  String get sCrossfadeEnable =>
      _cadenasLocalizadas['s_crossfade_enable'] ?? '';
  String get sCrossfadeEnableDesc =>
      _cadenasLocalizadas['s_crossfade_enable_desc'] ?? '';
  String get sCrossfadeDuration =>
      _cadenasLocalizadas['s_crossfade_duration'] ?? '';
  String get sCrossfadeDurationDesc =>
      _cadenasLocalizadas['s_crossfade_duration_desc'] ?? '';
  String get sCrossfadeManualDuration =>
      _cadenasLocalizadas['s_crossfade_manual_duration'] ?? '';
  String get sCrossfadeManualDurationDesc =>
      _cadenasLocalizadas['s_crossfade_manual_duration_desc'] ?? '';
  String get sCrossfadeCurve => _cadenasLocalizadas['s_crossfade_curve'] ?? '';
  String get sCrossfadeCurveDesc =>
      _cadenasLocalizadas['s_crossfade_curve_desc'] ?? '';
  String get sCrossfadeCurveEqualPower =>
      _cadenasLocalizadas['s_crossfade_curve_equal_power'] ?? '';
  String get sCrossfadeCurveLinear =>
      _cadenasLocalizadas['s_crossfade_curve_linear'] ?? '';
  String get sAudioOutput => _cadenasLocalizadas['s_audio_output'] ?? '';
  String get sAudioOutputDesc =>
      _cadenasLocalizadas['s_audio_output_desc'] ?? '';
  String get sExclusiveAudio => _cadenasLocalizadas['s_exclusive_audio'] ?? '';
  String get sExclusiveAudioDesc =>
      _cadenasLocalizadas['s_exclusive_audio_desc'] ?? '';
  String get sReplayGainMode => _cadenasLocalizadas['s_replay_gain_mode'] ?? '';
  String get sReplayGainModeDesc =>
      _cadenasLocalizadas['s_replay_gain_mode_desc'] ?? '';
  String get sReplayGainPreamp =>
      _cadenasLocalizadas['s_replay_gain_preamp'] ?? '';
  String get sReplayGainPreampDesc =>
      _cadenasLocalizadas['s_replay_gain_preamp_desc'] ?? '';
  String get sGaplessPlayback =>
      _cadenasLocalizadas['s_gapless_playback'] ?? '';
  String get sGaplessPlaybackDesc =>
      _cadenasLocalizadas['s_gapless_playback_desc'] ?? '';
  String get sAppearanceSection =>
      _cadenasLocalizadas['s_appearance_section'] ?? '';
  String get sThemeMode => _cadenasLocalizadas['s_theme_mode'] ?? '';
  String get sThemeModeDesc => _cadenasLocalizadas['s_theme_mode_desc'] ?? '';
  String get sThemeSystem => _cadenasLocalizadas['s_theme_system'] ?? '';
  String get sThemeLight => _cadenasLocalizadas['s_theme_light'] ?? '';
  String get sThemeDark => _cadenasLocalizadas['s_theme_dark'] ?? '';
  String get sThemeOled => _cadenasLocalizadas['s_theme_oled'] ?? '';
  String get sThemeOledDesc => _cadenasLocalizadas['s_theme_oled_desc'] ?? '';
  String get sAccentColor => _cadenasLocalizadas['s_accent_color'] ?? '';
  String get sAccentColorDesc =>
      _cadenasLocalizadas['s_accent_color_desc'] ?? '';
  String get sDynamicColor => _cadenasLocalizadas['s_dynamic_color'] ?? '';
  String get sDynamicColorDesc =>
      _cadenasLocalizadas['s_dynamic_color_desc'] ?? '';
  String get sCustomBackground =>
      _cadenasLocalizadas['s_custom_background'] ?? '';
  String get sCustomBackgroundDesc =>
      _cadenasLocalizadas['s_custom_background_desc'] ?? '';
  String get sSelectBackgroundImage =>
      _cadenasLocalizadas['s_select_background_image'] ?? '';
  String get sChangeBackgroundImage =>
      _cadenasLocalizadas['s_change_background_image'] ?? '';
  String get sRemoveBackgroundImage =>
      _cadenasLocalizadas['s_remove_background_image'] ?? '';
  String get sBackgroundBlur => _cadenasLocalizadas['s_background_blur'] ?? '';
  String get sBackgroundBlurDesc =>
      _cadenasLocalizadas['s_background_blur_desc'] ?? '';
  String get sBackgroundDim => _cadenasLocalizadas['s_background_dim'] ?? '';
  String get sBackgroundDimDesc =>
      _cadenasLocalizadas['s_background_dim_desc'] ?? '';
  String get sCustomBackgroundFileError =>
      _cadenasLocalizadas['s_custom_background_file_error'] ?? '';
  String get sLanguageSection =>
      _cadenasLocalizadas['s_language_section'] ?? '';
  String get sLanguage => _cadenasLocalizadas['s_language'] ?? '';
  String get sLanguageDesc => _cadenasLocalizadas['s_language_desc'] ?? '';
  String get sLanguageSearchHint =>
      _cadenasLocalizadas['s_language_search_hint'] ?? '';
  String get sIntegrationsSection =>
      _cadenasLocalizadas['s_integrations_section'] ?? '';
  String get sDiscordRpc => _cadenasLocalizadas['s_discord_rpc'] ?? '';
  String get sDiscordRpcDesc => _cadenasLocalizadas['s_discord_rpc_desc'] ?? '';
  String get sMediaNotifications =>
      _cadenasLocalizadas['s_media_notifications'] ?? '';
  String get sMediaNotificationsDesc =>
      _cadenasLocalizadas['s_media_notifications_desc'] ?? '';
  String get sAboutSection => _cadenasLocalizadas['s_about_section'] ?? '';
  String get sAppVersion => _cadenasLocalizadas['s_app_version'] ?? '';
  String get sCheckUpdates => _cadenasLocalizadas['s_check_updates'] ?? '';
  String get sCheckUpdatesDesc =>
      _cadenasLocalizadas['s_check_updates_desc'] ?? '';
  String get sViewChangelog => _cadenasLocalizadas['s_view_changelog'] ?? '';
  String get sGithubRepo => _cadenasLocalizadas['s_github_repo'] ?? '';
  String get sLicense => _cadenasLocalizadas['s_license'] ?? '';
  String get sStorageUsed => _cadenasLocalizadas['s_storage_used'] ?? '';
  String get sClearCache => _cadenasLocalizadas['s_clear_cache'] ?? '';
  String get sClearCacheDesc => _cadenasLocalizadas['s_clear_cache_desc'] ?? '';
  String get sClearCacheSuccess =>
      _cadenasLocalizadas['s_clear_cache_success'] ?? '';

  // ---------------------------------------------------------------------------
  // up_: Software Updater
  // ---------------------------------------------------------------------------
  String get upTitle => _cadenasLocalizadas['up_title'] ?? '';
  String get upAvailable => _cadenasLocalizadas['up_available'] ?? '';
  String get upAvailableDesc => _cadenasLocalizadas['up_available_desc'] ?? '';
  String get upUpToDate => _cadenasLocalizadas['up_up_to_date'] ?? '';
  String get upChecking => _cadenasLocalizadas['up_checking'] ?? '';
  String get upCheckNow => _cadenasLocalizadas['up_check_now'] ?? '';
  String get upCurrentVersion =>
      _cadenasLocalizadas['up_current_version'] ?? '';
  String get upLatestVersion => _cadenasLocalizadas['up_latest_version'] ?? '';
  String get upDownloadButton =>
      _cadenasLocalizadas['up_download_button'] ?? '';
  String get upDownloading => _cadenasLocalizadas['up_downloading'] ?? '';
  String get upInstallButton => _cadenasLocalizadas['up_install_button'] ?? '';
  String get upDismiss => _cadenasLocalizadas['up_dismiss'] ?? '';
  String get upReleaseNotes => _cadenasLocalizadas['up_release_notes'] ?? '';
  String get upError => _cadenasLocalizadas['up_error'] ?? '';
  String get upErrorNetwork => _cadenasLocalizadas['up_error_network'] ?? '';

  // ---------------------------------------------------------------------------
  // cl_: Changelog Viewer
  // ---------------------------------------------------------------------------
  String get clTitle => _cadenasLocalizadas['cl_title'] ?? '';
  String get clClose => _cadenasLocalizadas['cl_close'] ?? '';
  String get clVersion => _cadenasLocalizadas['cl_version'] ?? '';
  String get clLatestChanges => _cadenasLocalizadas['cl_latest_changes'] ?? '';
  String get clErrorLoading => _cadenasLocalizadas['cl_error_loading'] ?? '';
  String get clViewOnGithub => _cadenasLocalizadas['cl_view_on_github'] ?? '';

  // ---------------------------------------------------------------------------
  // sel_: Multi-selection Toolbar
  // ---------------------------------------------------------------------------
  String get selSelectedCount =>
      _cadenasLocalizadas['sel_selected_count'] ?? '';
  String get selSelect => _cadenasLocalizadas['sel_select'] ?? '';
  String get selCancel => _cadenasLocalizadas['sel_cancel'] ?? '';
  String get selSelectAll => _cadenasLocalizadas['sel_select_all'] ?? '';
  String get selDeselectAll => _cadenasLocalizadas['sel_deselect_all'] ?? '';

  // ---------------------------------------------------------------------------
  // common_: Common UI Labels
  // ---------------------------------------------------------------------------
  String get commonViewAsCards =>
      _cadenasLocalizadas['common_view_as_cards'] ?? '';
  String get commonViewAsList =>
      _cadenasLocalizadas['common_view_as_list'] ?? '';
  String get commonBack => _cadenasLocalizadas['common_back'] ?? '';
  String get commonMinimize => _cadenasLocalizadas['common_minimize'] ?? '';

  // ---------------------------------------------------------------------------
  // scan_: Scan Progress Overlay
  // ---------------------------------------------------------------------------
  String get scanStageIdle => _cadenasLocalizadas['scan_stage_idle'] ?? '';
  String get scanStageGettingDatabase =>
      _cadenasLocalizadas['scan_stage_getting_database'] ?? '';
  String get scanStageGettingTracks =>
      _cadenasLocalizadas['scan_stage_getting_tracks'] ?? '';
  String get scanStageDiscovering =>
      _cadenasLocalizadas['scan_stage_discovering'] ?? '';
  String get scanStageComparing =>
      _cadenasLocalizadas['scan_stage_comparing'] ?? '';
  String get scanStageExtracting =>
      _cadenasLocalizadas['scan_stage_extracting'] ?? '';
  String get scanStageInserting =>
      _cadenasLocalizadas['scan_stage_inserting'] ?? '';
  String get scanStageCleaningOrphans =>
      _cadenasLocalizadas['scan_stage_cleaning_orphans'] ?? '';
  String get scanStageCleaningThumbnails =>
      _cadenasLocalizadas['scan_stage_cleaning_thumbnails'] ?? '';
  String get scanStageCompleted =>
      _cadenasLocalizadas['scan_stage_completed'] ?? '';
  String get scanStageFailed => _cadenasLocalizadas['scan_stage_failed'] ?? '';
  String get scanStageCancelled =>
      _cadenasLocalizadas['scan_stage_cancelled'] ?? '';
  String get scanCancelTooltip =>
      _cadenasLocalizadas['scan_cancel_tooltip'] ?? '';

  String scanStageText(ScanStage stage) {
    switch (stage) {
      case ScanStage.idle:
        return scanStageIdle;
      case ScanStage.gettingDatabase:
        return scanStageGettingDatabase;
      case ScanStage.gettingTracks:
        return scanStageGettingTracks;
      case ScanStage.discovering:
        return scanStageDiscovering;
      case ScanStage.comparing:
        return scanStageComparing;
      case ScanStage.extracting:
        return scanStageExtracting;
      case ScanStage.inserting:
        return scanStageInserting;
      case ScanStage.cleaningOrphans:
        return scanStageCleaningOrphans;
      case ScanStage.cleaningThumbnails:
        return scanStageCleaningThumbnails;
      case ScanStage.completed:
        return scanStageCompleted;
      case ScanStage.failed:
        return scanStageFailed;
      case ScanStage.cancelled:
        return scanStageCancelled;
    }
  }

  // ---------------------------------------------------------------------------
  // Parametric Formatters
  // ---------------------------------------------------------------------------
  String trCountFormatted(int count) =>
      trCount.replaceAll('{count}', count.toString());
  String trAddedToPlaylistFormatted(String name) =>
      trAddedToPlaylist.replaceAll('{name}', name);
  String selSelectedCountFormatted(int count) =>
      selSelectedCount.replaceAll('{count}', count.toString());
  String alTracksCountFormatted(int count) =>
      alTracksCount.replaceAll('{count}', count.toString());
  String arAlbumsCountFormatted(int count) =>
      arAlbumsCount.replaceAll('{count}', count.toString());
  String arTracksCountFormatted(int count) =>
      arTracksCount.replaceAll('{count}', count.toString());
  String plTracksCountFormatted(int count) =>
      plTracksCount.replaceAll('{count}', count.toString());
  String plDeleteConfirmFormatted(String name) =>
      plDeleteConfirm.replaceAll('{name}', name);
  String gTracksCountFormatted(int count) =>
      gTracksCount.replaceAll('{count}', count.toString());
  String gAlbumsCountFormatted(int count) =>
      gAlbumsCount.replaceAll('{count}', count.toString());
  String fItemsCountFormatted(int count) =>
      fItemsCount.replaceAll('{count}', count.toString());
  String srViewMoreFormatted(int count) =>
      srViewMore.replaceAll('{count}', count.toString());
  String sScanningProgressFormatted(int progress) =>
      sScanningProgress.replaceAll('{progress}', progress.toString());
  String upCurrentVersionFormatted(String version) =>
      upCurrentVersion.replaceAll('{version}', version);
  String upLatestVersionFormatted(String version) =>
      upLatestVersion.replaceAll('{version}', version);
  String upDownloadingFormatted(int progress) =>
      upDownloading.replaceAll('{progress}', progress.toString());
  String clVersionFormatted(String version) =>
      clVersion.replaceAll('{version}', version);
  String npLyricsThresholdWaitingFormatted(int seconds) =>
      npLyricsThresholdWaiting.replaceAll('{seconds}', seconds.toString());

  // ---------------------------------------------------------------------------
  // Registry Catalog
  // ---------------------------------------------------------------------------
  static const List<String> _allAppStrings = <String>[
    // np_
    'np_title', 'np_play', 'np_pause', 'np_previous', 'np_next', 'np_stop',
    'np_mute', 'np_unmute', 'np_volume', 'np_shuffle_off', 'np_shuffle_on',
    'np_repeat_off', 'np_repeat_all', 'np_repeat_one', 'np_elapsed',
    'np_remaining', 'np_duration', 'np_seek_forward', 'np_seek_backward',
    'np_queue', 'np_queue_clear', 'np_queue_clear_confirm',
    'np_queue_empty', 'np_queue_reorder',
    'np_lyrics', 'np_lyrics_empty', 'np_lyrics_sync', 'np_lyrics_unsync',
    'np_lyrics_translate',
    'np_lyrics_translating',
    'np_lyrics_translation_mode',
    'np_lyrics_original', 'np_lyrics_translated', 'np_lyrics_interleaved',
    'np_lyrics_sources', 'np_lyrics_research', 'np_lyrics_resume_sync',
    'np_lyrics_sources_title',
    'np_lyrics_source_local',
    'np_lyrics_source_local_desc',
    'np_lyrics_source_lrclib', 'np_lyrics_source_lrclib_desc',
    'np_lyrics_source_ovh', 'np_lyrics_source_ovh_desc',
    'np_lyrics_sources_research', 'np_lyrics_sources_research_btn',
    'np_lyrics_retranslate_btn',
    'np_lyrics_sources_close', 'np_lyrics_sources_close_btn',
    'np_lyrics_tab_sources', 'np_lyrics_tab_translation',
    'np_lyrics_source_lang', 'np_lyrics_target_lang',
    'np_lyrics_lang_auto', 'np_lyrics_rate_limit_error',
    'np_lyrics_threshold_waiting', 'np_lyrics_banner_dismiss',
    'np_lyrics_source_embedded',
    'np_lyrics_source_file',
    'np_lyrics_source_none',
    'np_lyrics_loading', 'np_lyrics_error', 'np_lyrics_translate_error',
    'np_audio_controls', 'np_speed', 'np_pitch', 'np_volume_boost',
    'np_replay_gain', 'np_replay_gain_off', 'np_replay_gain_track',
    'np_replay_gain_album',
    'np_preamp',
    'np_crossfade',
    'np_crossfade_duration',
    'np_audio_devices',
    'np_audio_device_default',
    'np_crossfade_auto',
    'np_crossfade_manual',
    'np_exclusive_audio',
    'np_fullscreen',
    'np_exit_fullscreen',
    'np_visualizer',
    'np_background_artwork', 'np_background_gradient', 'np_add_to_playlist',
    'np_like',
    'np_unlike',
    'np_technical_info',
    'np_bitrate',
    'np_sample_rate',
    'np_channels', 'np_format',
    // tr_
    'tr_title', 'tr_search_hint', 'tr_play', 'tr_play_next', 'tr_add_queue',
    'tr_add_playlist', 'tr_view_album', 'tr_view_artist', 'tr_edit_tags',
    'tr_file_info', 'tr_share', 'tr_delete', 'tr_delete_confirm',
    'tr_deleted_success',
    'tr_no_tracks',
    'tr_no_tracks_desc',
    'tr_loading_tracks',
    'tr_count',
    'tr_sort', 'tr_sort_title', 'tr_sort_artist', 'tr_sort_album',
    'tr_sort_date_added', 'tr_sort_duration', 'tr_sort_ascending',
    'tr_sort_descending', 'tr_file_path', 'tr_codec', 'tr_file_size',
    'tr_unknown_artist', 'tr_added_to_playlist','tr_more_actions',
    // al_
    'al_title', 'al_search_hint', 'al_tracks_count', 'al_release_year',
    'al_play_all', 'al_shuffle_all', 'al_add_queue', 'al_add_playlist',
    'al_view_artist', 'al_no_albums', 'al_no_albums_desc', 'al_sort',
    'al_sort_title', 'al_sort_artist', 'al_sort_year', 'al_sort_track_count',
    'al_total_duration',
    // ar_
    'ar_title', 'ar_search_hint', 'ar_albums_count', 'ar_tracks_count',
    'ar_play_all', 'ar_shuffle_all', 'ar_discography', 'ar_all_tracks',
    'ar_biography', 'ar_no_artists', 'ar_no_artists_desc', 'ar_sort',
    'ar_sort_name', 'ar_sort_albums', 'ar_sort_tracks',
    // pl_
    'pl_title', 'pl_create_new', 'pl_new_name_hint', 'pl_create_button',
    'pl_cancel_button', 'pl_delete', 'pl_delete_confirm', 'pl_rename',
    'pl_edit', 'pl_empty', 'pl_empty_desc', 'pl_add_tracks', 'pl_remove_track',
    'pl_play_all', 'pl_shuffle_all', 'pl_liked_songs', 'pl_history',
    'pl_recently_added',
    'pl_tracks_count',
    'pl_reorder_hint',
    'pl_no_playlists',
    // g_
    'g_title', 'g_search_hint', 'g_unknown', 'g_tracks_count', 'g_albums_count',
    'g_play_all', 'g_shuffle_all', 'g_no_genres', 'g_no_genres_desc',
    // f_
    'f_title', 'f_navigate_up', 'f_current_folder', 'f_empty_folder',
    'f_scan_folder', 'f_add_to_library', 'f_items_count', 'f_inaccessible',
    'f_inaccessible_desc', 'f_breadcrumb_root', 'f_view_as_grid',
    'f_view_as_list', 'f_rescan_all',
    // sr_
    'sr_title',
    'sr_hint',
    'sr_filter_all',
    'sr_no_results',
    'sr_no_results_desc',
    'sr_tracks_found', 'sr_albums_found', 'sr_artists_found', 'sr_genres_found',
    'sr_playlists_found',
    'sr_view_more',
    'sr_recent_searches',
    'sr_clear_history',
    // s_
    's_title', 's_music_folders', 's_music_folders_desc', 's_add_folder',
    's_add_folder_title', 's_folder_path_hint', 's_folder_path_label',
    's_browse_folder', 's_folder_error_invalid', 's_no_folders_yet',
    's_browse_folders_desc', 's_cancel', 's_add', 's_clear',
    's_translation_target_lang', 's_translation_target_lang_desc',
    's_translation_lang_default',
    's_audio_devices_title', 's_equalizer_title', 's_equalizer_enabled',
    's_equalizer_preset',
    's_eq_preset_flat', 's_eq_preset_rock', 's_eq_preset_pop',
    's_eq_preset_jazz', 's_eq_preset_classical', 's_eq_preset_bass_boost',
    's_eq_preset_custom',
    's_remove_folder', 's_rescan_library', 's_rescan_library_desc',
    's_scanning_progress',
    's_clean_missing_tracks',
    's_clean_missing_tracks_desc',
    's_audio_section', 's_crossfade_enable', 's_crossfade_enable_desc',
    's_crossfade_duration', 's_crossfade_duration_desc',
    's_crossfade_manual_duration', 's_crossfade_manual_duration_desc',
    's_crossfade_curve',
    's_crossfade_curve_desc',
    's_crossfade_curve_equal_power',
    's_crossfade_curve_linear',
    's_audio_output',
    's_audio_output_desc', 's_exclusive_audio', 's_exclusive_audio_desc',
    's_replay_gain_mode', 's_replay_gain_mode_desc', 's_replay_gain_preamp',
    's_replay_gain_preamp_desc',
    's_gapless_playback',
    's_gapless_playback_desc',
    's_appearance_section',
    's_theme_mode',
    's_theme_mode_desc',
    's_theme_system',
    's_theme_light', 's_theme_dark', 's_theme_oled', 's_theme_oled_desc',
    's_accent_color', 's_accent_color_desc', 's_dynamic_color',
    's_dynamic_color_desc', 's_custom_background', 's_custom_background_desc',
    's_select_background_image', 's_change_background_image',
    's_remove_background_image', 's_background_blur', 's_background_blur_desc',
    's_background_dim', 's_background_dim_desc',
    's_custom_background_file_error',
    's_language_section',
    's_language',
    's_language_desc',
    's_language_search_hint',
    's_integrations_section',
    's_discord_rpc', 's_discord_rpc_desc', 's_media_notifications',
    's_media_notifications_desc', 's_about_section', 's_app_version',
    's_check_updates', 's_check_updates_desc', 's_view_changelog',
    's_github_repo', 's_license', 's_storage_used', 's_clear_cache',
    's_clear_cache_desc', 's_clear_cache_success',
    // up_
    'up_title', 'up_available', 'up_available_desc', 'up_up_to_date',
    'up_checking', 'up_check_now', 'up_current_version', 'up_latest_version',
    'up_download_button', 'up_downloading', 'up_install_button', 'up_dismiss',
    'up_release_notes', 'up_error', 'up_error_network',
    // cl_
    'cl_title', 'cl_close', 'cl_version', 'cl_latest_changes',
    'cl_error_loading', 'cl_view_on_github',
    // sel_
    'sel_selected_count', 'sel_select', 'sel_cancel', 'sel_select_all',
    'sel_deselect_all',
    // common_
    'common_view_as_cards', 'common_view_as_list', 'common_back',
    'common_minimize',
    // scan_
    'scan_stage_idle', 'scan_stage_getting_database',
    'scan_stage_getting_tracks', 'scan_stage_discovering',
    'scan_stage_comparing', 'scan_stage_extracting',
    'scan_stage_inserting', 'scan_stage_cleaning_orphans',
    'scan_stage_cleaning_thumbnails', 'scan_stage_completed',
    'scan_stage_failed', 'scan_stage_cancelled', 'scan_cancel_tooltip',
  ];

  List<String> get allKeys => List.unmodifiable(_allAppStrings);

  Map<String, String> toJson() =>
      Map<String, String>.unmodifiable(_cadenasLocalizadas);

  Future<void> updateFromJson(
    Map<String, String> jsonData, {
    bool assertAllKeysPresent = false,
  }) async {
    if (_allAppStrings.any((key) => !jsonData.containsKey(key))) {
      final missingKeys = _allAppStrings
          .where((key) => !jsonData.containsKey(key))
          .toList();
      debugPrint('Missing localization keys: ${missingKeys.join(', ')}');
      if (assertAllKeysPresent) {
        throw FormatException(
          'Missing localization keys: ${missingKeys.join(', ')}',
        );
      }
    }
    _cadenasLocalizadas.addAll(jsonData);
  }
}
