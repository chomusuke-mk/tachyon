import 'package:flutter/foundation.dart';
import 'package:tachyon/core/metadata/domain/scan_progress.dart';

/// Central domain class managing localized string lookups for Tachyon.
///
/// Exposes strictly-typed camelCase getters for all keys cataloged in
/// `i18n/en.jsonc` and `i18n/es.jsonc`. All getters guarantee a null-safe
/// empty string fallback.
class AppStringKey {
  final Map<String, String> _localizedStrings = <String, String>{};

  // ---------------------------------------------------------------------------
  // np_: Now Playing & Transport Controls
  // ---------------------------------------------------------------------------
  String get npTitle => _localizedStrings['np_title'] ?? '';
  String get npPlay => _localizedStrings['np_play'] ?? '';
  String get npPause => _localizedStrings['np_pause'] ?? '';
  String get npPrevious => _localizedStrings['np_previous'] ?? '';
  String get npNext => _localizedStrings['np_next'] ?? '';
  String get npStop => _localizedStrings['np_stop'] ?? '';
  String get npMute => _localizedStrings['np_mute'] ?? '';
  String get npUnmute => _localizedStrings['np_unmute'] ?? '';
  String get npVolume => _localizedStrings['np_volume'] ?? '';
  String get npShuffleOff => _localizedStrings['np_shuffle_off'] ?? '';
  String get npShuffleOn => _localizedStrings['np_shuffle_on'] ?? '';
  String get npRepeatOff => _localizedStrings['np_repeat_off'] ?? '';
  String get npRepeatAll => _localizedStrings['np_repeat_all'] ?? '';
  String get npRepeatOne => _localizedStrings['np_repeat_one'] ?? '';
  String get npElapsed => _localizedStrings['np_elapsed'] ?? '';
  String get npRemaining => _localizedStrings['np_remaining'] ?? '';
  String get npDuration => _localizedStrings['np_duration'] ?? '';
  String get npSeekForward => _localizedStrings['np_seek_forward'] ?? '';
  String get npSeekBackward => _localizedStrings['np_seek_backward'] ?? '';
  String get npQueue => _localizedStrings['np_queue'] ?? '';
  String get npQueueClear => _localizedStrings['np_queue_clear'] ?? '';
  String get npQueueClearConfirm =>
      _localizedStrings['np_queue_clear_confirm'] ?? '';
  String get npQueueEmpty => _localizedStrings['np_queue_empty'] ?? '';
  String get npQueueReorder => _localizedStrings['np_queue_reorder'] ?? '';
  String get npQueueAddToPlaylist =>
      _localizedStrings['np_queue_add_to_playlist'] ?? '';
  String get npInfiniteMix =>
      _localizedStrings['np_infinite_mix'] ?? '';
  String get npLyrics => _localizedStrings['np_lyrics'] ?? '';
  String get npLyricsEmpty => _localizedStrings['np_lyrics_empty'] ?? '';
  String get npLyricsSync => _localizedStrings['np_lyrics_sync'] ?? '';
  String get npLyricsUnsync => _localizedStrings['np_lyrics_unsync'] ?? '';
  String get npLyricsTranslate =>
      _localizedStrings['np_lyrics_translate'] ?? '';
  String get npLyricsTranslating =>
      _localizedStrings['np_lyrics_translating'] ?? '';
  String get npLyricsTranslationMode =>
      _localizedStrings['np_lyrics_translation_mode'] ?? '';
  String get npLyricsOriginal =>
      _localizedStrings['np_lyrics_original'] ?? '';
  String get npLyricsTranslated =>
      _localizedStrings['np_lyrics_translated'] ?? '';
  String get npLyricsInterleaved =>
      _localizedStrings['np_lyrics_interleaved'] ?? '';
  String get npLyricsSources => _localizedStrings['np_lyrics_sources'] ?? '';
  String get npLyricsResearch =>
      _localizedStrings['np_lyrics_research'] ?? '';
  String get npLyricsResumeSync =>
      _localizedStrings['np_lyrics_resume_sync'] ?? '';
  String get npLyricsSourcesTitle =>
      _localizedStrings['np_lyrics_sources_title'] ?? '';
  String get npLyricsSourceLocal =>
      _localizedStrings['np_lyrics_source_local'] ?? '';
  String get npLyricsSourceLocalDesc =>
      _localizedStrings['np_lyrics_source_local_desc'] ?? '';
  String get npLyricsSourceLrclib =>
      _localizedStrings['np_lyrics_source_lrclib'] ?? '';
  String get npLyricsSourceLrclibDesc =>
      _localizedStrings['np_lyrics_source_lrclib_desc'] ?? '';
  String get npLyricsSourceOvh =>
      _localizedStrings['np_lyrics_source_ovh'] ?? '';
  String get npLyricsSourceOvhDesc =>
      _localizedStrings['np_lyrics_source_ovh_desc'] ?? '';
  String get npLyricsSourcesResearch =>
      _localizedStrings['np_lyrics_sources_research'] ?? '';
  String get npLyricsSourcesResearchBtn =>
      _localizedStrings['np_lyrics_sources_research_btn'] ?? '';
  String get npLyricsRetranslateBtn =>
      _localizedStrings['np_lyrics_retranslate_btn'] ?? '';
  String get npLyricsSourcesClose =>
      _localizedStrings['np_lyrics_sources_close'] ?? '';
  String get npLyricsSourcesCloseBtn =>
      _localizedStrings['np_lyrics_sources_close_btn'] ?? '';
  String get npLyricsTabSources =>
      _localizedStrings['np_lyrics_tab_sources'] ?? '';
  String get npLyricsTabTranslation =>
      _localizedStrings['np_lyrics_tab_translation'] ?? '';
  String get npLyricsSourceLang =>
      _localizedStrings['np_lyrics_source_lang'] ?? '';
  String get npLyricsTargetLang =>
      _localizedStrings['np_lyrics_target_lang'] ?? '';
  String get npLyricsLangAuto =>
      _localizedStrings['np_lyrics_lang_auto'] ?? '';
  String get npLyricsLangAutoTarget =>
      _localizedStrings['np_lyrics_lang_auto_target'] ?? '';
  String get npLyricsRateLimitError =>
      _localizedStrings['np_lyrics_rate_limit_error'] ?? '';
  String get npLyricsThresholdWaiting =>
      _localizedStrings['np_lyrics_threshold_waiting'] ?? '';
  String get npLyricsBannerDismiss =>
      _localizedStrings['np_lyrics_banner_dismiss'] ?? '';
  String get npLyricsSourceEmbedded =>
      _localizedStrings['np_lyrics_source_embedded'] ?? '';
  String get npLyricsSourceFile =>
      _localizedStrings['np_lyrics_source_file'] ?? '';
  String get npLyricsSourceNone =>
      _localizedStrings['np_lyrics_source_none'] ?? '';
  String get npLyricsLoading => _localizedStrings['np_lyrics_loading'] ?? '';
  String get npLyricsError => _localizedStrings['np_lyrics_error'] ?? '';
  String get npLyricsTranslateError =>
      _localizedStrings['np_lyrics_translate_error'] ?? '';
  String get npAudioControls => _localizedStrings['np_audio_controls'] ?? '';
  String get npSpeed => _localizedStrings['np_speed'] ?? '';
  String get npPitch => _localizedStrings['np_pitch'] ?? '';
  String get npVolumeBoost => _localizedStrings['np_volume_boost'] ?? '';
  String get npReplayGain => _localizedStrings['np_replay_gain'] ?? '';
  String get npReplayGainOff => _localizedStrings['np_replay_gain_off'] ?? '';
  String get npReplayGainTrack =>
      _localizedStrings['np_replay_gain_track'] ?? '';
  String get npReplayGainAlbum =>
      _localizedStrings['np_replay_gain_album'] ?? '';
  String get npPreamp => _localizedStrings['np_preamp'] ?? '';
  String get npCrossfade => _localizedStrings['np_crossfade'] ?? '';
  String get npCrossfadeDuration =>
      _localizedStrings['np_crossfade_duration'] ?? '';
  String get npAudioDevices => _localizedStrings['np_audio_devices'] ?? '';
  String get npAudioDeviceDefault =>
      _localizedStrings['np_audio_device_default'] ?? '';
  String get npCrossfadeAuto => _localizedStrings['np_crossfade_auto'] ?? '';
  String get npCrossfadeManual =>
      _localizedStrings['np_crossfade_manual'] ?? '';
  String get npExclusiveAudio =>
      _localizedStrings['np_exclusive_audio'] ?? '';
  String get npFullscreen => _localizedStrings['np_fullscreen'] ?? '';
  String get npExitFullscreen =>
      _localizedStrings['np_exit_fullscreen'] ?? '';
  String get npVisualizer => _localizedStrings['np_visualizer'] ?? '';
  String get npBackgroundArtwork =>
      _localizedStrings['np_background_artwork'] ?? '';
  String get npBackgroundGradient =>
      _localizedStrings['np_background_gradient'] ?? '';
  String get npAddToPlaylist => _localizedStrings['np_add_to_playlist'] ?? '';
  String get npLike => _localizedStrings['np_like'] ?? '';
  String get npUnlike => _localizedStrings['np_unlike'] ?? '';
  String get npTechnicalInfo => _localizedStrings['np_technical_info'] ?? '';
  String get npBitrate => _localizedStrings['np_bitrate'] ?? '';
  String get npSampleRate => _localizedStrings['np_sample_rate'] ?? '';
  String get npChannels => _localizedStrings['np_channels'] ?? '';
  String get npFormat => _localizedStrings['np_format'] ?? '';

