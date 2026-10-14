#include "flutter_window.h"
#include <malloc.h>
#include <windows.h>
#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

// Trims excess heap allocations and flushes unreferenced pages from the working set.
void TrimProcessMemory() {
  _heapmin();
  HANDLE process_heap = ::GetProcessHeap();
  if (process_heap != NULL) {
    ::HeapCompact(process_heap, 0);
  }
  ::SetProcessWorkingSetSize(::GetCurrentProcess(), static_cast<SIZE_T>(-1),
                             static_cast<SIZE_T>(-1));
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

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
    TrimProcessMemory();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  // Periodic memory trim timer during idle (every 3000ms)
  ::SetTimer(GetHandle(), 1001, 3000, nullptr);

  return true;
}

void FlutterWindow::OnDestroy() {
  ::KillTimer(GetHandle(), 1001);

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
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
    case WM_SIZE:
      if (wparam == SIZE_MINIMIZED) {
        TrimProcessMemory();
      }
      break;
    case WM_ACTIVATE:
      if (LOWORD(wparam) == WA_INACTIVE) {
        TrimProcessMemory();
      }
      break;
    case WM_TIMER:
      if (wparam == 1001) {
        TrimProcessMemory();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
