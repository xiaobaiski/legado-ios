import SwiftUI

/// 阅读统计与阅读时长记录页面（对标 Legado「阅读记录」）
public struct ReadingStatsView: View {
    @State private var records: [ReadRecord] = []
    @State private var todaySeconds: TimeInterval = 0
    @State private var totalSeconds: TimeInterval = 0
    @State private var isShowingClearAlert = false

    public init() {}

    public var body: some View {
        List {
            summarySection

            if records.isEmpty {
                Section {
                    ContentUnavailableView(
                        "暂无阅读记录",
                        systemImage: "chart.bar.xaxis",
                        description: Text("打开书架中的书籍开始阅读后，这里会自动累计每日与单本书阅读时长"))
                }
            } else {
                Section("书籍阅读时长排行") {
                    ForEach(records) { record in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.bookName)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(record.bookAuthor.isEmpty ? "本地导入" : record.bookAuthor)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(ReadRecordStore.formatDuration(record.readTimeSeconds))
                                    .font(.subheadline.weight(.medium).monospacedDigit())
                                    .foregroundStyle(Color.accentColor)
                                Text(record.lastReadDate, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("阅读统计")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !records.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        isShowingClearAlert = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .onAppear(perform: reload)
        .alert("清空阅读统计", isPresented: $isShowingClearAlert) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                ReadRecordStore.shared.clearAll()
                reload()
            }
        } message: {
            Text("确定清空所有今日与历史阅读时长记录吗？不会影响书架中的书籍和阅读进度。")
        }
    }

    private var summarySection: some View {
        Section {
            HStack(spacing: 12) {
                statCard(
                    title: "今日阅读",
                    value: ReadRecordStore.formatDuration(todaySeconds),
                    icon: "sun.max.fill",
                    tint: .orange)

                statCard(
                    title: "累计时长",
                    value: ReadRecordStore.formatDuration(totalSeconds),
                    icon: "clock.fill",
                    tint: .blue)

                statCard(
                    title: "读过书籍",
                    value: "\(records.count) 本",
                    icon: "books.vertical.fill",
                    tint: .purple)
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            .listRowBackground(Color.clear)
        }
    }

    private func statCard(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(tint)
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    private func reload() {
        let store = ReadRecordStore.shared
        records = store.allRecordsSorted()
        todaySeconds = store.todayReadSeconds()
        totalSeconds = store.totalReadSeconds()
    }
}
