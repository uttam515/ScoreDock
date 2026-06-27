import Foundation

// MARK: - ESPN Scoreboard Response Structs

private struct ESPNScoreboardHeader: Decodable {
    struct Sport: Decodable {
        struct League: Decodable {
            struct Event: Decodable {
                struct Status: Decodable {
                    struct StatusType: Decodable {
                        let state: String? // "pre", "in", "post"
                        let detail: String? // e.g. "Live" or "Final"
                    }
                    let type: StatusType?
                    let period: Int?
                    let session: String?
                }
                struct Competitor: Decodable {
                    let id: String?
                    let abbreviation: String?
                    let displayName: String?
                    let shortDisplayName: String?
                    let score: String?
                    let homeAway: String? // "home" or "away"
                    let color: String?
                    let alternateColor: String?
                    let logo: String?
                }
                let id: String?
                let name: String?
                let date: String?   // ISO-8601 scheduled start time, e.g. "2026-06-26T17:30:00Z"
                let status: String?
                let fullStatus: Status?
                let competitors: [Competitor]?
                let description: String?
            }
            let name: String?
            let events: [Event]?
        }
        let name: String?
        let leagues: [League]?
    }
    let sports: [Sport]?
}

// MARK: - ESPN Mapper Namespace

public struct ESPNMapper {
    public static func map(response: Data, sportType: String) -> [MatchState] {
        var states: [MatchState] = []
        
        do {
            let decoded = try JSONDecoder().decode(ESPNScoreboardHeader.self, from: response)
            guard let sports = decoded.sports else { return [] }
            
            for sport in sports {
                guard let leagues = sport.leagues else { continue }
                for league in leagues {
                    let leagueName = league.name ?? "International"
                    guard let events = league.events else { continue }
                    
                    for event in events {
                        guard let competitors = event.competitors, competitors.count >= 2 else { continue }
                        
                        // Defensive extraction of competitors
                        let compA = competitors[0]
                        let compB = competitors[1]
                        
                        let nameA = normalizeAbbreviation(compA.abbreviation) ?? abbreviate(compA.displayName)
                        let nameB = normalizeAbbreviation(compB.abbreviation) ?? abbreviate(compB.displayName)
                        
                        let scoreAVal = compA.score ?? "0"
                        let scoreBVal = compB.score ?? "0"
                        
                        let stateStr = event.fullStatus?.type?.state ?? event.status ?? "pre"
                        let detailStr = event.fullStatus?.type?.detail ?? "Scheduled"
                        
                        var isLive = stateStr == "in"
                        var gameTime = detailStr
                        
                        // Treat "Stumps" as Live
                        if stateStr == "post" && detailStr.lowercased().contains("stumps") {
                            isLive = true
                            gameTime = "Stumps"
                        } else if stateStr == "post" {
                            continue // Skip completed
                        }
                        
                        // Parse scheduled time for upcoming matches
                        let scheduledTime: Date? = event.date.flatMap { dateStr in
                            let fmt = ISO8601DateFormatter()
                            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                            return fmt.date(from: dateStr) ?? ISO8601DateFormatter().date(from: dateStr)
                        }
                        
                        // --- FILTER: skip upcoming matches that are more than X hours away ---
                        if stateStr == "pre" {
                            if let scheduled = scheduledTime {
                                let hoursAway = scheduled.timeIntervalSinceNow / 3600
                                let limit = MatchCoordinator.shared.upcomingMatchWindow
                                if hoursAway > limit || hoursAway < -1 { continue } // more than limit ahead, or already missed
                            } else {
                                continue // no date info — skip
                            }
                        }
                        
                        // --- FILTER: skip "in"-state matches where ESPN has no score data yet ---
                        // This happens when a match has started (toss done) but play hasn't begun.
                        // Both scores will be empty strings "" rather than "0" in this case.
                        if isLive {
                            let rawA = compA.score ?? ""
                            let rawB = compB.score ?? ""
                            if rawA.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                               rawB.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                continue // No actual play data yet — skip
                            }
                        }
                        
                        // Parse sport-specific metadata
                        var metadata: SportMetadata? = nil
                        if sportType == "cricket" {
                            var overs: String? = nil
                            var wickets: String? = nil
                            var runs: String? = nil
                            
                            // Check both scores for active batting details
                            for scoreVal in [scoreAVal, scoreBVal] {
                                let cleanScore = scoreVal.trimmingCharacters(in: .whitespacesAndNewlines)
                                if cleanScore.contains("(") {
                                    let parts = cleanScore.components(separatedBy: " ")
                                    if let scorePart = parts.first {
                                        let runsWkts = scorePart.components(separatedBy: "/")
                                        if runsWkts.count == 2 {
                                            runs = runsWkts[0]
                                            wickets = runsWkts[1]
                                        }
                                    }
                                    if let startIdx = cleanScore.firstIndex(of: "("), let endIdx = cleanScore.firstIndex(of: ")") {
                                        let range = cleanScore.index(after: startIdx)..<endIdx
                                        let oversPart = String(cleanScore[range]).replacingOccurrences(of: " ov", with: "")
                                        overs = oversPart
                                    }
                                }
                            }
                            
                            // Fallback for runs/wickets if no active batting parenthesis is present
                            if runs == nil {
                                for scoreVal in [scoreAVal, scoreBVal] {
                                    let cleanScore = scoreVal.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if cleanScore.contains("/") {
                                        let parts = cleanScore.components(separatedBy: " ")
                                        if let scorePart = parts.first {
                                            let runsWkts = scorePart.components(separatedBy: "/")
                                            if runsWkts.count == 2 {
                                                runs = runsWkts[0]
                                                wickets = runsWkts[1]
                                            }
                                        }
                                    }
                                }
                            }
                            
                            metadata = SportMetadata(overs: overs, wickets: wickets, runs: runs)
                        } else if sportType == "football" {
                            let period = event.fullStatus?.period
                            metadata = SportMetadata(period: period, matchPhase: stateStr.uppercased())
                        }
                        
                        // Clean up cricket score strings (remove trailing overs/targets from the team's score block)
                        var finalScoreA = scoreAVal
                        var finalScoreB = scoreBVal
                        if sportType == "cricket" {
                            if let spaceIdx = scoreAVal.firstIndex(of: " ") {
                                finalScoreA = String(scoreAVal[..<spaceIdx])
                            }
                            if let spaceIdx = scoreBVal.firstIndex(of: " ") {
                                finalScoreB = String(scoreBVal[..<spaceIdx])
                            }
                        }
                        
                        // Map flags using display names
                        let displayNameA = compA.displayName ?? nameA
                        let displayNameB = compB.displayName ?? nameB
                        let flagA = flagEmoji(forCountry: displayNameA, sport: sportType)
                        let flagB = flagEmoji(forCountry: displayNameB, sport: sportType)
                        
                        let match = MatchState(
                            sport: sportType,
                            espnID: event.id,
                            teamA: nameA.uppercased(),
                            teamAId: compA.id,
                            teamAShortName: compA.shortDisplayName,
                            teamAFlag: flagA,
                            scoreA: isLive ? finalScoreA : "–",
                            teamB: nameB.uppercased(),
                            teamBId: compB.id,
                            teamBShortName: compB.shortDisplayName,
                            teamBFlag: flagB,
                            scoreB: isLive ? finalScoreB : "–",
                            gameTime: gameTime,
                            isLive: isLive,
                            tournament: leagueName,
                            metadata: metadata,
                            scheduledTime: isLive ? nil : scheduledTime,
                            teamAColor: compA.color,
                            teamBColor: compB.color,
                            teamALogo: compA.logo,
                            teamBLogo: compB.logo
                        )
                        states.append(match)
                    }
                }
            }
        } catch {
            debugLog("[-] ESPNMapper failed to decode ESPN JSON for \(sportType): \(error)")
        }
        
