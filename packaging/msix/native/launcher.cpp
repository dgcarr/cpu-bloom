#include "platform.h"

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR arguments, int) {
    try {
        winrt::init_apartment(winrt::apartment_type::multi_threaded);
        configureEnvironment();
        const auto directory = applicationDirectory();
        const auto java = directory + L"\\java\\bin\\javaw.exe";
        std::wstring command = L"\"" + java + L"\" -Xmx320m -cp \"" + directory + L"\\lib\\*\" cpu_bloom ";
#ifdef CPU_BLOOM_STARTUP
        command += L"--start-minimized ";
#endif
        command += arguments;
        STARTUPINFOW startup{}; startup.cb = sizeof(startup);
        PROCESS_INFORMATION process{};
        if (!CreateProcessW(java.c_str(), command.data(), nullptr, nullptr, FALSE, 0, nullptr,
            directory.c_str(), &startup, &process)) winrt::throw_last_error();
        CloseHandle(process.hThread); CloseHandle(process.hProcess);
        return 0;
    } catch (const winrt::hresult_error& error) {
        MessageBoxW(nullptr, error.message().c_str(), L"CPU Bloom could not start", MB_OK | MB_ICONERROR);
        return 1;
    }
}
