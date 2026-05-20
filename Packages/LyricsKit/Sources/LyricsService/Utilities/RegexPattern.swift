//
//  RegexPattern.swift
//  LyricsX - https://github.com/ddddxxx/LyricsX
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Regex

private let timeTagRegex = Regex(#"\[([-+]?\d+):(\d+(?:\.\d+)?)\]"#)
func resolveTimeTag(_ str: String) -> [TimeInterval] {
    let matchs = timeTagRegex.matches(in: str)
    return matchs.map { match in
        let min = Double(match[1]!.content)!
        let sec = Double(match[2]!.content)!
        return min * 60 + sec
    }
}

let id3TagRegex = Regex(#"^(?!\[[+-]?\d+:\d+(?:\.\d+)?\])\[(.+?):(.+)\]$"# as StaticString, options: .anchorsMatchLines)

let krcLineRegex = Regex(#"^\[(\d+),(\d+)\](.*)"# as StaticString, options: .anchorsMatchLines)

let netEaseInlineTagRegex = Regex(#"\(0,(\d+)\)([^(]+)(\(0,1\) )?"# as StaticString)

let kugouInlineTagRegex = Regex(#"<(\d+),(\d+),0>([^<]*)"# as StaticString)

let ttpodXtrcLineRegex = Regex(
    #"^((?:\[[+-]?\d+:\d+(?:\.\d+)?\])+)(?:((?:<\d+>[^<\r\n]+)+)|(.*))$(?:[\r\n]+\[x\-trans\](.*))?"# as StaticString,
    options: .anchorsMatchLines)

let ttpodXtrcInlineTagRegex = Regex(#"<(\d+)>([^<\r\n]*)"# as StaticString)

let syairSearchResultRegex = Regex(#"<div class="title"><a href="([^"]+)">"# as StaticString)

let syairLyricsContentRegex = Regex(#"<div class="entry">(.+?)<div"# as StaticString, options: .dotMatchesLineSeparators)