        return states
    }
    
    public static func normalizeAbbreviation(_ raw: String?) -> String? {
        guard let raw = raw else { return nil }
        let folded = raw.applyingTransform(.stripDiacritics, reverse: false) ?? raw
        let cleaned = folded.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0.isWhitespace) }
        let squeezed = cleaned.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        let result = String(squeezed.uppercased().prefix(5))
        return result.isEmpty ? nil : result
    }

    public static func abbreviate(_ name: String?) -> String {
        guard let name = name else { return "TBD" }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count <= 3 { return clean.uppercased() }
        let components = clean.components(separatedBy: " ")
        if components.count >= 2 {
            let first = components[0].prefix(1)
            let second = components[1].prefix(1)
            return "\(first)\(second)".uppercased()
        }
        return String(clean.prefix(3)).uppercased()
    }
    
    public static func flagEmoji(forCountry country: String, sport: String) -> String {
        let clean = country.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        let mapping: [String: String] = [
            "india": "🇮🇳", "ind": "🇮🇳", "ind-a": "🇮🇳", "india a": "🇮🇳",
            "australia": "🇦🇺", "aus": "🇦🇺",
            "england": "🏴󠁧󠁢󠁥󠁮󠁧󠁿", "eng": "🏴󠁧󠁢󠁥󠁮󠁧󠁿",
            "pakistan": "🇵🇰", "pak": "🇵🇰",
            "south africa": "🇿🇦", "rsa": "🇿🇦", "zaf": "🇿🇦",
            "new zealand": "🇳🇿", "nz": "🇳🇿", "nzl": "🇳🇿",
            "sri lanka": "🇱🇰", "sl": "🇱🇰", "lka": "🇱🇰", "sl-a": "🇱🇰", "sri lanka a": "🇱🇰",
            "bangladesh": "🇧🇩", "ban": "🇧🇩", "bgd": "🇧🇩",
            "west indies": "🌴", "wi": "🌴", "wias": "🌴", "wia": "🌴",
            "zimbabwe": "🇿🇼", "zim": "🇿🇼", "zwe": "🇿🇼",
            "afghanistan": "🇦🇫", "afg": "🇦🇫",
            "ireland": "🇮🇪", "ire": "🇮🇪", "irl": "🇮🇪",
            "scotland": "🏴󠁧󠁢󠁳󠁣󠁴󠁿", "sco": "🏴󠁧󠁢󠁳󠁣󠁴󠁿",
            "nepal": "🇳🇵", "nep": "🇳🇵",
            "oman": "🇴🇲", "oma": "🇴🇲",
            "namibia": "🇳🇦", "nam": "🇳🇦",
            "uganda": "🇺🇬", "uga": "🇺🇬",
            "kenya": "🇰🇪", "ken": "🇰🇪",
            "spain": "🇪🇸", "esp": "🇪🇸",
            "france": "🇫🇷", "fra": "🇫🇷",
            "germany": "🇩🇪", "ger": "🇩🇪", "deu": "🇩🇪",
            "italy": "🇮🇹", "ita": "🇮🇹",
            "portugal": "🇵🇹", "por": "🇵🇹",
            "netherlands": "🇳🇱", "ned": "🇳🇱", "nld": "🇳🇱", "holland": "🇳🇱",
            "belgium": "🇧🇪", "bel": "🇧🇪",
            "croatia": "🇭🇷", "cro": "🇭🇷", "hrv": "🇭🇷",
            "denmark": "🇩🇰", "den": "🇩🇰", "dnk": "🇩🇰",
            "sweden": "🇸🇪", "swe": "🇸🇪",
            "norway": "🇳🇴", "nor": "🇳🇴",
            "switzerland": "🇨🇭", "sui": "🇨🇭", "che": "🇨🇭",
            "austria": "🇦🇹", "aut": "🇦🇹",
            "poland": "🇵🇱", "pol": "🇵🇱",
            "ukraine": "🇺🇦", "ukr": "🇺🇦",
            "russia": "🇷🇺", "rus": "🇷🇺",
            "turkey": "🇹🇷", "tur": "🇹🇷", "türkiye": "🇹🇷",
            "greece": "🇬🇷", "gre": "🇬🇷",
            "hungary": "🇭🇺", "hun": "🇭🇺",
            "romania": "🇷🇴", "rou": "🇷🇴", "rom": "🇷🇴",
            "slovakia": "🇸🇰", "svk": "🇸🇰",
            "slovenia": "🇸🇮", "svn": "🇸🇮",
            "czech republic": "🇨🇿", "czechia": "🇨🇿", "cze": "🇨🇿",
            "finland": "🇫🇮", "fin": "🇫🇮",
            "iceland": "🇮🇸", "isl": "🇮🇸",
            "wales": "🏴󠁧󠁢󠁷󠁬󠁳󠁿", "wal": "🏴󠁧󠁢󠁷󠁬󠁳󠁿",
            "northern ireland": "🇬🇧", "nir": "🇬🇧",
            "albania": "🇦🇱", "alb": "🇦🇱",
            "bosnia": "🇧🇦", "bih": "🇧🇦", "bos": "🇧🇦",
            "kosovo": "🇽🇰", "kos": "🇽🇰",
            "north macedonia": "🇲🇰", "mkd": "🇲🇰",
            "georgia": "🇬🇪", "geo": "🇬🇪",
            "armenia": "🇦🇲", "arm": "🇦🇲",
            "azerbaijan": "🇦🇿", "aze": "🇦🇿",
            "israel": "🇮🇱", "isr": "🇮🇱",
            "moldova": "🇲🇩", "mda": "🇲🇩",
            "belarus": "🇧🇾", "blr": "🇧🇾",
            "lithuania": "🇱🇹", "ltu": "🇱🇹",
            "latvia": "🇱🇻", "lva": "🇱🇻",
            "estonia": "🇪🇪", "est": "🇪🇪",
            "cyprus": "🇨🇾", "cyp": "🇨🇾",
            "malta": "🇲🇹", "mlt": "🇲🇹",
            "andorra": "🇦🇩", "and": "🇦🇩",
            "montenegro": "🇲🇪", "mne": "🇲🇪",
            "luxembourg": "🇱🇺", "lux": "🇱🇺",
            "serbia": "🇷🇸", "srb": "🇷🇸",
            "bulgaria": "🇧🇬", "bul": "🇧🇬",
            "brazil": "🇧🇷", "bra": "🇧🇷",
            "argentina": "🇦🇷", "arg": "🇦🇷",
            "colombia": "🇨🇴", "col": "🇨🇴",
            "chile": "🇨🇱", "chi": "🇨🇱",
            "mexico": "🇲🇽", "mex": "🇲🇽",
            "uruguay": "🇺🇾", "uru": "🇺🇾",
            "ecuador": "🇪🇨", "ecu": "🇪🇨",
            "paraguay": "🇵🇾", "par": "🇵🇾",
            "peru": "🇵🇪", "per": "🇵🇪",
            "bolivia": "🇧🇴", "bol": "🇧🇴",
            "venezuela": "🇻🇪", "ven": "🇻🇪",
            "costa rica": "🇨🇷", "crc": "🇨🇷",
            "jamaica": "🇯🇲", "jam": "🇯🇲",
            "trinidad and tobago": "🇹🇹", "tri": "🇹🇹",
            "haiti": "🇭🇹", "hai": "🇭🇹",
            "honduras": "🇭🇳", "hon": "🇭🇳",
            "el salvador": "🇸🇻", "slv": "🇸🇻",
            "guatemala": "🇬🇹", "gua": "🇬🇹",
            "panama": "🇵🇦", "pan": "🇵🇦",
            "canada": "🇨🇦", "can": "🇨🇦",
            "usa": "🇺🇸", "united states": "🇺🇸", "us": "🇺🇸",
            "cuba": "🇨🇺", "cub": "🇨🇺",
            "nigeria": "🇳🇬", "nga": "🇳🇬",
            "ghana": "🇬🇭", "gha": "🇬🇭",
            "cameroon": "🇨🇲", "cmr": "🇨🇲",
            "senegal": "🇸🇳", "sen": "🇸🇳",
            "morocco": "🇲🇦", "mar": "🇲🇦",
            "egypt": "🇪🇬", "egy": "🇪🇬",
            "algeria": "🇩🇿", "alg": "🇩🇿",
            "tunisia": "🇹🇳", "tun": "🇹🇳",
            "ivory coast": "🇨🇮", "côte d'ivoire": "🇨🇮", "civ": "🇨🇮",
            "mali": "🇲🇱", "mli": "🇲🇱",
            "burkina faso": "🇧🇫", "bfa": "🇧🇫",
            "guinea": "🇬🇳", "gui": "🇬🇳",
            "ethiopia": "🇪🇹", "eth": "🇪🇹",
            "tanzania": "🇹🇿", "tan": "🇹🇿",
            "angola": "🇦🇴", "ang": "🇦🇴",
            "zambia": "🇿🇲", "zam": "🇿🇲",
            "cape verde": "🇨🇻", "cpv": "🇨🇻",
            "gabon": "🇬🇦", "gab": "🇬🇦",
            "dr congo": "🇨🇩", "cod": "🇨🇩",
            "japan": "🇯🇵", "jpn": "🇯🇵",
            "south korea": "🇰🇷", "kor": "🇰🇷", "korea republic": "🇰🇷",
            "north korea": "🇰🇵", "prk": "🇰🇵",
            "china": "🇨🇳", "chn": "🇨🇳", "china pr": "🇨🇳",
            "iran": "🇮🇷", "irn": "🇮🇷",
            "saudi arabia": "🇸🇦", "ksa": "🇸🇦",
            "qatar": "🇶🇦", "qat": "🇶🇦",
            "iraq": "🇮🇶", "irq": "🇮🇶",
            "jordan": "🇯🇴", "jor": "🇯🇴",
            "bahrain": "🇧🇭", "bhr": "🇧🇭",
            "kuwait": "🇰🇼", "kuw": "🇰🇼",
            "uae": "🇦🇪", "united arab emirates": "🇦🇪",
            "philippines": "🇵🇭", "phi": "🇵🇭",
            "vietnam": "🇻🇳", "vie": "🇻🇳",
            "thailand": "🇹🇭", "tha": "🇹🇭",
            "singapore": "🇸🇬", "sgp": "🇸🇬",
            "indonesia": "🇮🇩", "ina": "🇮🇩",
            "malaysia": "🇲🇾", "mas": "🇲🇾",
            "uzbekistan": "🇺🇿", "uzb": "🇺🇿",
            "kazakhstan": "🇰🇿", "kaz": "🇰🇿",
            "hong kong": "🇭🇰", "hkg": "🇭🇰",
            "taiwan": "🇹🇼", "tpe": "🇹🇼",
            "fiji": "🇫🇯", "fij": "🇫🇯",
            "papua new guinea": "🇵🇬", "png": "🇵🇬",
            "cuiaba": "🔰", "cui": "🔰"
        ]
        
        if let direct = mapping[clean] { return direct }
        for (key, val) in mapping {
            if clean.hasPrefix(key + " ") || clean.hasSuffix(" " + key) { return val }
        }
        for (key, val) in mapping where key.count >= 3 {
            if clean.contains(key) || key.contains(clean) { return val }
        }
        return sport == "cricket" ? "🏏" : "⚽"
    }
}

