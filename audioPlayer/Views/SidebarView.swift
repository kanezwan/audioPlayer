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

            List(selection: Binding(
                get: { viewModel.selectedFile?.id },
                set: { _ in }
            )) {
                ForEach(viewModel.displayedFiles) { item in
                    HStack {
                        Image(systemName: audioIcon(for: item))
                            .foregroundColor(viewModel.playingFile?.id == item.id ? .accentColor : .secondary)
                        Text(item.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectFile(item)
                    }
                    .onTapGesture(count: 2) {
                        viewModel.doubleClickFile(item)
                    }
                    .contextMenu {
                        Button("播放") { viewModel.doubleClickFile(item) }
                    }
                }

                if viewModel.filteredFiles.count > viewModel.displayedFiles.count {
                    HStack {
                        Spacer()
                        ProgressView()
                            .onAppear {
                                viewModel.loadNextPage()
                            }
                        Spacer()
                    }
                }
            }
            .listStyle(.sidebar)

            if viewModel.allFileItems.isEmpty {
                VStack {
                    Spacer()
                    Text("点击「浏览文件夹」添加音频文件")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Spacer()
                }
            }
        }
        .frame(minWidth: 200, idealWidth: 250)
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
