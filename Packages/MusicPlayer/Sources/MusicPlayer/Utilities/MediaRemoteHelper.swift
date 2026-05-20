//
//  MediaRemoteHelper.swift
//  LyricsX - https://github.com/ddddxxx/LyricsX
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

#if os(macOS) || os(iOS)

import Foundation

struct MRNowPlayingInfo {
    
    var dict: NSDictionary
    
    init(dict: NSDictionary) {
        self.dict = dict
    }
    
    private subscript<T>(key: String) -> T? {
        return dict.value(forKey: key) as? T
    }
    
    var _timestamp: Date? {
        return self["kMRMediaRemoteNowPlayingInfoTimestamp"]
    }
    
    var _elapsedTime: TimeInterval? {
        return self["kMRMediaRemoteNowPlayingInfoElapsedTime"]
    }

    var _calculatedElapsedTime: TimeInterval? {
        return self["kMRMediaRemoteNowPlayingInfoCalculatedElapsedTime"]
    }

    var elapsedTime: TimeInterval? {
        return _elapsedTime ?? _calculatedElapsedTime
    }

    var currentElapsedTime: TimeInterval? {
        guard let elapsedTime = elapsedTime else {
            return nil
        }
        guard let timestamp = _timestamp,
              (_playbackRate ?? 0) != 0 else {
            return elapsedTime
        }
        return elapsedTime + Date().timeIntervalSince(timestamp) * (_playbackRate ?? 1)
    }

    var _playbackRate: Double? {
        return self["kMRMediaRemoteNowPlayingInfoPlaybackRate"]
    }
    
    var _startTime: Date? {
        return self["kMRMediaRemoteNowPlayingInfoStartTime"]
    }
    
    var _uniqueIdentifier: Int? {
        return self["kMRMediaRemoteNowPlayingInfoUniqueIdentifier"]
    }
    
    var _title: String? {
        return self["kMRMediaRemoteNowPlayingInfoTitle"]
    }
    
    var _album: String? {
        return self["kMRMediaRemoteNowPlayingInfoAlbum"]
    }
    
    var _artist: String? {
        return self["kMRMediaRemoteNowPlayingInfoArtist"]
    }
    
    var _duration: TimeInterval? {
        return self["kMRMediaRemoteNowPlayingInfoDuration"]
    }

    var _durationMillis: TimeInterval? {
        return self["kMRMediaRemoteNowPlayingInfoDurationMilliseconds"].map { (value: Double) in value / 1000 }
    }
    
    var _artworkData: Data? {
        return self["kMRMediaRemoteNowPlayingInfoArtworkData"]
    }

    var _contentItemIdentifier: String? {
        return self["kMRMediaRemoteNowPlayingInfoContentItemIdentifier"]
    }

    var _identifier: String? {
        return self["kMRMediaRemoteNowPlayingInfoIdentifier"]
    }
    
    var id: String? {
        if let id = _uniqueIdentifier {
            return id.description
        } else if let id = _contentItemIdentifier, !id.isEmpty {
            return id
        } else if let id = _identifier, !id.isEmpty {
            return id
        } else if let title = _title {
            return "NowPlaying-\(title)-\(_album ?? "")-\(duration.map(Int.init) ?? 0)"
        } else {
            return nil
        }
    }
    
    var startTime: Date? {
        if let _elapsedTime = currentElapsedTime {
            return Date(timeIntervalSinceNow: -_elapsedTime)
        } else {
            return nil
        }
    }
    
    var artwork: Image? {
        guard let artworkData = _artworkData else {
            return nil
        }
        return Image(data: artworkData)
    }
    
    var track: MusicTrack? {
        guard let id = id else {
            return nil
        }
        return MusicTrack(id: id, title: _title, album: _album, artist: _artist, duration: duration, fileURL: nil, artwork: artwork, originalTrack: nil)
    }

    var duration: TimeInterval? {
        return _duration ?? _durationMillis
    }
}

#endif
