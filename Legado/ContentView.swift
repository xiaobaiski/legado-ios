import SwiftUI

/// App 主导航标签页枚举（纯粹阅读器定位：书架 + 设置）
public enum MainTab: String, CaseIterable, Identifiable {
    case bookshelf
    case settings

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .bookshelf: return "书架"
        case .settings: return "设置"
        }
    }

    public var icon: String {
        switch self {
        case .bookshelf: return "books.vertical.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// App 根视图：采用 iOS 18 原生 TabView 与 Tab 容器架构，专注纯粹本地阅读体验
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppAppearanceMode.storageKey) private var appearanceModeRaw = AppAppearanceMode.system.rawValue
    @EnvironmentObject private var environment: AppEnvironment
    @State private var selectedTab: MainTab = .bookshelf
    @State private var demoReaderPresented = false

    private var resolvedColorScheme: ColorScheme? {
        (AppAppearanceMode(rawValue: appearanceModeRaw) ?? .system).colorScheme
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(MainTab.bookshelf.title, systemImage: MainTab.bookshelf.icon, value: .bookshelf) {
                BookshelfView(viewModel: environment.makeBookshelfViewModel())
            }

            Tab(MainTab.settings.title, systemImage: MainTab.settings.icon, value: .settings) {
                SettingsView(viewModel: environment.makeSettingsViewModel())
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .preferredColorScheme(resolvedColorScheme)
        .fullScreenCover(isPresented: $demoReaderPresented) {
            let sampleBook = Book(
                bookUrl: "local://sample/circle_of_inevitability",
                tocUrl: "",
                origin: "local",
                originName: "内置试读",
                name: "宿命之环",
                author: "爱潜水的乌贼",
                durChapterTitle: "第一章 宿命之始",
                durChapterIndex: 0)
            let showHUD = ProcessInfo.processInfo.arguments.contains("--open-reader-hud")
            ReaderView(viewModel: environment.makeReaderViewModel(
                book: sampleBook,
                initialChapterIndex: 0,
                showHUDInitially: showHUD))
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--open-reader-demo") ||
                ProcessInfo.processInfo.arguments.contains("--open-reader-hud") {
                demoReaderPresented = true
            } else if ProcessInfo.processInfo.arguments.contains("--tab-settings") {
                selectedTab = .settings
            }
        }
        .onOpenURL { url in
            guard url.isFileURL else { return }
            selectedTab = .bookshelf
            environment.enqueueExternalImport(url)
        }
        .task {
            _ = await environment.webDAVRealtimeSyncService.pullLatestProgressIfNeeded()
            _ = await environment.webDAVRealtimeSyncService.pullLatestRulesIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    _ = await environment.webDAVRealtimeSyncService.pullLatestProgressIfNeeded()
                    _ = await environment.webDAVRealtimeSyncService.pullLatestRulesIfNeeded()
                }
            } else if phase == .background {
                environment.webDAVRealtimeSyncService.flushPendingProgressPush()
                environment.webDAVRealtimeSyncService.flushPendingRulesPush()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppEnvironment(inMemory: true))
}
