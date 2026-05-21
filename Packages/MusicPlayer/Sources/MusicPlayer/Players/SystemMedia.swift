//
//  SystemMedia.swift
//  LyricsX - https://github.com/ddddxxx/LyricsX
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

#if os(macOS) || os(iOS)

import AppKit
import Foundation
import MediaRemotePrivate
import CXShim

extension MusicPlayers {
    
    public final class SystemMedia: ObservableObject {
        
        public static var available: Bool {
            return MRIsMediaRemoteLoaded
        }
        
        @Published public private(set) var currentTrack: MusicTrack?
        @Published public private(set) var playbackState: PlaybackState = .stopped
        
        private var systemPlaybackState: SystemPlaybackState?
        private let playerNameOverride: MusicPlayerName?
        private var nowPlayingBundleIdentifier: String?
        private let debugLogURL = URL(fileURLWithPath: "/tmp/lyricsx-system-media.log")
        private var lastLoggedClientSnapshot: String?
        private var lastAcceptedInfoDate: Date?
        private var lastClientDiagnosticDate: Date?
        
        public init?(name: MusicPlayerName? = nil) {
            guard Self.available else { return nil }
            playerNameOverride = name
            writeDebugLog("init player=\(name?.rawValue ?? "system")")
            MRMediaRemoteSetWantsNowPlayingNotifications_?(true)
            MRMediaRemoteRegisterForNowPlayingNotifications_?(DispatchQueue.playerUpdate)
            
            let nc = NotificationCenter.default
            nc.addObserver(forName: .mediaRemoteNowPlayingApplicationPlaybackStateDidChange, object: nil, queue: nil) { [weak self] n in
                self?.mediaRemoteNowPlayingApplicationPlaybackStateDidChange(n: n)
            }
            nc.addObserver(forName: .mediaRemoteNowPlayingInfoDidChange, object: nil, queue: nil) { [weak self] n in
                self?.mediaRemoteNowPlayingInfoDidChange(n: n)
            }
            nc.addObserver(forName: .mediaRemotePlayerNowPlayingInfoDidChange, object: nil, queue: nil) { [weak self] n in
                self?.mediaRemoteNowPlayingInfoDidChange(n: n)
            }
            nc.addObserver(forName: .mediaRemotePlayerPlaybackStateDidChange, object: nil, queue: nil) { [weak self] n in
                self?.mediaRemoteNowPlayingApplicationPlaybackStateDidChange(n: n)
            }
            nc.addObserver(forName: .mediaRemoteNowPlayingApplicationIsPlayingDidChange, object: nil, queue: nil) { [weak self] n in
                self?.mediaRemoteNowPlayingApplicationIsPlayingDidChange(n: n)
            }
            
            MRMediaRemoteGetNowPlayingApplicationIsPlaying_?(DispatchQueue.playerUpdate) { [weak self] isPlaying in
                self?.systemPlaybackState = isPlaying.boolValue ? .playing : .paused
                self?.updatePlayerState()
            }
        }
        
        deinit {
            MRMediaRemoteSetWantsNowPlayingNotifications_?(false)
            MRMediaRemoteUnregisterForNowPlayingNotifications_?()
        }
        
