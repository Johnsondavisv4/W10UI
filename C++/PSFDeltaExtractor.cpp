#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <sstream>
#include <memory>
#include <algorithm>
#include <limits>
#include <stdexcept>
#include <objbase.h>
#include <xmllite.h>
#include <shlwapi.h>
#include <wrl/client.h>
#pragma comment(lib, "xmllite.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "ole32.lib")

typedef struct _DELTA_INPUT {
    union {
        LPCVOID lpStart;
        LPCSTR  lpszStart;
    };
    SIZE_T uSize;
    BOOL   Editable;
} DELTA_INPUT, *PDELTA_INPUT;

typedef struct _DELTA_OUTPUT {
    LPVOID lpStart;
    SIZE_T uSize;
} DELTA_OUTPUT, *PDELTA_OUTPUT;

typedef BOOL (WINAPI *pfnApplyDeltaB)(
    ULONG64 ApplyFlags,
    DELTA_INPUT Source,
    DELTA_INPUT Delta,
    PDELTA_OUTPUT Target
);

typedef BOOL (WINAPI *pfnDeltaFree)(
    LPVOID lpStart
);

// Every owned handle, COM object and delta allocation is released on success
// and failure. Trimming the working set does not fix leaked allocations.
struct HandleCloser {
    void operator()(void* h) const { if (h && h != INVALID_HANDLE_VALUE) CloseHandle(h); }
};
using OwnedHandle = std::unique_ptr<void, HandleCloser>;
struct ModuleCloser { void operator()(HINSTANCE h) const { if (h) FreeLibrary(h); } };
using OwnedModule = std::unique_ptr<HINSTANCE__, ModuleCloser>;
struct DeltaResult {
    DELTA_OUTPUT value = {};
    pfnDeltaFree release;
    explicit DeltaResult(pfnDeltaFree function) : release(function) {}
    DeltaResult(const DeltaResult&) = delete;
    DeltaResult& operator=(const DeltaResult&) = delete;
    ~DeltaResult() { if (value.lpStart) release(value.lpStart); }
};
struct ComScope {
    ComScope() { if (FAILED(CoInitializeEx(NULL, COINIT_MULTITHREADED))) throw std::runtime_error("COM initialization failed"); }
    ~ComScope() { CoUninitialize(); }
};
static void Check(bool success, const char* message) {
    if (!success) throw std::runtime_error(std::string(message) + " (Win32 " + std::to_string(GetLastError()) + ")");
}
static void CheckHR(HRESULT status, const char* message) {
    if (FAILED(status)) throw std::runtime_error(std::string(message) + " (HRESULT " + std::to_string(status) + ")");
}
static std::wstring AbsolutePath(const std::wstring& path) {
    DWORD size = GetFullPathNameW(path.c_str(), 0, NULL, NULL);
    Check(size != 0, "GetFullPathName");
    std::wstring absolute(size, L'\0');
    DWORD used = GetFullPathNameW(path.c_str(), size, &absolute[0], NULL);
    Check(used && used < size, "GetFullPathName");
    absolute.resize(used);
    return absolute;
}
static std::wstring ExtendedPath(const std::wstring& path) {
    std::wstring absolute = AbsolutePath(path);
    if (absolute.compare(0, 4, LR"(\\?\)") == 0) return absolute;
    if (absolute.compare(0, 2, LR"(\\)") == 0) return LR"(\\?\UNC\)" + absolute.substr(2);
    return LR"(\\?\)" + absolute;
}
static void MakeParents(const std::wstring& path) {
    size_t pos = 6; // Skip the drive root in an extended path.
    if (path.compare(0, 8, LR"(\\?\UNC\)") == 0) {
        pos = path.find(L'\\', 8);
        if (pos != std::wstring::npos) pos = path.find(L'\\', pos + 1);
    }
    while (pos != std::wstring::npos && (pos = path.find(L'\\', pos + 1)) != std::wstring::npos) {
        std::wstring parent = path.substr(0, pos);
        if (!CreateDirectoryW(parent.c_str(), NULL)) {
            DWORD error = GetLastError();
            DWORD attributes = GetFileAttributesW(parent.c_str());
            Check(error == ERROR_ALREADY_EXISTS && attributes != INVALID_FILE_ATTRIBUTES &&
                  (attributes & FILE_ATTRIBUTE_DIRECTORY), "CreateDirectory");
        }
    }
}
static ULONGLONG Number(const std::wstring& text) {
    if (text.empty()) throw std::runtime_error("Missing numeric XML attribute");
    ULONGLONG value = 0;
    for (wchar_t c : text) {
        if (c < L'0' || c > L'9' || value > ((std::numeric_limits<ULONGLONG>::max)() - (c - L'0')) / 10)
            throw std::runtime_error("Invalid numeric XML attribute");
        value = value * 10 + (c - L'0');
    }
    return value;
}
static std::wstring Attribute(IXmlReader* reader, const wchar_t* name) {
    if (reader->MoveToAttributeByName(name, NULL) != S_OK) throw std::runtime_error("Missing XML attribute");
    const wchar_t* value = NULL;
    UINT size = 0;
    CheckHR(reader->GetValue(&value, &size), "Read XML attribute");
    std::wstring result(value, size);
    CheckHR(reader->MoveToElement(), "Return to XML element");
    return result;
}
static void Transfer(HANDLE file, BYTE* data, size_t length, bool write) {
    while (length) {
        DWORD chunk = static_cast<DWORD>((std::min)(length, size_t(1024 * 1024)));
        DWORD done = 0;
        Check((write ? WriteFile(file, data, chunk, &done, NULL) : ReadFile(file, data, chunk, &done, NULL)) != FALSE,
              write ? "WriteFile" : "ReadFile");
        if (!done) throw std::runtime_error("Incomplete file transfer");
        length -= done;
        data += done;
    }
}
struct FileEntry {
    std::wstring name, type;
    ULONGLONG time = 0, offset = 0, length = 0;
    bool source = false;
};
struct PendingFile {
    std::wstring path;
    bool owned = false;
    ~PendingFile() { if (owned) DeleteFileW(path.c_str()); }
};
static void ExtractFile(const FileEntry& entry, const std::wstring& directory, HANDLE psf,
                        ULONGLONG psfSize, pfnApplyDeltaB apply, pfnDeltaFree release) {
    if (entry.name.empty() || !entry.source) throw std::runtime_error("Incomplete XML file entry");
    std::wstring name = entry.name;
    for (auto& c : name) if (c == L'/') c = L'\\';
    if (name.front() == L'\\' || name.find(L':') != std::wstring::npos) throw std::runtime_error("Invalid PSF output path");
    std::wistringstream parts(name);
    std::wstring part;
    while (std::getline(parts, part, L'\\'))
        if (part.empty() || part == L".." || part == L".") throw std::runtime_error("Invalid PSF output path");
    const std::wstring output = ExtendedPath(directory + L"\\" + name);
    DWORD attributes = GetFileAttributesW(output.c_str());
    if (attributes != INVALID_FILE_ATTRIBUTES) {
        if (attributes & FILE_ATTRIBUTE_DIRECTORY) throw std::runtime_error("Output is a directory");
        return; // Match the fallback: preserve files already extracted from the WIM.
    }
    if (entry.offset > psfSize || entry.length > psfSize - entry.offset || entry.length > SIZE_MAX)
        throw std::runtime_error("PSF offset/length outside input file");
    LARGE_INTEGER offset;
    offset.QuadPart = entry.offset;
    Check(SetFilePointerEx(psf, offset, NULL, FILE_BEGIN) != FALSE, "Seek PSF");
    std::vector<BYTE> buffer(static_cast<size_t>(entry.length));
    Transfer(psf, buffer.data(), buffer.size(), false);
    DeltaResult result(release);
    BYTE* data = buffer.data();
    size_t size = buffer.size();
    if (entry.type == L"PA30" || entry.type == L"PA31") {
        DELTA_INPUT source = {}, delta = {};
        delta.lpStart = buffer.data();
        delta.uSize = buffer.size();
        delta.Editable = TRUE;
        Check(apply(0, source, delta, &result.value) != FALSE, "ApplyDeltaB");
        if (!result.value.lpStart) throw std::runtime_error("Delta returned no output");
        data = static_cast<BYTE*>(result.value.lpStart);
        size = result.value.uSize;
    }
    MakeParents(output);
    PendingFile pending;
    pending.path = output + L".psfdelta-" + std::to_wstring(GetCurrentProcessId()) + L".tmp";
    OwnedHandle file(CreateFileW(pending.path.c_str(), GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL));
    Check(file.get() != INVALID_HANDLE_VALUE, "Create output file");
    pending.owned = true;
    Transfer(file.get(), data, size, true);
    FILETIME timestamp = {static_cast<DWORD>(entry.time), static_cast<DWORD>(entry.time >> 32)};
    Check(SetFileTime(file.get(), NULL, NULL, &timestamp) != FALSE, "SetFileTime");
    file.reset();
    Check(MoveFileExW(pending.path.c_str(), output.c_str(), 0) != FALSE, "Commit output file");
    pending.owned = false;
}

