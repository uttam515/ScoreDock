import SwiftUI

public struct PreferencesView: View {
    @ObservedObject var coordinator = MatchCoordinator.shared
    
    @State private var newFavTeam: String = ""
    @State private var newFavTourney: String = ""
    @State private var selectedSport: String = "All"
    @State private var apiSourceReal: Bool = false
    @State private var upcomingWindowIndex: Int = 1
    
    private let windowOptions = [6.0, 12.0, 24.0, 48.0]
    
    public init() {}
    
    public var body: some View {
        TabView {
            favoritesTab
                .tabItem {
                    Label("Favorites", systemImage: "star.fill")
                }
            
            apiTab
                .tabItem {
                    Label("API Config", systemImage: "network")
                }
            
            rotationTab
                .tabItem {
                    Label("Rotation Mode", systemImage: "arrow.triangle.2.circlepath")
                }
        }
        .frame(width: 420, height: 320)
        .padding()
        .onAppear {
            apiSourceReal = coordinator.useRealAPIs
            if let idx = windowOptions.firstIndex(of: coordinator.upcomingMatchWindow) {
                upcomingWindowIndex = idx
            }
        }
    }
    
    // MARK: - Data Models
    
    struct TeamInfo: Hashable {
        let name: String
        let flag: String
        let logoURL: String?
        let id: String?
    }
    
    struct TournamentInfo: Hashable {
        let name: String
    }
    
    // MARK: - Extracted Data
    
    private var activeSports: [String] {
        let sports = coordinator.matches.map { $0.sport.capitalized }
        var unique = Array(Set(sports)).sorted()
        unique.insert("All", at: 0)
        return unique
    }
    
    private func activeTeams(for sport: String) -> [TeamInfo] {
        let filtered = coordinator.matches.filter { sport == "All" || $0.sport.caseInsensitiveCompare(sport) == .orderedSame }
        
        var teamsDict: [String: TeamInfo] = [:]
        for match in filtered {
            teamsDict[match.teamA.uppercased()] = TeamInfo(name: match.teamA.uppercased(), flag: match.teamAFlag, logoURL: match.teamALogo, id: match.teamAId)
            teamsDict[match.teamB.uppercased()] = TeamInfo(name: match.teamB.uppercased(), flag: match.teamBFlag, logoURL: match.teamBLogo, id: match.teamBId)
        }
        return teamsDict.values.sorted { $0.name < $1.name }
    }
    
    private func activeTournaments(for sport: String) -> [TournamentInfo] {
        let filtered = coordinator.matches.filter { sport == "All" || $0.sport.caseInsensitiveCompare(sport) == .orderedSame }
        let tourneys = filtered.map { $0.tournament }.filter { !$0.lowercased().contains("tour ") && !$0.lowercased().contains(" tour") }
        let unique = Array(Set(tourneys)).sorted()
        return unique.map { TournamentInfo(name: $0) }
    }
    
    @State private var searchText = ""
    
    private var favoritesTab: some View {
        VStack(spacing: 12) {
            // Top Level: Sport Selection
            Picker("", selection: $selectedSport) {
                ForEach(activeSports, id: \.self) { sport in
                    Text(sport).tag(sport)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.bottom, 4)
            
            // Search / Manual Add
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search or enter manual favorite...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                
                if !searchText.isEmpty {
                    Menu("Add Manually") {
                        Button("Add as Team") {
                            newFavTeam = searchText
                            addFavorite()
                            searchText = ""
                        }
                        Button("Add as Tournament") {
                            newFavTourney = searchText
                            addTourney()
                            searchText = ""
                        }
                    }
                    .menuStyle(BorderlessButtonMenuStyle())
                    .frame(width: 120)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    
                    // 1. YOUR FAVORITES
                    if !coordinator.favoriteTeams.isEmpty || !coordinator.favoriteTournaments.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Your Favorites").font(.headline).foregroundColor(.secondary)
                            
                            ForEach(coordinator.favoriteTeams, id: \.self) { team in
                                FavoriteRow(title: team.uppercased(), isTeam: true) { removeFavorite(team) }
                            }
                            ForEach(coordinator.favoriteTournaments, id: \.self) { tourney in
                                FavoriteRow(title: tourney, isTeam: false) { removeTourney(tourney) }
                            }
                        }
                        .padding(.bottom, 8)
                        Divider()
                    }
                    
                    // 2. ACTIVE TEAMS
                    let filteredTeams = activeTeams(for: selectedSport).filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
                    if !filteredTeams.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Active Teams").font(.headline).foregroundColor(.secondary)
                            ForEach(filteredTeams, id: \.name) { team in
                                let isFav = coordinator.favoriteTeams.map { $0.lowercased() }.contains(team.name.lowercased())
                                TeamRow(team: team, isFavorite: isFav) {
                                    if isFav {
                                        removeFavorite(team.name)
                                    } else {
                                        newFavTeam = team.name
                                        addFavorite()
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    
                    // 3. ACTIVE TOURNAMENTS
                    let filteredTourneys = activeTournaments(for: selectedSport).filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
                    if !filteredTourneys.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Active Tournaments").font(.headline).foregroundColor(.secondary)
                            ForEach(filteredTourneys, id: \.name) { tourney in
                                let isFav = coordinator.favoriteTournaments.map { $0.lowercased() }.contains(tourney.name.lowercased())
                                TournamentRow(name: tourney.name, isFavorite: isFav) {
                                    if isFav {
                                        removeTourney(tourney.name)
                                    } else {
                                        newFavTourney = tourney.name
                                        addTourney()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.trailing, 10) // scrollbar padding
            }
        }
        .padding()
    }
}

// MARK: - Row Views

struct TeamRow: View {
    let team: PreferencesView.TeamInfo
    let isFavorite: Bool
    let action: () -> Void
    @State private var hover = false
    
    var body: some View {
        HStack {
            if let logo = team.logoURL, let url = URL(string: logo) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit().frame(width: 20, height: 20)
                    } else {
                        Text(team.flag).font(.system(size: 16))
                    }
                }
                .frame(width: 24, height: 24)
            } else {
                Text(team.flag).font(.system(size: 16)).frame(width: 24, height: 24)
            }
            
            Text(team.name).font(.body)
            Spacer()
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) { action() }
            }) {
                Image(systemName: isFavorite ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundColor(isFavorite ? .green : .blue)
                    .opacity(hover || isFavorite ? 1.0 : 0.4)
                    .imageScale(.large)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(hover ? Color(NSColor.controlBackgroundColor) : Color.clear)
        .cornerRadius(6)
        .onHover { hover = $0 }
    }
}

struct TournamentRow: View {
    let name: String
    let isFavorite: Bool
    let action: () -> Void
    @State private var hover = false
    
