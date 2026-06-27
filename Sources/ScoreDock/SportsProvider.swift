import Foundation

public protocol SportsProvider {
    func fetchMatches() async throws -> [MatchState]
}

public final class MockSportsProvider: SportsProvider {
    private var mockMatches: [MatchState]
    private let queue = DispatchQueue(label: "com.scoredock.mockprovider")
    
    public init() {
        self.mockMatches = [
            MatchState(
                sport: "football",
                teamA: "LIV",
                teamAFlag: "🔴",
                scoreA: "2",
                teamB: "ARS",
                teamBFlag: "🔴",
                scoreB: "1",
                gameTime: "73'",
                isLive: true,
                tournament: "Premier League",
                metadata: SportMetadata(period: 2, matchPhase: "2H")
            ),
            MatchState(
                sport: "football",
                teamA: "MCI",
                teamAFlag: "🔵",
                scoreA: "0",
                teamB: "MUN",
                teamBFlag: "🔴",
                scoreB: "0",
                gameTime: "12'",
                isLive: true,
                tournament: "Premier League",
                metadata: SportMetadata(period: 1, matchPhase: "1H")
            ),
            MatchState(
                sport: "football",
                teamA: "RMA",
                teamAFlag: "⚪",
                scoreA: "3",
                teamB: "FCB",
                teamBFlag: "🔴",
                scoreB: "2",
                gameTime: "89'",
                isLive: true,
                tournament: "La Liga",
                metadata: SportMetadata(period: 2, matchPhase: "2H")
            ),
            MatchState(
                sport: "basketball",
                teamA: "LAL",
                teamAFlag: "🟣",
                scoreA: "102",
                teamB: "BOS",
                teamBFlag: "🟢",
                scoreB: "98",
                gameTime: "Q4 2:14",
                isLive: true,
                tournament: "NBA"
            ),
            MatchState(
                sport: "cricket",
                teamA: "IND",
                teamAFlag: "🇮🇳",
                scoreA: "283/4",
                teamB: "AUS",
                teamBFlag: "🇦🇺",
                scoreB: "104/1",
                gameTime: "Overs 32",
                isLive: true,
                tournament: "IPL",
                metadata: SportMetadata(overs: "32.0", wickets: "4", runs: "283")
            )
        ]
    }
    
    public func fetchMatches() async throws -> [MatchState] {
        return queue.sync {
            // Increment scores for active live matches
            mockMatches = mockMatches.map { match -> MatchState in
                guard match.isLive else { return match }
                var newScoreA = match.scoreA
                var newScoreB = match.scoreB
                var newMeta = match.metadata ?? SportMetadata()
                
                if match.sport == "basketball" {
                    let scoreAInt = Int(match.scoreA) ?? 102
                    let scoreBInt = Int(match.scoreB) ?? 98
                    newScoreA = "\(scoreAInt + Int.random(in: 0...3))"
                    newScoreB = "\(scoreBInt + Int.random(in: 0...3))"
                } else if match.sport == "cricket" {
                    let partsA = match.scoreA.components(separatedBy: "/")
                    if partsA.count == 2, let runs = Int(partsA[0]), let wickets = Int(partsA[1]) {
                        if Double.random(in: 0...1) > 0.6 {
                            let addRuns = Int.random(in: 1...6)
                            let addWickets = Double.random(in: 0...1) > 0.93 && wickets < 10 ? 1 : 0
                            newScoreA = "\(runs + addRuns)/\(wickets + addWickets)"
                            newMeta.runs = "\(runs + addRuns)"
                            newMeta.wickets = "\(wickets + addWickets)"
                        }
                    }
                } else { // Football
                    if Double.random(in: 0...1) > 0.92 {
                        let scoreAInt = Int(match.scoreA) ?? 0
                        newScoreA = "\(scoreAInt + 1)"
                    }
                    if Double.random(in: 0...1) > 0.92 {
                        let scoreBInt = Int(match.scoreB) ?? 0
                        newScoreB = "\(scoreBInt + 1)"
                    }
                }
                
                return MatchState(
                    sport: match.sport,
                    teamA: match.teamA,
                    teamAFlag: match.teamAFlag,
                    scoreA: newScoreA,
                    teamB: match.teamB,
                    teamBFlag: match.teamBFlag,
                    scoreB: newScoreB,
                    gameTime: match.gameTime,
                    isLive: match.isLive,
                    tournament: match.tournament,
                    metadata: newMeta,
                    scheduledTime: match.scheduledTime,
                    teamAColor: match.teamAColor,
                    teamBColor: match.teamBColor,
                    teamALogo: match.teamALogo,
                    teamBLogo: match.teamBLogo
                )
            }
            return mockMatches
        }
    }
}
