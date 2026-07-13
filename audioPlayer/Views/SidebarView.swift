import SwiftUI

struct SidebarView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { viewModel.openFolder() }) {
                    Label("浏览文件夹", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.plain)
                .padding(6)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            TextField("过滤文件名...", text: Binding(
                get: { viewModel.filterText },
                set: { viewModel.filterText = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            if viewModel.allFileItems.isEmpty {
                VStack {
                    Spacer()
                    Text("点击「浏览文件夹」添加音频文件")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.displayedFiles) { item in
                            FileRow(
                                item: item,
                                isPlaying: viewModel.playingFile?.id == item.id,
                                isSelected: viewModel.selectedFile?.id == item.id,
                                audioIcon: audioIcon(for: item),
                                onSingleClick: { viewModel.selectFile(item) },
                                onDoubleClick: { viewModel.doubleClickFile(item) },
                                onPlayContext: { viewModel.doubleClickFile(item) }
                            )
                            .onAppear {
                                // Trigger pagination when the LAST visible row appears
                                if item.id == viewModel.displayedFiles.last?.id {
                                    viewModel.loadNextPage()
                                }
                            }
                        }

                        if viewModel.hasMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.7)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .onAppear { viewModel.loadNextPage() }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 160, idealWidth: 240, maxWidth: 280)
    }

    private func audioIcon(for item: AudioFileItem) -> String {
        let ext = item.url.pathExtension.lowercased()
        switch ext {
        case "wav": return "waveform"
        case "mp3": return "music.note"
        case "aac": return "music.note.list"
        default: return "doc"
        }
    }
}

private struct FileRow: View {
    let item: AudioFileItem
    let isPlaying: Bool
    let isSelected: Bool
    let audioIcon: String
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void
    let onPlayContext: () -> Void

    var body: some View {
        HStack {
            Image(systemName: audioIcon)
                .foregroundColor(isPlaying ? .accentColor : .secondary)
                .frame(width: 18)
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.18)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 4)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleClick() }
        .onTapGesture { onSingleClick() }
        .contextMenu {
            Button("播放") { onPlayContext() }
        }
    }
}
