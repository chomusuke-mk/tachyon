#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <shellapi.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that hosts a Flutter view, custom titlebar framing, memory trimming,
// and native Win32 system tray controls.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void SetupWindowStateChannel();
  void EmitWindowStateChanged();
  void EmitTrayAction(const std::string& action);
  flutter::EncodableMap BuildWindowStateMap() const;
  void UpdateTrayIcon(const flutter::EncodableMap& args);
  void RemoveTrayIcon();
  void ShowTrayContextMenu();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Bidirectional MethodChannel for window & tray state synchronization.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_state_channel_;

  bool is_minimized_ = false;
  bool is_focused_ = true;
  bool is_maximized_ = false;
  bool is_hidden_to_tray_ = false;

  NOTIFYICONDATAW tray_icon_data_{};
  bool tray_icon_added_ = false;
  bool tray_is_playing_ = false;
  bool tray_is_shuffled_ = false;
  bool tray_has_track_ = false;
  std::wstring tray_tooltip_ = L"Tachyon";
  std::wstring tray_play_label_ = L"Play";
  std::wstring tray_pause_label_ = L"Pause";
  std::wstring tray_next_label_ = L"Next track";
  std::wstring tray_previous_label_ = L"Previous track";
  std::wstring tray_shuffle_label_ = L"Shuffle";
  std::wstring tray_show_app_label_ = L"Show Tachyon";
  std::wstring tray_quit_label_ = L"Quit";
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
