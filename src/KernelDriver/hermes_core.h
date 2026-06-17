/******************************************************************************
 * hermes_core.h — HermesCore Kernel Driver Definitions
 ******************************************************************************/

#pragma once

// ──────────────────────────────────────────────
// Device Extension — per-device state
// ──────────────────────────────────────────────

typedef struct _DEVICE_EXTENSION
{
    // Event for synchronization
    KEVENT Event;

    // Statistics counters
    ULONG64 ProcessEventCount;
    ULONG64 ThreadEventCount;
    ULONG64 ImageLoadEventCount;

    // Reserved
    ULONG64 Reserved[4];

} DEVICE_EXTENSION, *PDEVICE_EXTENSION;
