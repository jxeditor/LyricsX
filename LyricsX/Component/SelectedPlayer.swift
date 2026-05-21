//
//  AppController.swift
//  LyricsX - https://github.com/ddddxxx/LyricsX
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import MusicPlayer
import GenericID
import CXShim

extension MusicPlayers {
    
    final class Selected: Agent {
        
        static let shared = MusicPlayers.Selected()
        
        private var defaultsObservation: DefaultsObservation?
        
        private var manualUpdateObservation: AnyCancellable?
        
        var manualUpdateInterval: TimeInterval = 1.0 {
            didSet {
                scheduleManualUpdate()
            }
        }
        
        override init() {
            super.init()
            selectPlayer()
            scheduleManualUpdate()
            defaultsObservation = defaults.observe(keys: [.preferredPlayerIndex, .useSystemWideNowPlaying]) { [weak self] in
                self?.selectPlayer()
            }
            manualUpdateObservation = playbackStateWillChange.sink { [weak self] state in
                guard let self = self else { return }
                if state.isPlaying {
                    self.scheduleManualUpdate()
                } else if self.shouldKeepPollingNowPlaying {
                    self.scheduleManualUpdate()
                } else {
                    self.scheduleCanceller?.cancel()
                }
            }
        }
        
        private func selectPlayer() {
            let idx = defaults[.preferredPlayerIndex]
            if idx == -1 {
                var players: [MusicPlayerProtocol] = MusicPlayerName.scriptableCases
                    .filter { $0 != .neteaseCloudMusic }
                    .compactMap(MusicPlayers.Scriptable.init)
                if let neteasePlayer = MusicPlayers.SystemMedia(name: .neteaseCloudMusic) {
                    players.append(neteasePlayer)
                }
                if defaults[.useSystemWideNowPlaying],
                   let systemPlayer = MusicPlayers.SystemMedia() {
                    players.append(systemPlayer)
                }
                let nowPlaying = MusicPlayers.NowPlaying(players: players)
                nowPlaying.preferredPlayerNameProvider = Self.currentSystemPlayingPlayerName
                designatedPlayer = nowPlaying
            } else {
                let name = MusicPlayerName(index: idx)
                if name == .neteaseCloudMusic {
                    designatedPlayer = MusicPlayers.SystemMedia(name: .neteaseCloudMusic)
                } else {
                    designatedPlayer = name.flatMap(MusicPlayers.Scriptable.init)
                }
            }
            designatedPlayer?.updatePlayerState()
            scheduleManualUpdate()
        }

        private var shouldKeepPollingNowPlaying: Bool {
            let idx = defaults[.preferredPlayerIndex]
            return idx == 5 || idx == -1
        }
        
        private var scheduleCanceller: Cancellable?
        func scheduleManualUpdate() {
            scheduleCanceller?.cancel()
            guard manualUpdateInterval > 0 else { return }
            let q = DispatchQueue.global().cx
            let i: CXWrappers.DispatchQueue.SchedulerTimeType.Stride = .seconds(manualUpdateInterval)
            scheduleCanceller = q.schedule(after: q.now.advanced(by: i), interval: i, tolerance: i * 0.1, options: nil) { [unowned self] in
                if let nowPlaying = self.designatedPlayer as? MusicPlayers.NowPlaying {
                    nowPlaying.updateCandidatePlayerStates()
                } else {
                    self.designatedPlayer?.updatePlayerState()
                }
            }
        }

        private static func currentSystemPlayingPlayerName() -> MusicPlayerName? {
            guard let snapshot = MediaControlAutoSnapshot.fetch() else {
                return nil
            }
            switch snapshot.bundleIdentifier {
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
    }
}

private struct MediaControlAutoSnapshot: Decodable {
    var bundleIdentifier: String?

    static func fetch() -> MediaControlAutoSnapshot? {
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

        let deadline = Date().addingTimeInterval(1.0)
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
        return try? JSONDecoder().decode(MediaControlAutoSnapshot.self, from: data)
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
}

private final class BundleProbe {}
