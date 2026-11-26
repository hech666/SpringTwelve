#pragma once
#import <Foundation/Foundation.h>
// Broker runs only in SpringBoard; consumer runs only in MobilePhone.
FOUNDATION_EXPORT NSString * const HaogeCallRecorderRecordingAccessReady;
FOUNDATION_EXPORT void haoge_callrecorder_installRecordingAccess(void);
FOUNDATION_EXPORT void haoge_callrecorder_consumeRecordingAccess(void);
FOUNDATION_EXPORT void haoge_callrecorder_requestRecordingAccess(void);
FOUNDATION_EXPORT void haoge_callrecorder_accessLog(const char *stage, int code);
