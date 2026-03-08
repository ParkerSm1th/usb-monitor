#include "USBLowLevel.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>

static kern_return_t usb_toggle_create_device_interface(io_service_t service,
                                                         IOUSBDeviceInterface650 ***outDevice,
                                                         IOCFPlugInInterface ***outPlugin) {
    if (!outDevice || !outPlugin) {
        return kIOReturnBadArgument;
    }

    *outDevice = NULL;
    *outPlugin = NULL;

    SInt32 score = 0;
    IOCFPlugInInterface **plugin = NULL;

    kern_return_t status = IOCreatePlugInInterfaceForService(
        service,
        kIOUSBDeviceUserClientTypeID,
        kIOCFPlugInInterfaceID,
        &plugin,
        &score
    );

    if (status != kIOReturnSuccess || plugin == NULL) {
        return status == kIOReturnSuccess ? kIOReturnNoResources : status;
    }

    IOUSBDeviceInterface650 **device = NULL;
    HRESULT queryStatus = (*plugin)->QueryInterface(
        plugin,
        CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID650),
        (LPVOID *)&device
    );

    if (queryStatus != S_OK || device == NULL) {
        (*plugin)->Release(plugin);
        return kIOReturnError;
    }

    *outDevice = device;
    *outPlugin = plugin;
    return kIOReturnSuccess;
}

static void usb_toggle_release_device_interface(IOUSBDeviceInterface650 **device,
                                                IOCFPlugInInterface **plugin) {
    if (device != NULL) {
        (*device)->Release(device);
    }
    if (plugin != NULL) {
        (*plugin)->Release(plugin);
    }
}

kern_return_t usb_toggle_get_device_information(io_service_t service, uint32_t *outInfoBits) {
    if (service == IO_OBJECT_NULL || outInfoBits == NULL) {
        return kIOReturnBadArgument;
    }

    IOUSBDeviceInterface650 **device = NULL;
    IOCFPlugInInterface **plugin = NULL;

    kern_return_t status = usb_toggle_create_device_interface(service, &device, &plugin);
    if (status != kIOReturnSuccess) {
        return status;
    }

    uint32_t info = 0;
    status = (*device)->GetUSBDeviceInformation(device, &info);
    if (status == kIOReturnSuccess) {
        *outInfoBits = info;
    }

    usb_toggle_release_device_interface(device, plugin);
    return status;
}

kern_return_t usb_toggle_reenumerate(io_service_t service, uint32_t options) {
    if (service == IO_OBJECT_NULL) {
        return kIOReturnBadArgument;
    }

    IOUSBDeviceInterface650 **device = NULL;
    IOCFPlugInInterface **plugin = NULL;

    kern_return_t status = usb_toggle_create_device_interface(service, &device, &plugin);
    if (status != kIOReturnSuccess) {
        return status;
    }

    status = (*device)->USBDeviceReEnumerate(device, options);

    usb_toggle_release_device_interface(device, plugin);
    return status;
}
