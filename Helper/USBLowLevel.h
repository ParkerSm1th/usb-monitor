#ifndef USBLowLevel_h
#define USBLowLevel_h

#include <IOKit/IOKitLib.h>
#include <IOKit/usb/USB.h>

#ifdef __cplusplus
extern "C" {
#endif

kern_return_t usb_toggle_get_device_information(io_service_t service, uint32_t *outInfoBits);
kern_return_t usb_toggle_reenumerate(io_service_t service, uint32_t options);

#ifdef __cplusplus
}
#endif

#endif