        private func getNowPlayingInfoCallback(_ infoDict: CFDictionary?, clearOnEmpty: Bool = true) {
            if let playerNameOverride = playerNameOverride,
               playerNameOverride == .neteaseCloudMusic,
               nowPlayingBundleIdentifier != nil,
               nowPlayingBundleIdentifier != "com.netease.163music" {
                writeDebugLog("skip now playing app \(nowPlayingBundleIdentifier ?? "nil") for NetEase")
                playbackState = .stopped
                currentTrack = nil
                return
            }
            guard let infoDict = infoDict as NSDictionary? else {
                writeDebugLog("empty now playing info app=\(nowPlayingBundleIdentifier ?? "nil")")
                if clearOnEmpty {
                    playbackState = .stopped
                    currentTrack = nil
                }
                return
            }
            writeDebugLog("raw keys=\(infoDict.allKeys)")
            lastAcceptedInfoDate = Date()
            let info = MRNowPlayingInfo(dict: infoDict)
            let newState: PlaybackState
            switch systemPlaybackState ?? info.inferredPlaybackState {
            case .playing:
                newState = info.startTime.map(PlaybackState.playing) ?? .stopped
            case .paused:
                newState = info.elapsedTime.map(PlaybackState.paused) ?? .stopped
            default:
                newState = .stopped
            }
            if !playbackState.approximateEqual(to: newState) {
                playbackState = newState
            }
            
            let newTrack = info.track
            writeDebugLog("app=\(nowPlayingBundleIdentifier ?? "nil") title=\(newTrack?.title ?? "nil") artist=\(newTrack?.artist ?? "nil") id=\(newTrack?.id ?? "nil") state=\(newState)")
            if newTrack?.id != currentTrack?.id {
                currentTrack = newTrack
            }
        }
        
        private func mediaRemoteNowPlayingApplicationPlaybackStateDidChange(n: Notification) {
            guard let info = n.userInfo as! [String: Any]? else {
                playbackState = .stopped
                currentTrack = nil
                return
            }
            
            systemPlaybackState = playbackState(from: info)
            if systemPlaybackState == .playing || systemPlaybackState == .paused {
                updatePlayerState()
            } else {
                playbackState = .stopped
                currentTrack = nil
            }
        }

        private func mediaRemoteNowPlayingApplicationIsPlayingDidChange(n: Notification) {
            guard let info = n.userInfo else {
                updatePlayerState()
                return
            }
            if let isPlaying = info["kMRMediaRemoteNowPlayingApplicationIsPlayingUserInfoKey"] as? Bool {
                systemPlaybackState = isPlaying ? .playing : .paused
            } else if let isPlaying = info["kMRMediaRemoteNowPlayingApplicationIsPlayingUserInfoKey"] as? NSNumber {
                systemPlaybackState = isPlaying.boolValue ? .playing : .paused
            }
            updatePlayerState()
        }
        
        private func mediaRemoteNowPlayingInfoDidChange(n: Notification) {
            if let infoDict = n.userInfo?["kMRMediaRemoteNowPlayingInfoUserInfo"] as? NSDictionary {
                if let bundle = nowPlayingBundleIdentifier(from: n.userInfo) {
                    nowPlayingBundleIdentifier = bundle
                }
                getNowPlayingInfoCallback(infoDict, clearOnEmpty: false)
                return
            }
            if playerNameOverride == .neteaseCloudMusic {
                writeDebugLog("netease now playing notification keys=\(n.userInfo?.keys.map(String.init(describing:)) ?? []) values=\(describeNotificationUserInfo(n.userInfo))")
            }
            updatePlayerState()
        }
    }
}

extension MusicPlayers.SystemMedia: MusicPlayerProtocol {
    
    public var currentTrackWillChange: AnyPublisher<MusicTrack?, Never> {
        return $currentTrack.eraseToAnyPublisher()
    }
    
    public var playbackStateWillChange: AnyPublisher<PlaybackState, Never> {
        return $playbackState.eraseToAnyPublisher()
    }
    
    public var name: MusicPlayerName? {
        if let playerNameOverride = playerNameOverride {
            return playerNameOverride
        }
        switch nowPlayingBundleIdentifier {
        case "com.spotify.client":
            return .spotify
        case "com.netease.163music":
            return .neteaseCloudMusic
        case "com.apple.Music", "com.apple.iTunes":
            return .appleMusic
        default:
            return nil
        }
    }
    
    public var playbackTime: TimeInterval {
        get {
            return playbackState.time
        }
        set {
            MRMediaRemoteSetElapsedTime_?(newValue)
            playbackState = playbackState.withTime(newValue)
        }
    }
    
