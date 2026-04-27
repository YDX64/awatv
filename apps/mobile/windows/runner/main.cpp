#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // Default size matches the macOS native window and the
  // `desktop_window.dart` fallback so first-paint feels consistent
  // across platforms. The window is centred on the primary monitor;
  // we compute the origin from the work area so the chrome bar isn't
  // hidden by the taskbar on small displays.
  const int kDefaultWidth = 1280;
  const int kDefaultHeight = 800;

  RECT work_area;
  int origin_x = 100;
  int origin_y = 100;
  if (::SystemParametersInfo(SPI_GETWORKAREA, 0, &work_area, 0)) {
    const int work_w = work_area.right - work_area.left;
    const int work_h = work_area.bottom - work_area.top;
    origin_x = work_area.left + std::max(0, (work_w - kDefaultWidth) / 2);
    origin_y = work_area.top + std::max(0, (work_h - kDefaultHeight) / 2);
  }
  Win32Window::Point origin(origin_x, origin_y);
  Win32Window::Size size(kDefaultWidth, kDefaultHeight);
  if (!window.Create(L"AWAtv", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
