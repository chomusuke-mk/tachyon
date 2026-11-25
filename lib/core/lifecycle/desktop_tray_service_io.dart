import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tachyon/core/lifecycle/app_lifecycle_controller.dart';
import 'package:tachyon/core/lifecycle/linux_status_notifier_tray.dart';
import 'package:tachyon/core/lifecycle/window_control_bridge.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/features/locales/presentation/controllers/locale_controller.dart';

/// Synchronizes desktop system tray icons, hover track tooltips, and localized
/// context menus across Linux (`StatusNotifierItem`), Windows (`Shell_NotifyIcon`),
/// and macOS (`NSStatusBar`).
class DesktopTrayService {
  final PlaybackController _playbackController;
  final LocaleController _localeController;
  final WindowControlBridge _windowBridge;

  LinuxStatusNotifierTray? _linuxTray;
  AppLifecycleController? _lifecycleController;
  bool _isVisible = false;
  bool _isDisposed = false;
  String? _lastBackgroundTooltip;

  /// Creates a [DesktopTrayService].
  DesktopTrayService({
    required this._playbackController,
    required this._localeController,
    required this._windowBridge,
  }) {
    _playbackController.addListener(_syncTrayPresentation);
    _localeController.addListener(_onLocaleUpdated);
  }

  /// Attaches [lifecycleController] so tray clicks dispatch directly to it.
  void attachLifecycleController(AppLifecycleController lifecycleController) {
    _lifecycleController = lifecycleController;
  }

  /// Initializes platform tray state and syncs initial localized tooltips.
  Future<void> initialize() async {
    if (_isDisposed || kIsWeb || !_windowBridge.isDesktopPlatform) return;
    if (Platform.isLinux) {
      _linuxTray ??= LinuxStatusNotifierTray(
        onAction: _handleAction,
        processId: pid,
      );
    }
    _syncBackgroundHeaderButtonTooltip();
  }

  /// Shows or hides the system tray icon.
  Future<void> setVisible(bool visible) async {
    if (_isDisposed || kIsWeb || !_windowBridge.isDesktopPlatform) return;
    _isVisible = visible;
    if (Platform.isLinux) {
      _linuxTray ??= LinuxStatusNotifierTray(
        onAction: _handleAction,
        processId: pid,
      );
      await _linuxTray!.setVisible(visible);
    }
    await _syncTrayPresentationAsync();
  }

  void _handleAction(DesktopTrayAction action) {
    final lifecycle = _lifecycleController;
    switch (action) {
      case DesktopTrayAction.restore:
        unawaited(lifecycle?.restoreFromBackground());
        break;
      case DesktopTrayAction.playPause:
        unawaited(_playbackController.playOrPause());
        break;
      case DesktopTrayAction.next:
        unawaited(_playbackController.next());
        break;
      case DesktopTrayAction.previous:
        unawaited(_playbackController.previous());
        break;
      case DesktopTrayAction.toggleShuffle:
        unawaited(_playbackController.toggleShuffle());
        break;
      case DesktopTrayAction.quit:
        unawaited(lifecycle?.closeApplication());
        break;
    }
  }

  void _onLocaleUpdated() {
    _syncBackgroundHeaderButtonTooltip();
    _syncTrayPresentation();
  }

  void _syncBackgroundHeaderButtonTooltip() {
    if (_isDisposed || kIsWeb || !Platform.isLinux) return;
    final label = _localeController.localeStrings.winSendToBackground;
    final tooltip = label.isNotEmpty ? label : 'Send to background';
    if (tooltip == _lastBackgroundTooltip) return;
    _lastBackgroundTooltip = tooltip;
    unawaited(_windowBridge.setBackgroundButtonTooltip(tooltip));
  }

  TrayPresentationState _buildPresentationState() {
    final strings = _localeController.localeStrings;
    final playable = _playbackController.currentPlayable;
    final displayMeta = _playbackController.currentDisplayMetadata;

    String tooltipTitle = 'Tachyon';
    String tooltipSubtitle = '';
    if (playable != null) {
      final title = (displayMeta?.title ?? playable.title).trim();
      final artist = (displayMeta?.subtitle ?? playable.artistNames.join(', '))
          .trim();
      if (title.isNotEmpty) {
        tooltipTitle = title;
      }
      if (artist.isNotEmpty) {
        tooltipSubtitle = artist;
      }
    }

    final rawFull = tooltipSubtitle.isNotEmpty
        ? '$tooltipTitle — $tooltipSubtitle'
        : tooltipTitle;
    final fullTooltip = rawFull.length > 127
        ? '${rawFull.substring(0, 124)}...'
        : rawFull;

    String pickLabel(String localized, String fallback) =>
        localized.isNotEmpty ? localized : fallback;

    return TrayPresentationState(
      tooltipTitle: tooltipTitle,
      tooltipSubtitle: tooltipSubtitle,
      fullTooltip: fullTooltip,
      isPlaying: _playbackController.isPlaying,
      isShuffled: _playbackController.isShuffled,
      hasTrack: playable != null,
      playLabel: pickLabel(strings.npPlay, 'Play'),
      pauseLabel: pickLabel(strings.npPause, 'Pause'),
      nextLabel: pickLabel(strings.npNext, 'Next track'),
      previousLabel: pickLabel(strings.npPrevious, 'Previous track'),
      shuffleLabel: pickLabel(strings.trayShuffle, 'Shuffle'),
      showAppLabel: pickLabel(strings.trayShowApp, 'Show Tachyon'),
      quitLabel: pickLabel(strings.trayQuit, 'Quit'),
    );
  }

  void _syncTrayPresentation() {
    if (_isDisposed || !_isVisible) return;
    unawaited(_syncTrayPresentationAsync());
  }

  Future<void> _syncTrayPresentationAsync() async {
    if (_isDisposed || kIsWeb || !_windowBridge.isDesktopPlatform) return;
    final state = _buildPresentationState();
    if (Platform.isLinux) {
      await _linuxTray?.updateState(state);
    } else if (Platform.isWindows || Platform.isMacOS) {
      await _windowBridge.updateNativeTrayState(
        visible: _isVisible,
        tooltip: state.fullTooltip,
        isPlaying: state.isPlaying,
        isShuffled: state.isShuffled,
        hasTrack: state.hasTrack,
        playLabel: state.playLabel,
        pauseLabel: state.pauseLabel,
        nextLabel: state.nextLabel,
        previousLabel: state.previousLabel,
        shuffleLabel: state.shuffleLabel,
        showAppLabel: state.showAppLabel,
        quitLabel: state.quitLabel,
      );
    }
  }

  /// Releases playback/locale listeners and disposes native tray handles.
  Future<void> dispose() async {
    _isDisposed = true;
    _isVisible = false;
    _playbackController.removeListener(_syncTrayPresentation);
    _localeController.removeListener(_onLocaleUpdated);
    await _linuxTray?.dispose();
    _linuxTray = null;
  }
}
