import Foundation
import Combine
import UserNotifications

// MARK: - Sport Metadata Definition

public struct SportMetadata: Codable, Equatable {
    // Cricket specific
    public var overs: String?
    public var wickets: String?
    public var runs: String?
    public var target: String?
    public var inningNumber: Int?
    public var previousInningScoreA: String?
    public var previousInningScoreB: String?
    
    // Football specific
    public var addedTime: String?
    public var period: Int?
    public var matchPhase: String? // "1H", "2H", "HT", "FT"
    
    public var extraInfo: String?
    
    public init(
        overs: String? = nil,
        wickets: String? = nil,
        runs: String? = nil,
        target: String? = nil,
        inningNumber: Int? = nil,
        addedTime: String? = nil,
        period: Int? = nil,
        matchPhase: String? = nil,
        extraInfo: String? = nil
    ) {
        self.overs = overs
        self.wickets = wickets
        self.runs = runs
        self.target = target
        self.inningNumber = inningNumber
        self.addedTime = addedTime
        self.period = period
        self.matchPhase = matchPhase
        self.extraInfo = extraInfo
    }
}

// MARK: - Provider Status Definition

public enum ProviderStatus: String, Codable {
    case healthy = "Healthy"
    case degraded = "Degraded (Using Cached Data)"
    case failed = "Failed"
}

// MARK: - Match State Definition

public struct MatchState: Codable, Identifiable, Equatable {
    public var sport: String // "football", "cricket", "basketball", etc.
    public var espnID: String?
    public var teamA: String
    public var teamAId: String?
    public var teamAShortName: String?
    public var teamAFlag: String
    public var scoreA: String
    public var teamB: String
    public var teamBId: String?
    public var teamBShortName: String?
    public var teamBFlag: String
    public var scoreB: String
    public var gameTime: String
    public var isLive: Bool
    public var tournament: String
    public var metadata: SportMetadata?
    public var scheduledTime: Date?  // Non-nil for upcoming (pre) matches
    
    // UI details for club teams / dynamic themes
    public var teamAColor: String?
    public var teamBColor: String?
    public var teamALogo: String?
    public var teamBLogo: String?
    
    // True when the match hasn't kicked off yet and we have a known start time
    public var isUpcoming: Bool {
        !isLive && (scheduledTime.map { $0 > Date() } ?? false)
    }
    
    public var id: String {
        if let eid = espnID { return eid }
        return "\(sport.lowercased())_\(teamA.lowercased())_\(teamB.lowercased())"
    }
    
    public init(
        sport: String,
        espnID: String? = nil,
        teamA: String,
        teamAId: String? = nil,
        teamAShortName: String? = nil,
        teamAFlag: String,
        scoreA: String,
        teamB: String,
        teamBId: String? = nil,
        teamBShortName: String? = nil,
        teamBFlag: String,
        scoreB: String,
        gameTime: String,
        isLive: Bool,
        tournament: String,
        metadata: SportMetadata? = nil,
        scheduledTime: Date? = nil,
        teamAColor: String? = nil,
        teamBColor: String? = nil,
        teamALogo: String? = nil,
        teamBLogo: String? = nil
    ) {
        self.sport = sport
        self.espnID = espnID
        self.teamA = teamA
        self.teamAId = teamAId
        self.teamAShortName = teamAShortName
        self.teamAFlag = teamAFlag
        self.scoreA = scoreA
        self.teamB = teamB
        self.teamBId = teamBId
        self.teamBShortName = teamBShortName
        self.teamBFlag = teamBFlag
        self.scoreB = scoreB
        self.gameTime = gameTime
        self.isLive = isLive
        self.tournament = tournament
        self.metadata = metadata
        self.scheduledTime = scheduledTime
        self.teamAColor = teamAColor
        self.teamBColor = teamBColor
        self.teamALogo = teamALogo
        self.teamBLogo = teamBLogo
    }
}

// MARK: - Rotation Mode Definition

public enum RotationMode: String, Codable, CaseIterable {
    case automatic      = "Automatic"
    case favoritesOnly  = "Favorites Only"
    case pinnedOnly     = "Pinned Only"
    case livePriority   = "Live Priority"
}

// MARK: - Match Coordinator
public final class MatchCoordinator: ObservableObject {
    public static let shared = MatchCoordinator()
    
    @Published public private(set) var matches: [MatchState] = []
    @Published public private(set) var activeMatch: MatchState?
    @Published public private(set) var providerStatus: ProviderStatus = .healthy
    