  // ---------------------------------------------------------------------------
  // tr_: Tracks Screen & Actions
  // ---------------------------------------------------------------------------
  String get trTitle => _localizedStrings['tr_title'] ?? '';
  String get trSearchHint => _localizedStrings['tr_search_hint'] ?? '';
  String get trPlay => _localizedStrings['tr_play'] ?? '';
  String get trPlayNext => _localizedStrings['tr_play_next'] ?? '';
  String get trAddQueue => _localizedStrings['tr_add_queue'] ?? '';
  String get trAddPlaylist => _localizedStrings['tr_add_playlist'] ?? '';
  String get trViewAlbum => _localizedStrings['tr_view_album'] ?? '';
  String get trViewArtist => _localizedStrings['tr_view_artist'] ?? '';
  String get trEditTags => _localizedStrings['tr_edit_tags'] ?? '';
  String get trFileInfo => _localizedStrings['tr_file_info'] ?? '';
  String get trShare => _localizedStrings['tr_share'] ?? '';
  String get trDelete => _localizedStrings['tr_delete'] ?? '';
  String get trDeleteConfirm => _localizedStrings['tr_delete_confirm'] ?? '';
  String get trDeletedSuccess =>
      _localizedStrings['tr_deleted_success'] ?? '';
  String get trNoTracks => _localizedStrings['tr_no_tracks'] ?? '';
  String get trNoTracksDesc => _localizedStrings['tr_no_tracks_desc'] ?? '';
  String get trLoadingTracks => _localizedStrings['tr_loading_tracks'] ?? '';
  String get trCount => _localizedStrings['tr_count'] ?? '';
  String get trSort => _localizedStrings['tr_sort'] ?? '';
  String get trSortTitle => _localizedStrings['tr_sort_title'] ?? '';
  String get trSortArtist => _localizedStrings['tr_sort_artist'] ?? '';
  String get trSortAlbum => _localizedStrings['tr_sort_album'] ?? '';
  String get trSortDateAdded => _localizedStrings['tr_sort_date_added'] ?? '';
  String get trSortDuration => _localizedStrings['tr_sort_duration'] ?? '';
  String get trSortAscending => _localizedStrings['tr_sort_ascending'] ?? '';
  String get trSortDescending =>
      _localizedStrings['tr_sort_descending'] ?? '';
  String get trFilePath => _localizedStrings['tr_file_path'] ?? '';
  String get trCodec => _localizedStrings['tr_codec'] ?? '';
  String get trFileSize => _localizedStrings['tr_file_size'] ?? '';
  String get trUnknownArtist => _localizedStrings['tr_unknown_artist'] ?? '';
  String get trAddedToPlaylist =>
      _localizedStrings['tr_added_to_playlist'] ?? '';
  String get trMoreActions => _localizedStrings['tr_more_actions'] ?? '';
  String get trShuffleAll => _localizedStrings['tr_shuffle_all'] ?? '';

