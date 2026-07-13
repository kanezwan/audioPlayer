import SwiftUI

struct SettingsView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var vm = viewModel
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("设置")
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            Form {
                Section("段落检测") {
                    HStack {
                        Text("灵敏度系数")
                        Spacer()
                        Text(String(format: "%.1fx", viewModel.sensitivityFactor))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                    Slider(value: $vm.sensitivityFactor, in: 1...5, step: 0.5) {
                        Text("灵敏度系数")
                    } onEditingChanged: { editing in
                        if !editing {
                            viewModel.reanalyzeSegments()
                        }
                    }
                    Text("系数越大 → 阈值越低 → 检测到的段落越多。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider().padding(.vertical, 4)

                    HStack {
                        Text("段落扩展")
                        Spacer()
                        Text("±\(Int(viewModel.segmentExpansionSeconds))s")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                    Slider(value: $vm.segmentExpansionSeconds, in: 0...15, step: 1) {
                        Text("段落扩展")
                    } onEditingChanged: { editing in
                        if !editing {
                            viewModel.reanalyzeSegments()
                        }
                    }
                    Text("默认 1.25s。框也支持在波形上拖动创建或拖动边缘调整范围。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("导出") {
                    HStack {
                        Text("输出目录")
                        Spacer()
                        Text("所选文件夹下的 out/")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    HStack {
                        Text("命名格式")
                        Spacer()
                        Text("原名称_mm:ss-mm:ss.后缀")
                            .foregroundColor(.secondary)
                            .font(.caption.monospacedDigit())
                    }
                }

                Section("支持格式") {
                    HStack(spacing: 16) {
                        Label("WAV", systemImage: "waveform")
                        Label("MP3", systemImage: "music.note")
                        Label("AAC", systemImage: "music.note.list")
                    }
                    .foregroundColor(.secondary)
                    .font(.caption)
                }

                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("日志上限")
                        Spacer()
                        Text("200 条")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 4)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 440, height: 540)
    }
}

#Preview {
    SettingsView()
        .environment(AppViewModel())
}
