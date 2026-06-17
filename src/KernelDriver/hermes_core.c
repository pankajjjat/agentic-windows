/******************************************************************************
 * HermesCore.sys — Agentic Windows Kernel Driver
 *
 * Provides kernel-level system awareness for the Hermes agent:
 *   • Process creation/termination notifications
 *   • Thread creation/termination notifications
 *   • Image load notifications (DLLs, drivers)
 *   • Registry change monitoring
 *   • IOCTL interface for user-mode communication
 *
 * Requires: Windows Driver Kit (WDK) + Visual Studio
 * Build:    msbuild hermes_core.vcxproj /p:Configuration=Release /p:Platform=x64
 *
 * (c) 2025 Pankaj — MIT License
 ******************************************************************************/

#include <ntddk.h>
#include <wdm.h>
#include <ntstrsafe.h>

#include "ioctl.h"

// ──────────────────────────────────────────────
// Global state
// ──────────────────────────────────────────────

static PDEVICE_OBJECT      g_DeviceObject = NULL;
static PDEVICE_OBJECT      g_Pdo = NULL;
static PIO_REMOVE_LOCK     g_RemoveLock = NULL;
static PVOID               g_RegHandle = NULL;
static BOOLEAN             g_ProcessCallbackRegistered = FALSE;
static BOOLEAN             g_ThreadCallbackRegistered = FALSE;
static BOOLEAN             g_ImageCallbackRegistered = FALSE;

// Lock for synchronized access
static FAST_MUTEX          g_Lock;

// ──────────────────────────────────────────────
// Forward declarations
// ──────────────────────────────────────────────

DRIVER_INITIALIZE DriverEntry;
DRIVER_UNLOAD DriverUnload;
DRIVER_DISPATCH HermesCoreCreateClose;
DRIVER_DISPATCH HermesCoreDeviceControl;
DRIVER_DISPATCH HermesCoreCleanup;

NTSTATUS HermesCoreAddDevice(PDRIVER_OBJECT DriverObject, PDEVICE_OBJECT PhysicalDeviceObject);
VOID ProcessCreateNotifyRoutineEx(PEPROCESS Process, HANDLE ProcessId, PPS_CREATE_NOTIFY_INFO CreateInfo);
VOID ThreadCreateNotifyRoutine(HANDLE ProcessId, HANDLE ThreadId, BOOLEAN Create);
VOID ImageLoadNotifyRoutine(PUNICODE_STRING FullImageName, HANDLE ProcessId, PIMAGE_INFO ImageInfo);
NTSTATUS CompleteRequest(PIRP Irp, NTSTATUS Status, ULONG_PTR Information);
VOID HermesCoreUnload(PDRIVER_OBJECT DriverObject);

// ──────────────────────────────────────────────
// Driver Entry Point
// ──────────────────────────────────────────────

NTSTATUS DriverEntry(PDRIVER_OBJECT DriverObject, PUNICODE_STRING RegistryPath)
{
    NTSTATUS status;
    UNICODE_STRING deviceName;
    UNICODE_STRING symbolicLink;
    WCHAR deviceNameBuffer[256];
    WCHAR symbolicLinkBuffer[256];
    PDEVICE_EXTENSION devExt = NULL;

    UNREFERENCED_PARAMETER(RegistryPath);

    DbgPrint("HermesCore: DriverEntry called\n");

    // Initialize lock
    ExInitializeFastMutex(&g_Lock);

    // Set up driver dispatch routines
    DriverObject->MajorFunction[IRP_MJ_CREATE] = HermesCoreCreateClose;
    DriverObject->MajorFunction[IRP_MJ_CLOSE] = HermesCoreCreateClose;
    DriverObject->MajorFunction[IRP_MJ_DEVICE_CONTROL] = HermesCoreDeviceControl;
    DriverObject->MajorFunction[IRP_MJ_CLEANUP] = HermesCoreCleanup;
    DriverObject->DriverUnload = HermesCoreUnload;

    // Create the device
    RtlStringCbPrintW(deviceNameBuffer, sizeof(deviceNameBuffer),
        L"\\Device\\HermesCore");

    RtlInitUnicodeString(&deviceName, deviceNameBuffer);

    status = IoCreateDevice(
        DriverObject,
        sizeof(DEVICE_EXTENSION),
        &deviceName,
        FILE_DEVICE_UNKNOWN,
        0,
        FALSE,
        &g_DeviceObject
    );

    if (!NT_SUCCESS(status))
    {
        DbgPrint("HermesCore: IoCreateDevice failed with status 0x%08X\n", status);
        return status;
    }

    // Initialize device extension
    devExt = (PDEVICE_EXTENSION)g_DeviceObject->DeviceExtension;
    RtlZeroMemory(devExt, sizeof(DEVICE_EXTENSION));
    KeInitializeEvent(&devExt->Event, NotificationEvent, FALSE);

    // Create symbolic link for user-mode access
    RtlStringCbPrintW(symbolicLinkBuffer, sizeof(symbolicLinkBuffer),
        L"\\DosDevices\\HermesCore");

    RtlInitUnicodeString(&symbolicLink, symbolicLinkBuffer);

    status = IoCreateSymbolicLink(&symbolicLink, &deviceName);
    if (!NT_SUCCESS(status))
    {
        DbgPrint("HermesCore: IoCreateSymbolicLink failed with status 0x%08X\n", status);
        IoDeleteDevice(g_DeviceObject);
        g_DeviceObject = NULL;
        return status;
    }

    // Set device flags
    g_DeviceObject->Flags |= DO_DIRECT_IO;
    g_DeviceObject->Flags &= ~DO_DEVICE_INITIALIZING;

    DbgPrint("HermesCore: Device created successfully\n");

    return STATUS_SUCCESS;
}

