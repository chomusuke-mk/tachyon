#include "flutter_window.h"

#include <dwmapi.h>
#include <flutter/standard_method_codec.h>
#include <malloc.h>
#include <windows.h>
#include <windowsx.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr UINT kTrayIconId = 1;
constexpr UINT kTrayCallbackMessage = WM_APP + 100;
constexpr UINT_PTR kIdleTrimTimerId = 1001;

constexpr UINT kMenuCmdPlayPause = 2001;
constexpr UINT kMenuCmdNext = 2002;
constexpr UINT kMenuCmdPrevious = 2003;
constexpr UINT kMenuCmdShuffle = 2004;
constexpr UINT kMenuCmdShowApp = 2005;
constexpr UINT kMenuCmdQuit = 2006;

// Trims excess heap allocations and flushes unreferenced pages from the working
// set.
void TrimProcessMemory() {
  _heapmin();
  HANDLE process_heap = ::GetProcessHeap();
  if (process_heap != NULL) {
    ::HeapCompact(process_heap, 0);
  }
  ::SetProcessWorkingSetSize(::GetCurrentProcess(), static_cast<SIZE_T>(-1),
                             static_cast<SIZE_T>(-1));
}

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int needed = ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                     static_cast<int>(utf8.size()), nullptr, 0);
  if (needed <= 0) return std::wstring();
  std::wstring wide(static_cast<size_t>(needed), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                        wide.data(), needed);
  return wide;
}

std::string ReadStringValue(const flutter::EncodableMap& map,
                            const char* key,
                            const std::string& fallback) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it != map.end()) {
    if (const auto* s = std::get_if<std::string>(&it->second)) {
      if (!s->empty()) return *s;
    }
  }
  return fallback;
}

bool ReadBoolValue(const flutter::EncodableMap& map,
                   const char* key,
                   bool fallback) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it != map.end()) {
    if (const auto* b = std::get_if<bool>(&it->second)) {
      return *b;
    }
  }
  return fallback;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  SetupWindowStateChannel();

  // Keep subtle DWM frame shadow while letting Flutter draw the custom titlebar.
  MARGINS margins = {0, 0, 0, 1};
  ::DwmExtendFrameIntoClientArea(GetHandle(), &margins);
  ::SetWindowPos(GetHandle(), nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!is_hidden_to_tray_) {
      this->Show();
    }
    TrimProcessMemory();
  });

  flutter_controller_->ForceRedraw();

  ::SetTimer(GetHandle(), kIdleTrimTimerId, 3000, nullptr);

  return true;
}