  // ---------------------------------------------------------------------------
  // al_: Albums Screen & Detail
  // ---------------------------------------------------------------------------
  String get alTitle => _localizedStrings['al_title'] ?? '';
  String get alSearchHint => _localizedStrings['al_search_hint'] ?? '';
  String get alTracksCount => _localizedStrings['al_tracks_count'] ?? '';
  String get alReleaseYear => _localizedStrings['al_release_year'] ?? '';
  String get alPlayAll => _localizedStrings['al_play_all'] ?? '';
  String get alShuffleAll => _localizedStrings['al_shuffle_all'] ?? '';
  String get alAddQueue => _localizedStrings['al_add_queue'] ?? '';
  String get alAddPlaylist => _localizedStrings['al_add_playlist'] ?? '';
  String get alViewArtist => _localizedStrings['al_view_artist'] ?? '';
  String get alNoAlbums => _localizedStrings['al_no_albums'] ?? '';
  String get alNoAlbumsDesc => _localizedStrings['al_no_albums_desc'] ?? '';
  String get alSort => _localizedStrings['al_sort'] ?? '';
  String get alSortTitle => _localizedStrings['al_sort_title'] ?? '';
  String get alSortArtist => _localizedStrings['al_sort_artist'] ?? '';
  String get alSortYear => _localizedStrings['al_sort_year'] ?? '';
  String get alSortTrackCount =>
      _localizedStrings['al_sort_track_count'] ?? '';
  String get alTotalDuration => _localizedStrings['al_total_duration'] ?? '';

  // ---------------------------------------------------------------------------
  // ar_: Artists Screen & Discography
  // ---------------------------------------------------------------------------
  String get arTitle => _localizedStrings['ar_title'] ?? '';
  String get arSearchHint => _localizedStrings['ar_search_hint'] ?? '';
  String get arAlbumsCount => _localizedStrings['ar_albums_count'] ?? '';
  String get arTracksCount => _localizedStrings['ar_tracks_count'] ?? '';
  String get arPlayAll => _localizedStrings['ar_play_all'] ?? '';
  String get arShuffleAll => _localizedStrings['ar_shuffle_all'] ?? '';
  String get arDiscography => _localizedStrings['ar_discography'] ?? '';
  String get arAllTracks => _localizedStrings['ar_all_tracks'] ?? '';
  String get arBiography => _localizedStrings['ar_biography'] ?? '';
  String get arNoArtists => _localizedStrings['ar_no_artists'] ?? '';
  String get arNoArtistsDesc => _localizedStrings['ar_no_artists_desc'] ?? '';
  String get arSort => _localizedStrings['ar_sort'] ?? '';
  String get arSortName => _localizedStrings['ar_sort_name'] ?? '';
  String get arSortAlbums => _localizedStrings['ar_sort_albums'] ?? '';
  String get arSortTracks => _localizedStrings['ar_sort_tracks'] ?? '';