// ──────────────────────────────────────────────
// Driver Unload
// ──────────────────────────────────────────────

VOID HermesCoreUnload(PDRIVER_OBJECT DriverObject)
{
    UNICODE_STRING symbolicLink;
    WCHAR symbolicLinkBuffer[256];
    UNREFERENCED_PARAMETER(DriverObject);

    DbgPrint("HermesCore: Unloading driver\n");

    // Unregister callbacks
    if (g_ProcessCallbackRegistered)
    {
        PsSetCreateProcessNotifyRoutineEx(ProcessCreateNotifyRoutineEx, TRUE);
        g_ProcessCallbackRegistered = FALSE;
        DbgPrint("HermesCore: Process callback unregistered\n");
    }

    if (g_ThreadCallbackRegistered)
    {
        PsSetCreateThreadNotifyRoutine(ThreadCreateNotifyRoutine, TRUE);
        g_ThreadCallbackRegistered = FALSE;
        DbgPrint("HermesCore: Thread callback unregistered\n");
    }

    if (g_ImageCallbackRegistered)
    {
        PsSetLoadImageNotifyRoutine(ImageLoadNotifyRoutine, TRUE);
        g_ImageCallbackRegistered = FALSE;
        DbgPrint("HermesCore: Image callback unregistered\n");
    }

    // Delete symbolic link
    RtlStringCbPrintW(symbolicLinkBuffer, sizeof(symbolicLinkBuffer),
        L"\\DosDevices\\HermesCore");
    RtlInitUnicodeString(&symbolicLink, symbolicLinkBuffer);
    IoDeleteSymbolicLink(&symbolicLink);

    // Delete device
    if (g_DeviceObject)
    {
        IoDeleteDevice(g_DeviceObject);
        g_DeviceObject = NULL;
    }

    DbgPrint("HermesCore: Driver unloaded successfully\n");
}

// ──────────────────────────────────────────────
// Create/Close dispatch
// ──────────────────────────────────────────────

NTSTATUS HermesCoreCreateClose(PDEVICE_OBJECT DeviceObject, PIRP Irp)
{
    UNREFERENCED_PARAMETER(DeviceObject);
    return CompleteRequest(Irp, STATUS_SUCCESS, 0);
}

NTSTATUS HermesCoreCleanup(PDEVICE_OBJECT DeviceObject, PIRP Irp)
{
    UNREFERENCED_PARAMETER(DeviceObject);
    return CompleteRequest(Irp, STATUS_SUCCESS, 0);
}

// ──────────────────────────────────────────────
// IOCTL Dispatch — user-mode communication
// ──────────────────────────────────────────────