    public func resume() {
        _ = MRMediaRemoteSendCommand_?(.play, nil)
    }
    
    public func pause() {
        _ = MRMediaRemoteSendCommand_?(.pause, nil)
    }
    
    public func playPause() {
        _ = MRMediaRemoteSendCommand_?(.togglePlayPause, nil)
    }
    
    public func skipToNextItem() {
        _ = MRMediaRemoteSendCommand_?(.nextTrack, nil)
    }
    
    public func skipToPreviousItem() {
        _ = MRMediaRemoteSendCommand_?(.previousTrack, nil)
    }
    
    public func updatePlayerState() {
        if playerNameOverride == .neteaseCloudMusic {
            updateNeteasePlayerState()
            return
        }
        guard let getNowPlayingApplicationPID = MRMediaRemoteGetNowPlayingApplicationPID_ else {
            MRMediaRemoteGetNowPlayingInfo_?(DispatchQueue.playerUpdate) { [weak self] info in
                self?.getNowPlayingInfoCallback(info)
            }
            return
        }
        getNowPlayingApplicationPID(DispatchQueue.playerUpdate) { [weak self] pid in
            self?.nowPlayingBundleIdentifier = NSRunningApplication(processIdentifier: pid_t(pid))?.bundleIdentifier
            self?.writeDebugLog("nowPlayingPID=\(pid) bundle=\(self?.nowPlayingBundleIdentifier ?? "nil")")
            MRMediaRemoteGetNowPlayingInfo_?(DispatchQueue.playerUpdate) { [weak self] info in
                if info == nil, self?.playerNameOverride == .neteaseCloudMusic {
                    self?.logNowPlayingClientsForDiagnostics()
                }
                self?.getNowPlayingInfoCallback(info, clearOnEmpty: self?.shouldClearOnEmptyNowPlayingInfo() ?? true)
            }
        }
    }

    private func updateNeteasePlayerState() {
        logNowPlayingClientsForDiagnosticsIfNeeded()
        guard let getNowPlayingApplicationPID = MRMediaRemoteGetNowPlayingApplicationPID_ else {
            MRMediaRemoteGetNowPlayingInfo_?(DispatchQueue.playerUpdate) { [weak self] info in
                self?.getNowPlayingInfoCallback(info)
            }
            return
        }
        getNowPlayingApplicationPID(DispatchQueue.playerUpdate) { [weak self] pid in
            guard let self = self else { return }
            self.nowPlayingBundleIdentifier = NSRunningApplication(processIdentifier: pid_t(pid))?.bundleIdentifier
            self.writeDebugLog("netease nowPlayingPID=\(pid) bundle=\(self.nowPlayingBundleIdentifier ?? "nil")")
            MRMediaRemoteGetNowPlayingInfo_?(DispatchQueue.playerUpdate) { [weak self] info in
                if info == nil {
                    self?.writeDebugLog("netease global nowPlaying info=nil")
                    if self?.updateNeteasePlayerStateFromMediaControl() == true {
                        return
                    }
                }
                self?.getNowPlayingInfoCallback(info, clearOnEmpty: self?.shouldClearOnEmptyNowPlayingInfo() ?? true)
            }
        }
    }

    private func updateNeteasePlayerStateFromMediaControl() -> Bool {
        guard let snapshot = MediaControlNowPlayingSnapshot.fetch(),
              snapshot.bundleIdentifier == "com.netease.163music",
              let title = snapshot.title,
              !title.isEmpty else {
            writeDebugLog("media-control fallback unavailable")
            return false
        }

        let id = snapshot.contentItemIdentifier ?? "MediaControl-\(title)-\(snapshot.artist ?? "")-\(Int(snapshot.duration ?? 0))"
        let track = MusicTrack(id: id,
                               title: title,
                               album: snapshot.album,
                               artist: snapshot.artist,
                               duration: snapshot.duration,
                               fileURL: nil,
                               artwork: nil,
                               originalTrack: nil)
        let elapsed = snapshot.elapsedTimeNow ?? snapshot.elapsedTime ?? 0
        let newState: PlaybackState = snapshot.playing ? .playing(time: elapsed) : .paused(time: elapsed)
        writeDebugLog("media-control title=\(title) artist=\(snapshot.artist ?? "nil") elapsed=\(elapsed) duration=\(snapshot.duration ?? 0) playing=\(snapshot.playing)")

        if !playbackState.approximateEqual(to: newState) {
            playbackState = newState
        }
        if track.id != currentTrack?.id {
            currentTrack = track
        }
        lastAcceptedInfoDate = Date()
        return true
    }

