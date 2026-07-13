import SwiftUI

struct PlaybackBar: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { viewModel.skip(by: -3) }) {
                Image(systemName: "gobackward.3")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isPlaying && !viewModel.isPaused)

            Button(action: { viewModel.togglePlayPause() }) {
                Image(systemName: viewModel.isPlaying && !viewModel.isPaused
                    ? "pause.fill"
                    : "play.fill"
                )
                .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.selectedFile == nil)
            .keyboardShortcut(.space, modifiers: [])

            Button(action: { viewModel.stopPlayback() }) {
                Image(systemName: "stop.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isPlaying && !viewModel.isPaused)

            Button(action: { viewModel.skip(by: 3) }) {
                Image(systemName: "goforward.3")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isPlaying && !viewModel.isPaused)

            Spacer()

            Image(systemName: viewModel.volume == 0
                ? "speaker.slash.fill"
                : viewModel.volume < 0.5
                    ? "speaker.wave.1.fill"
                    : "speaker.wave.3.fill"
            )
            .foregroundColor(.secondary)
            .font(.caption)

            Slider(value: Binding(get: { Double(viewModel.volume) },
                                   set: { viewModel.setVolume(Float($0)) }),
                   in: 0...1)
            .frame(width: 80)
            .controlSize(.mini)
        }
    }
}
