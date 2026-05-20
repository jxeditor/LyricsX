//
//  SpotifyPrivate.swift
//  LyricsX - https://github.com/ddddxxx/LyricsX
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import LyricsCore
import CXShim

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension LyricsProviders {
    public final class SpotifyPrivate {
        public static var accessTokenProvider: (() -> String?)?
        public static var clientTokenProvider: (() -> String?)?
        public static var imageURLProvider: (() -> String?)?
        public static var statusHandler: ((String) -> Void)?

        public init() {}
    }
}

extension LyricsProviders.SpotifyPrivate: _LyricsProvider {

    public struct LyricsToken {
        let trackID: String
        let title: String?
        let artist: String?
        let duration: TimeInterval
    }

    public static let service: LyricsProviders.Service? = .spotifyPrivate

    public func lyricsSearchPublisher(request: LyricsSearchRequest) -> AnyPublisher<LyricsToken, Never> {
        guard let trackID = request.userInfo["spotifyTrackID"] ?? spotifyTrackID(from: request.userInfo["trackID"]) else {
            Self.statusHandler?("当前曲目没有 Spotify track id")
            return Empty().eraseToAnyPublisher()
        }
        let trackInfo = titleAndArtist(from: request.searchTerm)
        let token = LyricsToken(
            trackID: trackID,
            title: trackInfo.title,
            artist: trackInfo.artist,
            duration: request.duration
        )
        return Just(token).eraseToAnyPublisher()
    }

    public func lyricsFetchPublisher(token: LyricsToken) -> AnyPublisher<Lyrics, Never> {
        guard let accessToken = Self.accessTokenProvider?(), !accessToken.isEmpty else {
            Self.statusHandler?("Spotify private lyrics token 为空")
            return Empty().eraseToAnyPublisher()
        }

        var components = URLComponents(string: "https://spclient.wg.spotify.com/color-lyrics/v2/track/\(token.trackID)")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "vocalRemoval", value: "false"),
            URLQueryItem(name: "market", value: "from_token")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let clientToken = Self.clientTokenProvider?(), !clientToken.isEmpty {
            request.setValue(clientToken, forHTTPHeaderField: "client-token")
            request.setValue(clientToken, forHTTPHeaderField: "Client-Token")
        }
        request.setValue("https://open.spotify.com", forHTTPHeaderField: "Origin")
        request.setValue("https://open.spotify.com/", forHTTPHeaderField: "Referer")
        request.setValue("WebPlayer", forHTTPHeaderField: "app-platform")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN", forHTTPHeaderField: "Accept-Language")
        request.setValue("1.2.91.110.g17202b22", forHTTPHeaderField: "spotify-app-version")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        return sharedURLSession.cx.dataTaskPublisher(for: request)
            .compactMap { data, response -> SpotifyPrivateLyricsResponse? in
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(statusCode) else {
                    let body = String(data: data.prefix(360), encoding: .utf8) ?? ""
                    Self.statusHandler?("Spotify private lyrics HTTP \(statusCode)：\(body)")
                    return nil
                }
                do {
                    return try JSONDecoder().cx.decode(SpotifyPrivateLyricsResponse.self, from: data)
                } catch {
                    let body = String(data: data.prefix(360), encoding: .utf8) ?? ""
                    Self.statusHandler?("Spotify private lyrics 解码失败：\(error.localizedDescription)。响应：\(body)")
                    return nil
                }
            }
            .compactMap { response in
                let lines = response.lyrics.lines.compactMap { line -> LyricsLine? in
                    guard let time = TimeInterval(line.startTimeMs) else {
                        return nil
                    }
                    return LyricsLine(content: line.words, position: time / 1000)
                }
                guard !lines.isEmpty else {
                    Self.statusHandler?("Spotify private lyrics 返回为空")
                    return nil
                }
                let lyrics = Lyrics(lines: lines, idTags: [:])
                lyrics.idTags[.title] = token.title
                lyrics.idTags[.artist] = token.artist
                lyrics.length = token.duration
                lyrics.metadata.serviceToken = token.trackID
                Self.statusHandler?("Spotify private lyrics 获取成功：\(lines.count) 行")
                return lyrics
            }
            .catch { error -> Empty<Lyrics, Never> in
                Self.statusHandler?("Spotify private lyrics 获取失败：\(error.localizedDescription)")
                return Empty()
            }
            .eraseToAnyPublisher()
    }

    private func spotifyTrackID(from rawID: String?) -> String? {
        guard let rawID = rawID, !rawID.isEmpty else {
            return nil
        }
        if rawID.hasPrefix("spotify:track:") {
            return String(rawID.dropFirst("spotify:track:".count))
        }
        if let range = rawID.range(of: "/track/") {
            let suffix = rawID[range.upperBound...]
            return suffix.split(separator: "?").first.map(String.init)
        }
        return nil
    }

    private func titleAndArtist(from searchTerm: LyricsSearchRequest.SearchTerm) -> (title: String?, artist: String?) {
        switch searchTerm {
        case let .info(title, artist):
            return (title, artist)
        case let .keyword(keyword):
            return (keyword, nil)
        }
    }
}

private struct SpotifyPrivateLyricsResponse: Decodable {
    let lyrics: LyricsPayload

    struct LyricsPayload: Decodable {
        let lines: [Line]
    }

    struct Line: Decodable {
        let startTimeMs: String
        let words: String
    }
}
