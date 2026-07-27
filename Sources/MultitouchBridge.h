/*
 * Portions of the MultitouchSupport declarations are derived from MouseToucher.
 * Copyright (c) 2025 Roger Hughes, used under the MIT License.
 * See THIRD_PARTY_NOTICES.md.
 *
 * Magic Control modifications are licensed under GPL-3.0-only.
 */
#ifndef MultitouchBridge_h
#define MultitouchBridge_h
#include <CoreFoundation/CoreFoundation.h>

typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } MTVector;

typedef struct {
  int32_t frame;
  double timestamp;
  int32_t identifier;
  int32_t state;          // 4 = Touching
  int32_t fingerId, handId;
  MTVector normalized;    // position/velocity とも 0.0-1.0 正規化（Yは前方が大）
  float size;
  int32_t zero1;
  float angle, majorAxis, minorAxis;
  MTVector absolute;
  int32_t zero2, zero3;
  float zDensity;
} MTTouch;

typedef void *MTDeviceRef;
typedef int (*MTContactCallbackFunction)(MTDeviceRef device, MTTouch *touches,
                                         int numTouches, double timestamp, int frame);

CFMutableArrayRef MTDeviceCreateList(void);
void MTRegisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);
void MTUnregisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);
void MTDeviceStart(MTDeviceRef, int);
void MTDeviceStop(MTDeviceRef);
bool MTDeviceIsBuiltIn(MTDeviceRef);
OSStatus MTDeviceGetFamilyID(MTDeviceRef, int32_t *familyId);

// トラッキング速度ブースト用 SPI(IOHIDEventSystemClient)。
// システム設定の「軌跡の速さ」スライダーの実体(HIDMouseAcceleration)を直接書き換える。
// LinearMouse 等での実績あり(2026-07-10 判断メモ参照)。IOKit.framework にリンクして解決する。
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreateSimpleClient(CFAllocatorRef allocator);
extern void IOHIDEventSystemClientSetProperty(IOHIDEventSystemClientRef client, CFStringRef key, CFTypeRef property);
extern CFTypeRef IOHIDEventSystemClientCopyProperty(IOHIDEventSystemClientRef client, CFStringRef key);

#endif