  // ---------------------------------------------------------------------------
  // pl_: Playlists Management
  // ---------------------------------------------------------------------------
  String get plTitle => _localizedStrings['pl_title'] ?? '';
  String get plCreateNew => _localizedStrings['pl_create_new'] ?? '';
  String get plNewNameHint => _localizedStrings['pl_new_name_hint'] ?? '';
  String get plCreateButton => _localizedStrings['pl_create_button'] ?? '';
  String get plCancelButton => _localizedStrings['pl_cancel_button'] ?? '';
  String get plDelete => _localizedStrings['pl_delete'] ?? '';
  String get plDeleteConfirm => _localizedStrings['pl_delete_confirm'] ?? '';
  String get plRename => _localizedStrings['pl_rename'] ?? '';
  String get plEdit => _localizedStrings['pl_edit'] ?? '';
  String get plEmpty => _localizedStrings['pl_empty'] ?? '';
  String get plEmptyDesc => _localizedStrings['pl_empty_desc'] ?? '';
  String get plAddTracks => _localizedStrings['pl_add_tracks'] ?? '';
  String get plRemoveTrack => _localizedStrings['pl_remove_track'] ?? '';
  String get plPlayAll => _localizedStrings['pl_play_all'] ?? '';
  String get plShuffleAll => _localizedStrings['pl_shuffle_all'] ?? '';
  String get plLikedSongs => _localizedStrings['pl_liked_songs'] ?? '';
  String get plHistory => _localizedStrings['pl_history'] ?? '';
  String get plRecentlyAdded => _localizedStrings['pl_recently_added'] ?? '';
  String get plTracksCount => _localizedStrings['pl_tracks_count'] ?? '';
  String get plReorderHint => _localizedStrings['pl_reorder_hint'] ?? '';
  String get plNoPlaylists => _localizedStrings['pl_no_playlists'] ?? '';
  String get plDuplicateTitle =>
      _localizedStrings['pl_duplicate_title'] ?? '';
  String get plDuplicateConfirm =>
      _localizedStrings['pl_duplicate_confirm'] ?? '';
  String get plAddAnyway => _localizedStrings['pl_add_anyway'] ?? '';
  String get plDuplicateQueueTitle =>
      _localizedStrings['pl_duplicate_queue_title'] ?? '';
  String get plDuplicateQueueConfirm =>
      _localizedStrings['pl_duplicate_queue_confirm'] ?? '';
  String get plInsertOnlyNew =>
      _localizedStrings['pl_insert_only_new'] ?? '';

  // ---------------------------------------------------------------------------
  // g_: Genres Screen
  // ---------------------------------------------------------------------------
  String get gTitle => _localizedStrings['g_title'] ?? '';
  String get gSearchHint => _localizedStrings['g_search_hint'] ?? '';
  String get gUnknown => _localizedStrings['g_unknown'] ?? '';
  String get gTracksCount => _localizedStrings['g_tracks_count'] ?? '';
  String get gAlbumsCount => _localizedStrings['g_albums_count'] ?? '';
  String get gPlayAll => _localizedStrings['g_play_all'] ?? '';
  String get gShuffleAll => _localizedStrings['g_shuffle_all'] ?? '';
  String get gNoGenres => _localizedStrings['g_no_genres'] ?? '';
  String get gNoGenresDesc => _localizedStrings['g_no_genres_desc'] ?? '';

  // ---------------------------------------------------------------------------
  // perm_: Permissions Screen
  // ---------------------------------------------------------------------------
  String get permTitle => _localizedStrings['perm_title'] ?? '';
  String get permSubtitle => _localizedStrings['perm_subtitle'] ?? '';
  String get permMusicTitle => _localizedStrings['perm_music_title'] ?? '';
  String get permMusicDesc => _localizedStrings['perm_music_desc'] ?? '';
  String get permGranted => _localizedStrings['perm_granted'] ?? '';
  String get permGrantAccess => _localizedStrings['perm_grant_access'] ?? '';
  String get permOpenSettings =>
      _localizedStrings['perm_open_settings'] ?? '';
  String get permDeniedHint => _localizedStrings['perm_denied_hint'] ?? '';
  String get permContinue => _localizedStrings['perm_continue'] ?? '';


  // ---------------------------------------------------------------------------
  // f_: Folders & Filesystem Browser
  // ---------------------------------------------------------------------------
  String get fTitle => _localizedStrings['f_title'] ?? '';
  String get fNavigateUp => _localizedStrings['f_navigate_up'] ?? '';
  String get fCurrentFolder => _localizedStrings['f_current_folder'] ?? '';
  String get fEmptyFolder => _localizedStrings['f_empty_folder'] ?? '';
  String get fScanFolder => _localizedStrings['f_scan_folder'] ?? '';
  String get fAddToLibrary => _localizedStrings['f_add_to_library'] ?? '';
  String get fItemsCount => _localizedStrings['f_items_count'] ?? '';
  String get fInaccessible => _localizedStrings['f_inaccessible'] ?? '';
  String get fInaccessibleDesc =>
      _localizedStrings['f_inaccessible_desc'] ?? '';
  String get fBreadcrumbRoot => _localizedStrings['f_breadcrumb_root'] ?? '';
  String get fViewAsGrid => _localizedStrings['f_view_as_grid'] ?? '';
  String get fViewAsList => _localizedStrings['f_view_as_list'] ?? '';
  String get fRescanAll => _localizedStrings['f_rescan_all'] ?? '';

