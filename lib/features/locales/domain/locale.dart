import 'package:flutter/foundation.dart';

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
  /// Localized string for `np_title` ("Now Playing").
  String get npTitle => _localizedStrings['np_title'] ?? '';
  /// Localized string for `np_play` ("Play").
  String get npPlay => _localizedStrings['np_play'] ?? '';
  /// Localized string for `np_pause` ("Pause").
  String get npPause => _localizedStrings['np_pause'] ?? '';
  /// Localized string for `np_previous` ("Previous track").
  String get npPrevious => _localizedStrings['np_previous'] ?? '';
  /// Localized string for `np_next` ("Next track").
  String get npNext => _localizedStrings['np_next'] ?? '';
  /// Localized string for `np_stop` ("Stop").
  String get npStop => _localizedStrings['np_stop'] ?? '';
  /// Localized string for `np_mute` ("Mute").
  String get npMute => _localizedStrings['np_mute'] ?? '';
  /// Localized string for `np_unmute` ("Unmute").
  String get npUnmute => _localizedStrings['np_unmute'] ?? '';
  /// Localized string for `np_volume` ("Volume").
  String get npVolume => _localizedStrings['np_volume'] ?? '';
  /// Localized string for `np_shuffle_off` ("Shuffle Off").
  String get npShuffleOff => _localizedStrings['np_shuffle_off'] ?? '';
  /// Localized string for `np_shuffle_on` ("Shuffle On").
  String get npShuffleOn => _localizedStrings['np_shuffle_on'] ?? '';
  /// Localized string for `np_repeat_off` ("Repeat Off").
  String get npRepeatOff => _localizedStrings['np_repeat_off'] ?? '';
  /// Localized string for `np_repeat_all` ("Repeat All").
  String get npRepeatAll => _localizedStrings['np_repeat_all'] ?? '';
  /// Localized string for `np_repeat_one` ("Repeat One").
  String get npRepeatOne => _localizedStrings['np_repeat_one'] ?? '';
  /// Localized string for `np_elapsed` ("Elapsed").
  String get npElapsed => _localizedStrings['np_elapsed'] ?? '';
  /// Localized string for `np_remaining` ("Remaining").
  String get npRemaining => _localizedStrings['np_remaining'] ?? '';
  /// Localized string for `np_duration` ("Duration").
  String get npDuration => _localizedStrings['np_duration'] ?? '';
  /// Localized string for `np_seek_forward` ("Seek forward 10 seconds").
  String get npSeekForward => _localizedStrings['np_seek_forward'] ?? '';
  /// Localized string for `np_seek_backward` ("Seek backward 10 seconds").
  String get npSeekBackward => _localizedStrings['np_seek_backward'] ?? '';
  /// Localized string for `np_queue` ("Queue").
  String get npQueue => _localizedStrings['np_queue'] ?? '';
  /// Localized string for `np_queue_clear` ("Clear queue").
  String get npQueueClear => _localizedStrings['np_queue_clear'] ?? '';
  /// Localized string for `np_queue_clear_confirm` ("Are you sure you want to clear the playback queue?").
  String get npQueueClearConfirm =>
      _localizedStrings['np_queue_clear_confirm'] ?? '';
  /// Localized string for `np_queue_empty` ("Playback queue is empty").
  String get npQueueEmpty => _localizedStrings['np_queue_empty'] ?? '';
  /// Localized string for `np_queue_reorder` ("Drag to reorder").
  String get npQueueReorder => _localizedStrings['np_queue_reorder'] ?? '';
  /// Localized string for `np_queue_add_to_playlist` ("Add queue to playlist").
  String get npQueueAddToPlaylist =>
      _localizedStrings['np_queue_add_to_playlist'] ?? '';
  /// Localized string for `np_infinite_mix` ("Infinite library mix").
  String get npInfiniteMix =>
      _localizedStrings['np_infinite_mix'] ?? '';
  /// Localized string for `np_lyrics` ("Lyrics").
  String get npLyrics => _localizedStrings['np_lyrics'] ?? '';
  /// Localized string for `np_lyrics_empty` ("No lyrics found for this track").
  String get npLyricsEmpty => _localizedStrings['np_lyrics_empty'] ?? '';
  /// Localized string for `np_lyrics_sync` ("Synchronized lyrics").
  String get npLyricsSync => _localizedStrings['np_lyrics_sync'] ?? '';
  /// Localized string for `np_lyrics_unsync` ("Plain lyrics").
  String get npLyricsUnsync => _localizedStrings['np_lyrics_unsync'] ?? '';
  /// Localized string for `np_lyrics_translate` ("Translate lyrics").
  String get npLyricsTranslate =>
      _localizedStrings['np_lyrics_translate'] ?? '';
  /// Localized string for `np_lyrics_translating` ("Translating lyrics...").
  String get npLyricsTranslating =>
      _localizedStrings['np_lyrics_translating'] ?? '';
  /// Localized string for `np_lyrics_translation_mode` ("Translation mode").
  String get npLyricsTranslationMode =>
      _localizedStrings['np_lyrics_translation_mode'] ?? '';
  /// Localized string for `np_lyrics_original` ("Original").
  String get npLyricsOriginal =>
      _localizedStrings['np_lyrics_original'] ?? '';
  /// Localized string for `np_lyrics_translated` ("Translated").
  String get npLyricsTranslated =>
      _localizedStrings['np_lyrics_translated'] ?? '';
  /// Localized string for `np_lyrics_interleaved` ("Interleaved").
  String get npLyricsInterleaved =>
      _localizedStrings['np_lyrics_interleaved'] ?? '';
  /// Localized string for `np_lyrics_sources` ("Lyrics sources").
  String get npLyricsSources => _localizedStrings['np_lyrics_sources'] ?? '';
  /// Localized string for `np_lyrics_research` ("Re-search lyrics").
  String get npLyricsResearch =>
      _localizedStrings['np_lyrics_research'] ?? '';
  /// Localized string for `np_lyrics_resume_sync` ("Sync").
  String get npLyricsResumeSync =>
      _localizedStrings['np_lyrics_resume_sync'] ?? '';
  /// Localized string for `np_lyrics_sources_title` ("Lyrics Sources").
  String get npLyricsSourcesTitle =>
      _localizedStrings['np_lyrics_sources_title'] ?? '';
  /// Localized string for `np_lyrics_source_local` ("Local files").
  String get npLyricsSourceLocal =>
      _localizedStrings['np_lyrics_source_local'] ?? '';
  /// Localized string for `np_lyrics_source_local_desc` ("Embedded tags (ID3/FLAC) and local .lrc files").
  String get npLyricsSourceLocalDesc =>
      _localizedStrings['np_lyrics_source_local_desc'] ?? '';
  /// Localized string for `np_lyrics_source_lrclib` ("Primary server (lrclib.net)").
  String get npLyricsSourceLrclib =>
      _localizedStrings['np_lyrics_source_lrclib'] ?? '';
  /// Localized string for `np_lyrics_source_lrclib_desc` ("Synchronized and plain text lyrics API").
  String get npLyricsSourceLrclibDesc =>
      _localizedStrings['np_lyrics_source_lrclib_desc'] ?? '';
  /// Localized string for `np_lyrics_source_ovh` ("Fallback server (lyrics.ovh)").
  String get npLyricsSourceOvh =>
      _localizedStrings['np_lyrics_source_ovh'] ?? '';
  /// Localized string for `np_lyrics_source_ovh_desc` ("Unsynchronized plain text lyrics API").
  String get npLyricsSourceOvhDesc =>
      _localizedStrings['np_lyrics_source_ovh_desc'] ?? '';
  /// Localized string for `np_lyrics_sources_research` ("Search Again").
  String get npLyricsSourcesResearch =>
      _localizedStrings['np_lyrics_sources_research'] ?? '';
  /// Localized string for `np_lyrics_sources_research_btn` ("Re-search").
  String get npLyricsSourcesResearchBtn =>
      _localizedStrings['np_lyrics_sources_research_btn'] ?? '';
  /// Localized string for `np_lyrics_retranslate_btn` ("Retranslate").
  String get npLyricsRetranslateBtn =>
      _localizedStrings['np_lyrics_retranslate_btn'] ?? '';
  /// Localized string for `np_lyrics_sources_close` ("Close").
  String get npLyricsSourcesClose =>
      _localizedStrings['np_lyrics_sources_close'] ?? '';
  /// Localized string for `np_lyrics_sources_close_btn` ("Close").
  String get npLyricsSourcesCloseBtn =>
      _localizedStrings['np_lyrics_sources_close_btn'] ?? '';
  /// Localized string for `np_lyrics_tab_sources` ("Sources").
  String get npLyricsTabSources =>
      _localizedStrings['np_lyrics_tab_sources'] ?? '';
  /// Localized string for `np_lyrics_tab_translation` ("Translation").
  String get npLyricsTabTranslation =>
      _localizedStrings['np_lyrics_tab_translation'] ?? '';
  /// Localized string for `np_lyrics_source_lang` ("Source language").
  String get npLyricsSourceLang =>
      _localizedStrings['np_lyrics_source_lang'] ?? '';
  /// Localized string for `np_lyrics_target_lang` ("Target language").
  String get npLyricsTargetLang =>
      _localizedStrings['np_lyrics_target_lang'] ?? '';
  /// Localized string for `np_lyrics_lang_auto` ("Auto (Detect)").
  String get npLyricsLangAuto =>
      _localizedStrings['np_lyrics_lang_auto'] ?? '';
  /// Localized string for `np_lyrics_lang_auto_target` ("np_lyrics_lang_auto_target").
  String get npLyricsLangAutoTarget =>
      _localizedStrings['np_lyrics_lang_auto_target'] ?? '';
  /// Localized string for `np_lyrics_rate_limit_error` ("Translation service rate limit reached. Please wait a moment.").
  String get npLyricsRateLimitError =>
      _localizedStrings['np_lyrics_rate_limit_error'] ?? '';
  /// Localized string for `np_lyrics_threshold_waiting` ("Lyrics server (lrclib.net) rate limit detected, waiting {seconds} seconds...").
  String get npLyricsThresholdWaiting =>
      _localizedStrings['np_lyrics_threshold_waiting'] ?? '';
  /// Localized string for `np_lyrics_banner_dismiss` ("Dismiss").
  String get npLyricsBannerDismiss =>
      _localizedStrings['np_lyrics_banner_dismiss'] ?? '';
  /// Localized string for `np_lyrics_source_embedded` ("Embedded").
  String get npLyricsSourceEmbedded =>
      _localizedStrings['np_lyrics_source_embedded'] ?? '';
  /// Localized string for `np_lyrics_source_file` ("LRC file").
  String get npLyricsSourceFile =>
      _localizedStrings['np_lyrics_source_file'] ?? '';
  /// Localized string for `np_lyrics_source_none` ("No source").
  String get npLyricsSourceNone =>
      _localizedStrings['np_lyrics_source_none'] ?? '';
  /// Localized string for `np_lyrics_loading` ("Loading lyrics...").
  String get npLyricsLoading => _localizedStrings['np_lyrics_loading'] ?? '';
  /// Localized string for `np_lyrics_error` ("Error loading lyrics").
  String get npLyricsError => _localizedStrings['np_lyrics_error'] ?? '';
  /// Localized string for `np_lyrics_translate_error` ("Failed to translate lyrics").
  String get npLyricsTranslateError =>
      _localizedStrings['np_lyrics_translate_error'] ?? '';
  /// Localized string for `np_audio_controls` ("Audio Effects").
  String get npAudioControls => _localizedStrings['np_audio_controls'] ?? '';
  /// Localized string for `np_speed` ("Playback Speed").
  String get npSpeed => _localizedStrings['np_speed'] ?? '';
  /// Localized string for `np_pitch` ("Pitch").
  String get npPitch => _localizedStrings['np_pitch'] ?? '';
  /// Localized string for `np_volume_boost` ("Volume Boost").
  String get npVolumeBoost => _localizedStrings['np_volume_boost'] ?? '';
  /// Localized string for `np_replay_gain` ("ReplayGain").
  String get npReplayGain => _localizedStrings['np_replay_gain'] ?? '';
  /// Localized string for `np_replay_gain_off` ("Off").
  String get npReplayGainOff => _localizedStrings['np_replay_gain_off'] ?? '';
  /// Localized string for `np_replay_gain_track` ("Track").
  String get npReplayGainTrack =>
      _localizedStrings['np_replay_gain_track'] ?? '';
  /// Localized string for `np_replay_gain_album` ("Album").
  String get npReplayGainAlbum =>
      _localizedStrings['np_replay_gain_album'] ?? '';
  /// Localized string for `np_preamp` ("Preamp Gain").
  String get npPreamp => _localizedStrings['np_preamp'] ?? '';
  /// Localized string for `np_crossfade` ("Crossfade").
  String get npCrossfade => _localizedStrings['np_crossfade'] ?? '';
  /// Localized string for `np_crossfade_duration` ("Crossfade Duration").
  String get npCrossfadeDuration =>
      _localizedStrings['np_crossfade_duration'] ?? '';
  /// Localized string for `np_audio_devices` ("Audio Output Device").
  String get npAudioDevices => _localizedStrings['np_audio_devices'] ?? '';
  /// Localized string for `np_audio_device_default` ("Default").
  String get npAudioDeviceDefault =>
      _localizedStrings['np_audio_device_default'] ?? '';
  /// Localized string for `np_crossfade_auto` ("Auto Crossfade").
  String get npCrossfadeAuto => _localizedStrings['np_crossfade_auto'] ?? '';
  /// Localized string for `np_crossfade_manual` ("Manual Crossfade").
  String get npCrossfadeManual =>
      _localizedStrings['np_crossfade_manual'] ?? '';
  /// Localized string for `np_exclusive_audio` ("Exclusive Audio (WASAPI)").
  String get npExclusiveAudio =>
      _localizedStrings['np_exclusive_audio'] ?? '';
  /// Localized string for `np_fullscreen` ("Fullscreen").
  String get npFullscreen => _localizedStrings['np_fullscreen'] ?? '';
  /// Localized string for `np_exit_fullscreen` ("Exit fullscreen").
  String get npExitFullscreen =>
      _localizedStrings['np_exit_fullscreen'] ?? '';
  /// Localized string for `np_visualizer` ("Visualizer").
  String get npVisualizer => _localizedStrings['np_visualizer'] ?? '';
  /// Localized string for `np_visualizer_mode` ("Visualizer Mode").
  String get npVisualizerMode => _localizedStrings['np_visualizer_mode'] ?? '';
  /// Localized string for `np_visualizer_off` ("Cover Only").
  String get npVisualizerOff => _localizedStrings['np_visualizer_off'] ?? '';
  /// Localized string for `np_visualizer_wave` ("Cover & Wave").
  String get npVisualizerWave => _localizedStrings['np_visualizer_wave'] ?? '';
  /// Localized string for `np_visualizer_bars` ("Spectrum Bars").
  String get npVisualizerBars => _localizedStrings['np_visualizer_bars'] ?? '';
  /// Localized string for `np_visualizer_circle` ("Reactive Circle").
  String get npVisualizerCircle =>
      _localizedStrings['np_visualizer_circle'] ?? '';
  /// Localized string for `np_background_artwork` ("Album Art Background").
  String get npBackgroundArtwork =>
      _localizedStrings['np_background_artwork'] ?? '';
  /// Localized string for `np_background_gradient` ("Gradient Background").
  String get npBackgroundGradient =>
      _localizedStrings['np_background_gradient'] ?? '';
  /// Localized string for `np_add_to_playlist` ("Add to playlist").
  String get npAddToPlaylist => _localizedStrings['np_add_to_playlist'] ?? '';
  /// Localized string for `np_like` ("Add to Liked Songs").
  String get npLike => _localizedStrings['np_like'] ?? '';
  /// Localized string for `np_unlike` ("Remove from Liked Songs").
  String get npUnlike => _localizedStrings['np_unlike'] ?? '';
  /// Localized string for `np_technical_info` ("Technical Details").
  String get npTechnicalInfo => _localizedStrings['np_technical_info'] ?? '';
  /// Localized string for `np_bitrate` ("Bitrate").
  String get npBitrate => _localizedStrings['np_bitrate'] ?? '';
  /// Localized string for `np_sample_rate` ("Sample Rate").
  String get npSampleRate => _localizedStrings['np_sample_rate'] ?? '';
  /// Localized string for `np_channels` ("Channels").
  String get npChannels => _localizedStrings['np_channels'] ?? '';
  /// Localized string for `np_format` ("Format").
  String get npFormat => _localizedStrings['np_format'] ?? '';

  // ---------------------------------------------------------------------------
  // tr_: Tracks Screen & Actions
  // ---------------------------------------------------------------------------
  /// Localized string for `tr_title` ("Tracks").
  String get trTitle => _localizedStrings['tr_title'] ?? '';
  /// Localized string for `tr_search_hint` ("Search tracks...").
  String get trSearchHint => _localizedStrings['tr_search_hint'] ?? '';
  /// Localized string for `tr_play` ("Play").
  String get trPlay => _localizedStrings['tr_play'] ?? '';
  /// Localized string for `tr_play_next` ("Play next").
  String get trPlayNext => _localizedStrings['tr_play_next'] ?? '';
  /// Localized string for `tr_add_queue` ("Add to queue").
  String get trAddQueue => _localizedStrings['tr_add_queue'] ?? '';
  /// Localized string for `tr_add_playlist` ("Add to playlist").
  String get trAddPlaylist => _localizedStrings['tr_add_playlist'] ?? '';
  /// Localized string for `tr_view_album` ("Go to album").
  String get trViewAlbum => _localizedStrings['tr_view_album'] ?? '';
  /// Localized string for `tr_view_artist` ("Go to artist").
  String get trViewArtist => _localizedStrings['tr_view_artist'] ?? '';
  /// Localized string for `tr_edit_tags` ("Edit metadata tags").
  String get trEditTags => _localizedStrings['tr_edit_tags'] ?? '';
  /// Localized string for `tr_file_info` ("File information").
  String get trFileInfo => _localizedStrings['tr_file_info'] ?? '';
  /// Localized string for `tr_share` ("Share audio file").
  String get trShare => _localizedStrings['tr_share'] ?? '';
  /// Localized string for `tr_delete` ("Delete track").
  String get trDelete => _localizedStrings['tr_delete'] ?? '';
  /// Localized string for `tr_delete_confirm` ("Are you sure you want to delete this track from your library?").
  String get trDeleteConfirm => _localizedStrings['tr_delete_confirm'] ?? '';
  /// Localized string for `tr_deleted_success` ("Track removed from library").
  String get trDeletedSuccess =>
      _localizedStrings['tr_deleted_success'] ?? '';
  /// Localized string for `tr_no_tracks` ("No tracks in your library yet").
  String get trNoTracks => _localizedStrings['tr_no_tracks'] ?? '';
  /// Localized string for `tr_no_tracks_desc` ("Add music folders in Settings to start populating your library.").
  String get trNoTracksDesc => _localizedStrings['tr_no_tracks_desc'] ?? '';
  /// Localized string for `tr_loading_tracks` ("Loading tracks...").
  String get trLoadingTracks => _localizedStrings['tr_loading_tracks'] ?? '';
  /// Localized string for `tr_count` ("{count} tracks").
  String get trCount => _localizedStrings['tr_count'] ?? '';
  /// Localized string for `tr_sort` ("Sort by").
  String get trSort => _localizedStrings['tr_sort'] ?? '';
  /// Localized string for `tr_sort_title` ("Title").
  String get trSortTitle => _localizedStrings['tr_sort_title'] ?? '';
  /// Localized string for `tr_sort_artist` ("Artist").
  String get trSortArtist => _localizedStrings['tr_sort_artist'] ?? '';
  /// Localized string for `tr_sort_album` ("Album").
  String get trSortAlbum => _localizedStrings['tr_sort_album'] ?? '';
  /// Localized string for `tr_sort_date_added` ("Date added").
  String get trSortDateAdded => _localizedStrings['tr_sort_date_added'] ?? '';
  /// Localized string for `tr_sort_duration` ("Duration").
  String get trSortDuration => _localizedStrings['tr_sort_duration'] ?? '';
  /// Localized string for `tr_sort_ascending` ("Ascending").
  String get trSortAscending => _localizedStrings['tr_sort_ascending'] ?? '';
  /// Localized string for `tr_sort_descending` ("Descending").
  String get trSortDescending =>
      _localizedStrings['tr_sort_descending'] ?? '';
  /// Localized string for `tr_file_path` ("File Path").
  String get trFilePath => _localizedStrings['tr_file_path'] ?? '';
  /// Localized string for `tr_codec` ("Codec").
  String get trCodec => _localizedStrings['tr_codec'] ?? '';
  /// Localized string for `tr_file_size` ("File Size").
  String get trFileSize => _localizedStrings['tr_file_size'] ?? '';
  /// Localized string for `tr_unknown_artist` ("Unknown Artist").
  String get trUnknownArtist => _localizedStrings['tr_unknown_artist'] ?? '';
  /// Localized string for `tr_added_to_playlist` ("Added to {name}").
  String get trAddedToPlaylist =>
      _localizedStrings['tr_added_to_playlist'] ?? '';
  /// Localized string for `tr_more_actions` ("More actions").
  String get trMoreActions => _localizedStrings['tr_more_actions'] ?? '';
  /// Localized string for `tr_shuffle_all` ("Shuffle all tracks").
  String get trShuffleAll => _localizedStrings['tr_shuffle_all'] ?? '';

  // ---------------------------------------------------------------------------
  // al_: Albums Screen & Detail
  // ---------------------------------------------------------------------------
  /// Localized string for `al_title` ("Albums").
  String get alTitle => _localizedStrings['al_title'] ?? '';
  /// Localized string for `al_search_hint` ("Search albums...").
  String get alSearchHint => _localizedStrings['al_search_hint'] ?? '';
  /// Localized string for `al_tracks_count` ("{count} tracks").
  String get alTracksCount => _localizedStrings['al_tracks_count'] ?? '';
  /// Localized string for `al_release_year` ("Year").
  String get alReleaseYear => _localizedStrings['al_release_year'] ?? '';
  /// Localized string for `al_play_all` ("Play album").
  String get alPlayAll => _localizedStrings['al_play_all'] ?? '';
  /// Localized string for `al_shuffle_all` ("Shuffle album").
  String get alShuffleAll => _localizedStrings['al_shuffle_all'] ?? '';
  /// Localized string for `al_add_queue` ("Add album to queue").
  String get alAddQueue => _localizedStrings['al_add_queue'] ?? '';
  /// Localized string for `al_add_playlist` ("Add album to playlist").
  String get alAddPlaylist => _localizedStrings['al_add_playlist'] ?? '';
  /// Localized string for `al_view_artist` ("View artist").
  String get alViewArtist => _localizedStrings['al_view_artist'] ?? '';
  /// Localized string for `al_no_albums` ("No albums found").
  String get alNoAlbums => _localizedStrings['al_no_albums'] ?? '';
  /// Localized string for `al_no_albums_desc` ("Scan folders with organized album metadata to see them here.").
  String get alNoAlbumsDesc => _localizedStrings['al_no_albums_desc'] ?? '';
  /// Localized string for `al_sort` ("Sort albums").
  String get alSort => _localizedStrings['al_sort'] ?? '';
  /// Localized string for `al_sort_title` ("Album name").
  String get alSortTitle => _localizedStrings['al_sort_title'] ?? '';
  /// Localized string for `al_sort_artist` ("Artist name").
  String get alSortArtist => _localizedStrings['al_sort_artist'] ?? '';
  /// Localized string for `al_sort_year` ("Release year").
  String get alSortYear => _localizedStrings['al_sort_year'] ?? '';
  /// Localized string for `al_sort_track_count` ("Track count").
  String get alSortTrackCount =>
      _localizedStrings['al_sort_track_count'] ?? '';
  /// Localized string for `al_total_duration` ("Total duration").
  String get alTotalDuration => _localizedStrings['al_total_duration'] ?? '';

  // ---------------------------------------------------------------------------
  // ar_: Artists Screen & Discography
  // ---------------------------------------------------------------------------
  /// Localized string for `ar_title` ("Artists").
  String get arTitle => _localizedStrings['ar_title'] ?? '';
  /// Localized string for `ar_search_hint` ("Search artists...").
  String get arSearchHint => _localizedStrings['ar_search_hint'] ?? '';
  /// Localized string for `ar_albums_count` ("{count} albums").
  String get arAlbumsCount => _localizedStrings['ar_albums_count'] ?? '';
  /// Localized string for `ar_tracks_count` ("{count} tracks").
  String get arTracksCount => _localizedStrings['ar_tracks_count'] ?? '';
  /// Localized string for `ar_play_all` ("Play all tracks").
  String get arPlayAll => _localizedStrings['ar_play_all'] ?? '';
  /// Localized string for `ar_shuffle_all` ("Shuffle all tracks").
  String get arShuffleAll => _localizedStrings['ar_shuffle_all'] ?? '';
  /// Localized string for `ar_discography` ("Discography").
  String get arDiscography => _localizedStrings['ar_discography'] ?? '';
  /// Localized string for `ar_all_tracks` ("All Tracks").
  String get arAllTracks => _localizedStrings['ar_all_tracks'] ?? '';
  /// Localized string for `ar_biography` ("Biography").
  String get arBiography => _localizedStrings['ar_biography'] ?? '';
  /// Localized string for `ar_no_artists` ("No artists found").
  String get arNoArtists => _localizedStrings['ar_no_artists'] ?? '';
  /// Localized string for `ar_no_artists_desc` ("Tracks with artist tags will be grouped here.").
  String get arNoArtistsDesc => _localizedStrings['ar_no_artists_desc'] ?? '';
  /// Localized string for `ar_sort` ("Sort artists").
  String get arSort => _localizedStrings['ar_sort'] ?? '';
  /// Localized string for `ar_sort_name` ("Artist name").
  String get arSortName => _localizedStrings['ar_sort_name'] ?? '';
  /// Localized string for `ar_sort_albums` ("Number of albums").
  String get arSortAlbums => _localizedStrings['ar_sort_albums'] ?? '';
  /// Localized string for `ar_sort_tracks` ("Number of tracks").
  String get arSortTracks => _localizedStrings['ar_sort_tracks'] ?? '';

  // ---------------------------------------------------------------------------
  // pl_: Playlists Management
  // ---------------------------------------------------------------------------
  /// Localized string for `pl_title` ("List").
  String get plTitle => _localizedStrings['pl_title'] ?? '';
  /// Localized string for `pl_create_new` ("Create playlist").
  String get plCreateNew => _localizedStrings['pl_create_new'] ?? '';
  /// Localized string for `pl_new_name_hint` ("Playlist name").
  String get plNewNameHint => _localizedStrings['pl_new_name_hint'] ?? '';
  /// Localized string for `pl_create_button` ("Create").
  String get plCreateButton => _localizedStrings['pl_create_button'] ?? '';
  /// Localized string for `pl_cancel_button` ("Cancel").
  String get plCancelButton => _localizedStrings['pl_cancel_button'] ?? '';
  /// Localized string for `pl_delete` ("Delete playlist").
  String get plDelete => _localizedStrings['pl_delete'] ?? '';
  /// Localized string for `pl_delete_confirm` ("Are you sure you want to delete '{name}'?").
  String get plDeleteConfirm => _localizedStrings['pl_delete_confirm'] ?? '';
  /// Localized string for `pl_rename` ("Rename playlist").
  String get plRename => _localizedStrings['pl_rename'] ?? '';
  /// Localized string for `pl_edit` ("Edit playlist").
  String get plEdit => _localizedStrings['pl_edit'] ?? '';
  /// Localized string for `pl_empty` ("This playlist is empty").
  String get plEmpty => _localizedStrings['pl_empty'] ?? '';
  /// Localized string for `pl_empty_desc` ("Add songs by opening track menus and choosing Add to Playlist.").
  String get plEmptyDesc => _localizedStrings['pl_empty_desc'] ?? '';
  /// Localized string for `pl_add_tracks` ("Add tracks").
  String get plAddTracks => _localizedStrings['pl_add_tracks'] ?? '';
  /// Localized string for `pl_remove_track` ("Remove from playlist").
  String get plRemoveTrack => _localizedStrings['pl_remove_track'] ?? '';
  /// Localized string for `pl_play_all` ("Play playlist").
  String get plPlayAll => _localizedStrings['pl_play_all'] ?? '';
  /// Localized string for `pl_shuffle_all` ("Shuffle playlist").
  String get plShuffleAll => _localizedStrings['pl_shuffle_all'] ?? '';
  /// Localized string for `pl_liked_songs` ("Liked Songs").
  String get plLikedSongs => _localizedStrings['pl_liked_songs'] ?? '';
  /// Localized string for `pl_history` ("History").
  String get plHistory => _localizedStrings['pl_history'] ?? '';
  /// Localized string for `pl_recently_added` ("Recently Added").
  String get plRecentlyAdded => _localizedStrings['pl_recently_added'] ?? '';
  /// Localized string for `pl_tracks_count` ("{count} tracks").
  String get plTracksCount => _localizedStrings['pl_tracks_count'] ?? '';
  /// Localized string for `pl_reorder_hint` ("Drag items to reorder playlist").
  String get plReorderHint => _localizedStrings['pl_reorder_hint'] ?? '';
  /// Localized string for `pl_no_playlists` ("No playlists yet").
  String get plNoPlaylists => _localizedStrings['pl_no_playlists'] ?? '';
  /// Localized string for `pl_duplicate_title` ("Song already in playlist").
  String get plDuplicateTitle =>
      _localizedStrings['pl_duplicate_title'] ?? '';
  /// Localized string for `pl_duplicate_confirm` ("This track is already in '{name}'. Do you want to add it anyway?").
  String get plDuplicateConfirm =>
      _localizedStrings['pl_duplicate_confirm'] ?? '';
  /// Localized string for `pl_add_anyway` ("Add anyway").
  String get plAddAnyway => _localizedStrings['pl_add_anyway'] ?? '';
  /// Localized string for `pl_duplicate_queue_title` ("Duplicates in playlist").
  String get plDuplicateQueueTitle =>
      _localizedStrings['pl_duplicate_queue_title'] ?? '';
  /// Localized string for `pl_duplicate_queue_confirm` ("Some tracks in the queue are already in '{name}'. How would you like to proceed?").
  String get plDuplicateQueueConfirm =>
      _localizedStrings['pl_duplicate_queue_confirm'] ?? '';
  /// Localized string for `pl_insert_only_new` ("Insert only new ({count})").
  String get plInsertOnlyNew =>
      _localizedStrings['pl_insert_only_new'] ?? '';

  // ---------------------------------------------------------------------------
  // g_: Genres Screen
  // ---------------------------------------------------------------------------
  /// Localized string for `g_title` ("Genres").
  String get gTitle => _localizedStrings['g_title'] ?? '';
  /// Localized string for `g_search_hint` ("Search genres...").
  String get gSearchHint => _localizedStrings['g_search_hint'] ?? '';
  /// Localized string for `g_unknown` ("Unknown Genre").
  String get gUnknown => _localizedStrings['g_unknown'] ?? '';
  /// Localized string for `g_tracks_count` ("{count} tracks").
  String get gTracksCount => _localizedStrings['g_tracks_count'] ?? '';
  /// Localized string for `g_albums_count` ("{count} albums").
  String get gAlbumsCount => _localizedStrings['g_albums_count'] ?? '';
  /// Localized string for `g_play_all` ("Play genre").
  String get gPlayAll => _localizedStrings['g_play_all'] ?? '';
  /// Localized string for `g_shuffle_all` ("Shuffle genre").
  String get gShuffleAll => _localizedStrings['g_shuffle_all'] ?? '';
  /// Localized string for `g_no_genres` ("No genres found").
  String get gNoGenres => _localizedStrings['g_no_genres'] ?? '';
  /// Localized string for `g_no_genres_desc` ("Metadata tags with genre information will appear here.").
  String get gNoGenresDesc => _localizedStrings['g_no_genres_desc'] ?? '';

  // ---------------------------------------------------------------------------
  // perm_: Permissions Screen
  // ---------------------------------------------------------------------------
  /// Localized string for `perm_title` ("Before we start").
  String get permTitle => _localizedStrings['perm_title'] ?? '';
  /// Localized string for `perm_subtitle` ("Tachyon needs a couple of permissions to play your music.").
  String get permSubtitle => _localizedStrings['perm_subtitle'] ?? '';
  /// Localized string for `perm_music_title` ("Music library").
  String get permMusicTitle => _localizedStrings['perm_music_title'] ?? '';
  /// Localized string for `perm_music_desc` ("Read the audio files stored on your device.").
  String get permMusicDesc => _localizedStrings['perm_music_desc'] ?? '';
  /// Localized string for `perm_granted` ("Allowed").
  String get permGranted => _localizedStrings['perm_granted'] ?? '';
  /// Localized string for `perm_grant_access` ("Allow").
  String get permGrantAccess => _localizedStrings['perm_grant_access'] ?? '';
  /// Localized string for `perm_open_settings` ("Open settings").
  String get permOpenSettings =>
      _localizedStrings['perm_open_settings'] ?? '';
  /// Localized string for `perm_denied_hint` ("Permission denied. Enable it from the app settings.").
  String get permDeniedHint => _localizedStrings['perm_denied_hint'] ?? '';
  /// Localized string for `perm_continue` ("Continue").
  String get permContinue => _localizedStrings['perm_continue'] ?? '';


  // ---------------------------------------------------------------------------
  // f_: Folders & Filesystem Browser
  // ---------------------------------------------------------------------------
  /// Localized string for `f_title` ("Folders").
  String get fTitle => _localizedStrings['f_title'] ?? '';
  /// Localized string for `f_navigate_up` ("Go up").
  String get fNavigateUp => _localizedStrings['f_navigate_up'] ?? '';
  /// Localized string for `f_current_folder` ("Current Folder").
  String get fCurrentFolder => _localizedStrings['f_current_folder'] ?? '';
  /// Localized string for `f_empty_folder` ("This folder has no audio files").
  String get fEmptyFolder => _localizedStrings['f_empty_folder'] ?? '';
  /// Localized string for `f_scan_folder` ("Scan this folder").
  String get fScanFolder => _localizedStrings['f_scan_folder'] ?? '';
  /// Localized string for `f_add_to_library` ("Add folder to library").
  String get fAddToLibrary => _localizedStrings['f_add_to_library'] ?? '';
  /// Localized string for `f_items_count` ("{count} items").
  String get fItemsCount => _localizedStrings['f_items_count'] ?? '';
  /// Localized string for `f_inaccessible` ("Inaccessible directory").
  String get fInaccessible => _localizedStrings['f_inaccessible'] ?? '';
  /// Localized string for `f_inaccessible_desc` ("This directory could not be reached. It may have been moved or unmounted.").
  String get fInaccessibleDesc =>
      _localizedStrings['f_inaccessible_desc'] ?? '';
  /// Localized string for `f_breadcrumb_root` ("Music Root").
  String get fBreadcrumbRoot => _localizedStrings['f_breadcrumb_root'] ?? '';
  /// Localized string for `f_view_as_grid` ("Switch to grid view").
  String get fViewAsGrid => _localizedStrings['f_view_as_grid'] ?? '';
  /// Localized string for `f_view_as_list` ("Switch to list view").
  String get fViewAsList => _localizedStrings['f_view_as_list'] ?? '';
  /// Localized string for `f_rescan_all` ("Rescan all files").
  String get fRescanAll => _localizedStrings['f_rescan_all'] ?? '';

  // ---------------------------------------------------------------------------
  // rd_: Online Radios & Live Streams
  // ---------------------------------------------------------------------------
  /// Localized string for `rd_title` ("Radios").
  String get rdTitle => _localizedStrings['rd_title'] ?? '';
  /// Localized string for `rd_my_stations` ("My Stations").
  String get rdMyStations => _localizedStrings['rd_my_stations'] ?? '';
  /// Localized string for `rd_discover` ("Discover").
  String get rdDiscover => _localizedStrings['rd_discover'] ?? '';
  /// Localized string for `rd_search_hint` ("Search stations by name...").
  String get rdSearchHint => _localizedStrings['rd_search_hint'] ?? '';
  /// Localized string for `rd_all_genres` ("All Genres").
  String get rdAllGenres => _localizedStrings['rd_all_genres'] ?? '';
  /// Localized string for `rd_all_countries` ("All Countries").
  String get rdAllCountries => _localizedStrings['rd_all_countries'] ?? '';
  /// Localized string for `rd_image_url` ("Logo / Image URL").
  String get rdImageUrl => _localizedStrings['rd_image_url'] ?? '';
  /// Localized string for `rd_save_to_library` ("Save to Library").
  String get rdSaveToLibrary => _localizedStrings['rd_save_to_library'] ?? '';
  /// Localized string for `rd_saved_to_library` ("Saved to your library").
  String get rdSavedToLibrary => _localizedStrings['rd_saved_to_library'] ?? '';
  /// Localized string for `rd_already_in_library` ("Already in library").
  String get rdAlreadyInLibrary =>
      _localizedStrings['rd_already_in_library'] ?? '';
  /// Localized string for `rd_like` ("Add to Favorite Stations").
  String get rdLike => _localizedStrings['rd_like'] ?? '';
  /// Localized string for `rd_unlike` ("Remove from Favorite Stations").
  String get rdUnlike => _localizedStrings['rd_unlike'] ?? '';
  /// Localized string for `rd_refresh` ("Refresh").
  String get rdRefresh => _localizedStrings['rd_refresh'] ?? '';
  /// Localized string for `rd_popular` ("Popular").
  String get rdPopular => _localizedStrings['rd_popular'] ?? '';
  /// Localized string for `rd_loading` ("Loading stations...").
  String get rdLoading => _localizedStrings['rd_loading'] ?? '';
  /// Localized string for `rd_no_results` ("No stations found").
  String get rdNoResults => _localizedStrings['rd_no_results'] ?? '';
  /// Localized string for `rd_no_results_subtitle` ("Try different keywords or filters.").
  String get rdNoResultsSubtitle =>
      _localizedStrings['rd_no_results_subtitle'] ?? '';
  /// Localized string for `rd_add_station` ("Add Station").
  String get rdAddStation => _localizedStrings['rd_add_station'] ?? '';
  /// Localized string for `rd_edit_station` ("Edit Station").
  String get rdEditStation => _localizedStrings['rd_edit_station'] ?? '';
  /// Localized string for `rd_delete_station` ("Delete Station").
  String get rdDeleteStation => _localizedStrings['rd_delete_station'] ?? '';
  /// Localized string for `rd_delete_confirm` ("Are you sure you want to delete this radio station?").
  String get rdDeleteConfirm => _localizedStrings['rd_delete_confirm'] ?? '';
  /// Localized string for `rd_station_name` ("Station Name").
  String get rdStationName => _localizedStrings['rd_station_name'] ?? '';
  /// Localized string for `rd_stream_url` ("Stream URL (HTTP/HTTPS/M3U8)").
  String get rdStreamUrl => _localizedStrings['rd_stream_url'] ?? '';
  /// Localized string for `rd_genre` ("Genre").
  String get rdGenre => _localizedStrings['rd_genre'] ?? '';
  /// Localized string for `rd_country` ("Country").
  String get rdCountry => _localizedStrings['rd_country'] ?? '';
  /// Localized string for `rd_empty_title` ("No Radio Stations").
  String get rdEmptyTitle => _localizedStrings['rd_empty_title'] ?? '';
  /// Localized string for `rd_empty_subtitle` ("Add online radio stations or HLS live streams to listen directly.").
  String get rdEmptySubtitle => _localizedStrings['rd_empty_subtitle'] ?? '';
  /// Localized string for `rd_cancel` ("Cancel").
  String get rdCancel => _localizedStrings['rd_cancel'] ?? '';
  /// Localized string for `rd_save` ("Save").
  String get rdSave => _localizedStrings['rd_save'] ?? '';
  /// Localized string for `rd_delete` ("Delete").
  String get rdDelete => _localizedStrings['rd_delete'] ?? '';

  // ---------------------------------------------------------------------------
  // sr_: Global Search
  // ---------------------------------------------------------------------------
  /// Localized string for `sr_title` ("Search").
  String get srTitle => _localizedStrings['sr_title'] ?? '';
  /// Localized string for `sr_hint` ("Search by track, artist, album, genre...").
  String get srHint => _localizedStrings['sr_hint'] ?? '';
  /// Localized string for `sr_filter_all` ("All").
  String get srFilterAll => _localizedStrings['sr_filter_all'] ?? '';
  /// Localized string for `sr_no_results` ("No results found").
  String get srNoResults => _localizedStrings['sr_no_results'] ?? '';
  /// Localized string for `sr_no_results_desc` ("Try searching with different keywords or check spelling.").
  String get srNoResultsDesc => _localizedStrings['sr_no_results_desc'] ?? '';
  /// Localized string for `sr_tracks_found` ("Tracks").
  String get srTracksFound => _localizedStrings['sr_tracks_found'] ?? '';
  /// Localized string for `sr_albums_found` ("Albums").
  String get srAlbumsFound => _localizedStrings['sr_albums_found'] ?? '';
  /// Localized string for `sr_artists_found` ("Artists").
  String get srArtistsFound => _localizedStrings['sr_artists_found'] ?? '';
  /// Localized string for `sr_genres_found` ("Genres").
  String get srGenresFound => _localizedStrings['sr_genres_found'] ?? '';
  /// Localized string for `sr_playlists_found` ("Playlists").
  String get srPlaylistsFound =>
      _localizedStrings['sr_playlists_found'] ?? '';
  /// Localized string for `sr_view_more` ("See all ({count})").
  String get srViewMore => _localizedStrings['sr_view_more'] ?? '';
  /// Localized string for `sr_recent_searches` ("Recent Searches").
  String get srRecentSearches =>
      _localizedStrings['sr_recent_searches'] ?? '';
  /// Localized string for `sr_clear_history` ("Clear search history").
  String get srClearHistory => _localizedStrings['sr_clear_history'] ?? '';

  // ---------------------------------------------------------------------------
  // s_: Settings Screen
  // ---------------------------------------------------------------------------
  /// Localized string for `s_title` ("Settings").
  String get sTitle => _localizedStrings['s_title'] ?? '';
  /// Localized string for `s_music_folders` ("Music Sources").
  String get sMusicFolders => _localizedStrings['s_music_folders'] ?? '';
  /// Localized string for `s_music_folders_desc` ("Manage storage folders, local audio files, and audio links in your library.").
  String get sMusicFoldersDesc =>
      _localizedStrings['s_music_folders_desc'] ?? '';
  /// Localized string for `s_music_folders_header` ("Folders").
  String get sMusicFoldersHeader =>
      _localizedStrings['s_music_folders_header'] ?? 'Carpetas';
  /// Localized string for `s_music_files_header` ("Files & Links").
  String get sMusicFilesHeader =>
      _localizedStrings['s_music_files_header'] ?? 'Archivos y enlaces';
  /// Localized string for `s_add_folder` ("Add Folder").
  String get sAddFolder => _localizedStrings['s_add_folder'] ?? '';
  /// Localized string for `s_add_folder_title` ("Add Music Folder").
  String get sAddFolderTitle => _localizedStrings['s_add_folder_title'] ?? '';
  /// Localized string for `s_add_file` ("Add File").
  String get sAddFile => _localizedStrings['s_add_file'] ?? 'Añadir archivo';
  /// Localized string for `s_add_file_title` ("Add Music File or Link").
  String get sAddFileTitle =>
      _localizedStrings['s_add_file_title'] ??
      'Añadir archivo o enlace de música';
  /// Localized string for `s_add_file_local_option` ("Select Local Files").
  String get sAddFileLocalOption =>
      _localizedStrings['s_add_file_local_option'] ??
      'Seleccionar archivos locales';
  /// Localized string for `s_add_file_url_label` ("Direct Audio Link or Path (HTTP/HTTPS)").
  String get sAddFileUrlLabel =>
      _localizedStrings['s_add_file_url_label'] ??
      'Enlace directo o ruta de audio (HTTP/HTTPS)';
  /// Localized string for `s_add_file_url_hint` ("https://example.com/song.mp3").
  String get sAddFileUrlHint =>
      _localizedStrings['s_add_file_url_hint'] ??
      'https://ejemplo.com/cancion.mp3';
  /// Localized string for `s_file_error_invalid` ("File or link is invalid or does not exist").
  String get sFileErrorInvalid =>
      _localizedStrings['s_file_error_invalid'] ??
      'El archivo o enlace no es válido o no existe';
  /// Localized string for `s_no_files_yet` ("No individual files or links added yet.").
  String get sNoFilesYet =>
      _localizedStrings['s_no_files_yet'] ??
      'Aún no se han añadido archivos ni enlaces individuales.';
  /// Localized string for `s_remove_file` ("Remove File").
  String get sRemoveFile =>
      _localizedStrings['s_remove_file'] ?? 'Quitar archivo';
  /// Localized string for `s_view_all_files` ("View all ({count})").
  String get sViewAllFiles =>
      _localizedStrings['s_view_all_files'] ?? 'Ver todos ({count})';
  /// Localized string for `s_manage_files_title` ("Music Files & Links").
  String get sManageFilesTitle =>
      _localizedStrings['s_manage_files_title'] ??
      'Archivos y enlaces de música';
  /// Localized string for `s_search_files_hint` ("Filter files or links...").
  String get sSearchFilesHint =>
      _localizedStrings['s_search_files_hint'] ??
      'Filtrar archivos o enlaces...';
  /// Localized string for `s_filter_all` ("All").
  String get sFilterAll => _localizedStrings['s_filter_all'] ?? 'Todos';
  /// Localized string for `s_filter_local_files` ("Local").
  String get sFilterLocalFiles =>
      _localizedStrings['s_filter_local_files'] ?? 'Locales';
  /// Localized string for `s_filter_links` ("Links").
  String get sFilterLinks => _localizedStrings['s_filter_links'] ?? 'Enlaces';
  /// Localized string for `s_folder_path_hint` ("/path/to/music").
  String get sFolderPathHint => _localizedStrings['s_folder_path_hint'] ?? '';
  /// Localized string for `s_folder_path_label` ("Directory Path").
  String get sFolderPathLabel =>
      _localizedStrings['s_folder_path_label'] ?? '';
  /// Localized string for `s_browse_folder` ("Browse...").
  String get sBrowseFolder => _localizedStrings['s_browse_folder'] ?? '';
  /// Localized string for `s_folder_error_invalid` ("Directory does not exist or is already added").
  String get sFolderErrorInvalid =>
      _localizedStrings['s_folder_error_invalid'] ?? '';
  /// Localized string for `s_no_folders_yet` ("No music folders added yet.").
  String get sNoFoldersYet => _localizedStrings['s_no_folders_yet'] ?? '';
  /// Localized string for `s_browse_folders_desc` ("Add music directories in Settings to browse folders.").
  String get sBrowseFoldersDesc =>
      _localizedStrings['s_browse_folders_desc'] ?? '';
  /// Localized string for `s_cancel` ("Cancel").
  String get sCancel => _localizedStrings['s_cancel'] ?? '';
  /// Localized string for `s_add` ("Add").
  String get sAdd => _localizedStrings['s_add'] ?? '';
  /// Localized string for `s_clear` ("Clear").
  String get sClear => _localizedStrings['s_clear'] ?? '';
  /// Localized string for `s_translation_target_lang` ("Lyrics Translation Language").
  String get sTranslationTargetLang =>
      _localizedStrings['s_translation_target_lang'] ?? '';
  /// Localized string for `s_translation_target_lang_desc` ("Target language for automatic lyric translations.").
  String get sTranslationTargetLangDesc =>
      _localizedStrings['s_translation_target_lang_desc'] ?? '';
  /// Localized string for `s_translation_lang_default` ("Default").
  String get sTranslationLangDefault =>
      _localizedStrings['s_translation_lang_default'] ?? '';
  /// Localized string for `s_audio_devices_title` ("Audio Output Devices").
  String get sAudioDevicesTitle =>
      _localizedStrings['s_audio_devices_title'] ?? '';
  /// Localized string for `s_equalizer_title` ("Equalizer").
  String get sEqualizerTitle => _localizedStrings['s_equalizer_title'] ?? '';
  /// Localized string for `s_equalizer_enabled` ("Enable Equalizer").
  String get sEqualizerEnabled =>
      _localizedStrings['s_equalizer_enabled'] ?? '';
  /// Localized string for `s_equalizer_preset` ("Equalizer Preset").
  String get sEqualizerPreset =>
      _localizedStrings['s_equalizer_preset'] ?? '';
  /// Localized string for `s_eq_preset_flat` ("Flat").
  String get sEqPresetFlat => _localizedStrings['s_eq_preset_flat'] ?? '';
  /// Localized string for `s_eq_preset_rock` ("Rock").
  String get sEqPresetRock => _localizedStrings['s_eq_preset_rock'] ?? '';
  /// Localized string for `s_eq_preset_pop` ("Pop").
  String get sEqPresetPop => _localizedStrings['s_eq_preset_pop'] ?? '';
  /// Localized string for `s_eq_preset_jazz` ("Jazz").
  String get sEqPresetJazz => _localizedStrings['s_eq_preset_jazz'] ?? '';
  /// Localized string for `s_eq_preset_classical` ("Classical").
  String get sEqPresetClassical =>
      _localizedStrings['s_eq_preset_classical'] ?? '';
  /// Localized string for `s_eq_preset_bass_boost` ("Bass Boost").
  String get sEqPresetBassBoost =>
      _localizedStrings['s_eq_preset_bass_boost'] ?? '';
  /// Localized string for `s_eq_preset_custom` ("Custom").
  String get sEqPresetCustom => _localizedStrings['s_eq_preset_custom'] ?? '';
  /// Localized string for `s_remove_folder` ("Remove Folder").
  String get sRemoveFolder => _localizedStrings['s_remove_folder'] ?? '';
  /// Localized string for `s_rescan_library` ("Rescan Library").
  String get sRescanLibrary => _localizedStrings['s_rescan_library'] ?? '';
  /// Localized string for `s_rescan_library_desc` ("Force a background scan of all configured music folders.").
  String get sRescanLibraryDesc =>
      _localizedStrings['s_rescan_library_desc'] ?? '';
  /// Localized string for `s_scanning_progress` ("Scanning library... {progress}%").
  String get sScanningProgress =>
      _localizedStrings['s_scanning_progress'] ?? '';
  /// Localized string for `s_clean_missing_tracks` ("Clean Missing Tracks").
  String get sCleanMissingTracks =>
      _localizedStrings['s_clean_missing_tracks'] ?? '';
  /// Localized string for `s_clean_missing_tracks_desc` ("Remove database entries for files that no longer exist on disk.").
  String get sCleanMissingTracksDesc =>
      _localizedStrings['s_clean_missing_tracks_desc'] ?? '';
  /// Localized string for `s_audio_section` ("Audio Playback").
  String get sAudioSection => _localizedStrings['s_audio_section'] ?? '';
  /// Localized string for `s_crossfade_enable` ("Enable Crossfade").
  String get sCrossfadeEnable =>
      _localizedStrings['s_crossfade_enable'] ?? '';
  /// Localized string for `s_crossfade_enable_desc` ("Smoothly fade out the ending track while fading in the next track.").
  String get sCrossfadeEnableDesc =>
      _localizedStrings['s_crossfade_enable_desc'] ?? '';
  /// Localized string for `s_crossfade_duration` ("Crossfade Duration").
  String get sCrossfadeDuration =>
      _localizedStrings['s_crossfade_duration'] ?? '';
  /// Localized string for `s_crossfade_duration_desc` ("Set overlapping fade transition in seconds (1s to 12s).").
  String get sCrossfadeDurationDesc =>
      _localizedStrings['s_crossfade_duration_desc'] ?? '';
  /// Localized string for `s_crossfade_manual_duration` ("Manual Skip Crossfade").
  String get sCrossfadeManualDuration =>
      _localizedStrings['s_crossfade_manual_duration'] ?? '';
  /// Localized string for `s_crossfade_manual_duration_desc` ("Set fade transition duration when manually skipping tracks (0s to 10s).").
  String get sCrossfadeManualDurationDesc =>
      _localizedStrings['s_crossfade_manual_duration_desc'] ?? '';
  /// Localized string for `s_crossfade_curve` ("Crossfade Curve").
  String get sCrossfadeCurve => _localizedStrings['s_crossfade_curve'] ?? '';
  /// Localized string for `s_crossfade_curve_desc` ("Mathematical attenuation formula used during crossfade transitions.").
  String get sCrossfadeCurveDesc =>
      _localizedStrings['s_crossfade_curve_desc'] ?? '';
  /// Localized string for `s_crossfade_curve_equal_power` ("Equal Power (Smooth)").
  String get sCrossfadeCurveEqualPower =>
      _localizedStrings['s_crossfade_curve_equal_power'] ?? '';
  /// Localized string for `s_crossfade_curve_linear` ("Linear").
  String get sCrossfadeCurveLinear =>
      _localizedStrings['s_crossfade_curve_linear'] ?? '';
  /// Localized string for `s_audio_output` ("Audio Output Device").
  String get sAudioOutput => _localizedStrings['s_audio_output'] ?? '';
  /// Localized string for `s_audio_output_desc` ("Select the sound card or driver used for media output.").
  String get sAudioOutputDesc =>
      _localizedStrings['s_audio_output_desc'] ?? '';
  /// Localized string for `s_exclusive_audio` ("Exclusive Audio Mode").
  String get sExclusiveAudio => _localizedStrings['s_exclusive_audio'] ?? '';
  /// Localized string for `s_exclusive_audio_desc` ("Lock audio device for bit-perfect output on Windows (bypasses OS mixer).").
  String get sExclusiveAudioDesc =>
      _localizedStrings['s_exclusive_audio_desc'] ?? '';
  /// Localized string for `s_pause_on_device_change` ("Pause on Device Change").
  String get sPauseOnDeviceChange =>
      _localizedStrings['s_pause_on_device_change'] ?? '';
  /// Localized string for `s_pause_on_device_change_desc` ("Automatically pause playback when headphones are disconnected or the audio output devic...").
  String get sPauseOnDeviceChangeDesc =>
      _localizedStrings['s_pause_on_device_change_desc'] ?? '';
  /// Localized string for `s_replay_gain_mode` ("ReplayGain Normalization").
  String get sReplayGainMode => _localizedStrings['s_replay_gain_mode'] ?? '';
  /// Localized string for `s_replay_gain_mode_desc` ("Equalize loudness across tracks and albums automatically.").
  String get sReplayGainModeDesc =>
      _localizedStrings['s_replay_gain_mode_desc'] ?? '';
  /// Localized string for `s_replay_gain_preamp` ("ReplayGain Preamp").
  String get sReplayGainPreamp =>
      _localizedStrings['s_replay_gain_preamp'] ?? '';
  /// Localized string for `s_replay_gain_preamp_desc` ("Fine-tune preamp decibel offset applied during replay gain.").
  String get sReplayGainPreampDesc =>
      _localizedStrings['s_replay_gain_preamp_desc'] ?? '';
  /// Localized string for `s_gapless_playback` ("Gapless Playback").
  String get sGaplessPlayback =>
      _localizedStrings['s_gapless_playback'] ?? '';
  /// Localized string for `s_gapless_playback_desc` ("Ensure continuous playback without gaps between consecutive tracks.").
  String get sGaplessPlaybackDesc =>
      _localizedStrings['s_gapless_playback_desc'] ?? '';
  /// Localized string for `s_skip_silence` ("Skip Silence").
  String get sSkipSilence => _localizedStrings['s_skip_silence'] ?? '';
  /// Localized string for `s_skip_silence_desc` ("Automatically skip silent passages during playback.").
  String get sSkipSilenceDesc =>
      _localizedStrings['s_skip_silence_desc'] ?? '';
  /// Localized string for `s_preamp` ("Preamp").
  String get sPreamp => _localizedStrings['s_preamp'] ?? '';
  /// Localized string for `s_preamp_desc` ("Digital gain stage before equalization (-12 dB to +12 dB).").
  String get sPreampDesc => _localizedStrings['s_preamp_desc'] ?? '';
  /// Localized string for `s_stereo_balance` ("Stereo Balance").
  String get sStereoBalance => _localizedStrings['s_stereo_balance'] ?? '';
  /// Localized string for `s_stereo_balance_desc` ("Adjust channel balance between left and right.").
  String get sStereoBalanceDesc =>
      _localizedStrings['s_stereo_balance_desc'] ?? '';
  /// Localized string for `s_stereo_balance_center` ("Center").
  String get sStereoBalanceCenter =>
      _localizedStrings['s_stereo_balance_center'] ?? '';
  /// Localized string for `s_mono_audio` ("Mono Audio").
  String get sMonoAudio => _localizedStrings['s_mono_audio'] ?? '';
  /// Localized string for `s_mono_audio_desc` ("Downmix stereo channels to mono.").
  String get sMonoAudioDesc => _localizedStrings['s_mono_audio_desc'] ?? '';
  /// Localized string for `s_crossfeed` ("Bauer Crossfeed (bs2b)").
  String get sCrossfeed => _localizedStrings['s_crossfeed'] ?? '';
  /// Localized string for `s_crossfeed_desc` ("Simulates loudspeaker listening to reduce headphone fatigue.").
  String get sCrossfeedDesc => _localizedStrings['s_crossfeed_desc'] ?? '';
  /// Localized string for `s_crossfeed_off` ("Off").
  String get sCrossfeedOff => _localizedStrings['s_crossfeed_off'] ?? '';
  /// Localized string for `s_crossfeed_moffat` ("Default (700Hz / 4.5dB)").
  String get sCrossfeedMoffat =>
      _localizedStrings['s_crossfeed_moffat'] ?? '';
  /// Localized string for `s_crossfeed_chumoy` ("Chu Moy (700Hz / 6.0dB)").
  String get sCrossfeedChumoy =>
      _localizedStrings['s_crossfeed_chumoy'] ?? '';
  /// Localized string for `s_spatializer` ("Stereo Width").
  String get sSpatializer => _localizedStrings['s_spatializer'] ?? '';
  /// Localized string for `s_spatializer_desc` ("Widen or narrow the stereo field (0.0x to 2.0x).").
  String get sSpatializerDesc =>
      _localizedStrings['s_spatializer_desc'] ?? '';
  /// Localized string for `s_limiter` ("True-Peak Limiter").
  String get sLimiter => _localizedStrings['s_limiter'] ?? '';
  /// Localized string for `s_limiter_desc` ("Prevents DAC digital clipping and harsh distortion.").
  String get sLimiterDesc => _localizedStrings['s_limiter_desc'] ?? '';
  /// Localized string for `s_reverb` ("Studio Reverb").
  String get sReverb => _localizedStrings['s_reverb'] ?? '';
  /// Localized string for `s_reverb_desc` ("Acoustic space and room simulation.").
  String get sReverbDesc => _localizedStrings['s_reverb_desc'] ?? '';
  /// Localized string for `s_reverb_preset` ("Reverb Preset").
  String get sReverbPreset => _localizedStrings['s_reverb_preset'] ?? '';
  /// Localized string for `s_reverb_preset_off` ("Off").
  String get sReverbPresetOff =>
      _localizedStrings['s_reverb_preset_off'] ?? '';
  /// Localized string for `s_reverb_preset_small_room` ("Small Room").
  String get sReverbPresetSmallRoom =>
      _localizedStrings['s_reverb_preset_small_room'] ?? '';
  /// Localized string for `s_reverb_preset_studio` ("Studio").
  String get sReverbPresetStudio =>
      _localizedStrings['s_reverb_preset_studio'] ?? '';
  /// Localized string for `s_reverb_preset_concert_hall` ("Concert Hall").
  String get sReverbPresetConcertHall =>
      _localizedStrings['s_reverb_preset_concert_hall'] ?? '';
  /// Localized string for `s_reverb_preset_cathedral` ("Cathedral").
  String get sReverbPresetCathedral =>
      _localizedStrings['s_reverb_preset_cathedral'] ?? '';
  /// Localized string for `s_reverb_preset_plate` ("Plate").
  String get sReverbPresetPlate =>
      _localizedStrings['s_reverb_preset_plate'] ?? '';
  /// Localized string for `s_reverb_preset_ambient` ("Ambient").
  String get sReverbPresetAmbient =>
      _localizedStrings['s_reverb_preset_ambient'] ?? '';
  /// Localized string for `s_reverb_preset_custom` ("Custom").
  String get sReverbPresetCustom =>
      _localizedStrings['s_reverb_preset_custom'] ?? '';
  /// Localized string for `s_reverb_room_size` ("Room Size").
  String get sReverbRoomSize => _localizedStrings['s_reverb_room_size'] ?? '';
  /// Localized string for `s_reverb_damping` ("Damping").
  String get sReverbDamping => _localizedStrings['s_reverb_damping'] ?? '';
  /// Localized string for `s_reverb_width` ("Stereo Width").
  String get sReverbWidth => _localizedStrings['s_reverb_width'] ?? '';
  /// Localized string for `s_reverb_wet` ("Wet Mix").
  String get sReverbWet => _localizedStrings['s_reverb_wet'] ?? '';
  /// Localized string for `s_reverb_dry` ("Dry Level").
  String get sReverbDry => _localizedStrings['s_reverb_dry'] ?? '';
  /// Localized string for `s_audio_dsp_section` ("Stereo & DSP Effects").
  String get sAudioDspSection =>
      _localizedStrings['s_audio_dsp_section'] ?? '';
  /// Localized string for `s_appearance_section` ("Appearance").
  String get sAppearanceSection =>
      _localizedStrings['s_appearance_section'] ?? '';
  /// Localized string for `s_theme_mode` ("Theme").
  String get sThemeMode => _localizedStrings['s_theme_mode'] ?? '';
  /// Localized string for `s_theme_mode_desc` ("Choose between System, Light, Dark, or True OLED black.").
  String get sThemeModeDesc => _localizedStrings['s_theme_mode_desc'] ?? '';
  /// Localized string for `s_theme_system` ("Default").
  String get sThemeSystem => _localizedStrings['s_theme_system'] ?? '';
  /// Localized string for `s_theme_light` ("Light").
  String get sThemeLight => _localizedStrings['s_theme_light'] ?? '';
  /// Localized string for `s_theme_dark` ("Dark").
  String get sThemeDark => _localizedStrings['s_theme_dark'] ?? '';
  /// Localized string for `s_theme_oled` ("Pure OLED").
  String get sThemeOled => _localizedStrings['s_theme_oled'] ?? '';
  /// Localized string for `s_theme_oled_desc` ("Use absolute black (#000000) in dark theme for OLED displays.").
  String get sThemeOledDesc => _localizedStrings['s_theme_oled_desc'] ?? '';
  /// Localized string for `s_accent_color` ("Accent Color").
  String get sAccentColor => _localizedStrings['s_accent_color'] ?? '';
  /// Localized string for `s_accent_color_desc` ("Select the primary color used for highlights and controls.").
  String get sAccentColorDesc =>
      _localizedStrings['s_accent_color_desc'] ?? '';
  /// Localized string for `s_dynamic_color` ("Dynamic Artwork Color").
  String get sDynamicColor => _localizedStrings['s_dynamic_color'] ?? '';
  /// Localized string for `s_dynamic_color_desc` ("Adapt player UI colors to match the currently playing album artwork.").
  String get sDynamicColorDesc =>
      _localizedStrings['s_dynamic_color_desc'] ?? '';
  /// Localized string for `s_custom_background` ("Custom Background").
  String get sCustomBackground =>
      _localizedStrings['s_custom_background'] ?? '';
  /// Localized string for `s_custom_background_desc` ("Set a custom wallpaper image for the application.").
  String get sCustomBackgroundDesc =>
      _localizedStrings['s_custom_background_desc'] ?? '';
  /// Localized string for `s_select_background_image` ("Select Image").
  String get sSelectBackgroundImage =>
      _localizedStrings['s_select_background_image'] ?? '';
  /// Localized string for `s_change_background_image` ("Change Image").
  String get sChangeBackgroundImage =>
      _localizedStrings['s_change_background_image'] ?? '';
  /// Localized string for `s_remove_background_image` ("Remove Background").
  String get sRemoveBackgroundImage =>
      _localizedStrings['s_remove_background_image'] ?? '';
  /// Localized string for `s_background_blur` ("Gaussian Blur").
  String get sBackgroundBlur => _localizedStrings['s_background_blur'] ?? '';
  /// Localized string for `s_background_blur_desc` ("Adjust background blur intensity for readability.").
  String get sBackgroundBlurDesc =>
      _localizedStrings['s_background_blur_desc'] ?? '';
  /// Localized string for `s_background_dim` ("Background Dimming").
  String get sBackgroundDim => _localizedStrings['s_background_dim'] ?? '';
  /// Localized string for `s_background_dim_desc` ("Adjust overlay opacity to ensure contrast and readability.").
  String get sBackgroundDimDesc =>
      _localizedStrings['s_background_dim_desc'] ?? '';
  /// Localized string for `s_custom_background_file_error` ("Failed to load selected image.").
  String get sCustomBackgroundFileError =>
      _localizedStrings['s_custom_background_file_error'] ?? '';
  /// Localized string for `s_language_section` ("Language").
  String get sLanguageSection =>
      _localizedStrings['s_language_section'] ?? '';
  /// Localized string for `s_language` ("App Language").
  String get sLanguage => _localizedStrings['s_language'] ?? '';
  /// Localized string for `s_language_desc` ("Switch interface language in real time without restarting the app.").
  String get sLanguageDesc => _localizedStrings['s_language_desc'] ?? '';
  /// Localized string for `s_language_search_hint` ("Search language...").
  String get sLanguageSearchHint =>
      _localizedStrings['s_language_search_hint'] ?? '';
  /// Localized string for `s_integrations_section` ("Integrations").
  String get sIntegrationsSection =>
      _localizedStrings['s_integrations_section'] ?? '';
  /// Localized string for `s_discord_rpc` ("Discord Rich Presence").
  String get sDiscordRpc => _localizedStrings['s_discord_rpc'] ?? '';
  /// Localized string for `s_discord_rpc_desc` ("Show currently playing music title and artist on your Discord profile.").
  String get sDiscordRpcDesc => _localizedStrings['s_discord_rpc_desc'] ?? '';
  /// Localized string for `s_media_notifications` ("Media Notifications").
  String get sMediaNotifications =>
      _localizedStrings['s_media_notifications'] ?? '';
  /// Localized string for `s_media_notifications_desc` ("Display lockscreen controls and system notifications for playback.").
  String get sMediaNotificationsDesc =>
      _localizedStrings['s_media_notifications_desc'] ?? '';
  /// Localized string for `s_about_section` ("About Tachyon").
  String get sAboutSection => _localizedStrings['s_about_section'] ?? '';
  /// Localized string for `s_app_version` ("Version").
  String get sAppVersion => _localizedStrings['s_app_version'] ?? '';
  /// Localized string for `s_check_updates` ("Check for Updates").
  String get sCheckUpdates => _localizedStrings['s_check_updates'] ?? '';
  /// Localized string for `s_check_updates_desc` ("Verify whether a newer release is available on GitHub.").
  String get sCheckUpdatesDesc =>
      _localizedStrings['s_check_updates_desc'] ?? '';
  /// Localized string for `s_view_changelog` ("View Changelog").
  String get sViewChangelog => _localizedStrings['s_view_changelog'] ?? '';
  /// Localized string for `s_github_repo` ("Source Code Repository").
  String get sGithubRepo => _localizedStrings['s_github_repo'] ?? '';
  /// Localized string for `s_license` ("License & Third Party").
  String get sLicense => _localizedStrings['s_license'] ?? '';
  /// Localized string for `s_storage_used` ("Database & Cache Size").
  String get sStorageUsed => _localizedStrings['s_storage_used'] ?? '';
  /// Localized string for `s_clear_cache` ("Clear Cover Cache").
  String get sClearCache => _localizedStrings['s_clear_cache'] ?? '';
  /// Localized string for `s_clear_cache_desc` ("Delete locally cached album cover images to free up disk space.").
  String get sClearCacheDesc => _localizedStrings['s_clear_cache_desc'] ?? '';
  /// Localized string for `s_clear_cache_success` ("Cover cache cleared successfully").
  String get sClearCacheSuccess =>
      _localizedStrings['s_clear_cache_success'] ?? '';

  // ---------------------------------------------------------------------------
  // up_: Software Updater
  // ---------------------------------------------------------------------------
  /// Localized string for `up_title` ("Software Update").
  String get upTitle => _localizedStrings['up_title'] ?? '';
  /// Localized string for `up_available` ("Update Available").
  String get upAvailable => _localizedStrings['up_available'] ?? '';
  /// Localized string for `up_available_desc` ("A new version of Tachyon is available for download.").
  String get upAvailableDesc => _localizedStrings['up_available_desc'] ?? '';
  /// Localized string for `up_up_to_date` ("You are running the latest version").
  String get upUpToDate => _localizedStrings['up_up_to_date'] ?? '';
  /// Localized string for `up_checking` ("Checking for updates...").
  String get upChecking => _localizedStrings['up_checking'] ?? '';
  /// Localized string for `up_check_now` ("Check Now").
  String get upCheckNow => _localizedStrings['up_check_now'] ?? '';
  /// Localized string for `up_current_version` ("Current Version: {version}").
  String get upCurrentVersion =>
      _localizedStrings['up_current_version'] ?? '';
  /// Localized string for `up_latest_version` ("Latest Version: {version}").
  String get upLatestVersion => _localizedStrings['up_latest_version'] ?? '';
  /// Localized string for `up_download_button` ("Download Update").
  String get upDownloadButton =>
      _localizedStrings['up_download_button'] ?? '';
  /// Localized string for `up_downloading` ("Downloading update: {progress}%").
  String get upDownloading => _localizedStrings['up_downloading'] ?? '';
  /// Localized string for `up_install_button` ("Install & Restart").
  String get upInstallButton => _localizedStrings['up_install_button'] ?? '';
  /// Localized string for `up_dismiss` ("Later").
  String get upDismiss => _localizedStrings['up_dismiss'] ?? '';
  /// Localized string for `up_release_notes` ("Release Notes").
  String get upReleaseNotes => _localizedStrings['up_release_notes'] ?? '';
  /// Localized string for `up_error` ("Unable to check for updates").
  String get upError => _localizedStrings['up_error'] ?? '';
  /// Localized string for `up_error_network` ("Please check your network connection and try again.").
  String get upErrorNetwork => _localizedStrings['up_error_network'] ?? '';

  // ---------------------------------------------------------------------------
  // cl_: Changelog Viewer
  // ---------------------------------------------------------------------------
  /// Localized string for `cl_title` ("Changelog").
  String get clTitle => _localizedStrings['cl_title'] ?? '';
  /// Localized string for `cl_close` ("Close").
  String get clClose => _localizedStrings['cl_close'] ?? '';
  /// Localized string for `cl_version` ("Version {version}").
  String get clVersion => _localizedStrings['cl_version'] ?? '';
  /// Localized string for `cl_latest_changes` ("What's New").
  String get clLatestChanges => _localizedStrings['cl_latest_changes'] ?? '';
  /// Localized string for `cl_error_loading` ("Could not load changelog details.").
  String get clErrorLoading => _localizedStrings['cl_error_loading'] ?? '';
  /// Localized string for `cl_view_on_github` ("View full release notes on GitHub").
  String get clViewOnGithub => _localizedStrings['cl_view_on_github'] ?? '';

  // ---------------------------------------------------------------------------
  // sel_: Multi-selection Toolbar
  // ---------------------------------------------------------------------------
  /// Localized string for `sel_selected_count` ("{count} selected").
  String get selSelectedCount =>
      _localizedStrings['sel_selected_count'] ?? '';
  /// Localized string for `sel_select` ("Select").
  String get selSelect => _localizedStrings['sel_select'] ?? '';
  /// Localized string for `sel_cancel` ("Cancel").
  String get selCancel => _localizedStrings['sel_cancel'] ?? '';
  /// Localized string for `sel_select_all` ("Select all").
  String get selSelectAll => _localizedStrings['sel_select_all'] ?? '';
  /// Localized string for `sel_deselect_all` ("Deselect all").
  String get selDeselectAll => _localizedStrings['sel_deselect_all'] ?? '';

  // ---------------------------------------------------------------------------
  // common_: Common UI Labels
  // ---------------------------------------------------------------------------
  /// Localized string for `common_view_as_cards` ("Cards view").
  String get commonViewAsCards =>
      _localizedStrings['common_view_as_cards'] ?? '';
  /// Localized string for `common_view_as_list` ("List view").
  String get commonViewAsList =>
      _localizedStrings['common_view_as_list'] ?? '';
  /// Localized string for `common_back` ("Back").
  String get commonBack => _localizedStrings['common_back'] ?? '';
  /// Localized string for `common_minimize` ("Minimize").
  String get commonMinimize => _localizedStrings['common_minimize'] ?? '';

  // ---------------------------------------------------------------------------
  // win_ & tray_: Desktop Window & System Tray Controls
  // ---------------------------------------------------------------------------
  /// Localized string for `win_send_to_background` ("Send to background").
  String get winSendToBackground =>
      _localizedStrings['win_send_to_background'] ?? '';
  /// Localized string for `win_minimize` ("Minimize").
  String get winMinimize => _localizedStrings['win_minimize'] ?? '';
  /// Localized string for `win_maximize` ("Maximize").
  String get winMaximize => _localizedStrings['win_maximize'] ?? '';
  /// Localized string for `win_restore` ("Restore").
  String get winRestore => _localizedStrings['win_restore'] ?? '';
  /// Localized string for `win_close` ("Close").
  String get winClose => _localizedStrings['win_close'] ?? '';
  /// Localized string for `tray_show_app` ("Show Tachyon").
  String get trayShowApp => _localizedStrings['tray_show_app'] ?? '';
  /// Localized string for `tray_shuffle` ("Shuffle").
  String get trayShuffle => _localizedStrings['tray_shuffle'] ?? '';
  /// Localized string for `tray_quit` ("Quit").
  String get trayQuit => _localizedStrings['tray_quit'] ?? '';

  // ---------------------------------------------------------------------------
  // scan_: Scan Progress Overlay
  // ---------------------------------------------------------------------------
  /// Localized string for `scan_stage_idle` ("Idle").
  String get scanStageIdle => _localizedStrings['scan_stage_idle'] ?? '';
  /// Localized string for `scan_stage_getting_database` ("Loading database...").
  String get scanStageGettingDatabase =>
      _localizedStrings['scan_stage_getting_database'] ?? '';
  /// Localized string for `scan_stage_getting_tracks` ("Fetching tracks...").
  String get scanStageGettingTracks =>
      _localizedStrings['scan_stage_getting_tracks'] ?? '';
  /// Localized string for `scan_stage_discovering` ("Discovering files...").
  String get scanStageDiscovering =>
      _localizedStrings['scan_stage_discovering'] ?? '';
  /// Localized string for `scan_stage_comparing` ("Comparing files...").
  String get scanStageComparing =>
      _localizedStrings['scan_stage_comparing'] ?? '';
  /// Localized string for `scan_stage_extracting` ("Reading metadata").
  String get scanStageExtracting =>
      _localizedStrings['scan_stage_extracting'] ?? '';
  /// Localized string for `scan_stage_inserting` ("Saving tracks...").
  String get scanStageInserting =>
      _localizedStrings['scan_stage_inserting'] ?? '';
  /// Localized string for `scan_stage_cleaning_orphans` ("Cleaning missing tracks...").
  String get scanStageCleaningOrphans =>
      _localizedStrings['scan_stage_cleaning_orphans'] ?? '';
  /// Localized string for `scan_stage_cleaning_thumbnails` ("Cleaning thumbnails...").
  String get scanStageCleaningThumbnails =>
      _localizedStrings['scan_stage_cleaning_thumbnails'] ?? '';
  /// Localized string for `scan_stage_completed` ("Completed").
  String get scanStageCompleted =>
      _localizedStrings['scan_stage_completed'] ?? '';
  /// Localized string for `scan_stage_failed` ("Scan failed").
  String get scanStageFailed => _localizedStrings['scan_stage_failed'] ?? '';
  /// Localized string for `scan_stage_cancelled` ("Cancelled").
  String get scanStageCancelled =>
      _localizedStrings['scan_stage_cancelled'] ?? '';
  /// Localized string for `scan_cancel_tooltip` ("Cancel scan").
  String get scanCancelTooltip =>
      _localizedStrings['scan_cancel_tooltip'] ?? '';

  // ---------------------------------------------------------------------------
  // Parametric Formatters
  // ---------------------------------------------------------------------------
  /// Formats the localized `trCount` template with the provided arguments.
  String trCountFormatted(int count) =>
      trCount.replaceAll('{count}', count.toString());
  /// Formats the localized `trAddedToPlaylist` template with the provided arguments.
  String trAddedToPlaylistFormatted(String name) =>
      trAddedToPlaylist.replaceAll('{name}', name);
  /// Formats the localized `selSelectedCount` template with the provided arguments.
  String selSelectedCountFormatted(int count) =>
      selSelectedCount.replaceAll('{count}', count.toString());
  /// Formats the localized `alTracksCount` template with the provided arguments.
  String alTracksCountFormatted(int count) =>
      alTracksCount.replaceAll('{count}', count.toString());
  /// Formats the localized `arAlbumsCount` template with the provided arguments.
  String arAlbumsCountFormatted(int count) =>
      arAlbumsCount.replaceAll('{count}', count.toString());
  /// Formats the localized `arTracksCount` template with the provided arguments.
  String arTracksCountFormatted(int count) =>
      arTracksCount.replaceAll('{count}', count.toString());
  /// Formats the localized `plTracksCount` template with the provided arguments.
  String plTracksCountFormatted(int count) =>
      plTracksCount.replaceAll('{count}', count.toString());
  /// Formats the localized `plDeleteConfirm` template with the provided arguments.
  String plDeleteConfirmFormatted(String name) =>
      plDeleteConfirm.replaceAll('{name}', name);
  /// Formats the localized `plDuplicateConfirm` template with the provided arguments.
  String plDuplicateConfirmFormatted(String name) =>
      plDuplicateConfirm.replaceAll('{name}', name);
  /// Formats the localized `plDuplicateQueueConfirm` template with the provided arguments.
  String plDuplicateQueueConfirmFormatted(String name) =>
      plDuplicateQueueConfirm.replaceAll('{name}', name);
  /// Formats the localized `plInsertOnlyNew` template with the provided arguments.
  String plInsertOnlyNewFormatted(int count) =>
      plInsertOnlyNew.replaceAll('{count}', count.toString());
  /// Formats the localized `gTracksCount` template with the provided arguments.
  String gTracksCountFormatted(int count) =>
      gTracksCount.replaceAll('{count}', count.toString());
  /// Formats the localized `gAlbumsCount` template with the provided arguments.
  String gAlbumsCountFormatted(int count) =>
      gAlbumsCount.replaceAll('{count}', count.toString());
  /// Formats the localized `fItemsCount` template with the provided arguments.
  String fItemsCountFormatted(int count) =>
      fItemsCount.replaceAll('{count}', count.toString());
  /// Formats the localized `srViewMore` template with the provided arguments.
  String srViewMoreFormatted(int count) =>
      srViewMore.replaceAll('{count}', count.toString());
  /// Formats the localized `sScanningProgress` template with the provided arguments.
  String sScanningProgressFormatted(int progress) =>
      sScanningProgress.replaceAll('{progress}', progress.toString());
  /// Formats the localized `sViewAllFiles` template with the provided arguments.
  String sViewAllFilesFormatted(int count) =>
      sViewAllFiles.replaceAll('{count}', count.toString());
  /// Formats the localized `upCurrentVersion` template with the provided arguments.
  String upCurrentVersionFormatted(String version) =>
      upCurrentVersion.replaceAll('{version}', version);
  /// Formats the localized `upLatestVersion` template with the provided arguments.
  String upLatestVersionFormatted(String version) =>
      upLatestVersion.replaceAll('{version}', version);
  /// Formats the localized `upDownloading` template with the provided arguments.
  String upDownloadingFormatted(int progress) =>
      upDownloading.replaceAll('{progress}', progress.toString());
  /// Formats the localized `clVersion` template with the provided arguments.
  String clVersionFormatted(String version) =>
      clVersion.replaceAll('{version}', version);
  /// Formats the localized `npLyricsThresholdWaiting` template with the provided arguments.
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
    'np_visualizer_mode',
    'np_visualizer_off',
    'np_visualizer_wave',
    'np_visualizer_bars',
    'np_visualizer_circle',
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
    's_title', 's_music_folders', 's_music_folders_desc',
    's_music_folders_header', 's_music_files_header',
    's_add_folder', 's_add_folder_title',
    's_add_file', 's_add_file_title', 's_add_file_local_option',
    's_add_file_url_label', 's_add_file_url_hint', 's_file_error_invalid',
    's_no_files_yet', 's_remove_file', 's_view_all_files',
    's_manage_files_title', 's_search_files_hint',
    's_filter_all', 's_filter_local_files', 's_filter_links',
    's_folder_path_hint', 's_folder_path_label',
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
    // win_ & tray_
    'win_send_to_background', 'win_minimize', 'win_maximize', 'win_restore',
    'win_close', 'tray_show_app', 'tray_shuffle', 'tray_quit',
    // scan_
    'scan_stage_idle', 'scan_stage_getting_database',
    'scan_stage_getting_tracks', 'scan_stage_discovering',
    'scan_stage_comparing', 'scan_stage_extracting',
    'scan_stage_inserting', 'scan_stage_cleaning_orphans',
    'scan_stage_cleaning_thumbnails', 'scan_stage_completed',
    'scan_stage_failed', 'scan_stage_cancelled', 'scan_cancel_tooltip',
  ];

  /// Localized catalog helper member.
  List<String> get allKeys => List.unmodifiable(_allAppStrings);

  /// Localized catalog helper member.
  Map<String, String> toJson() =>
      Map<String, String>.unmodifiable(_localizedStrings);

  /// Updates the in-memory translation table from [jsonMap] and optionally verifies key completeness.
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
