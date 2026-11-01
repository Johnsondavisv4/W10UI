#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winsvc.h>
#include <tlhelp32.h>
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <sstream>
#include <stdexcept>
#include <limits>

// Revert impersonation on every exit path, including exceptions.
struct ImpersonationScope {
    ~ImpersonationScope() { RevertToSelf(); }
};

std::wstring ToWString(const std::string& str) {
    if (str.empty()) return L"";
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), NULL, 0);
    if (size_needed <= 0) throw std::runtime_error("Invalid registry text");
    std::wstring wstrTo(size_needed, 0);
    if (!MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), &wstrTo[0], size_needed))
        throw std::runtime_error("Cannot decode registry text");
    return wstrTo;
}

bool EnablePrivilege(HANDLE hToken, LPCWSTR lpszPrivilege) {
    TOKEN_PRIVILEGES tp = {};
    LUID luid;

    if (!LookupPrivilegeValueW(NULL, lpszPrivilege, &luid)) {
        return false;
    }

    tp.PrivilegeCount = 1;
    tp.Privileges[0].Luid = luid;
    tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;

    SetLastError(ERROR_SUCCESS);
    if (!AdjustTokenPrivileges(hToken, FALSE, &tp, sizeof(TOKEN_PRIVILEGES), NULL, NULL)) {
        return false;
    }

    return (GetLastError() == ERROR_SUCCESS);
}

bool ImpersonateProcess(DWORD pid) {
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!process) return false;
    HANDLE token = NULL, duplicate = NULL;
    bool success = OpenProcessToken(process, TOKEN_DUPLICATE | TOKEN_QUERY, &token) &&
        DuplicateTokenEx(token, TOKEN_IMPERSONATE | TOKEN_QUERY, NULL,
            SecurityImpersonation, TokenImpersonation, &duplicate) &&
        SetThreadToken(NULL, duplicate);
    if (duplicate) CloseHandle(duplicate);
    if (token) CloseHandle(token);
    CloseHandle(process);
    return success;
}

// The PowerShell fallback first impersonates SYSTEM before opening TI's token.
bool ImpersonateSystem() {
    SC_HANDLE manager = OpenSCManagerW(NULL, NULL, SC_MANAGER_CONNECT);
    if (!manager) return false;
    SC_HANDLE service = OpenServiceW(manager, L"SamSs", SERVICE_QUERY_STATUS);
    SERVICE_STATUS_PROCESS status = {};
    DWORD bytes = 0;
    bool queried = service && QueryServiceStatusEx(service, SC_STATUS_PROCESS_INFO,
        reinterpret_cast<BYTE*>(&status), sizeof(status), &bytes);
    if (service) CloseServiceHandle(service);
    CloseServiceHandle(manager);
    if (!queried || !status.dwProcessId) return false;
    return ImpersonateProcess(status.dwProcessId);
}

bool ImpersonateTrustedInstaller() {
    HANDLE hToken = NULL;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &hToken)) {
        return false;
    }

    bool privileges = EnablePrivilege(hToken, L"SeDebugPrivilege") &&
        EnablePrivilege(hToken, L"SeImpersonatePrivilege");
    CloseHandle(hToken);
    if (!privileges) return false;

    SC_HANDLE hSCM = OpenSCManagerW(NULL, NULL, SC_MANAGER_CONNECT);
    if (!hSCM) return false;

    SC_HANDLE hService = OpenServiceW(hSCM, L"TrustedInstaller", SERVICE_START | SERVICE_QUERY_STATUS);
    bool running = false;
    if (hService) {
        const ULONGLONG deadline = GetTickCount64() + 30000;
        bool requested = false;
        do {
            SERVICE_STATUS_PROCESS ssp = {};
            DWORD dwBytesNeeded = 0;
            if (!QueryServiceStatusEx(hService, SC_STATUS_PROCESS_INFO, (LPBYTE)&ssp, sizeof(ssp), &dwBytesNeeded)) break;
            if (ssp.dwCurrentState == SERVICE_RUNNING) { running = true; break; }
            if (ssp.dwCurrentState == SERVICE_STOPPED) {
                if (requested) break;
                if (!StartServiceW(hService, 0, NULL) && GetLastError() != ERROR_SERVICE_ALREADY_RUNNING) break;
                requested = true;
            }
            Sleep(100);
        } while (GetTickCount64() < deadline);
        CloseServiceHandle(hService);
    }
    CloseServiceHandle(hSCM);
    if (!running) return false;

    DWORD targetPID = 0;
    HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnap != INVALID_HANDLE_VALUE) {
        PROCESSENTRY32W pe;
        pe.dwSize = sizeof(pe);
        if (Process32FirstW(hSnap, &pe)) {
            do {
                if (_wcsicmp(pe.szExeFile, L"TrustedInstaller.exe") == 0) {
                    targetPID = pe.th32ProcessID;
                    break;
                }
            } while (Process32NextW(hSnap, &pe));
        }
        CloseHandle(hSnap);
    }

    if (targetPID == 0) return false;

    // Direct access can succeed with SeDebugPrivilege. Only use the SYSTEM
    // intermediate token if needed, so a protected SamSs does not block it.
    if (ImpersonateProcess(targetPID)) return true;
    return ImpersonateSystem() && ImpersonateProcess(targetPID);
}

