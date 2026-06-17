# Building HermesCore.sys Kernel Driver

This document explains how to build and install the HermesCore kernel-mode driver for deep Windows 11 integration.

## Prerequisites

1. **Windows Driver Kit (WDK)** — Required to compile kernel drivers
   ```powershell
   winget install "Windows Driver Kit" -s msstore
   ```

2. **Visual Studio 2022** (Community/Professional/Enterprise)
   - Required by WDK for compilation
   - Install via Visual Studio Installer with "Desktop development with C++" workload
   - Or via winget:
   ```powershell
   winget install Microsoft.VisualStudio.2022.Community
   ```

3. **Windows 11 SDK** (installed with WDK or separately):
   ```powershell
   winget install "Windows Software Development Kit" -s msstore
   ```

## Build Instructions

### Option 1: Visual Studio (Recommended)

1. Open a **Developer Command Prompt for VS 2022**
2. Navigate to the driver source directory:
   ```powershell
   cd src\KernelDriver
   ```
3. Build:
   ```powershell
   msbuild hermes_core.vcxproj /p:Configuration=Release /p:Platform=x64
   ```

The output (`hermes_core.sys`) will be in `x64\Release\`.

### Option 2: Build with WDK Command Line

```powershell
# Open "Build Environments" for WDK x64
build /cZ
```

## Installation

### 1. Enable Test Signing

Windows requires kernel drivers to be digitally signed. For development:
```powershell
# Run as Administrator
bcdedit /set testsigning on
```

Reboot your PC:
```powershell
shutdown /r /t 0
```

### 2. Copy the Driver

```powershell
copy x64\Release\hermes_core.sys C:\Windows\System32\drivers\
```

### 3. Create the Service

```powershell
# Run as Administrator
sc create HermesCore type= kernel binPath= "C:\Windows\System32\drivers\hermes_core.sys"
```

### 4. Start the Driver

```powershell
sc start HermesCore
```

### 5. Verify

```powershell
sc query HermesCore
```

Expected output: `STATE: 4 RUNNING`

## User-Mode Test Tool

Build the test tool:
```powershell
cl test_hermes_core.c /Fe:test_hermes_core.exe
```

Run:
```powershell
test_hermes_core.exe
```

## Uninstall

```powershell
sc stop HermesCore
sc delete HermesCore
```

## Troubleshooting

### "Access is denied"
Run all commands as Administrator.

### "The service cannot be started"
Check if testsigning is enabled:
```powershell
bcdedit /enum | findstr testsigning
```

### "The system cannot find the file specified"
Verify `hermes_core.sys` exists in `C:\Windows\System32\drivers\`.

### View Debug Output
Use **DebugView** (Sysinternals) to see kernel debug messages:
```powershell
winget install "DebugView" -s msstore
# or download from: https://learn.microsoft.com/en-us/sysinternals/downloads/debugview
```

Run DebugView as Administrator, enable "Capture Kernel" (Ctrl+K).

## Safety Notes

⚠️ Kernel drivers have full access to the system. An incorrect driver can cause:
- **BSOD** (Blue Screen of Death)
- **Data corruption**
- **System instability**

Always test in a VM first. The driver in this repo is designed to be safe:
- It only MONITORS, it does not BLOCK or modify
- No filesystem, network, or process injection
- All callbacks are read-only
- Proper cleanup on unload

## References

- [WDK and Visual Studio build](https://learn.microsoft.com/en-us/windows-hardware/drivers/)
- [Writing KMDF drivers](https://learn.microsoft.com/en-us/windows-hardware/drivers/wdf/)
- [Process notification routines](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/ntddk/nf-ntddk-pssetcreateprocessnotifyroutine)
- [IOCTL interface](https://learn.microsoft.com/en-us/windows-hardware/drivers/ifs/creating-ioctl-requests-in-drivers)
