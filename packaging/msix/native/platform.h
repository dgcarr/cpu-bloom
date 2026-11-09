#pragma once
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <appmodel.h>
#include <shlobj.h>
#include <string>
#include <vector>
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.ApplicationModel.h>

inline bool packaged() {
    UINT32 length = 0;
    return GetCurrentPackageFullName(&length, nullptr) == ERROR_INSUFFICIENT_BUFFER;
}
inline std::wstring knownFolder(REFKNOWNFOLDERID id, DWORD flags = 0) {
    PWSTR value = nullptr;
    winrt::check_hresult(SHGetKnownFolderPath(id, flags, nullptr, &value));
    std::wstring result(value); CoTaskMemFree(value); return result;
}
inline std::wstring applicationDirectory() {
    std::vector<wchar_t> path(32768);
    DWORD length = GetModuleFileNameW(nullptr, path.data(), (DWORD)path.size());
    if (!length || length == path.size()) throw winrt::hresult_error(E_FAIL, L"Cannot locate application");
    std::wstring result(path.data(), length);
    return result.substr(0, result.find_last_of(L"\\"));
}
inline void configureEnvironment() {
    SetEnvironmentVariableW(L"CPU_BLOOM_PACKAGED", packaged() ? L"1" : L"0");
    SetEnvironmentVariableW(L"CPU_BLOOM_APP_DIR", applicationDirectory().c_str());
    SetEnvironmentVariableW(L"CPU_BLOOM_PICTURES", knownFolder(FOLDERID_Pictures).c_str());
    SetEnvironmentVariableW(L"CPU_BLOOM_LEGACY_CONFIG",
        (knownFolder(FOLDERID_RoamingAppData, KF_FLAG_NO_PACKAGE_REDIRECTION) + L"\\CPU Bloom").c_str());
    if (packaged()) {
        auto data = winrt::Windows::Storage::ApplicationData::Current();
        SetEnvironmentVariableW(L"CPU_BLOOM_CONFIG_DIR", data.LocalFolder().Path().c_str());
        SetEnvironmentVariableW(L"CPU_BLOOM_CACHE_DIR", data.LocalCacheFolder().Path().c_str());
        SetEnvironmentVariableW(L"TEMP", data.TemporaryFolder().Path().c_str());
        SetEnvironmentVariableW(L"TMP", data.TemporaryFolder().Path().c_str());
    } else {
        // Clear inherited context; never silently redirect a portable instance into Store data.
        SetEnvironmentVariableW(L"CPU_BLOOM_CONFIG_DIR", nullptr);
        SetEnvironmentVariableW(L"CPU_BLOOM_CACHE_DIR", nullptr);
    }
}
