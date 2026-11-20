import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 书源导入液态玻璃面板
public struct SourceImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var inputText = ""
    @State private var isShowingFilePicker = false
    @State private var fileError: String?
    let onImport: (String) -> Void

    public init(onImport: @escaping (String) -> Void) {
        self.onImport = onImport
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("支持输入书源网络 URL 地址 (http/https)、粘贴书源 JSON 内容，或直接选择本地 JSON / TXT 书源文件。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // 输入区域
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 0.5))

                    if inputText.isEmpty {
                        Text("粘贴书源 URL 或 JSON 内容...")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .padding(14)
                    }

                    TextEditor(text: $inputText)
                        .font(.subheadline)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                }
                .frame(minHeight: 130, maxHeight: 180)

                if let fileError {
                    Text(fileError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 快捷操作按钮
                HStack(spacing: 12) {
                    Button {
                        if let clipboard = UIPasteboard.general.string {
                            inputText = clipboard
                            fileError = nil
                        }
                    } label: {
                        Label("剪贴板", systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass(cornerRadius: 12))

                    Button {
                        isShowingFilePicker = true
                    } label: {
                        Label("本地文件", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass(cornerRadius: 12))
                }

                Button {
                    let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        onImport(trimmed)
                    }
                } label: {
                    Label("确认导入", systemImage: "square.and.arrow.down.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent(tint: .accentColor, cornerRadius: 12))
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()
            }
            .padding(16)
            .navigationTitle("导入书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isShowingFilePicker) {
                DocumentPickerView(
                    allowedContentTypes: [.json, .plainText, .text, .data],
                    allowsMultipleSelection: false,
                    onPick: { urls in
                        isShowingFilePicker = false
                        if let url = urls.first {
                            loadSourceFile(from: url)
                        }
                    },
                    onCancel: {
                        isShowingFilePicker = false
                    })
                    .ignoresSafeArea()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
    }

    private func loadSourceFile(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
            if url.path.contains("LegadoImportStaging") {
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = CharsetDetector.decode(data: data)
            guard !decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                fileError = "所选书源文件为空"
                return
            }
            inputText = decoded
            fileError = nil
        } catch {
            fileError = "读取书源文件失败: \(error.localizedDescription)"
        }
    }
}
