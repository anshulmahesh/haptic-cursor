/*
  Menu Magnet Haptic Profiles - disposable enhanced actuator helper.
  Uses UNDOCUMENTED macOS MultitouchSupport functions via dlopen/dlsym.
  A private function can change without notice. Keep this code outside the UI.
  Nonzero levels issue exactly one hardware waveform (IDs 4,5,6,2).

  Public-domain empirical waveforms documented by MatMercer/mactic.
  Private API signatures documented by Yoshimasa Niwa's MIT example.
  No input hooks, gesture callbacks or cursor manipulation.
*/
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef CFArrayRef (*DeviceListFn)(void);
typedef CFTypeRef (*ActuatorCreateFn)(uint64_t);
typedef int32_t (*ActuatorOpenFn)(CFTypeRef);
typedef int32_t (*ActuatorCloseFn)(CFTypeRef);
typedef int32_t (*ActuatorActuateFn)(CFTypeRef, int32_t, uint32_t, float, float);

int main(void) {
    signal(SIGPIPE, SIG_IGN);
    void *framework = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW | RTLD_LOCAL);
    if (!framework) { puts("UNAVAILABLE framework"); fflush(stdout); return 2; }
    DeviceListFn deviceList = (DeviceListFn)dlsym(framework, "MTDeviceCreateList");
    ActuatorCreateFn create = (ActuatorCreateFn)dlsym(framework, "MTActuatorCreateFromDeviceID");
    ActuatorOpenFn openActuator = (ActuatorOpenFn)dlsym(framework, "MTActuatorOpen");
    ActuatorCloseFn closeActuator = (ActuatorCloseFn)dlsym(framework, "MTActuatorClose");
    ActuatorActuateFn actuate = (ActuatorActuateFn)dlsym(framework, "MTActuatorActuate");
    if (!deviceList || !create || !openActuator || !closeActuator || !actuate) {
        puts("UNAVAILABLE symbols"); fflush(stdout); dlclose(framework); return 2;
    }

    /* Device ID access at offset 64 is an empirical private ABI detail.
       All access happens here, not in the main GUI process. */
    CFArrayRef devices = deviceList();
    uint64_t selectedID = 0;
    if (devices) {
        CFIndex length = CFArrayGetCount(devices);
        for (CFIndex i = 0; i < length; ++i) {
            const uint8_t *device = (const uint8_t *)CFArrayGetValueAtIndex(devices, i);
            if (!device) continue;
            uint64_t candidate = 0;
            memcpy(&candidate, device + 64, sizeof(candidate));
            if (!candidate) continue;
            CFTypeRef probe = create(candidate);
            if (!probe) continue;
            if (openActuator(probe) == 0) {
                selectedID = candidate;
                closeActuator(probe);
                CFRelease(probe);
                break;
            }
            CFRelease(probe);
        }
        CFRelease(devices);
    }
    if (!selectedID) { puts("UNAVAILABLE trackpad"); fflush(stdout); dlclose(framework); return 2; }
    setvbuf(stdout, NULL, _IOLBF, 0);
    puts("READY");
    char input[32];
    while (fgets(input, sizeof(input), stdin)) {
        char *end = NULL;
        long level = strtol(input, &end, 10);
        if (!end || (*end != '\n' && *end != '\0')) continue;
        int32_t waveform = 0;
        switch (level) {
            case 1: waveform = 4; break; // light tap
            case 2: waveform = 5; break; // medium tap
            case 3: waveform = 6; break; // strong tap
            case 4: waveform = 2; break; // hard click
            default: continue;
        }
        CFTypeRef actuator = create(selectedID);
        if (!actuator) { puts("ERROR create"); break; }
        int32_t result = openActuator(actuator);
        if (result == 0) {
            result = actuate(actuator, waveform, 0, 0.0f, 0.0f);
            closeActuator(actuator);
        }
        CFRelease(actuator);
        if (result != 0) { puts("ERROR actuator"); break; }
    }
    dlclose(framework);
    return 0;
}
