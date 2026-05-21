//
//  NowPlaying.swift
//  LyricsX - https://github.com/ddddxxx/LyricsX
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import CXShim

extension MusicPlayers {
    
    public class NowPlaying: Agent {
        
        override public var designatedPlayer: MusicPlayerProtocol? {
            get { return super.designatedPlayer }
            set { preconditionFailure("setting currentPlayer for MusicPlayers.NowPlaying is forbidden") }
        }
        
        public var players: [MusicPlayerProtocol] {
            didSet {
                selectNewPlayer()
            }
        }

        public var preferredPlayerNameProvider: (() -> MusicPlayerName?)?
        private var lastPreferredPlayerName: MusicPlayerName?
        
        private var selectNewPlayerCanceller: AnyCancellable?
        
        public init(players: [MusicPlayerProtocol]) {
            self.players = players
            super.init()
            selectNewPlayer()
            selectNewPlayerCanceller = $designatedPlayer
                .map {
                    $0?.objectWillChange.eraseToAnyPublisher() ??
                        Publishers.MergeMany(players.map { $0.objectWillChange }).eraseToAnyPublisher()
                }
                .switchToLatest()
                .receive(on: DispatchQueue.playerUpdate.cx)
                .sink { [weak self] _ in
                    self?.selectNewPlayer()
                }
        }

        public func updateCandidatePlayerStates() {
            players.forEach { $0.updatePlayerState() }
            selectNewPlayer()
            DispatchQueue.playerUpdate.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.selectNewPlayer()
            }
        }
        
        private func selectNewPlayer() {
            var newPlayer: MusicPlayerProtocol?
            if let preferredName = preferredPlayerNameProvider?() {
                lastPreferredPlayerName = preferredName
                if let preferred = players.first(where: { $0.name == preferredName && $0.isSelectableForAuto }) {
                    newPlayer = preferred
                }
            }
            if newPlayer == nil,
               let lastPreferredPlayerName = lastPreferredPlayerName,
               let preferred = players.first(where: { $0.name == lastPreferredPlayerName && $0.isSelectableForAuto }) {
                newPlayer = preferred
            }
            if newPlayer == nil,
               let spotify = players.first(where: { $0.playbackState.isPlaying && $0.hasSpotifyTrackID }),
               designatedPlayer?.hasSpotifyTrackID != true {
                newPlayer = spotify
            } else if newPlayer == nil, designatedPlayer?.playbackState.isPlaying == true {
                newPlayer = designatedPlayer
            } else if newPlayer == nil, let playing = players.first(where: { $0.playbackState.isPlaying }) {
                newPlayer = playing
            } else if newPlayer == nil, let running = players.first(where: { $0.playbackState != .stopped }) {
                newPlayer = running
            }
            if newPlayer !== designatedPlayer {
                super.designatedPlayer = newPlayer
            } else if newPlayer != nil {
                objectWillChange.send()
            }
        }
    }
}

private extension MusicPlayerProtocol {
    var hasSpotifyTrackID: Bool {
        name == .spotify && currentTrack?.id.hasPrefix("spotify:track:") == true
    }

    var isSelectableForAuto: Bool {
        playbackState.isPlaying || playbackState != .stopped || currentTrack != nil
    }
}