    var body: some View {
        HStack {
            Image(systemName: "trophy.fill").foregroundColor(.yellow).frame(width: 24, height: 24)
            Text(name).font(.body)
            Spacer()
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) { action() }
            }) {
                Image(systemName: isFavorite ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundColor(isFavorite ? .green : .blue)
                    .opacity(hover || isFavorite ? 1.0 : 0.4)
                    .imageScale(.large)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(hover ? Color(NSColor.controlBackgroundColor) : Color.clear)
        .cornerRadius(6)
        .onHover { hover = $0 }
    }
}

struct FavoriteRow: View {
    let title: String
    let isTeam: Bool
    let action: () -> Void
    @State private var hover = false
    
    var body: some View {
        HStack {
            Image(systemName: isTeam ? "flag.fill" : "trophy.fill")
                .foregroundColor(isTeam ? .blue : .yellow)
                .frame(width: 24, height: 24)
            Text(title).font(.body).fontWeight(.medium)
            Spacer()
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) { action() }
            }) {
                Image(systemName: "trash.circle.fill")
                    .foregroundColor(.red)
                    .opacity(hover ? 1.0 : 0.4)
                    .imageScale(.large)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(hover ? Color.red.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .onHover { hover = $0 }
    }
}

extension PreferencesView {
    
    private var apiTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("API Integration & Settings")
                .font(.headline)
            Text("By default, ScoreDock displays simulated/mock sports data. Toggle below to enable real-time keyless feeds fetched from ESPN.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Picker("Score Source:", selection: $apiSourceReal) {
                Text("Simulated / Mock Data (Offline Demo)").tag(false)
                Text("Real ESPN Live Data (Keyless Feeds)").tag(true)
            }
            .pickerStyle(RadioGroupPickerStyle())
            .onChange(of: apiSourceReal) { oldValue, newValue in
                coordinator.useRealAPIs = newValue
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Upcoming Match Lookahead")
                    .font(.headline)
                Text("Show matches starting within the next X hours.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("", selection: Binding(
                    get: { self.upcomingWindowIndex },
                    set: { newVal in
                        self.upcomingWindowIndex = newVal
                        coordinator.upcomingMatchWindow = windowOptions[newVal]
                    }
                )) {
                    Text("6 Hours").tag(0)
                    Text("12 Hours").tag(1)
                    Text("24 Hours").tag(2)
                    Text("48 Hours").tag(3)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 300)
            }
            .padding(.top, 16)
            
            Spacer()
        }
        .padding()
    }
    
    private var rotationTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Widget Rotation Mode")
                .font(.headline)
            Text("Configure how matches rotate and display in the Dock widget overlay.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Picker("Rotation Mode:", selection: Binding(
                get: { coordinator.rotationMode },
                set: { coordinator.rotationMode = $0 }
            )) {
                ForEach(RotationMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(RadioGroupPickerStyle())
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Mode Explanations:")
                    .font(.subheadline)
                    .fontWeight(.bold)
                
                Group {
                    Text("• Automatic: Cycles through all available matches in priority order.")
                    Text("• Favorites Only: Cycles only through matches featuring your favorite teams.")
                    Text("• Pinned Only: Freezes the widget onto a single manually-pinned match.")
                    Text("• Live Priority: Cycles live matches first; falls back to others if none are active.")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Actions
    
    private func addFavorite() {
        let clean = newFavTeam.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { return }
        
        var current = coordinator.favoriteTeams
        if !current.contains(clean) {
            current.append(clean)
            coordinator.favoriteTeams = current
        }
        newFavTeam = ""
    }
    
    private func removeFavorite(_ team: String) {
        var current = coordinator.favoriteTeams
        current.removeAll { $0.uppercased() == team.uppercased() }
        coordinator.favoriteTeams = current
    }
    
    private func addTourney() {
        let clean = newFavTourney.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        
        var current = coordinator.favoriteTournaments
        if !current.contains(clean) {
            current.append(clean)
            coordinator.favoriteTournaments = current
        }
        newFavTourney = ""
    }
    
    private func removeTourney(_ tourney: String) {
        var current = coordinator.favoriteTournaments
        current.removeAll { $0 == tourney }
        coordinator.favoriteTournaments = current
    }
    
    // Credentials helper removed as ESPN uses keyless scoreboard feeds.
}
