import SwiftUI
import Combine

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r, g, b: Double
        if hexSanitized.count == 6 {
            r = Double((rgb & 0xFF0000) >> 16) / 255.0
            g = Double((rgb & 0x00FF00) >> 8) / 255.0
            b = Double(rgb & 0x0000FF) / 255.0
        } else {
            return nil
        }
        self.init(red: r, green: g, blue: b)
    }
}

public class ScoreViewModel: ObservableObject {
    @Published public var currentMatch: MatchState
    @Published public var isHovered = false // Expose hover state to AppDelegate for tracking
    @Published public var isHorizontal = true // Tracks Dock orientation (horizontal vs vertical)
    @Published public var containerWidth: CGFloat = 240 // The width of the spanned helper tiles from AppDelegate
    @Published public var iconHeight: CGFloat = 64
    
    public var onWidgetClicked: (() -> Void)?
    
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        // Fallback default match in case activeMatch is nil initially
        self.currentMatch = MatchState(sport: "football", teamA: "LIV", teamAFlag: "🔴", scoreA: "0", teamB: "ARS", teamBFlag: "🔴", scoreB: "0", gameTime: "0'", isLive: false, tournament: "Premier League")
        
        // Listen to updates from MatchCoordinator
        MatchCoordinator.shared.$activeMatch
            .map { match in
                if let match = match { return match }
                // Return a dummy 'No Matches' state when the filtered list is empty
                return MatchState(
                    sport: "football",
                    teamA: "-",
                    teamAFlag: "∅",
                    scoreA: "-",
                    teamB: "-",
                    teamBFlag: "∅",
                    scoreB: "-",
                    gameTime: "No Matches",
                    isLive: false,
                    tournament: "Favorites"
                )
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] match in
                // Set match state inside a spring animation for smooth transitions
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    self?.currentMatch = match
                }
            }
            .store(in: &cancellables)
    }
    
    public func cycleMatch() {
        MatchCoordinator.shared.cycleNextMatch()
    }
    
    // Check if we should display team name text abbreviation
    public var showTeamNames: Bool {
        // Never show team names for cricket to prevent overlapping with flags in tight spaces
        if currentMatch.sport.lowercased() == "cricket" {
            return false
        }
        
        // For upcoming matches, always hide names (only flags + countdown shown)
        if currentMatch.isUpcoming {
            return false
        }
        
        // If team names are short abbreviations (≤ 3 chars), always show them.
        if currentMatch.teamA.count <= 3 && currentMatch.teamB.count <= 3 {
            return true
        }
        
        let scoreLength = currentMatch.scoreA.count + currentMatch.scoreB.count
        // Displayed names are capped at 3 chars each
        let nameLength = min(currentMatch.teamA.count, 3) + min(currentMatch.teamB.count, 3)
        
        // Calculate required width to show the team names fully without truncation
        let requiredWidth = 128 + CGFloat(scoreLength) * 9 + CGFloat(nameLength) * 6
        
        // Hide team names if the container width is too small to fit them properly without wrapping/truncation
        if containerWidth < requiredWidth {
            return false
        }
        return true
    }
    
    // Calculates a dynamic width for the horizontal card to hug the text content length tightly
    public var estimatedCardWidth: CGFloat {
        // Upcoming countdown card is compact
        if currentMatch.isUpcoming {
            return min(180, containerWidth)
        }
        
        let scoreLength = currentMatch.scoreA.count + currentMatch.scoreB.count
        
        var targetWidth: CGFloat
        if showTeamNames {
            // Each name is shown at most 3 chars
            let nameLength = min(currentMatch.teamA.count, 3) + min(currentMatch.teamB.count, 3)
            // Calculate the exact required width with team names
            targetWidth = 128 + CGFloat(scoreLength) * 9 + CGFloat(nameLength) * 6
        } else {
            // Calculate the width without team names
            let contentWidth = 116 + CGFloat(scoreLength) * 9
            // Clamp to a minimum of 180px
            targetWidth = max(contentWidth, 180)
        }
        
        // Clamp to the available container width to prevent overflow/clipping
        return min(targetWidth, containerWidth)
    }
}

