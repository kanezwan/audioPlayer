import SwiftUI

struct PlaybackBar: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(viewModel.currentTimeFormatted)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .trailing)

                Slider(
                    value: Binding(
                        get: { viewModel.progress },
                        set: { viewModel.seek(to: $0) }
                    ),
                    in: 0...1
                )
                .disabled(viewModel.duration == 0)

                Text(viewModel.durationFormatted)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .leading)
            }

            HStack(spacing: 16) {
                Button(action: { viewModel.togglePlayPause() }) {
                    Image(
                        systemName: viewModel.isPlaying && !viewModel.isPaused
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

                Divider().frame(height: 20)

                Image(systemName: viewModel.volume == 0
                    ? "speaker.slash.fill"
                    : viewModel.volume < 0.5
                        ? "speaker.wave.1.fill"
                        : "speaker.wave.3.fill"
                )
                .foregroundColor(.secondary)

                Slider(value: Binding(
                    get: { Double(viewModel.volume) },
                    set: { viewModel.setVolume(Float($0)) }
                ), in: 0...1)
                .frame(width: 100)

                Spacer()

                if let file = viewModel.selectedFile {
                    Text(file.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