// MARK: - ESPN Sports Provider

private struct ESPNSiteScoreboard: Decodable {
    struct Event: Decodable {
        struct Competition: Decodable {
            struct StatusInfo: Decodable {
                struct StatusType: Decodable {
                    let state: String?      // "pre", "in", "post"
                    let detail: String?     // e.g. "Fri, June 27th at 3:00 PM EDT"
                    let shortDetail: String?
                }
                let type: StatusType?
            }
            struct Competitor: Decodable {
                struct Team: Decodable {
                    let id: String?
                    let abbreviation: String?
                    let displayName: String?
                    let shortDisplayName: String?
                    let color: String?
                    let alternateColor: String?
                    let logo: String?
                }
                let team: Team?
                let score: String?
                let homeAway: String?
            }
            let date: String?
            let status: StatusInfo?
            let competitors: [Competitor]?
            let notes: [Note]?
            struct Note: Decodable { let headline: String? }
        }
        let id: String?
        let date: String?
        let name: String?
        let competitions: [Competition]?
    }
    let events: [Event]?
}

public struct ESPNSiteMapper {
    public static func map(response: Data, sportType: String, tournamentName: String) -> [MatchState] {
        var states: [MatchState] = []
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFmt2 = DateFormatter()
        isoFmt2.dateFormat = "yyyy-MM-dd'T'HH:mmZ"
        isoFmt2.locale = Locale(identifier: "en_US_POSIX")
        
        do {
            let decoded = try JSONDecoder().decode(ESPNSiteScoreboard.self, from: response)
            guard let events = decoded.events else { return [] }
            
            for event in events {
                guard let comp = event.competitions?.first,
                      let competitors = comp.competitors, competitors.count >= 2 else { continue }
                
                let stateStr = comp.status?.type?.state ?? "pre"
                let detailStr = comp.status?.type?.shortDetail ?? comp.status?.type?.detail ?? "Scheduled"
                
                var isLive = stateStr == "in"
                var gameTime = detailStr
                
                if stateStr == "post" && detailStr.lowercased().contains("stumps") {
                    isLive = true
                    gameTime = "Stumps"
                } else if stateStr == "post" {
                    continue
                }
                
                // Parse scheduled time
                let dateStr = comp.date ?? event.date ?? ""
                let scheduledTime = isoFmt.date(from: dateStr) ?? isoFmt2.date(from: dateStr)
                
                // For upcoming, check window
                if stateStr == "pre" {
                    if let scheduled = scheduledTime {
                        let hoursAway = scheduled.timeIntervalSinceNow / 3600
                        let limit = MatchCoordinator.shared.upcomingMatchWindow
                        if hoursAway > limit || hoursAway < -1 { continue }
                    } else {
                        continue
                    }
                }
                
                // Skip live with no score data
                if isLive {
                    let rawA = competitors[0].score ?? ""
                    let rawB = competitors[1].score ?? ""
                    if rawA.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                       rawB.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                }
                
                let sortedComps = competitors.sorted { ($0.homeAway ?? "") == "home" && ($1.homeAway ?? "") != "home" }
                let compA = sortedComps[0]
                let compB = sortedComps[1]
                
                let nameA = ESPNMapper.normalizeAbbreviation(compA.team?.abbreviation) ?? ESPNMapper.abbreviate(compA.team?.displayName)
                let nameB = ESPNMapper.normalizeAbbreviation(compB.team?.abbreviation) ?? ESPNMapper.abbreviate(compB.team?.displayName)
                
                let scoreAVal = isLive ? (compA.score ?? "0") : "–"
                let scoreBVal = isLive ? (compB.score ?? "0") : "–"
                
                let flagA = ESPNMapper.flagEmoji(forCountry: compA.team?.displayName ?? nameA, sport: sportType)
                let flagB = ESPNMapper.flagEmoji(forCountry: compB.team?.displayName ?? nameB, sport: sportType)
                
                let match = MatchState(
                    sport: sportType,
                    espnID: event.id,
                    teamA: nameA.uppercased(),
                    teamAId: compA.team?.id,
                    teamAShortName: compA.team?.shortDisplayName,
                    teamAFlag: flagA,
                    scoreA: scoreAVal,
                    teamB: nameB.uppercased(),
                    teamBId: compB.team?.id,
                    teamBShortName: compB.team?.shortDisplayName,
                    teamBFlag: flagB,
                    scoreB: scoreBVal,
                    gameTime: gameTime,
                    isLive: isLive,
                    tournament: tournamentName,
                    metadata: nil,
                    scheduledTime: isLive ? nil : scheduledTime,
                    teamAColor: compA.team?.color,
                    teamBColor: compB.team?.color,
                    teamALogo: compA.team?.logo,
                    teamBLogo: compB.team?.logo
                )
                states.append(match)
            }
        } catch {
            debugLog("[-] ESPNSiteMapper failed to decode for \(tournamentName): \(error)")
        }
        return states
    }
}