    private func logNowPlayingClientsForDiagnostics() {
        MRMediaRemoteGetNowPlayingClient_?(DispatchQueue.playerUpdate) { [weak self] client in
            guard let self = self else { return }
            self.writeDebugLog("netease current client=\(self.describeNowPlayingClient(client))")
        }
        MRMediaRemoteGetNowPlayingClients_?(DispatchQueue.playerUpdate) { [weak self] clients in
            guard let self = self else { return }
            let array = clients as NSArray
            let snapshot = array.compactMap { self.describeNowPlayingClient($0 as CFTypeRef) }.joined(separator: " | ")
            if snapshot != self.lastLoggedClientSnapshot {
                self.lastLoggedClientSnapshot = snapshot
                self.writeDebugLog("netease clients count=\(array.count) \(snapshot)")
            }
        }
    }

    private func logNowPlayingClientsForDiagnosticsIfNeeded() {
        let now = Date()
        if let lastClientDiagnosticDate = lastClientDiagnosticDate,
           now.timeIntervalSince(lastClientDiagnosticDate) < 10 {
            return
        }
        lastClientDiagnosticDate = now
        logNowPlayingClientsForDiagnostics()
    }

    private func describeNowPlayingClient(_ client: CFTypeRef?) -> String {
        guard let client = client else { return "nil" }
        let bundle = MRNowPlayingClientGetBundleIdentifier_?(client)?.takeUnretainedValue() as String?
        let parent = MRNowPlayingClientGetParentAppBundleIdentifier_?(client)?.takeUnretainedValue() as String?
        let displayName = MRNowPlayingClientGetDisplayName_?(client)?.takeUnretainedValue() as String?
        let pid = MRNowPlayingClientGetProcessIdentifier_?(client) ?? 0
        return "pid=\(pid) bundle=\(bundle ?? "nil") parent=\(parent ?? "nil") name=\(displayName ?? "nil")"
    }

    private func shouldClearOnEmptyNowPlayingInfo() -> Bool {
        guard playerNameOverride == .neteaseCloudMusic else { return true }
        if case .stopped = playbackState, currentTrack == nil {
            return false
        }
        if let lastAcceptedInfoDate = lastAcceptedInfoDate,
           Date().timeIntervalSince(lastAcceptedInfoDate) < 10 {
            return false
        }
        return false
    }

    private func nowPlayingBundleIdentifier(from userInfo: [AnyHashable: Any]?) -> String? {
        guard let userInfo = userInfo else { return nil }
        for key in [
            "kMRMediaRemoteNowPlayingApplicationBundleIdentifierUserInfoKey",
            "kMRMediaRemoteNowPlayingClientBundleIdentifierUserInfoKey",
            "kMRMediaRemoteClientBundleIdentifierUserInfoKey"
        ] {
            if let value = userInfo[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func playbackState(from userInfo: [String: Any]) -> SystemPlaybackState? {
        for key in [
            "kMRMediaRemotePlaybackStateUserInfoKey",
            "kMRMediaRemoteNowPlayingApplicationPlaybackStateUserInfoKey",
            "kMRMediaRemotePlayerPlaybackStateUserInfoKey"
        ] {
            if let value = userInfo[key] as? Int {
                return SystemPlaybackState(rawValue: value)
            }
            if let value = userInfo[key] as? NSNumber {
                return SystemPlaybackState(rawValue: value.intValue)
            }
        }
        return nil
    }

    private func describeNotificationUserInfo(_ userInfo: [AnyHashable: Any]?) -> String {
        guard let userInfo = userInfo else { return "nil" }
        return userInfo.map { key, value in
            "\(String(describing: key))=\(type(of: value))"
        }.joined(separator: ", ")
    }

    private func writeDebugLog(_ message: String) {
        let line = "\(Date()) \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: debugLogURL.path),
               let handle = try? FileHandle(forWritingTo: debugLogURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: debugLogURL)
            }
        }
        NSLog("CustomLog:SystemMedia: \(message)")
    }

}

private extension MusicPlayers.SystemMedia {
    
