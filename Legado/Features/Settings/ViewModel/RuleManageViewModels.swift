import Foundation
import UIKit

/// 替换净化规则管理视图模型（兼容 Legado Android `replaceRule.json`）
@MainActor
public final class ReplaceRuleManageViewModel: ObservableObject {
    @Published public private(set) var rules: [ReplaceRule] = []
    @Published public var toastMessage: String?

    private let store: ReplaceRuleStore
    public var onRulesMutated: (@MainActor () -> Void)?

    public init(store: ReplaceRuleStore = .shared) {
        self.store = store
        self.rules = store.loadRules()
    }

    public func reload() {
        rules = store.loadRules()
    }

    public func toggleEnabled(id: String) {
        rules = store.toggleEnabled(id: id)
        onRulesMutated?()
    }

    public func save(_ rule: ReplaceRule) {
        guard rule.isValid else {
            showToast("规则无效：请检查正则语法或匹配内容")
            return
        }
        rules = store.upsert(rule)
        onRulesMutated?()
        showToast("已保存规则「\(rule.name.isEmpty ? "未命名规则" : rule.name)」")
    }

    public func delete(id: String) {
        rules = store.delete(id: id)
        onRulesMutated?()
        showToast("已删除替换规则")
    }

    public func resetDefaults() {
        rules = store.resetToDefaults()
        onRulesMutated?()
        showToast("已恢复内置净化规则")
    }

    public func importFromClipboard() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              let data = text.data(using: .utf8) else {
            showToast("剪贴板为空，请先复制 Legado 替换规则 JSON")
            return
        }
        importData(data)
    }

    public func importFromFile(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
            if url.path.contains("LegadoImportStaging") {
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            }
        }
        guard let data = try? Data(contentsOf: url) else {
            showToast("无法读取所选 JSON 文件")
            return
        }
        importData(data)
    }

    public func copyExportJSON() {
        UIPasteboard.general.string = store.exportLegadoJSON()
        showToast("已复制 \(rules.count) 条 Legado 兼容规则 JSON")
    }

    public func previewResult(sample: String, rule: ReplaceRule) -> String {
        guard !sample.isEmpty, rule.isValid else { return sample }
        return PurifyContentUseCase.shared.processContent(
            sample,
            rules: [rule],
            enableReplace: true,
            removeSameTitle: false,
            reSegment: false)
    }

    private func importData(_ data: Data) {
        do {
            let count = try store.importLegadoJSON(data)
            rules = store.loadRules()
            if count > 0 {
                onRulesMutated?()
            }
            showToast(count > 0 ? "成功导入 \(count) 条替换净化规则" : "未发现有效替换规则")
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }
}

/// TXT 目录分章规则管理视图模型（兼容 Legado Android `txtTocRule.json`）
@MainActor
public final class TxtTocRuleManageViewModel: ObservableObject {
    @Published public private(set) var rules: [TxtTocRule] = []
    @Published public var toastMessage: String?

    private let store: TxtTocRuleStore
    public var onRulesMutated: (@MainActor () -> Void)?

    public init(store: TxtTocRuleStore = .shared) {
        self.store = store
        self.rules = store.loadRules()
    }

    public func reload() {
        rules = store.loadRules()
    }

    public func toggleEnabled(id: Int64) {
        rules = store.toggleEnabled(id: id)
        onRulesMutated?()
    }

    public func save(_ rule: TxtTocRule) {
        guard rule.isValid else {
            showToast("正则表达式语法无效，请检查后重试")
            return
        }
        rules = store.upsert(rule)
        onRulesMutated?()
        showToast("已保存目录规则「\(rule.name.isEmpty ? "自定义规则" : rule.name)」")
    }

    public func delete(id: Int64) {
        rules = store.delete(id: id)
        onRulesMutated?()
        showToast("已删除目录规则")
    }

    public func resetDefaults() {
        rules = store.resetToDefaults()
        onRulesMutated?()
        showToast("已恢复 Legado 官方默认目录规则")
    }

    public func importFromClipboard() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              let data = text.data(using: .utf8) else {
            showToast("剪贴板为空，请先复制 Legado txtTocRule.json")
            return
        }
        importData(data)
    }

    public func importFromFile(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
            if url.path.contains("LegadoImportStaging") {
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            }
        }
        guard let data = try? Data(contentsOf: url) else {
            showToast("无法读取所选 JSON 文件")
            return
        }
        importData(data)
    }

    public func copyExportJSON() {
        UIPasteboard.general.string = store.exportLegadoJSON()
        showToast("已复制 \(rules.count) 条 Legado TXT 目录规则 JSON")
    }

    public func testRuleMatches(pattern: String, sample: String) -> [String] {
        guard !pattern.isEmpty, !sample.isEmpty,
              let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return []
        }
        let nsSample = sample as NSString
        let matches = regex.matches(in: sample, options: [], range: NSRange(location: 0, length: nsSample.length))
        return matches.map { nsSample.substring(with: $0.range).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func importData(_ data: Data) {
        do {
            let count = try store.importLegadoJSON(data)
            rules = store.loadRules()
            if count > 0 {
                onRulesMutated?()
            }
            showToast(count > 0 ? "成功导入 \(count) 条目录规则" : "未发现有效目录规则")
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }
}
