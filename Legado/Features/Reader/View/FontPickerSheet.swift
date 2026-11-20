import SwiftUI

/// 字体选择与管理视图（仅展示系统默认、用户导入本地字体与设备实际已安装字体，绝不列出无效假字体）
public struct FontPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var systemFonts: [SystemFontOption] = []

    let selectedPostScriptName: String?
    let importedFonts: [ImportedFont]
    let onSelectSystemDefault: () -> Void
    let onSelectFont: (_ postScriptName: String, _ displayName: String) -> Void
    let onDeleteImportedFont: (ImportedFont) -> Void
    let onOpenFontImporter: () -> Void

    public init(
        selectedPostScriptName: String?,
        importedFonts: [ImportedFont],
        onSelectSystemDefault: @escaping () -> Void,
        onSelectFont: @escaping (_ postScriptName: String, _ displayName: String) -> Void,
        onDeleteImportedFont: @escaping (ImportedFont) -> Void,
        onOpenFontImporter: @escaping () -> Void) {
        self.selectedPostScriptName = selectedPostScriptName
        self.importedFonts = importedFonts
        self.onSelectSystemDefault = onSelectSystemDefault
        self.onSelectFont = onSelectFont
        self.onDeleteImportedFont = onDeleteImportedFont
        self.onOpenFontImporter = onOpenFontImporter
    }

    private var filteredSystemFonts: [SystemFontOption] {
        guard !searchText.isEmpty else { return systemFonts }
        return systemFonts.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
                $0.postScriptName.localizedCaseInsensitiveContains(searchText)
        }
    }

    public var body: some View {
        NavigationStack {
            List {
                defaultSection
                importedSection
                deviceFontsSection
            }
            .navigationTitle("选择阅读字体")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索设备已安装字体...")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onOpenFontImporter()
                    } label: {
                        Label("导入字体", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
            .onAppear {
                if systemFonts.isEmpty {
                    systemFonts = LocalFontManager.shared.listAvailableSystemFonts()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var defaultSection: some View {
        Section {
            Button {
                onSelectSystemDefault()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("系统默认")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("春风十里，不如翻开一页好书。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selectedPostScriptName == nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var importedSection: some View {
        Section {
            Button {
                onOpenFontImporter()
            } label: {
                Label("导入本地字体文件 (TTF / OTF / TTC)", systemImage: "doc.badge.plus")
            }

            ForEach(importedFonts) { font in
                let isSelected = selectedPostScriptName == font.postScriptName
                HStack {
                    Button {
                        onSelectFont(font.postScriptName, font.displayName)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(font.displayName)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text("春风十里，不如翻开一页好书。")
                                    .font(.custom(font.postScriptName, size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        onDeleteImportedFont(font)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text("已导入的自定义字体")
        } footer: {
            Text("推荐导入您喜爱的宋体、楷体、霞鹜文楷或方正书宋等 TTF / OTF 字体文件，导入后立即生效。")
        }
    }

    private var deviceFontsSection: some View {
        Section {
            ForEach(filteredSystemFonts) { font in
                let isSelected = selectedPostScriptName == font.postScriptName
                Button {
                    onSelectFont(font.postScriptName, font.displayName)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(font.displayName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("春风十里，不如翻开一页好书。ABC 123")
                                .font(.custom(font.postScriptName, size: 13))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("本机已安装的真实字体 (\(filteredSystemFonts.count))")
        }
    }
}