    // User settings stored in UserDefaults
    private let favoritesKey = "com.scoredock.favorites"
    private let tournamentsKey = "com.scoredock.tournaments"
    private let rotationModeKey = "com.scoredock.rotationMode"
    private let apiSourceKey = "com.scoredock.apiSource" // "mock" or "real"
    private let pinnedMatchIDKey = "com.scoredock.pinnedMatchID"
    
    private var activeProvider: SportsProvider
    private var timer: AnyCancellable?
    private var currentInterval: TimeInterval = 300.0
    private var cycleIndex = 0
    
    private init() {
        // Initialize the provider based on current setting
        let apiSetting = UserDefaults.standard.string(forKey: apiSourceKey)
        if apiSetting == "mock" {
            self.activeProvider = MockSportsProvider()
        } else {
            self.activeProvider = ESPNSportsProvider()
        }
        
        // Load initial state from cache
        if let cached = loadFromCache(), !cached.isEmpty {
            self.matches = cached
            debugLog("[+] Loaded \(cached.count) matches from local JSON cache.")
        }
        
        // Select initial active match
        updateActiveMatch()
        
        // Start polling loop
        startPolling()
        
        // Fetch initially
        fetchScores()
    }
    
    // MARK: - Getters & Setters for Settings
    
    public var favoriteTeams: [String] {
        get { UserDefaults.standard.stringArray(forKey: favoritesKey) ?? ["LIV", "IND", "AUS"] }
        set {
            UserDefaults.standard.set(newValue, forKey: favoritesKey)
            updateActiveMatch()
        }
    }
    
    public var favoriteTournaments: [String] {
        get { UserDefaults.standard.stringArray(forKey: tournamentsKey) ?? ["Premier League", "IPL"] }
        set {
            UserDefaults.standard.set(newValue, forKey: tournamentsKey)
            updateActiveMatch()
        }
    }
    
