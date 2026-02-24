#include "flutter_window.h"

#include <algorithm>
#include <filesystem>
#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
               const std::vector<std::string>& startup_arguments)
  : project_(project), startup_arguments_(startup_arguments) {}

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
  CaptureInitialSharedFiles();
  SetupShareChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
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
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::CaptureInitialSharedFiles() {
  pending_shared_file_paths_.clear();
  for (const auto& argument : startup_arguments_) {
    std::error_code ec;
    std::filesystem::path path(argument);
    const auto normalized = std::filesystem::absolute(path, ec);
    if (ec) {
      continue;
    }
    if (!std::filesystem::exists(normalized, ec) || ec) {
      continue;
    }
    if (!std::filesystem::is_regular_file(normalized, ec) || ec) {
      continue;
    }
    const auto value = normalized.u8string();
    if (std::find(pending_shared_file_paths_.begin(), pending_shared_file_paths_.end(), value) ==
        pending_shared_file_paths_.end()) {
      pending_shared_file_paths_.push_back(value);
    }
  }
}

void FlutterWindow::SetupShareChannel() {
  share_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "dropnet/share_intent",
      &flutter::StandardMethodCodec::GetInstance());

  share_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "consumePendingSharedFiles") {
      result->NotImplemented();
      return;
    }

    flutter::EncodableList paths;
    for (const auto& file_path : pending_shared_file_paths_) {
      paths.emplace_back(file_path);
    }
    pending_shared_file_paths_.clear();
    result->Success(paths);
  });
}