  // ---------------------------------------------------------------------------
  // sr_: Global Search
  // ---------------------------------------------------------------------------
  String get srTitle => _localizedStrings['sr_title'] ?? '';
  String get srHint => _localizedStrings['sr_hint'] ?? '';
  String get srFilterAll => _localizedStrings['sr_filter_all'] ?? '';
  String get srNoResults => _localizedStrings['sr_no_results'] ?? '';
  String get srNoResultsDesc => _localizedStrings['sr_no_results_desc'] ?? '';
  String get srTracksFound => _localizedStrings['sr_tracks_found'] ?? '';
  String get srAlbumsFound => _localizedStrings['sr_albums_found'] ?? '';
  String get srArtistsFound => _localizedStrings['sr_artists_found'] ?? '';
  String get srGenresFound => _localizedStrings['sr_genres_found'] ?? '';
  String get srPlaylistsFound =>
      _localizedStrings['sr_playlists_found'] ?? '';
  String get srViewMore => _localizedStrings['sr_view_more'] ?? '';
  String get srRecentSearches =>
      _localizedStrings['sr_recent_searches'] ?? '';
  String get srClearHistory => _localizedStrings['sr_clear_history'] ?? '';

  // ---------------------------------------------------------------------------
  // s_: Settings Screen
  // ---------------------------------------------------------------------------
  String get sTitle => _localizedStrings['s_title'] ?? '';
  String get sMusicFolders => _localizedStrings['s_music_folders'] ?? '';
  String get sMusicFoldersDesc =>
      _localizedStrings['s_music_folders_desc'] ?? '';
  String get sAddFolder => _localizedStrings['s_add_folder'] ?? '';
  String get sAddFolderTitle => _localizedStrings['s_add_folder_title'] ?? '';
  String get sFolderPathHint => _localizedStrings['s_folder_path_hint'] ?? '';
  String get sFolderPathLabel =>
      _localizedStrings['s_folder_path_label'] ?? '';
  String get sBrowseFolder => _localizedStrings['s_browse_folder'] ?? '';
  String get sFolderErrorInvalid =>
      _localizedStrings['s_folder_error_invalid'] ?? '';
  String get sNoFoldersYet => _localizedStrings['s_no_folders_yet'] ?? '';
  String get sBrowseFoldersDesc =>
      _localizedStrings['s_browse_folders_desc'] ?? '';
  String get sCancel => _localizedStrings['s_cancel'] ?? '';
  String get sAdd => _localizedStrings['s_add'] ?? '';
  String get sClear => _localizedStrings['s_clear'] ?? '';
  String get sTranslationTargetLang =>
      _localizedStrings['s_translation_target_lang'] ?? '';
  String get sTranslationTargetLangDesc =>
      _localizedStrings['s_translation_target_lang_desc'] ?? '';
  String get sTranslationLangDefault =>
      _localizedStrings['s_translation_lang_default'] ?? '';
  String get sAudioDevicesTitle =>
      _localizedStrings['s_audio_devices_title'] ?? '';
  String get sEqualizerTitle => _localizedStrings['s_equalizer_title'] ?? '';
  String get sEqualizerEnabled =>
      _localizedStrings['s_equalizer_enabled'] ?? '';
  String get sEqualizerPreset =>
      _localizedStrings['s_equalizer_preset'] ?? '';
  String get sEqPresetFlat => _localizedStrings['s_eq_preset_flat'] ?? '';
  String get sEqPresetRock => _localizedStrings['s_eq_preset_rock'] ?? '';
  String get sEqPresetPop => _localizedStrings['s_eq_preset_pop'] ?? '';
  String get sEqPresetJazz => _localizedStrings['s_eq_preset_jazz'] ?? '';
  String get sEqPresetClassical =>
      _localizedStrings['s_eq_preset_classical'] ?? '';
  String get sEqPresetBassBoost =>
      _localizedStrings['s_eq_preset_bass_boost'] ?? '';
  String get sEqPresetCustom => _localizedStrings['s_eq_preset_custom'] ?? '';
  String get sRemoveFolder => _localizedStrings['s_remove_folder'] ?? '';
  String get sRescanLibrary => _localizedStrings['s_rescan_library'] ?? '';
  String get sRescanLibraryDesc =>
      _localizedStrings['s_rescan_library_desc'] ?? '';
  String get sScanningProgress =>
      _localizedStrings['s_scanning_progress'] ?? '';
  String get sCleanMissingTracks =>
      _localizedStrings['s_clean_missing_tracks'] ?? '';
  String get sCleanMissingTracksDesc =>
      _localizedStrings['s_clean_missing_tracks_desc'] ?? '';
  String get sAudioSection => _localizedStrings['s_audio_section'] ?? '';
  String get sCrossfadeEnable =>
      _localizedStrings['s_crossfade_enable'] ?? '';
  String get sCrossfadeEnableDesc =>
      _localizedStrings['s_crossfade_enable_desc'] ?? '';
  String get sCrossfadeDuration =>
      _localizedStrings['s_crossfade_duration'] ?? '';
  String get sCrossfadeDurationDesc =>
      _localizedStrings['s_crossfade_duration_desc'] ?? '';
  String get sCrossfadeManualDuration =>
      _localizedStrings['s_crossfade_manual_duration'] ?? '';
  String get sCrossfadeManualDurationDesc =>
      _localizedStrings['s_crossfade_manual_duration_desc'] ?? '';
  String get sCrossfadeCurve => _localizedStrings['s_crossfade_curve'] ?? '';
  String get sCrossfadeCurveDesc =>
      _localizedStrings['s_crossfade_curve_desc'] ?? '';
  String get sCrossfadeCurveEqualPower =>
      _localizedStrings['s_crossfade_curve_equal_power'] ?? '';
  String get sCrossfadeCurveLinear =>
      _localizedStrings['s_crossfade_curve_linear'] ?? '';
  String get sAudioOutput => _localizedStrings['s_audio_output'] ?? '';
  String get sAudioOutputDesc =>
      _localizedStrings['s_audio_output_desc'] ?? '';
  String get sExclusiveAudio => _localizedStrings['s_exclusive_audio'] ?? '';
  String get sExclusiveAudioDesc =>
      _localizedStrings['s_exclusive_audio_desc'] ?? '';
  String get sPauseOnDeviceChange =>
      _localizedStrings['s_pause_on_device_change'] ?? '';
  String get sPauseOnDeviceChangeDesc =>
      _localizedStrings['s_pause_on_device_change_desc'] ?? '';
  String get sReplayGainMode => _localizedStrings['s_replay_gain_mode'] ?? '';
  String get sReplayGainModeDesc =>
      _localizedStrings['s_replay_gain_mode_desc'] ?? '';
  String get sReplayGainPreamp =>
      _localizedStrings['s_replay_gain_preamp'] ?? '';
  String get sReplayGainPreampDesc =>
      _localizedStrings['s_replay_gain_preamp_desc'] ?? '';
  String get sGaplessPlayback =>
      _localizedStrings['s_gapless_playback'] ?? '';
  String get sGaplessPlaybackDesc =>
      _localizedStrings['s_gapless_playback_desc'] ?? '';
  String get sSkipSilence => _localizedStrings['s_skip_silence'] ?? '';
  String get sSkipSilenceDesc =>
      _localizedStrings['s_skip_silence_desc'] ?? '';
  String get sPreamp => _localizedStrings['s_preamp'] ?? '';
  String get sPreampDesc => _localizedStrings['s_preamp_desc'] ?? '';
  String get sStereoBalance => _localizedStrings['s_stereo_balance'] ?? '';
  String get sStereoBalanceDesc =>
      _localizedStrings['s_stereo_balance_desc'] ?? '';
  String get sStereoBalanceCenter =>
      _localizedStrings['s_stereo_balance_center'] ?? '';
  String get sMonoAudio => _localizedStrings['s_mono_audio'] ?? '';
  String get sMonoAudioDesc => _localizedStrings['s_mono_audio_desc'] ?? '';
  String get sCrossfeed => _localizedStrings['s_crossfeed'] ?? '';
  String get sCrossfeedDesc => _localizedStrings['s_crossfeed_desc'] ?? '';
  String get sCrossfeedOff => _localizedStrings['s_crossfeed_off'] ?? '';
  String get sCrossfeedMoffat =>
      _localizedStrings['s_crossfeed_moffat'] ?? '';
  String get sCrossfeedChumoy =>
      _localizedStrings['s_crossfeed_chumoy'] ?? '';
  String get sSpatializer => _localizedStrings['s_spatializer'] ?? '';
  String get sSpatializerDesc =>
      _localizedStrings['s_spatializer_desc'] ?? '';
  String get sLimiter => _localizedStrings['s_limiter'] ?? '';
  String get sLimiterDesc => _localizedStrings['s_limiter_desc'] ?? '';
  String get sReverb => _localizedStrings['s_reverb'] ?? '';
  String get sReverbDesc => _localizedStrings['s_reverb_desc'] ?? '';
  String get sReverbPreset => _localizedStrings['s_reverb_preset'] ?? '';
  String get sReverbPresetOff =>
      _localizedStrings['s_reverb_preset_off'] ?? '';
  String get sReverbPresetSmallRoom =>
      _localizedStrings['s_reverb_preset_small_room'] ?? '';
  String get sReverbPresetStudio =>
      _localizedStrings['s_reverb_preset_studio'] ?? '';
  String get sReverbPresetConcertHall =>
      _localizedStrings['s_reverb_preset_concert_hall'] ?? '';
  String get sReverbPresetCathedral =>
      _localizedStrings['s_reverb_preset_cathedral'] ?? '';
  String get sReverbPresetPlate =>
      _localizedStrings['s_reverb_preset_plate'] ?? '';
  String get sReverbPresetAmbient =>
      _localizedStrings['s_reverb_preset_ambient'] ?? '';
  String get sReverbPresetCustom =>
      _localizedStrings['s_reverb_preset_custom'] ?? '';
  String get sReverbRoomSize => _localizedStrings['s_reverb_room_size'] ?? '';
  String get sReverbDamping => _localizedStrings['s_reverb_damping'] ?? '';
  String get sReverbWidth => _localizedStrings['s_reverb_width'] ?? '';
  String get sReverbWet => _localizedStrings['s_reverb_wet'] ?? '';
  String get sReverbDry => _localizedStrings['s_reverb_dry'] ?? '';
  String get sAudioDspSection =>
      _localizedStrings['s_audio_dsp_section'] ?? '';
  String get sAppearanceSection =>
      _localizedStrings['s_appearance_section'] ?? '';
  String get sThemeMode => _localizedStrings['s_theme_mode'] ?? '';
  String get sThemeModeDesc => _localizedStrings['s_theme_mode_desc'] ?? '';
  String get sThemeSystem => _localizedStrings['s_theme_system'] ?? '';
  String get sThemeLight => _localizedStrings['s_theme_light'] ?? '';
  String get sThemeDark => _localizedStrings['s_theme_dark'] ?? '';
  String get sThemeOled => _localizedStrings['s_theme_oled'] ?? '';
  String get sThemeOledDesc => _localizedStrings['s_theme_oled_desc'] ?? '';
  String get sAccentColor => _localizedStrings['s_accent_color'] ?? '';
  String get sAccentColorDesc =>
      _localizedStrings['s_accent_color_desc'] ?? '';
  String get sDynamicColor => _localizedStrings['s_dynamic_color'] ?? '';
  String get sDynamicColorDesc =>
      _localizedStrings['s_dynamic_color_desc'] ?? '';
  String get sCustomBackground =>
      _localizedStrings['s_custom_background'] ?? '';
  String get sCustomBackgroundDesc =>
      _localizedStrings['s_custom_background_desc'] ?? '';
  String get sSelectBackgroundImage =>
      _localizedStrings['s_select_background_image'] ?? '';
  String get sChangeBackgroundImage =>
      _localizedStrings['s_change_background_image'] ?? '';
  String get sRemoveBackgroundImage =>
      _localizedStrings['s_remove_background_image'] ?? '';
  String get sBackgroundBlur => _localizedStrings['s_background_blur'] ?? '';
  String get sBackgroundBlurDesc =>
      _localizedStrings['s_background_blur_desc'] ?? '';
  String get sBackgroundDim => _localizedStrings['s_background_dim'] ?? '';
  String get sBackgroundDimDesc =>
      _localizedStrings['s_background_dim_desc'] ?? '';
  String get sCustomBackgroundFileError =>
      _localizedStrings['s_custom_background_file_error'] ?? '';
  String get sLanguageSection =>
      _localizedStrings['s_language_section'] ?? '';
  String get sLanguage => _localizedStrings['s_language'] ?? '';
  String get sLanguageDesc => _localizedStrings['s_language_desc'] ?? '';
  String get sLanguageSearchHint =>
      _localizedStrings['s_language_search_hint'] ?? '';
  String get sIntegrationsSection =>
      _localizedStrings['s_integrations_section'] ?? '';
  String get sDiscordRpc => _localizedStrings['s_discord_rpc'] ?? '';
  String get sDiscordRpcDesc => _localizedStrings['s_discord_rpc_desc'] ?? '';
  String get sMediaNotifications =>
      _localizedStrings['s_media_notifications'] ?? '';
  String get sMediaNotificationsDesc =>
      _localizedStrings['s_media_notifications_desc'] ?? '';
  String get sAboutSection => _localizedStrings['s_about_section'] ?? '';
  String get sAppVersion => _localizedStrings['s_app_version'] ?? '';
  String get sCheckUpdates => _localizedStrings['s_check_updates'] ?? '';
  String get sCheckUpdatesDesc =>
      _localizedStrings['s_check_updates_desc'] ?? '';
  String get sViewChangelog => _localizedStrings['s_view_changelog'] ?? '';
  String get sGithubRepo => _localizedStrings['s_github_repo'] ?? '';
  String get sLicense => _localizedStrings['s_license'] ?? '';
  String get sStorageUsed => _localizedStrings['s_storage_used'] ?? '';
  String get sClearCache => _localizedStrings['s_clear_cache'] ?? '';
  String get sClearCacheDesc => _localizedStrings['s_clear_cache_desc'] ?? '';
  String get sClearCacheSuccess =>
      _localizedStrings['s_clear_cache_success'] ?? '';