    public var rotationMode: RotationMode {
        get {
            if let raw = UserDefaults.standard.string(forKey: rotationModeKey),
               let mode = RotationMode(rawValue: raw) {
                return mode
            }
            return .automatic
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: rotationModeKey)
            updateActiveMatch()
        }
    }
    
    public var useRealAPIs: Bool {
        get { UserDefaults.standard.string(forKey: apiSourceKey) != "mock" }
        set {
            UserDefaults.standard.set(newValue ? "real" : "mock", forKey: apiSourceKey)
            updateProvider()
            fetchScores() // Re-fetch immediately on source change
        }
    }
    
    public var pinnedMatchID: String? {
        get { UserDefaults.standard.string(forKey: pinnedMatchIDKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: pinnedMatchIDKey)
            updateActiveMatch()
        }
    }
    
    public var upcomingMatchWindow: Double {
        get { UserDefaults.standard.double(forKey: "upcomingWindowHoursKey") == 0 ? 24.0 : UserDefaults.standard.double(forKey: "upcomingWindowHoursKey") }
        set {
            UserDefaults.standard.set(newValue, forKey: "upcomingWindowHoursKey")
            fetchScores() // re-fetch to apply new filter
        }
    }
    
    private func updateProvider() {
        if useRealAPIs {
            self.activeProvider = ESPNSportsProvider()
        } else {
            self.activeProvider = MockSportsProvider()
        }
    }
    
    // MARK: - Core Public API
    
    private var isFetching = false
    
    public func fetchScores() {
        guard !isFetching else { return }
        isFetching = true
        
        Task {
            do {
                let fetched = try await activeProvider.fetchMatches()
                await MainActor.run {
                    self.isFetching = false
                    if !fetched.isEmpty {
                        self.processPushNotifications(oldMatches: self.matches, newMatches: fetched)
                        self.matches = fetched
                        self.providerStatus = .healthy
                        self.saveToCache(fetched)
                        self.updateActiveMatch()
                    }
                    self.adjustPollingInterval(for: self.matches)
                }
            } catch {
                debugLog("[-] Active provider failed to fetch matches: \(error)")
                await MainActor.run {
                    self.isFetching = false
                    // Graceful degradation: Load from cache
                    if let cached = self.loadFromCache(), !cached.isEmpty {
                        self.matches = cached
                        self.providerStatus = .degraded
                        self.updateActiveMatch()
                    } else {
                        // If cache is empty/invalid, fall back to mock data
                        Task {
                            let mock = MockSportsProvider()
                            if let mockData = try? await mock.fetchMatches() {
                                await MainActor.run {
                                    self.matches = mockData
                                    self.providerStatus = .failed
                                    self.updateActiveMatch()
                                }
                            }
                        }
                    }
                    self.adjustPollingInterval(for: self.matches)
                }
            }
        }
    }
    
    public func cycleNextMatch() {
        let list = getFilteredMatches()
        if list.isEmpty { return }
        
        cycleIndex += 1
        if cycleIndex >= list.count {
            cycleIndex = 0
        }
        activeMatch = list[cycleIndex]
    }
    
    public func cyclePrevMatch() {
        let list = getFilteredMatches()
        if list.isEmpty { return }
        
        cycleIndex -= 1
        if cycleIndex < 0 {
            cycleIndex = list.count - 1
        }
        activeMatch = list[cycleIndex]
    }
    
    private func processPushNotifications(oldMatches: [MatchState], newMatches: [MatchState]) {
        for newMatch in newMatches {
            // Only notify for favorite matches
            guard isFavorite(newMatch), newMatch.isLive else { continue }
            
            if let oldMatch = oldMatches.first(where: { $0.id == newMatch.id }) {
                // Football: Goal Scored
                if newMatch.sport.lowercased() == "football" {
                    let oldA = Int(oldMatch.scoreA) ?? 0
                    let oldB = Int(oldMatch.scoreB) ?? 0
                    let newA = Int(newMatch.scoreA) ?? 0
                    let newB = Int(newMatch.scoreB) ?? 0
                    
                    if newA > oldA {
                        sendNotification(title: "⚽️ GOAL \(newMatch.teamA)!", body: "\(newMatch.teamA) \(newMatch.scoreA) - \(newMatch.scoreB) \(newMatch.teamB)")
                    } else if newB > oldB {
                        sendNotification(title: "⚽️ GOAL \(newMatch.teamB)!", body: "\(newMatch.teamA) \(newMatch.scoreA) - \(newMatch.scoreB) \(newMatch.teamB)")
                    }
                }
                
                // Cricket: Wicket Falls
                if newMatch.sport.lowercased() == "cricket" {
                    let oldWicketsA = Int(oldMatch.metadata?.wickets ?? "0") ?? 0
                    let newWicketsA = Int(newMatch.metadata?.wickets ?? "0") ?? 0
                    
                    // Simple heuristic: if scoreA is Team A batting, and wickets increased
                    if newWicketsA > oldWicketsA {
                        sendNotification(title: "🏏 WICKET!", body: "\(newMatch.teamA) is \(newMatch.scoreA)")
                    }
                }
            }
        }
    }
    
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[MatchCoordinator] Notification failed: \(error.localizedDescription)")
            }
        }
    }
    
    public func pinMatch(id: String?) {
        self.pinnedMatchID = id
        if id != nil {
            self.rotationMode = .pinnedOnly
        } else {
            self.rotationMode = .automatic
        }
    }
    
    // MARK: - Match Filtration Logic
    
    public func getFilteredMatches() -> [MatchState] {
        if matches.isEmpty { return [] }
        
        // Prioritize: Live games first, favorites next
        let sortedMatches = matches.sorted { m1, m2 in
            if m1.isLive != m2.isLive {
                return m1.isLive && !m2.isLive
            }
            let m1IsFav = isFavorite(m1)
            let m2IsFav = isFavorite(m2)
            if m1IsFav != m2IsFav {
                return m1IsFav && !m2IsFav
            }
            return false
        }
        
        switch rotationMode {
        case .pinnedOnly:
            if let pinnedID = pinnedMatchID,
               let pinned = sortedMatches.first(where: { $0.id == pinnedID }) {
                return [pinned]
            }
            return sortedMatches // fallback if pinned match no longer exists
            
        case .favoritesOnly:
            let favs = sortedMatches.filter { isFavorite($0) }
            return favs.isEmpty ? sortedMatches : favs // fallback to all if no favorites exist
            
        case .livePriority:
            let lives = sortedMatches.filter { $0.isLive }
            return lives.isEmpty ? sortedMatches : lives
            
        case .automatic:
            // Live matches: favorites only (don't cycle random live scores)
            let liveFavs = sortedMatches.filter { $0.isLive && isFavorite($0) }
            // Upcoming matches: favorites only (same rule as live — don't show random countdown timers)
            let favUpcoming = sortedMatches.filter { $0.isUpcoming && isFavorite($0) }
            // Combine: live favorites first, then upcoming favorites
            let combined = liveFavs + favUpcoming
            
            // If the user has explicitly configured ANY favorites, respect them strictly.
            // Do not fall back to random matches if their favorites aren't playing.
            let hasFavorites = !favoriteTeams.isEmpty || !favoriteTournaments.isEmpty
            if hasFavorites {
                return combined
            }
            
            // Fallbacks only apply for fresh installs with NO favorites set
            if !combined.isEmpty { return combined }
            let anyLive = sortedMatches.filter { $0.isLive }
            if !anyLive.isEmpty { return anyLive }
            return sortedMatches
        }
    }
    
    public func isFavorite(_ match: MatchState) -> Bool {
        let favTeams = favoriteTeams.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        let favTourneys = favoriteTournaments.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        
        let matchTourney = match.tournament.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // --- Team matching (check Name, Short Name, and ID) ---
        let tA = match.teamA.lowercased()
        let tB = match.teamB.lowercased()
        let sA = match.teamAShortName?.lowercased() ?? ""
        let sB = match.teamBShortName?.lowercased() ?? ""
        let idA = match.teamAId?.lowercased() ?? ""
        let idB = match.teamBId?.lowercased() ?? ""
        
        let teamMatches = favTeams.contains(tA) || favTeams.contains(tB) ||
                          (!sA.isEmpty && favTeams.contains(sA)) ||
                          (!sB.isEmpty && favTeams.contains(sB)) ||
                          (!idA.isEmpty && favTeams.contains(idA)) ||
                          (!idB.isEmpty && favTeams.contains(idB))
        
        // --- Tournament matching (whole string matching + known aliases) ---
        let aliases: [String: String] = [
            "wc": "world cup",
            "ucl": "champions league",
            "cl": "champions league",
            "pl": "premier league",
            "epl": "premier league",
            "bpl": "premier league",
            "el": "europa league",
            "ipl": "ipl",
            "t20wc": "t20 world cup",
            "cwc": "cricket world cup"
        ]
        
        let tourneyMatches = favTourneys.contains { favTourney in
            let expanded = aliases[favTourney] ?? favTourney
            // We check if the ESPN tournament contains our exact favorite string (or vice-versa)
            // e.g. "world cup" in "icc men's t20 world cup" -> TRUE
            // e.g. "world cup" in "central europe cup" -> FALSE (because "world cup" is not in there)
            return matchTourney.contains(expanded) || matchTourney.contains(favTourney) || expanded.contains(matchTourney)
        }
        
        return teamMatches || tourneyMatches
    }

    
    private func updateActiveMatch() {
        let list = getFilteredMatches()
        guard !list.isEmpty else {
            activeMatch = nil
            return
        }
        
        if let current = activeMatch, let index = list.firstIndex(where: { $0.id == current.id }) {
            // Keep the active match on the same game if possible
            activeMatch = list[index]
            cycleIndex = index
        } else {
            // Default to the first match in the list
            activeMatch = list[0]
            cycleIndex = 0
        }
    }
    
    // MARK: - Polling & Adjustments
    
    private func startPolling() {
        timer?.cancel()
        timer = Timer.publish(every: currentInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchScores()
            }
    }
    
    private func adjustPollingInterval(for matchStates: [MatchState]) {
        var interval: TimeInterval = 300.0 // 5 minutes default
        
        // In mock mode, we want faster updates so simulation runs nicely (e.g. 5 seconds)
        if !useRealAPIs {
            interval = 5.0
        } else {
            let hasCricket = matchStates.contains { $0.sport.lowercased() == "cricket" && $0.isLive }
            let hasFootball = matchStates.contains { $0.sport.lowercased() == "football" && $0.isLive }
            
            if hasCricket {
                interval = 20.0
            } else if hasFootball {
                interval = 45.0
            }
        }
        
        if currentInterval != interval {
            currentInterval = interval
            debugLog("[*] Adaptive Polling: set refresh to \(currentInterval)s")
            startPolling()
        }
    }
    
    // MARK: - JSON Cache Operations
    
    private var cacheURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportDir = paths[0].appendingPathComponent("ScoreDock")
        try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true, attributes: nil)
        return appSupportDir.appendingPathComponent("match_cache.json")
    }
    
    private func saveToCache(_ matchStates: [MatchState]) {
        do {
            let data = try JSONEncoder().encode(matchStates)
            try data.write(to: cacheURL)
        } catch {
            debugLog("[-] Failed to save cache JSON: \(error.localizedDescription)")
        }
    }
    
    private func loadFromCache() -> [MatchState]? {
        do {
            let data = try Data(contentsOf: cacheURL)
            return try JSONDecoder().decode([MatchState].self, from: data)
        } catch {
            return nil
        }
    }
}