NTSTATUS HermesCoreDeviceControl(PDEVICE_OBJECT DeviceObject, PIRP Irp)
{
    NTSTATUS status = STATUS_INVALID_DEVICE_REQUEST;
    PIO_STACK_LOCATION stack = IoGetCurrentIrpStackLocation(Irp);
    ULONG controlCode = stack->Parameters.DeviceIoControl.IoControlCode;
    PVOID inputBuffer = Irp->AssociatedIrp.SystemBuffer;
    ULONG inputLength = stack->Parameters.DeviceIoControl.InputBufferLength;
    PVOID outputBuffer = Irp->AssociatedIrp.SystemBuffer;
    ULONG outputLength = stack->Parameters.DeviceIoControl.OutputBufferLength;
    ULONG_PTR info = 0;
    PDEVICE_EXTENSION devExt = (PDEVICE_EXTENSION)DeviceObject->DeviceExtension;

    UNREFERENCED_PARAMETER(DeviceObject);

    switch (controlCode)
    {
        case IOCTL_HERMES_QUERY_VERSION:
        {
            // Return driver version
            HERMES_VERSION_INFO version;
            RtlZeroMemory(&version, sizeof(version));
            version.Major = HERMES_DRIVER_MAJOR;
            version.Minor = HERMES_DRIVER_MINOR;
            RtlStringCbCopyW(version.BuildInfo, sizeof(version.BuildInfo), L"HermesCore v1.0");

            if (outputLength >= sizeof(HERMES_VERSION_INFO))
            {
                RtlCopyMemory(outputBuffer, &version, sizeof(HERMES_VERSION_INFO));
                info = sizeof(HERMES_VERSION_INFO);
                status = STATUS_SUCCESS;
            }
            else
            {
                status = STATUS_BUFFER_TOO_SMALL;
            }
            break;
        }

        case IOCTL_HERMES_ENABLE_MONITORING:
        {
            // Register kernel callbacks
            ExAcquireFastMutex(&g_Lock);

            if (!g_ProcessCallbackRegistered)
            {
                status = PsSetCreateProcessNotifyRoutineEx(
                    ProcessCreateNotifyRoutineEx, FALSE);
                if (NT_SUCCESS(status))
                {
                    g_ProcessCallbackRegistered = TRUE;
                    DbgPrint("HermesCore: Process monitoring enabled\n");
                }
            }
            else
            {
                status = STATUS_SUCCESS;
            }

            if (NT_SUCCESS(status) && !g_ThreadCallbackRegistered)
            {
                status = PsSetCreateThreadNotifyRoutine(ThreadCreateNotifyRoutine);
                if (NT_SUCCESS(status))
                {
                    g_ThreadCallbackRegistered = TRUE;
                    DbgPrint("HermesCore: Thread monitoring enabled\n");
                }
            }

            if (NT_SUCCESS(status) && !g_ImageCallbackRegistered)
            {
                status = PsSetLoadImageNotifyRoutine(ImageLoadNotifyRoutine);
                if (NT_SUCCESS(status))
                {
                    g_ImageCallbackRegistered = TRUE;
                    DbgPrint("HermesCore: Image load monitoring enabled\n");
                }
            }

            ExReleaseFastMutex(&g_Lock);

            info = sizeof(NTSTATUS);
            RtlCopyMemory(outputBuffer, &status, sizeof(NTSTATUS));
            break;
        }

        case IOCTL_HERMES_DISABLE_MONITORING:
        {
            // Unregister kernel callbacks
            ExAcquireFastMutex(&g_Lock);

            if (g_ProcessCallbackRegistered)
            {
                PsSetCreateProcessNotifyRoutineEx(ProcessCreateNotifyRoutineEx, TRUE);
                g_ProcessCallbackRegistered = FALSE;
            }

            if (g_ThreadCallbackRegistered)
            {
                PsSetCreateThreadNotifyRoutine(ThreadCreateNotifyRoutine, TRUE);
                g_ThreadCallbackRegistered = FALSE;
            }

            if (g_ImageCallbackRegistered)
            {
                PsSetLoadImageNotifyRoutine(ImageLoadNotifyRoutine, TRUE);
                g_ImageCallbackRegistered = FALSE;
            }

            ExReleaseFastMutex(&g_Lock);

            status = STATUS_SUCCESS;
            info = 0;
            DbgPrint("HermesCore: Monitoring disabled\n");
            break;
        }

        case IOCTL_HERMES_QUERY_STATS:
        {
            // Return current statistics
            HERMES_STATS stats;
            RtlZeroMemory(&stats, sizeof(stats));

            ExAcquireFastMutex(&g_Lock);
            stats.ProcessEvents = devExt->ProcessEventCount;
            stats.ThreadEvents = devExt->ThreadEventCount;
            stats.ImageLoadEvents = devExt->ImageLoadEventCount;
            stats.MonitoringActive = g_ProcessCallbackRegistered ||
                                     g_ThreadCallbackRegistered ||
                                     g_ImageCallbackRegistered;
            ExReleaseFastMutex(&g_Lock);

            if (outputLength >= sizeof(HERMES_STATS))
            {
                RtlCopyMemory(outputBuffer, &stats, sizeof(HERMES_STATS));
                info = sizeof(HERMES_STATS);
                status = STATUS_SUCCESS;
            }
            else
            {
                status = STATUS_BUFFER_TOO_SMALL;
            }
            break;
        }

        default:
            status = STATUS_INVALID_DEVICE_REQUEST;
            break;
    }

    return CompleteRequest(Irp, status, info);
}