  // ---------------------------------------------------------------------------
  // up_: Software Updater
  // ---------------------------------------------------------------------------
  String get upTitle => _localizedStrings['up_title'] ?? '';
  String get upAvailable => _localizedStrings['up_available'] ?? '';
  String get upAvailableDesc => _localizedStrings['up_available_desc'] ?? '';
  String get upUpToDate => _localizedStrings['up_up_to_date'] ?? '';
  String get upChecking => _localizedStrings['up_checking'] ?? '';
  String get upCheckNow => _localizedStrings['up_check_now'] ?? '';
  String get upCurrentVersion =>
      _localizedStrings['up_current_version'] ?? '';
  String get upLatestVersion => _localizedStrings['up_latest_version'] ?? '';
  String get upDownloadButton =>
      _localizedStrings['up_download_button'] ?? '';
  String get upDownloading => _localizedStrings['up_downloading'] ?? '';
  String get upInstallButton => _localizedStrings['up_install_button'] ?? '';
  String get upDismiss => _localizedStrings['up_dismiss'] ?? '';
  String get upReleaseNotes => _localizedStrings['up_release_notes'] ?? '';
  String get upError => _localizedStrings['up_error'] ?? '';
  String get upErrorNetwork => _localizedStrings['up_error_network'] ?? '';

