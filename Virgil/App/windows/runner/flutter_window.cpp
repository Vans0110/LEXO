#include "flutter_window.h"

#include <commdlg.h>
#include <optional>
#include <string>

#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {

constexpr wchar_t kTxtFilter[] =
    L"Text Files (*.txt)\0*.txt\0All Files (*.*)\0*.*\0";

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() = default;

void FlutterWindow::RegisterFilePickerChannel() {
  file_picker_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "lexo/windows_file_picker",
          &flutter::StandardMethodCodec::GetInstance());

  file_picker_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "pickTxtFile") {
          result->NotImplemented();
          return;
        }

        wchar_t file_path[MAX_PATH] = {0};
        OPENFILENAMEW dialog = {0};
        dialog.lStructSize = sizeof(dialog);
        dialog.hwndOwner = GetHandle();
        dialog.lpstrFilter = kTxtFilter;
        dialog.lpstrFile = file_path;
        dialog.nMaxFile = MAX_PATH;
        dialog.Flags = OFN_EXPLORER | OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST |
                       OFN_NOCHANGEDIR;
        dialog.lpstrDefExt = L"txt";

        if (!GetOpenFileNameW(&dialog)) {
          const DWORD error_code = CommDlgExtendedError();
          if (error_code == 0) {
            result->Success();
            return;
          }
          result->Error(
              "file_dialog_error",
              "Windows file dialog failed with code " +
                  std::to_string(static_cast<unsigned long>(error_code)));
          return;
        }

        std::wstring selected_path(file_path);
        const size_t name_offset = selected_path.find_last_of(L"\\/");
        const std::wstring file_name =
            name_offset == std::wstring::npos
                ? selected_path
                : selected_path.substr(name_offset + 1);

        flutter::EncodableMap payload;
        payload[flutter::EncodableValue("path")] =
            flutter::EncodableValue(Utf8FromUtf16(selected_path.c_str()));
        payload[flutter::EncodableValue("name")] =
            flutter::EncodableValue(Utf8FromUtf16(file_name.c_str()));
        result->Success(flutter::EncodableValue(payload));
      });
}

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
  RegisterFilePickerChannel();

  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
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
