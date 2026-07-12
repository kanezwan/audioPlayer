import SwiftUI

struct MainPlayerView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            WaveformView()
                .padding(12)

            Divider()

            PlaybackBar()
        }
        .overlay {
            if viewModel.isLoadingWaveform {
                ProgressView("分析中...")
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