// ──────────────────────────────────────────────
// Process Creation Callback
// ──────────────────────────────────────────────

VOID ProcessCreateNotifyRoutineEx(
    PEPROCESS Process,
    HANDLE ProcessId,
    PPS_CREATE_NOTIFY_INFO CreateInfo
)
{
    PDEVICE_EXTENSION devExt;
    UNREFERENCED_PARAMETER(Process);

    // Get device extension
    if (!g_DeviceObject) return;
    devExt = (PDEVICE_EXTENSION)g_DeviceObject->DeviceExtension;
    if (!devExt) return;

    ExAcquireFastMutex(&g_Lock);
    devExt->ProcessEventCount++;
    ExReleaseFastMutex(&g_Lock);

    if (CreateInfo != NULL)
    {
        // Process is being CREATED
        HANDLE parentId = CreateInfo->ParentProcessId;

        // Log to debugger
        DbgPrint("HermesCore: [+] Process Create — PID=%lu, Parent=%lu\n",
            HandleToULong(ProcessId), HandleToULong(parentId));

        if (CreateInfo->ImageFileName)
        {
            DbgPrint("HermesCore:     Image: %wZ\n", CreateInfo->ImageFileName);

            // Log suspicious patterns (example: temp directory execution)
            if (CreateInfo->ImageFileName->Buffer &&
                wcsstr(CreateInfo->ImageFileName->Buffer, L"\\Temp\\") != NULL)
            {
                DbgPrint("HermesCore:     ⚠️ Process running from Temp directory\n");
            }
        }
    }
    else
    {
        // Process is being TERMINATED
        DbgPrint("HermesCore: [-] Process Exit — PID=%lu\n",
            HandleToULong(ProcessId));
    }
}

// ──────────────────────────────────────────────
// Thread Creation Callback
// ──────────────────────────────────────────────

VOID ThreadCreateNotifyRoutine(
    HANDLE ProcessId,
    HANDLE ThreadId,
    BOOLEAN Create
)
{
    PDEVICE_EXTENSION devExt;

    if (!g_DeviceObject) return;
    devExt = (PDEVICE_EXTENSION)g_DeviceObject->DeviceExtension;
    if (!devExt) return;

    ExAcquireFastMutex(&g_Lock);
    devExt->ThreadEventCount++;
    ExReleaseFastMutex(&g_Lock);

    if (Create)
    {
        DbgPrint("HermesCore: [+] Thread Create — PID=%lu, TID=%lu\n",
            HandleToULong(ProcessId), HandleToULong(ThreadId));
    }
    else
    {
        DbgPrint("HermesCore: [-] Thread Exit — TID=%lu\n",
            HandleToULong(ThreadId));
    }
}

// ──────────────────────────────────────────────
// Image Load Callback
// ──────────────────────────────────────────────

VOID ImageLoadNotifyRoutine(
    PUNICODE_STRING FullImageName,
    HANDLE ProcessId,
    PIMAGE_INFO ImageInfo
)
{
    PDEVICE_EXTENSION devExt;

    if (!g_DeviceObject) return;
    devExt = (PDEVICE_EXTENSION)g_DeviceObject->DeviceExtension;
    if (!devExt) return;

    ExAcquireFastMutex(&g_Lock);
    devExt->ImageLoadEventCount++;
    ExReleaseFastMutex(&g_Lock);

    if (FullImageName && FullImageName->Buffer)
    {
        DbgPrint("HermesCore: [=] Image Load — PID=%lu, Name: %wZ\n",
            HandleToULong(ProcessId), FullImageName);
    }
}

// ──────────────────────────────────────────────
// Helper: Complete an IRP
// ──────────────────────────────────────────────

NTSTATUS CompleteRequest(PIRP Irp, NTSTATUS Status, ULONG_PTR Information)
{
    Irp->IoStatus.Status = Status;
    Irp->IoStatus.Information = Information;
    IoCompleteRequest(Irp, IO_NO_INCREMENT);
    return Status;
}