  // ---------------------------------------------------------------------------
  // cl_: Changelog Viewer
  // ---------------------------------------------------------------------------
  String get clTitle => _localizedStrings['cl_title'] ?? '';
  String get clClose => _localizedStrings['cl_close'] ?? '';
  String get clVersion => _localizedStrings['cl_version'] ?? '';
  String get clLatestChanges => _localizedStrings['cl_latest_changes'] ?? '';
  String get clErrorLoading => _localizedStrings['cl_error_loading'] ?? '';
  String get clViewOnGithub => _localizedStrings['cl_view_on_github'] ?? '';

  // ---------------------------------------------------------------------------
  // sel_: Multi-selection Toolbar
  // ---------------------------------------------------------------------------
  String get selSelectedCount =>
      _localizedStrings['sel_selected_count'] ?? '';
  String get selSelect => _localizedStrings['sel_select'] ?? '';
  String get selCancel => _localizedStrings['sel_cancel'] ?? '';
  String get selSelectAll => _localizedStrings['sel_select_all'] ?? '';
  String get selDeselectAll => _localizedStrings['sel_deselect_all'] ?? '';

  // ---------------------------------------------------------------------------
  // common_: Common UI Labels
  // ---------------------------------------------------------------------------
  String get commonViewAsCards =>
      _localizedStrings['common_view_as_cards'] ?? '';
  String get commonViewAsList =>
      _localizedStrings['common_view_as_list'] ?? '';
  String get commonBack => _localizedStrings['common_back'] ?? '';
  String get commonMinimize => _localizedStrings['common_minimize'] ?? '';

