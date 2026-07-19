// Private IOKit HID event-system-client declarations needed to set per-device
// pointer resolution / acceleration (the LinearMouse technique). Only symbols
// NOT in the public SDK are declared here; IOHIDEventSystemClientCopyServices
// and IOHIDServiceClientSetProperty come from the SDK.
#ifndef HEADMOUSE_IOKIT_SPI_H
#define HEADMOUSE_IOKIT_SPI_H

#import <IOKit/hid/IOHIDManager.h>

CF_IMPLICIT_BRIDGING_ENABLED

typedef struct CF_BRIDGED_TYPE(id) __IOHIDServiceClient * IOHIDServiceClientRef;
typedef struct CF_BRIDGED_TYPE(id) __IOHIDEventSystemClient * IOHIDEventSystemClientRef;

IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef key);

CF_IMPLICIT_BRIDGING_DISABLED

#endif