// AppKit Helper to track hover in background / inactive applications
public final class HoverNSView: NSView {
    public var onHoverChanged: (Bool) -> Void
    private var trackingArea: NSTrackingArea?
    
    public init(onHoverChanged: @escaping (Bool) -> Void) {
        self.onHoverChanged = onHoverChanged
        super.init(frame: .zero)
        setupTrackingArea()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupTrackingArea() {
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }
    
    public override func mouseEntered(with event: NSEvent) {
        onHoverChanged(true)
    }
    
    public override func mouseExited(with event: NSEvent) {
        onHoverChanged(false)
    }
}

public struct HoverTracker: NSViewRepresentable {
    public var onHoverChanged: (Bool) -> Void
    
    public init(onHoverChanged: @escaping (Bool) -> Void) {
        self.onHoverChanged = onHoverChanged
    }
    
    public func makeNSView(context: Context) -> HoverNSView {
        return HoverNSView(onHoverChanged: onHoverChanged)
    }
    
    public func updateNSView(_ nsView: HoverNSView, context: Context) {
        nsView.onHoverChanged = onHoverChanged
    }
}

// MARK: - Countdown Formatter

@ViewBuilder
private func TeamBadge(logoURL: String?, flag: String, size: CGFloat = 20) -> some View {
    if let urlStr = logoURL, let url = URL(string: urlStr) {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit().frame(width: size, height: size)
            } else {
                Text(flag).font(.system(size: size - 4))
            }
        }
    } else {
        Text(flag).font(.system(size: size - 4))
    }
}

// MARK: - Countdown Formatter