  // ---------------------------------------------------------------------------
  // scan_: Scan Progress Overlay
  // ---------------------------------------------------------------------------
  String get scanStageIdle => _localizedStrings['scan_stage_idle'] ?? '';
  String get scanStageGettingDatabase =>
      _localizedStrings['scan_stage_getting_database'] ?? '';
  String get scanStageGettingTracks =>
      _localizedStrings['scan_stage_getting_tracks'] ?? '';
  String get scanStageDiscovering =>
      _localizedStrings['scan_stage_discovering'] ?? '';
  String get scanStageComparing =>
      _localizedStrings['scan_stage_comparing'] ?? '';
  String get scanStageExtracting =>
      _localizedStrings['scan_stage_extracting'] ?? '';
  String get scanStageInserting =>
      _localizedStrings['scan_stage_inserting'] ?? '';
  String get scanStageCleaningOrphans =>
      _localizedStrings['scan_stage_cleaning_orphans'] ?? '';
  String get scanStageCleaningThumbnails =>
      _localizedStrings['scan_stage_cleaning_thumbnails'] ?? '';
  String get scanStageCompleted =>
      _localizedStrings['scan_stage_completed'] ?? '';
  String get scanStageFailed => _localizedStrings['scan_stage_failed'] ?? '';
  String get scanStageCancelled =>
      _localizedStrings['scan_stage_cancelled'] ?? '';
  String get scanCancelTooltip =>
      _localizedStrings['scan_cancel_tooltip'] ?? '';

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
  String plDuplicateConfirmFormatted(String name) =>
      plDuplicateConfirm.replaceAll('{name}', name);
  String plDuplicateQueueConfirmFormatted(String name) =>
      plDuplicateQueueConfirm.replaceAll('{name}', name);
  String plInsertOnlyNewFormatted(int count) =>
      plInsertOnlyNew.replaceAll('{count}', count.toString());
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
    'np_queue_empty', 'np_queue_reorder', 'np_queue_add_to_playlist',
    'np_infinite_mix',
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
    'tr_shuffle_all',
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
    'pl_duplicate_title',
    'pl_duplicate_confirm',
    'pl_add_anyway',
    'pl_duplicate_queue_title',
    'pl_duplicate_queue_confirm',
    'pl_insert_only_new',
    // g_
    'g_title', 'g_search_hint', 'g_unknown', 'g_tracks_count', 'g_albums_count',
    'g_play_all', 'g_shuffle_all', 'g_no_genres', 'g_no_genres_desc',
    // perm_
    'perm_title', 'perm_subtitle', 'perm_music_title', 'perm_music_desc',
    'perm_granted',
    'perm_grant_access', 'perm_open_settings', 'perm_denied_hint',
    'perm_continue',
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
    's_pause_on_device_change', 's_pause_on_device_change_desc',
    's_replay_gain_mode', 's_replay_gain_mode_desc', 's_replay_gain_preamp',
    's_replay_gain_preamp_desc',
    's_gapless_playback',
    's_gapless_playback_desc',
    's_skip_silence',
    's_skip_silence_desc',
    's_preamp',
    's_preamp_desc',
    's_stereo_balance',
    's_stereo_balance_desc',
    's_stereo_balance_center',
    's_mono_audio',
    's_mono_audio_desc',
    's_crossfeed',
    's_crossfeed_desc',
    's_crossfeed_off',
    's_crossfeed_moffat',
    's_crossfeed_chumoy',
    's_spatializer',
    's_spatializer_desc',
    's_limiter',
    's_limiter_desc',
    's_reverb',
    's_reverb_desc',
    's_reverb_preset',
    's_reverb_preset_off',
    's_reverb_preset_small_room',
    's_reverb_preset_studio',
    's_reverb_preset_concert_hall',
    's_reverb_preset_cathedral',
    's_reverb_preset_plate',
    's_reverb_preset_ambient',
    's_reverb_preset_custom',
    's_reverb_room_size',
    's_reverb_damping',
    's_reverb_width',
    's_reverb_wet',
    's_reverb_dry',
    's_audio_dsp_section',
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
      Map<String, String>.unmodifiable(_localizedStrings);

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
    _localizedStrings.addAll(jsonData);
  }
}
