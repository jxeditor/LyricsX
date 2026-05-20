//
//  MRPrivateLoader.h
//  LyricsX - https://github.com/ddddxxx/LyricsX
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

#if TARGET_OS_MAC

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "MediaRemotePrivate.h"
#import "SymbolLoader.h"

#define kMediaRemotePath "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

bool MRIsMediaRemoteLoaded = false;

SLDefineFunction(MRMediaRemoteSendCommand, Boolean, MRCommand, _Nullable id);
SLDefineFunction(MRMediaRemoteSetElapsedTime, void, double);

SLDefineFunction(MRMediaRemoteGetNowPlayingInfo, void, dispatch_queue_t, void(^)(_Nullable CFDictionaryRef));
SLDefineFunction(MRMediaRemoteGetNowPlayingInfoForPlayer, void, CFTypeRef, Boolean, dispatch_queue_t, void(^)(_Nullable CFDictionaryRef));
SLDefineFunction(MRMediaRemoteGetNowPlayingClient, void, dispatch_queue_t, void(^)(_Nullable CFTypeRef));
SLDefineFunction(MRMediaRemoteGetNowPlayingClients, void, dispatch_queue_t, void(^)(CFArrayRef));
SLDefineFunction(MRMediaRemoteGetNowPlayingApplicationIsPlaying, void, dispatch_queue_t, void(^)(Boolean));
SLDefineFunction(MRMediaRemoteGetNowPlayingApplicationPID, void, dispatch_queue_t, void(^)(int));

SLDefineFunction(MRNowPlayingClientGetBundleIdentifier, _Nullable CFStringRef, CFTypeRef);
SLDefineFunction(MRNowPlayingClientGetDisplayName, _Nullable CFStringRef, CFTypeRef);
SLDefineFunction(MRNowPlayingClientGetParentAppBundleIdentifier, _Nullable CFStringRef, CFTypeRef);
SLDefineFunction(MRNowPlayingClientGetProcessIdentifier, int, CFTypeRef);

SLDefineFunction(MRMediaRemoteRegisterForNowPlayingNotifications, void, dispatch_queue_t);
SLDefineFunction(MRMediaRemoteSetWantsNowPlayingNotifications, void, Boolean);
SLDefineFunction(MRMediaRemoteUnregisterForNowPlayingNotifications, void);

__attribute__((constructor)) static void loadMediaRemote() {
    void *handle = dlopen(kMediaRemotePath, RTLD_LAZY);
    if (handle == NULL) {
        return;
    }
    
    MRIsMediaRemoteLoaded = true;
    
    SLLoad(handle, MRMediaRemoteSendCommand);
    SLLoad(handle, MRMediaRemoteSetElapsedTime);
    
    SLLoad(handle, MRMediaRemoteGetNowPlayingInfo);
    SLLoad(handle, MRMediaRemoteGetNowPlayingInfoForPlayer);
    SLLoad(handle, MRMediaRemoteGetNowPlayingClient);
    SLLoad(handle, MRMediaRemoteGetNowPlayingClients);
    SLLoad(handle, MRMediaRemoteGetNowPlayingApplicationIsPlaying);
    SLLoad(handle, MRMediaRemoteGetNowPlayingApplicationPID);

    SLLoad(handle, MRNowPlayingClientGetBundleIdentifier);
    SLLoad(handle, MRNowPlayingClientGetDisplayName);
    SLLoad(handle, MRNowPlayingClientGetParentAppBundleIdentifier);
    SLLoad(handle, MRNowPlayingClientGetProcessIdentifier);
    
    SLLoad(handle, MRMediaRemoteRegisterForNowPlayingNotifications);
    SLLoad(handle, MRMediaRemoteSetWantsNowPlayingNotifications);
    SLLoad(handle, MRMediaRemoteUnregisterForNowPlayingNotifications);
    
    dlclose(handle);
}

#endif