private func formatCountdown(to target: Date) -> String {
    let seconds = Int(target.timeIntervalSinceNow)
    if seconds <= 0 { return "Now" }
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    } else {
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Main Score Widget View

public struct ScoreWidgetView: View {
    @ObservedObject var viewModel: ScoreViewModel
    @State private var pulsing = false
    @State private var isHovered = false
    @State private var now = Date()  // Drives the live countdown updates
    
    // Timer that fires every second to update the countdown
    private let countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    public init(viewModel: ScoreViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        GeometryReader { geo in
            // The GeometryReader gets the full height of the dock bar.
            // Based on exact visual measurements, standard macOS Dock icons visually take up about 65% of the dock bar's height.
            let basePillHeight = viewModel.isHorizontal ? (geo.size.height * 0.65) : geo.size.height
            let pillHeight = isHovered ? (basePillHeight + 12) : basePillHeight
                
            let pillWidth = geo.size.width
            
            
            ZStack {
                Group {
                    if viewModel.isHorizontal {
                        horizontalBody
                            .id(viewModel.currentMatch.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                            .scaleEffect(isHovered ? 1.12 : 1.0)
                    } else {
                        verticalBody
                            .id(viewModel.currentMatch.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            ))
                            .scaleEffect(isHovered ? 1.12 : 1.0)
                    }
                }
                .padding(.vertical, viewModel.isHorizontal ? 4 : 8)
                .padding(.horizontal, viewModel.isHorizontal ? 16 : 4)
                // Draw the view at exactly its base intended size...
                .frame(width: pillWidth, height: pillHeight)
                // ...and let HoverTracker run on this fixed size
                .background(
                    HoverTracker { hovering in
                        withAnimation {
                            isHovered = hovering
                            viewModel.isHovered = hovering
                        }
                    }
                )
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(cardBackground.opacity(isHovered ? 0.45 : 0.35))
                        .background(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(isHovered ? 0.22 : 0.12), lineWidth: 1)
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .contentShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(isHovered ? 0.35 : 0.15), radius: isHovered ? 6 : 3, x: 0, y: isHovered ? 3 : 1)
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: viewModel.estimatedCardWidth)
                .animation(.spring(response: 0.24, dampingFraction: 0.68), value: isHovered)
                .contextMenu {
                    if let espnID = viewModel.currentMatch.espnID {
                        let espnURLString = "https://www.espn.in/\(viewModel.currentMatch.sport.lowercased())/match/_/gameId/\(espnID)"
                        
                        Button(action: {
                            if let url = URL(string: espnURLString) {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            Label("Open in ESPN", systemImage: "safari")
                        }
                        
                        Button(action: {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(espnURLString, forType: .string)
                        }) {
                            Label("Copy ESPN Link", systemImage: "doc.on.doc")
                        }
                    } else {
                        Text("ESPN Link Unavailable")
                    }
                }
                .onTapGesture {
                    withAnimation {
                        MatchCoordinator.shared.cycleNextMatch()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 15, coordinateSpace: .local)
                        .onEnded { value in
                            if value.translation.width < -10 {
                                withAnimation {
                                    MatchCoordinator.shared.cycleNextMatch()
                                }
                            } else if value.translation.width > 10 {
                                withAnimation {
                                    MatchCoordinator.shared.cyclePrevMatch()
                                }
                            }
                        }
                )
            }
            // Center the pill horizontally, but shift it slightly downwards vertically 
            // (macOS dock has more padding at the top, so exact mathematical center looks too high).
            .position(x: geo.size.width / 2, y: (geo.size.height / 2) + (geo.size.height * 0.05))
        }
        .onReceive(countdownTimer) { date in
            if viewModel.currentMatch.isUpcoming {
                now = date
            }
        }
    }
    
    // Dynamic gradient based on team colors, or blue for upcoming, black for live fallback
    private var cardBackground: AnyShapeStyle {
        if viewModel.currentMatch.isUpcoming {
            return AnyShapeStyle(Color(red: 0.05, green: 0.12, blue: 0.35))
        }
        return AnyShapeStyle(Color.black)
    }
    
    // MARK: - Horizontal Layout
    
    private var horizontalBody: some View {
        Group {
            if viewModel.currentMatch.isUpcoming {
                horizontalUpcomingBody
            } else {
                horizontalLiveBody
            }
        }
    }
    
    // Upcoming match: FlagA — ⏱countdown — FlagB
    private var horizontalUpcomingBody: some View {
        HStack(spacing: 8) {
            TeamBadge(logoURL: viewModel.currentMatch.teamALogo, flag: viewModel.currentMatch.teamAFlag, size: 24)
                .fixedSize()
            
            VStack(spacing: 2) {
                Text("vs")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                    .minimumScaleFactor(0.4)
                
                if let target = viewModel.currentMatch.scheduledTime {
                    Text(formatCountdown(to: target))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.4, green: 0.75, blue: 1.0))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .minimumScaleFactor(0.7)
                }
                
                Text(viewModel.currentMatch.tournament)
                    .font(.system(size: 6, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(minWidth: 55)
            
            TeamBadge(logoURL: viewModel.currentMatch.teamBLogo, flag: viewModel.currentMatch.teamBFlag, size: 24)
                .fixedSize()
        }
    }
    
    // Live match: Flag Score — Time — Score Flag
    private var horizontalLiveBody: some View {
        HStack(spacing: 8) {
            // 1. Left Side: Flag A & optional Name A & Score A
            HStack(spacing: 4) {
                TeamBadge(logoURL: viewModel.currentMatch.teamALogo, flag: viewModel.currentMatch.teamAFlag, size: 18)
                    .fixedSize()
                
                if viewModel.showTeamNames {
                    Text(viewModel.currentMatch.teamA.prefix(3))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                }
                
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    if let prev = viewModel.currentMatch.metadata?.previousInningScoreA {
                        Text(prev)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    Text(viewModel.currentMatch.scoreA)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .layoutPriority(1) // High layout priority to prevent score truncation
                }
            }
            
            // 2. Middle: Divider line and Pulsing Time
            VStack(spacing: 1) {
                Text(viewModel.currentMatch.tournament.prefix(12))
                    .font(.system(size: 7, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .offset(y: 3.5)
                
                Text("—")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.25))
                
                HStack(spacing: 2) {
                    if viewModel.currentMatch.isLive {
                        Circle()
                            .fill(Color(red: 0.93, green: 0.27, blue: 0.27))
                            .frame(width: 4, height: 4)
                            .scaleEffect(pulsing ? 1.3 : 0.8)
                            .opacity(pulsing ? 1.0 : 0.4)
                            .onAppear {
                                withAnimation(
                                    Animation.easeInOut(duration: 0.8)
                                        .repeatForever(autoreverses: true)
                                ) {
                                    pulsing = true
                                }
                            }
                    }
                    
                    Text(viewModel.currentMatch.gameTime.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                
                if viewModel.currentMatch.sport.lowercased() == "cricket",
                   let overs = viewModel.currentMatch.metadata?.overs {
                    Text("\(overs) ov")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                        .offset(y: -2)
                }
            }
            .frame(minWidth: 35)
            
            // 3. Right Side: Score B & optional Name B & Flag B
            HStack(spacing: 4) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(viewModel.currentMatch.scoreB)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .layoutPriority(1) // High layout priority to prevent score truncation
                        
                    if let prev = viewModel.currentMatch.metadata?.previousInningScoreB {
                        Text(prev)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
                
                if viewModel.showTeamNames {
                    Text(viewModel.currentMatch.teamB.prefix(3))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                }
                
                TeamBadge(logoURL: viewModel.currentMatch.teamBLogo, flag: viewModel.currentMatch.teamBFlag, size: 18)
                    .fixedSize()
            }
        }
    }
    
    // MARK: - Vertical Layout (sidebar Dock)
    
    private var verticalBody: some View {
        Group {
            if viewModel.currentMatch.isUpcoming {
                verticalUpcomingBody
            } else {
                verticalLiveBody
            }
        }
    }
    
    private var verticalUpcomingBody: some View {
        VStack(spacing: 6) {
            TeamBadge(logoURL: viewModel.currentMatch.teamALogo, flag: viewModel.currentMatch.teamAFlag, size: 22)
                .fixedSize()
            
            if let target = viewModel.currentMatch.scheduledTime {
                Text(formatCountdown(to: target))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.4, green: 0.75, blue: 1.0))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            
            TeamBadge(logoURL: viewModel.currentMatch.teamBLogo, flag: viewModel.currentMatch.teamBFlag, size: 22)
                .fixedSize()
        }
    }
    
    // Portrait widget layout for vertical left/right Dock — live match
    private var verticalLiveBody: some View {
        VStack(spacing: 12) {
            // Top Team: Flag and Score A
            VStack(spacing: 4) {
                TeamBadge(logoURL: viewModel.currentMatch.teamALogo, flag: viewModel.currentMatch.teamAFlag, size: 22)
                    .fixedSize()
                
                Text(viewModel.currentMatch.scoreA)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .layoutPriority(1)
            }
            
            // Middle: Divider and pulsing live clock
            VStack(spacing: 3) {
                Text(viewModel.currentMatch.tournament.prefix(12))
                    .font(.system(size: 7, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                
                Text("—")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.25))
                
                HStack(spacing: 2) {
                    if viewModel.currentMatch.isLive {
                        Circle()
                            .fill(Color(red: 0.93, green: 0.27, blue: 0.27))
                            .frame(width: 4, height: 4)
                            .scaleEffect(pulsing ? 1.3 : 0.8)
                            .opacity(pulsing ? 1.0 : 0.4)
                            .onAppear {
                                withAnimation(
                                    Animation.easeInOut(duration: 0.8)
                                        .repeatForever(autoreverses: true)
                                ) {
                                    pulsing = true
                                }
                            }
                    }
                    
                    Text(viewModel.currentMatch.gameTime.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                
                if viewModel.currentMatch.sport.lowercased() == "cricket",
                   let overs = viewModel.currentMatch.metadata?.overs {
                    Text("\(overs) ov")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            
            // Bottom Team: Score B and Flag
            VStack(spacing: 4) {
                Text(viewModel.currentMatch.scoreB)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .layoutPriority(1)
                
                TeamBadge(logoURL: viewModel.currentMatch.teamBLogo, flag: viewModel.currentMatch.teamBFlag, size: 22)
                    .fixedSize()
            }
        }
    }
}