int wmain(int argc, wchar_t* argv[]) {
    try {
        if (argc < 2 || argc > 3) throw std::runtime_error("Usage: PSFDeltaExtractor.exe <cab_package_name> [dll_path]");
        std::wstring directory = AbsolutePath(argv[1]);
        std::wstring dllName = argc == 3 ? argv[2] : L"msdelta.dll";
        // convert-UUP currently passes only the package path. Use its extracted
        // servicing DLL when available, just as the PowerShell call does.
        if (argc == 2) {
            size_t parent = directory.find_last_of(L"\\/");
            std::wstring candidate = directory.substr(0, parent + 1) + L"UpdateCompression.dll";
            if (GetFileAttributesW(candidate.c_str()) != INVALID_FILE_ATTRIBUTES) dllName = candidate;
        }
        if (_wcsicmp(dllName.c_str(), L"msdelta.dll") == 0) {
            wchar_t system[MAX_PATH];
            Check(GetSystemDirectoryW(system, MAX_PATH) != 0, "GetSystemDirectory");
            std::wstring compression = std::wstring(system) + L"\\UpdateCompression.dll";
            if (GetFileAttributesW(compression.c_str()) != INVALID_FILE_ATTRIBUTES) dllName = compression;
        }
        // Do not silently replace the caller's PA31-capable DLL with msdelta.dll.
        OwnedModule module(LoadLibraryW(dllName.c_str()));
        Check(module != nullptr, "Load delta DLL");
        auto apply = reinterpret_cast<pfnApplyDeltaB>(GetProcAddress(module.get(), "ApplyDeltaB"));
        auto release = reinterpret_cast<pfnDeltaFree>(GetProcAddress(module.get(), "DeltaFree"));
        Check(apply && release, "Find delta functions");
        size_t dot = directory.find_last_of(L'.');
        size_t slash = directory.find_last_of(L"\\/");
        if (dot == std::wstring::npos || (slash != std::wstring::npos && dot < slash)) throw std::runtime_error("Package has no extension");
        directory.resize(dot);
        OwnedHandle psf(CreateFileW(ExtendedPath(directory + L".psf").c_str(), GENERIC_READ,
            FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL));
        Check(psf.get() != INVALID_HANDLE_VALUE, "Open PSF");
        LARGE_INTEGER psfSize;
        Check(GetFileSizeEx(psf.get(), &psfSize) != FALSE, "Get PSF size");
        ComScope com;
        Microsoft::WRL::ComPtr<IStream> stream;
        CheckHR(SHCreateStreamOnFileEx(ExtendedPath(directory + L"\\express.psf.cix.xml").c_str(),
            STGM_READ | STGM_SHARE_DENY_WRITE, 0, FALSE, NULL, &stream), "Open XML");
        Microsoft::WRL::ComPtr<IXmlReader> reader;
        CheckHR(CreateXmlReader(__uuidof(IXmlReader), reinterpret_cast<void**>(reader.GetAddressOf()), NULL), "Create XML reader");
        CheckHR(reader->SetProperty(XmlReaderProperty_DtdProcessing, DtdProcessing_Prohibit), "Disable XML DTD");
        CheckHR(reader->SetInput(stream.Get()), "Set XML input");
        FileEntry entry;
        bool inFile = false, inDelta = false;
        UINT fileDepth = 0, deltaDepth = 0;
        size_t count = 0;
        XmlNodeType node;
        HRESULT status;
        while ((status = reader->Read(&node)) == S_OK) {
            if (node != XmlNodeType_Element && node != XmlNodeType_EndElement) continue;
            const wchar_t* local = NULL;
            CheckHR(reader->GetLocalName(&local, NULL), "Get XML name");
            std::wstring name(local);
            UINT depth = 0;
            CheckHR(reader->GetDepth(&depth), "Get XML depth");
            if (node == XmlNodeType_Element && name == L"File") {
                if (inFile || reader->IsEmptyElement()) throw std::runtime_error("Invalid XML File element");
                entry = FileEntry();
                entry.name = Attribute(reader.Get(), L"name");
                entry.time = Number(Attribute(reader.Get(), L"time"));
                inFile = true;
                fileDepth = depth;
            } else if (inFile && node == XmlNodeType_Element && name == L"Delta" && depth == fileDepth + 1) {
                deltaDepth = depth;
                inDelta = !reader->IsEmptyElement();
            } else if (inDelta && node == XmlNodeType_Element && name == L"Source" && depth == deltaDepth + 1 && !entry.source) {
                entry.type = Attribute(reader.Get(), L"type");
                entry.offset = Number(Attribute(reader.Get(), L"offset"));
                entry.length = Number(Attribute(reader.Get(), L"length"));
                entry.source = true;
            } else if (node == XmlNodeType_EndElement && inDelta && name == L"Delta" && depth == deltaDepth + 1) {
                inDelta = false;
            } else if (node == XmlNodeType_EndElement && inFile && name == L"File" && depth == fileDepth + 1) {
                ExtractFile(entry, directory, psf.get(), psfSize.QuadPart, apply, release);
                ++count;
                inFile = false;
            }
        }
        CheckHR(status, "Read XML");
        if (inFile || !count) throw std::runtime_error("Incomplete or empty PSF XML");
        std::cout << "PSFDeltaExtractor: " << count << " files processed successfully.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "PSFDeltaExtractor: " << error.what() << '\n';
        return 1;
    }
}
