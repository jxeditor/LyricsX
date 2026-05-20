//
//  LXPlayerNetEaseCloudMusic.m
//  LyricsX - https://github.com/ddddxxx/LyricsX
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

#if TARGET_OS_MAC && !TARGET_OS_IPHONE

#import "LXScriptingMusicPlayer+Private.h"
#import "LXMusicTrack+Private.h"
#import "LXWeakProxy.h"

#define NETEASE_INTERNAL_UPDATE_INTERVAL 1.5

static id scriptValue(id app, NSString *key) {
    @try {
        if ([app respondsToSelector:NSSelectorFromString(key)]) {
            id value = [app valueForKey:key];
            return value == NSNull.null ? nil : value;
        }
    } @catch (__unused NSException *exception) {
    }
    return nil;
}

static NSString *scriptString(id app, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        id value = scriptValue(app, key);
        if ([value isKindOfClass:NSString.class] && ((NSString *)value).length > 0) {
            return value;
        }
    }
    return nil;
}

static NSNumber *scriptNumber(id app, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        id value = scriptValue(app, key);
        if ([value isKindOfClass:NSNumber.class]) {
            return value;
        }
    }
    return nil;
}

static BOOL scriptBool(id app, NSArray<NSString *> *keys, BOOL fallback) {
    for (NSString *key in keys) {
        id value = scriptValue(app, key);
        if ([value respondsToSelector:@selector(boolValue)]) {
            return [value boolValue];
        }
    }
    return fallback;
}

static void performCommand(id app, NSArray<NSString *> *selectors) {
    for (NSString *selectorName in selectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([app respondsToSelector:selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [app performSelector:selector];
#pragma clang diagnostic pop
            return;
        }
    }
}

static LXMusicTrack *currentTrack(id app) {
    NSString *persistentID = scriptString(app, @[@"persistentID", @"id", @"trackID", @"currentTrackID", @"currentTrackUrl"]);
    NSString *title = scriptString(app, @[@"name", @"title", @"track", @"currentTrackName"]);
    NSString *artist = scriptString(app, @[@"artist", @"currentArtist"]);
    NSString *album = scriptString(app, @[@"album", @"currentAlbum"]);
    if (!persistentID) {
        persistentID = [@[title ?: @"", artist ?: @"", album ?: @""] componentsJoinedByString:@" - "];
    }
    if (persistentID.length == 0) {
        return nil;
    }
    LXMusicTrack *track = [[LXMusicTrack alloc] initWithPersistentID:persistentID];
    track.title = title;
    track.artist = artist;
    track.album = album;
    track.duration = scriptNumber(app, @[@"duration", @"totalTime", @"currentTrackDuration"]);
    NSString *url = scriptString(app, @[@"fileURL", @"location", @"currentTrackUrl"]);
    if (url) {
        track.fileURL = [NSURL URLWithString:url] ?: [NSURL fileURLWithPath:url];
    }
    return track;
}

static NSTimeInterval playbackTime(id app) {
    return [scriptNumber(app, @[@"playerPosition", @"currentTime", @"position"]) doubleValue];
}

static LXPlaybackState playbackState(id app) {
    NSString *state = [scriptString(app, @[@"playerState", @"state", @"status"]) lowercaseString];
    if ([state containsString:@"play"]) {
        return LXPlaybackStatePlaying;
    } else if ([state containsString:@"pause"]) {
        return LXPlaybackStatePaused;
    } else if ([state containsString:@"stop"]) {
        return LXPlaybackStateStopped;
    }
    return scriptBool(app, @[@"playing", @"isPlaying"], false) ? LXPlaybackStatePlaying : LXPlaybackStatePaused;
}

static LXPlayerState *playerState(id app) {
    return [LXPlayerState state:playbackState(app) playbackTime:playbackTime(app)];
}

@implementation LXPlayerNetEaseCloudMusic {
    NSTimer *_timer;
}

+ (LXMusicPlayerName)playerName {
    return LXMusicPlayerNameNetEaseCloudMusic;
}

- (id)app {
    return super.originalPlayer;
}

- (instancetype)init {
    if ((self = [super init])) {
        if (self.isRunning) {
            self.currentTrack = currentTrack(self.app);
            self.playerState = playerState(self.app);
        }
        _timer = [NSTimer scheduledTimerWithTimeInterval:NETEASE_INTERNAL_UPDATE_INTERVAL target:[[LXWeakProxy alloc] initWithObject:self] selector:@selector(updatePlayerState) userInfo:nil repeats:YES];
        [self rescheduleInternalUpdate];
    }
    return self;
}

- (void)dealloc {
    [_timer invalidate];
}

- (void)setRunning:(BOOL)running {
    [super setRunning:running];
    [self rescheduleInternalUpdate];
}

- (void)rescheduleInternalUpdate {
    _timer.fireDate = self.isRunning ? [NSDate dateWithTimeIntervalSinceNow:NETEASE_INTERNAL_UPDATE_INTERVAL] : NSDate.distantFuture;
}

- (void)setPlaybackTime:(NSTimeInterval)playbackTime {
    if (!self.isRunning) { return; }
    @try {
        if ([self.app respondsToSelector:@selector(setValue:forKey:)]) {
            [self.app setValue:@(playbackTime) forKey:@"playerPosition"];
        }
    } @catch (__unused NSException *exception) {
    }
    self.playerState = [LXPlayerState state:self.playerState.state playbackTime:playbackTime];
}

- (void)updatePlayerState {
    if (!self.isRunning) { return; }
    LXMusicTrack *track = currentTrack(self.app);
    LXPlayerState *state = playerState(self.app);
    if (track && [self.currentTrack.persistentID isEqualToString:track.persistentID]) {
        [self setPlayerState:state tolerate:1.5];
    } else {
        self.currentTrack = track;
        self.playerState = state;
    }
    [self rescheduleInternalUpdate];
}

- (void)resume {
    if (!self.isRunning) { return; }
    performCommand(self.app, @[@"play", @"resume"]);
}

- (void)pause {
    if (!self.isRunning) { return; }
    performCommand(self.app, @[@"pause"]);
}

- (void)playPause {
    if (!self.isRunning) { return; }
    performCommand(self.app, @[@"playpause", @"playPause"]);
}

- (void)skipToNextItem {
    if (!self.isRunning) { return; }
    performCommand(self.app, @[@"nextTrack", @"next"]);
}

- (void)skipToPreviousItem {
    if (!self.isRunning) { return; }
    performCommand(self.app, @[@"previousTrack", @"previous"]);
}

@end

#endif