void FlutterWindow::OnDestroy() {
  ::KillTimer(GetHandle(), kIdleTrimTimerId);
  RemoveTrayIcon();
  window_state_channel_.reset();

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::SetupWindowStateChannel() {
  window_state_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "dev.chomusuke.tachyon/window_state",
          &flutter::StandardMethodCodec::GetInstance());

  window_state_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string& method = call.method_name();
        HWND hwnd = GetHandle();

        if (method == "getWindowState") {
          result->Success(flutter::EncodableValue(BuildWindowStateMap()));
        } else if (method == "isMinimized") {
          result->Success(flutter::EncodableValue(is_minimized_));
        } else if (method == "minimize") {
          if (hwnd) {
            ::ShowWindow(hwnd, SW_MINIMIZE);
          }
          result->Success();
        } else if (method == "toggleMaximize") {
          if (hwnd) {
            ::ShowWindow(hwnd, ::IsZoomed(hwnd) ? SW_RESTORE : SW_MAXIMIZE);
          }
          result->Success();
        } else if (method == "closeWindow") {
          RemoveTrayIcon();
          if (hwnd) {
            ::PostMessage(hwnd, WM_CLOSE, 0, 0);
          }
          result->Success();
        } else if (method == "startWindowDrag") {
          if (hwnd) {
            ::ReleaseCapture();
            ::SendMessage(hwnd, WM_SYSCOMMAND, SC_MOVE | HTCAPTION, 0);
          }
          result->Success();
        } else if (method == "enterBackgroundMode") {
          is_hidden_to_tray_ = true;
          if (hwnd) {
            ::ShowWindow(hwnd, SW_HIDE);
          }
          TrimProcessMemory();
          EmitWindowStateChanged();
          result->Success();
        } else if (method == "restoreFromBackground") {
          is_hidden_to_tray_ = false;
          is_minimized_ = false;
          is_focused_ = true;
          if (hwnd) {
            ::ShowWindow(hwnd, is_maximized_ ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL);
            ::SetForegroundWindow(hwnd);
          }
          if (flutter_controller_) {
            flutter_controller_->ForceRedraw();
          }
          EmitWindowStateChanged();
          result->Success();
        } else if (method == "updateTrayState") {
          if (const auto* map =
                  std::get_if<flutter::EncodableMap>(call.arguments())) {
            UpdateTrayIcon(*map);
          }
          result->Success();
        } else if (method == "setBackgroundButtonTooltip") {
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

flutter::EncodableMap FlutterWindow::BuildWindowStateMap() const {
  return flutter::EncodableMap{
      {flutter::EncodableValue("hasNativeHeaderBar"),
       flutter::EncodableValue(false)},
      {flutter::EncodableValue("hasSystemDecorations"),
       flutter::EncodableValue(false)},
      {flutter::EncodableValue("isMinimized"),
       flutter::EncodableValue(is_minimized_)},
      {flutter::EncodableValue("isFocused"),
       flutter::EncodableValue(is_focused_)},
      {flutter::EncodableValue("isMaximized"),
       flutter::EncodableValue(is_maximized_)},
      {flutter::EncodableValue("isHiddenToTray"),
       flutter::EncodableValue(is_hidden_to_tray_)},
  };
}

void FlutterWindow::EmitWindowStateChanged() {
  if (!window_state_channel_) return;
  window_state_channel_->InvokeMethod(
      "onWindowStateChanged",
      std::make_unique<flutter::EncodableValue>(BuildWindowStateMap()));
}

void FlutterWindow::EmitTrayAction(const std::string& action) {
  if (!window_state_channel_) return;
  window_state_channel_->InvokeMethod(
      "onTrayAction",
      std::make_unique<flutter::EncodableValue>(action));
}

void FlutterWindow::UpdateTrayIcon(const flutter::EncodableMap& args) {
  bool visible = ReadBoolValue(args, "visible", false);
  tray_is_playing_ = ReadBoolValue(args, "isPlaying", false);
  tray_is_shuffled_ = ReadBoolValue(args, "isShuffled", false);
  tray_has_track_ = ReadBoolValue(args, "hasTrack", false);
  tray_tooltip_ = Utf8ToWide(ReadStringValue(args, "tooltip", "Tachyon"));
  tray_play_label_ = Utf8ToWide(ReadStringValue(args, "playLabel", "Play"));
  tray_pause_label_ = Utf8ToWide(ReadStringValue(args, "pauseLabel", "Pause"));
  tray_next_label_ =
      Utf8ToWide(ReadStringValue(args, "nextLabel", "Next track"));
  tray_previous_label_ =
      Utf8ToWide(ReadStringValue(args, "previousLabel", "Previous track"));
  tray_shuffle_label_ =
      Utf8ToWide(ReadStringValue(args, "shuffleLabel", "Shuffle"));
  tray_show_app_label_ =
      Utf8ToWide(ReadStringValue(args, "showAppLabel", "Show Tachyon"));
  tray_quit_label_ = Utf8ToWide(ReadStringValue(args, "quitLabel", "Quit"));

  if (!visible) {
    RemoveTrayIcon();
    return;
  }

  HWND hwnd = GetHandle();
  if (!hwnd) return;

  tray_icon_data_.cbSize = sizeof(NOTIFYICONDATAW);
  tray_icon_data_.hWnd = hwnd;
  tray_icon_data_.uID = kTrayIconId;
  tray_icon_data_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_icon_data_.uCallbackMessage = kTrayCallbackMessage;
  tray_icon_data_.hIcon =
      ::LoadIconW(::GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));

  constexpr size_t kMaxTipChars = 127;
  size_t copy_len =
      tray_tooltip_.size() < kMaxTipChars ? tray_tooltip_.size() : kMaxTipChars;
  wmemcpy(tray_icon_data_.szTip, tray_tooltip_.c_str(), copy_len);
  tray_icon_data_.szTip[copy_len] = L'\0';

  if (!tray_icon_added_) {
    tray_icon_added_ =
        ::Shell_NotifyIconW(NIM_ADD, &tray_icon_data_) == TRUE;
  } else {
    ::Shell_NotifyIconW(NIM_MODIFY, &tray_icon_data_);
  }
}

void FlutterWindow::RemoveTrayIcon() {
  if (tray_icon_added_) {
    ::Shell_NotifyIconW(NIM_DELETE, &tray_icon_data_);
    tray_icon_added_ = false;
  }
}

void FlutterWindow::ShowTrayContextMenu() {
  HWND hwnd = GetHandle();
  if (!hwnd) return;

  HMENU menu = ::CreatePopupMenu();
  if (!menu) return;

  const UINT track_flags =
      tray_has_track_ ? MF_STRING : (MF_STRING | MF_GRAYED);
  const std::wstring& play_pause_label =
      tray_is_playing_ ? tray_pause_label_ : tray_play_label_;

  ::AppendMenuW(menu, track_flags, kMenuCmdPlayPause, play_pause_label.c_str());
  ::AppendMenuW(menu, track_flags, kMenuCmdNext, tray_next_label_.c_str());
  ::AppendMenuW(menu, track_flags, kMenuCmdPrevious,
                tray_previous_label_.c_str());
  ::AppendMenuW(menu, MF_STRING, kMenuCmdShuffle, tray_shuffle_label_.c_str());
  if (tray_is_shuffled_) {
    ::CheckMenuRadioItem(menu, kMenuCmdShuffle, kMenuCmdShuffle,
                         kMenuCmdShuffle, MF_BYCOMMAND);
  }
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING, kMenuCmdShowApp, tray_show_app_label_.c_str());
  ::AppendMenuW(menu, MF_STRING, kMenuCmdQuit, tray_quit_label_.c_str());

  POINT cursor_pos{};
  ::GetCursorPos(&cursor_pos);
  ::SetForegroundWindow(hwnd);

  const UINT selected = static_cast<UINT>(::TrackPopupMenuEx(
      menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY, cursor_pos.x,
      cursor_pos.y, hwnd, nullptr));

  ::PostMessage(hwnd, WM_NULL, 0, 0);
  ::DestroyMenu(menu);

  switch (selected) {
    case kMenuCmdPlayPause:
      EmitTrayAction("playPause");
      break;
    case kMenuCmdNext:
      EmitTrayAction("next");
      break;
    case kMenuCmdPrevious:
      EmitTrayAction("previous");
      break;
    case kMenuCmdShuffle:
      EmitTrayAction("toggleShuffle");
      break;
    case kMenuCmdShowApp:
      EmitTrayAction("restore");
      break;
    case kMenuCmdQuit:
      EmitTrayAction("quit");
      break;
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == kTrayCallbackMessage) {
    const UINT event = LOWORD(lparam);
    if (event == WM_LBUTTONUP || event == WM_LBUTTONDBLCLK) {
      EmitTrayAction("restore");
      return 0;
    }
    if (event == WM_RBUTTONUP || event == WM_CONTEXTMENU) {
      ShowTrayContextMenu();
      return 0;
    }
  }

  if (message == WM_NCCALCSIZE && wparam == TRUE) {
    if (::IsZoomed(hwnd)) {
      HMONITOR mon = ::MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
      MONITORINFO mi{};
      mi.cbSize = sizeof(mi);
      if (::GetMonitorInfoW(mon, &mi)) {
        auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
        params->rgrc[0] = mi.rcWork;
      }
    }
    return 0;
  }

  if (message == WM_NCHITTEST && !::IsZoomed(hwnd)) {
    POINT pt{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
    RECT rc{};
    ::GetWindowRect(hwnd, &rc);
    constexpr int kResizeBorder = 6;
    const bool left = pt.x >= rc.left && pt.x < rc.left + kResizeBorder;
    const bool right = pt.x < rc.right && pt.x >= rc.right - kResizeBorder;
    const bool top = pt.y >= rc.top && pt.y < rc.top + kResizeBorder;
    const bool bottom = pt.y < rc.bottom && pt.y >= rc.bottom - kResizeBorder;

    if (top && left) return HTTOPLEFT;
    if (top && right) return HTTOPRIGHT;
    if (bottom && left) return HTBOTTOMLEFT;
    if (bottom && right) return HTBOTTOMRIGHT;
    if (left) return HTLEFT;
    if (right) return HTRIGHT;
    if (top) return HTTOP;
    if (bottom) return HTBOTTOM;
  }

  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_SIZE: {
      const bool next_minimized = (wparam == SIZE_MINIMIZED);
      const bool next_maximized = (wparam == SIZE_MAXIMIZED);
      if (next_minimized) {
        TrimProcessMemory();
      }
      if (!is_hidden_to_tray_ &&
          (is_minimized_ != next_minimized ||
           is_maximized_ != next_maximized)) {
        is_minimized_ = next_minimized;
        is_maximized_ = next_maximized;
        EmitWindowStateChanged();
      }
      break;
    }
    case WM_ACTIVATE: {
      const bool next_focused = (LOWORD(wparam) != WA_INACTIVE);
      if (!next_focused) {
        TrimProcessMemory();
      }
      if (!is_hidden_to_tray_ && is_focused_ != next_focused) {
        is_focused_ = next_focused;
        EmitWindowStateChanged();
      }
      break;
    }
    case WM_TIMER:
      if (wparam == kIdleTrimTimerId) {
        TrimProcessMemory();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
