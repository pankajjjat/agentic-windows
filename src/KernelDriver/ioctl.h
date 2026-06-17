/******************************************************************************
 * ioctl.h — HermesCore IOCTL interface definitions
 *
 * User-mode applications communicate with HermesCore.sys via these IOCTL codes.
 * Include this header in both the kernel driver and the user-mode agent.
 ******************************************************************************/

#pragma once

#include <winioctl.h>

// ──────────────────────────────────────────────
// Driver version
// ──────────────────────────────────────────────

#define HERMES_DRIVER_MAJOR 1
#define HERMES_DRIVER_MINOR 0

// ──────────────────────────────────────────────
// IOCTL codes
// ──────────────────────────────────────────────

// Query driver version info
#define IOCTL_HERMES_QUERY_VERSION \
    CTL_CODE(FILE_DEVICE_UNKNOWN, 0x800, METHOD_BUFFERED, FILE_ANY_ACCESS)

// Enable kernel monitoring (process, thread, image callbacks)
#define IOCTL_HERMES_ENABLE_MONITORING \
    CTL_CODE(FILE_DEVICE_UNKNOWN, 0x801, METHOD_BUFFERED, FILE_ANY_ACCESS)

// Disable kernel monitoring
#define IOCTL_HERMES_DISABLE_MONITORING \
    CTL_CODE(FILE_DEVICE_UNKNOWN, 0x802, METHOD_BUFFERED, FILE_ANY_ACCESS)

// Query driver statistics
#define IOCTL_HERMES_QUERY_STATS \
    CTL_CODE(FILE_DEVICE_UNKNOWN, 0x803, METHOD_BUFFERED, FILE_ANY_ACCESS)

// ──────────────────────────────────────────────
// Data structures
// ──────────────────────────────────────────────

typedef struct _HERMES_VERSION_INFO
{
    ULONG Major;
    ULONG Minor;
    WCHAR BuildInfo[128];

} HERMES_VERSION_INFO, *PHERMES_VERSION_INFO;

typedef struct _HERMES_STATS
{
    ULONG64 ProcessEvents;
    ULONG64 ThreadEvents;
    ULONG64 ImageLoadEvents;
    BOOLEAN MonitoringActive;
    BYTE Reserved[7];

} HERMES_STATS, *PHERMES_STATS;
