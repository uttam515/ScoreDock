import SwiftUI

public struct MatchHUDView: View {
    @ObservedObject var viewModel: ScoreViewModel
    
    public init(viewModel: ScoreViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            
            Spacer(minLength: 0)
            
            HStack {
                Spacer()
                Button(action: {
                    viewModel.cycleMatch()
                }) {
                    Text("Next Match")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(16)
        .frame(width: 300, height: 110)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.12).opacity(0.85))
                .background(.ultraThinMaterial)
        )
    }
    
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.currentMatch.tournament)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.blue)
                    .textCase(.uppercase)
                
                HStack(spacing: 8) {
                    Text("\(viewModel.currentMatch.teamAFlag) \(viewModel.currentMatch.teamAShortName ?? viewModel.currentMatch.teamA)")
                        .font(.system(size: 18, weight: .bold))
                    Text("vs")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    Text("\(viewModel.currentMatch.teamBFlag) \(viewModel.currentMatch.teamBShortName ?? viewModel.currentMatch.teamB)")
                        .font(.system(size: 18, weight: .bold))
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(viewModel.currentMatch.isLive ? "LIVE" : (viewModel.currentMatch.isUpcoming ? "UPCOMING" : "FINAL"))
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(viewModel.currentMatch.isLive ? Color.red : (viewModel.currentMatch.isUpcoming ? Color.blue : Color.gray))
                    .cornerRadius(4)
                
                Text(viewModel.currentMatch.gameTime)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }
}