bool ProcessRegistryLine(const std::string& line) {
    if (line.find_first_not_of(" \t\r") == std::string::npos) return true;

    if (line.find("New-ItemProperty") != std::string::npos) {
        size_t keyStart = line.find("'HKLM:\\");
        if (keyStart == std::string::npos) keyStart = line.find("\"HKLM:\\");
        if (keyStart == std::string::npos) return false;

        char quoteChar = line[keyStart];
        keyStart += 7;
        size_t keyEnd = line.find(quoteChar, keyStart);
        if (keyEnd == std::string::npos) return false;

        std::string subKeyStr = line.substr(keyStart, keyEnd - keyStart);

        std::string rest = line.substr(keyEnd + 1);
        std::stringstream ss(rest);
        std::string valueName;
        ss >> valueName;
        if (valueName.empty()) return false;

        size_t valPos = line.find("-Value ");
        DWORD dwValue = 0;
        if (valPos != std::string::npos) {
            std::string valStr = line.substr(valPos + 7);
            std::stringstream valSS(valStr);
            unsigned long long parsed = 0;
            if (!(valSS >> parsed) || parsed > (std::numeric_limits<DWORD>::max)()) return false;
            dwValue = static_cast<DWORD>(parsed);
        } else return false;

        std::wstring wSubKey = ToWString(subKeyStr);
        std::wstring wValueName = ToWString(valueName);

        HKEY hKey = NULL;
        DWORD dwDisposition = 0;
        if (RegCreateKeyExW(HKEY_LOCAL_MACHINE, wSubKey.c_str(), 0, NULL, REG_OPTION_NON_VOLATILE, KEY_SET_VALUE | KEY_WOW64_64KEY, NULL, &hKey, &dwDisposition) == ERROR_SUCCESS) {
            LSTATUS status = RegSetValueExW(hKey, wValueName.c_str(), 0, REG_DWORD, (const BYTE*)&dwValue, sizeof(DWORD));
            RegCloseKey(hKey);
            return status == ERROR_SUCCESS;
        }
        return false;
    }
    else if (line.find("Remove-ItemProperty") != std::string::npos) {
        size_t keyStart = line.find("'HKLM:\\");
        if (keyStart == std::string::npos) keyStart = line.find("\"HKLM:\\");
        if (keyStart == std::string::npos) return false;

        char quoteChar = line[keyStart];
        keyStart += 7;
        size_t keyEnd = line.find(quoteChar, keyStart);
        if (keyEnd == std::string::npos) return false;

        std::string subKeyStr = line.substr(keyStart, keyEnd - keyStart);

        size_t valStart = line.find(quoteChar, keyEnd + 1);
        if (valStart == std::string::npos) return false;
        size_t valEnd = line.find(quoteChar, valStart + 1);
        if (valEnd == std::string::npos) return false;

        std::string valueNameStr = line.substr(valStart + 1, valEnd - valStart - 1);

        std::wstring wSubKey = ToWString(subKeyStr);
        std::wstring wValueName = ToWString(valueNameStr);

        HKEY hKey = NULL;
        LSTATUS status = RegOpenKeyExW(HKEY_LOCAL_MACHINE, wSubKey.c_str(), 0, KEY_SET_VALUE | KEY_WOW64_64KEY, &hKey);
        if (status == ERROR_FILE_NOT_FOUND || status == ERROR_PATH_NOT_FOUND) return true;
        if (status == ERROR_SUCCESS) {
            status = RegDeleteValueW(hKey, wValueName.c_str());
            RegCloseKey(hKey);
            return status == ERROR_SUCCESS || status == ERROR_FILE_NOT_FOUND;
        }
        return false;
    }
    return false;
}

int RunCBSReg(int argc, wchar_t* argv[]) {
    if (argc != 2) {
        std::cout << "CBSReg Native Registry Modifier v1.1" << std::endl;
        std::cout << "Usage: CBSReg.exe <path_to_W10UIreg.txt>" << std::endl;
        return 1;
    }

    std::wstring regFilePath = argv[1];
    std::ifstream inFile(regFilePath);
    if (!inFile.is_open()) {
        std::wcerr << L"Failed to open registry command file: " << regFilePath << std::endl;
        return 1;
    }

    ImpersonationScope impersonation;
    if (!ImpersonateTrustedInstaller()) {
        std::cerr << "Failed to impersonate TrustedInstaller" << std::endl;
        return 1;
    }

    std::string line;
    while (std::getline(inFile, line)) {
        if (!ProcessRegistryLine(line)) {
            std::cerr << "Failed registry command: " << line << std::endl;
            return 1;
        }
    }

    if (inFile.bad()) return 1;
    inFile.close();
    return 0;
}

int wmain(int argc, wchar_t* argv[]) {
    try {
        return RunCBSReg(argc, argv);
    } catch (const std::exception& error) {
        std::cerr << "CBSReg: " << error.what() << std::endl;
        return 1;
    }
}
