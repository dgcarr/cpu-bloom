#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <wchar.h>

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR args, int show) {
    wchar_t directory[32768], java[32768], command[32768];
    DWORD length = GetModuleFileNameW(NULL, directory, 32768);
    if (!length || length >= 32768) return 1;
    wchar_t *slash = wcsrchr(directory, L'\\');
    if (!slash) return 1;
    *slash = 0;
    if (swprintf(java, 32768, L"%ls\\java\\bin\\javaw.exe", directory) < 0 ||
        swprintf(command, 32768, L"\"%ls\" -Xmx320m -cp \"%ls\\lib\\*\" cpu_bloom %ls", java, directory, args) < 0) return 1;
    STARTUPINFOW startup = {0};
    PROCESS_INFORMATION process = {0};
    startup.cb = sizeof(startup);
    if (!CreateProcessW(java, command, NULL, NULL, FALSE, 0, NULL, directory, &startup, &process)) {
        MessageBoxW(NULL, L"Could not start the bundled Java runtime. Extract the entire ZIP before running CPU Bloom.", L"CPU Bloom", MB_OK | MB_ICONERROR);
        return 1;
    }
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return 0;
}
