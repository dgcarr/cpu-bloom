#include "platform.h"
#include <iostream>

using namespace winrt::Windows::ApplicationModel;
const char* stateName(StartupTaskState state) {
    switch (state) {
    case StartupTaskState::Disabled: return "Disabled";
    case StartupTaskState::DisabledByUser: return "DisabledByUser";
    case StartupTaskState::Enabled: return "Enabled";
    case StartupTaskState::DisabledByPolicy: return "DisabledByPolicy";
    case StartupTaskState::EnabledByPolicy: return "EnabledByPolicy";
    default: return "Unknown";
    }
}
int wmain(int argc, wchar_t** argv) {
    try {
        winrt::init_apartment(winrt::apartment_type::multi_threaded);
        if (argc != 2) return 2;
        std::wstring operation(argv[1]);
        if (operation == L"context") {
            std::cout << "packaged=" << (packaged() ? "true" : "false") << "\n";
            if (packaged()) {
                auto data = winrt::Windows::Storage::ApplicationData::Current();
                std::cout << "settings=" << winrt::to_string(data.LocalFolder().Path()) << "\n";
                std::cout << "cache=" << winrt::to_string(data.LocalCacheFolder().Path()) << "\n";
            }
            std::cout << "pictures=" << winrt::to_string(knownFolder(FOLDERID_Pictures)) << "\n";
            return 0;
        }
        if (operation != L"startup-query" && operation != L"startup-enable" && operation != L"startup-disable") return 2;
        if (!packaged()) { std::cout << "Unpackaged\n"; return 3; }
        auto task = StartupTask::GetAsync(L"CpuBloomStartup").get();
        auto state = task.State();
        if (operation == L"startup-enable" && state == StartupTaskState::Disabled)
            state = task.RequestEnableAsync().get();
        else if (operation == L"startup-disable" && state == StartupTaskState::Enabled) {
            task.Disable(); state = task.State();
        }
        std::cout << stateName(state) << "\n";
        return 0;
    } catch (const winrt::hresult_error& error) {
        std::cerr << winrt::to_string(error.message()) << "\n"; return 1;
    }
}