public final class ESPNSportsProvider: SportsProvider {
    
    public init() {}
    
    public func fetchMatches() async throws -> [MatchState] {
        return try await withThrowingTaskGroup(of: [MatchState].self) { group -> [MatchState] in
            // 1. Football – personalized header (live + recent)
            group.addTask {
                let url = URL(string: "https://site.api.espn.com/apis/personalized/v2/scoreboard/header?sport=soccer&region=in&tz=Asia/Calcutta")!
                let (data, _) = try await URLSession.shared.data(from: url)
                return ESPNMapper.map(response: data, sportType: "football")
            }
            
            // 2. Cricket – personalized header
            group.addTask {
                let url = URL(string: "https://site.api.espn.com/apis/personalized/v2/scoreboard/header?sport=cricket&region=in&tz=Asia/Calcutta")!
                let (data, _) = try await URLSession.shared.data(from: url)
                return ESPNMapper.map(response: data, sportType: "cricket")
            }
            
            // 3. FIFA World Cup – dedicated site API fetch
            // The personalized header only loads today's played matches;
            // the site scoreboard proactively returns upcoming group/knockout fixtures.
            group.addTask {
                let limitHours = MatchCoordinator.shared.upcomingMatchWindow
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd"
                let today = Date()
                let future = today.addingTimeInterval(limitHours * 3600)
                let dateParam = "\(formatter.string(from: today))-\(formatter.string(from: future))"
                
                let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/scoreboard?dates=\(dateParam)")!
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    return ESPNSiteMapper.map(response: data, sportType: "football", tournamentName: "FIFA World Cup")
                } catch {
                    debugLog("[-] FIFA WC site fetch failed: \(error)")
                    return []
                }
            }
            
            var combined: [MatchState] = []
            var seenIDs = Set<String>()
            for try await matches in group {
                for match in matches {
                    if seenIDs.insert(match.id).inserted {
                        combined.append(match)
                    }
                }
            }
            return combined
        }
    }
}