    enum SystemPlaybackState: Int {
        case terminated = 0
        case playing = 1
        case paused = 2
        case stopped = 3
    }
}

private struct MediaControlNowPlayingSnapshot: Decodable {
    var title: String?
    var artist: String?
    var album: String?
    var duration: TimeInterval?
    var elapsedTime: TimeInterval?
    var elapsedTimeNow: TimeInterval?
    var playing: Bool
    var bundleIdentifier: String?
    var contentItemIdentifier: String?

    static func fetch() -> MediaControlNowPlayingSnapshot? {
        let now = Date()
        cacheLock.lock()
        if let cachedSnapshot = cachedSnapshot,
           let cachedDate = cachedDate,
           now.timeIntervalSince(cachedDate) < cacheTimeToLive {
            cacheLock.unlock()
            return cachedSnapshot
        }
        if isFetching {
            cacheLock.unlock()
            return nil
        }
        isFetching = true
        cacheLock.unlock()
        defer {
            cacheLock.lock()
            isFetching = false
            cacheLock.unlock()
        }

        let executablePaths = bundledExecutablePaths + [
            "/opt/homebrew/bin/media-control",
            "/usr/local/bin/media-control"
        ]
        guard let executablePath = executablePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["get", "--now", "--no-artwork"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(1.5)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let snapshot = try? JSONDecoder().decode(MediaControlNowPlayingSnapshot.self, from: data)
        cacheLock.lock()
        cachedSnapshot = snapshot
        cachedDate = Date()
        cacheLock.unlock()
        return snapshot
    }

    private static var bundledExecutablePaths: [String] {
        let bundleCandidates = [
            Bundle.main,
            Bundle(for: BundleProbe.self)
        ]
        return bundleCandidates.compactMap {
            $0.resourceURL?.appendingPathComponent("media-control/bin/media-control").path
        }
    }

    private static let cacheTimeToLive: TimeInterval = 1
    private static let cacheLock = NSLock()
    private static var cachedSnapshot: MediaControlNowPlayingSnapshot?
    private static var cachedDate: Date?
    private static var isFetching = false
}

private final class BundleProbe {}

private extension MRNowPlayingInfo {

    var inferredPlaybackState: MusicPlayers.SystemMedia.SystemPlaybackState? {
        guard let rate = _playbackRate else { return nil }
        return rate == 0 ? .paused : .playing
    }
}

private extension Notification.Name {
    
    static let mediaRemoteNowPlayingInfoDidChange = Notification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification")
    static let mediaRemoteNowPlayingApplicationPlaybackStateDidChange = Notification.Name("kMRMediaRemoteNowPlayingApplicationPlaybackStateDidChangeNotification")
    static let mediaRemoteNowPlayingApplicationIsPlayingDidChange = Notification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification")
    static let mediaRemotePlayerNowPlayingInfoDidChange = Notification.Name("_MRMediaRemotePlayerNowPlayingInfoDidChangeNotification")
    static let mediaRemotePlayerPlaybackStateDidChange = Notification.Name("_MRMediaRemotePlayerPlaybackStateDidChangeNotification")
}

#endif
