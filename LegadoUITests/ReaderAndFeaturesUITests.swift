import UIKit
import XCTest

/// 阅读器核心与纯粹本地阅读特性 UI 自动化测试（目录/书签、正文全文搜索与排版面板）
final class ReaderAndFeaturesUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--open-reader-hud"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testReaderHUDTocBookmarksSearchAndTypography() {

        // MARK: - 步骤 1: 验证阅读器 HUD 成功展现

        let bookTitle = app.staticTexts["宿命之环"]
        XCTAssertTrue(bookTitle.waitForExistence(timeout: 8), "阅读器 HUD 顶部应展示书名【宿命之环】")
        XCTAssertFalse(app.buttons["听书"].exists, "纯净阅读版阅读器 HUD 不应存在【听书】按钮")
        XCTAssertFalse(app.buttons["换源"].exists, "纯净阅读版阅读器 HUD 不应存在【换源】按钮")
        captureScreenshot(name: "reader_01_hud_active")

        // MARK: - 步骤 2: 打开目录抽屉并切换至书签栏目

        let tocButton = app.buttons["目录"]
        if tocButton.waitForExistence(timeout: 4) {
            tocButton.tap()

            let bookmarkTab = app.buttons["书签"]
            XCTAssertTrue(bookmarkTab.waitForExistence(timeout: 5), "目录与书签液态面板应成功弹出")
            captureScreenshot(name: "reader_02_toc_sheet")

            // 切换至书签 Tab
            bookmarkTab.tap()
            captureScreenshot(name: "reader_03_bookmarks_tab")

            let closeTocButton = app.buttons.matching(identifier: "完成").firstMatch
            if closeTocButton.waitForExistence(timeout: 3) {
                closeTocButton.tap()
                _ = bookmarkTab.waitForNonExistence(timeout: 3)
            }
        }

        // MARK: - 步骤 3: 打开正文全文搜索面板

        let searchButton = app.buttons["搜索"]
        if searchButton.waitForExistence(timeout: 4) {
            tapElementSafely(searchButton)

            let searchField = app.textFields["搜索本书正文内容..."]
            if searchField.waitForExistence(timeout: 4) {
                captureScreenshot(name: "reader_04_search_content_sheet")
                searchField.tap()
                searchField.typeText("命运")
                captureScreenshot(name: "reader_05_search_content_typed")
            }

            let doneSearchButton = app.buttons.matching(identifier: "完成").firstMatch
            if doneSearchButton.waitForExistence(timeout: 3) {
                doneSearchButton.tap()
                _ = searchField.waitForNonExistence(timeout: 3)
            }
        }

        // MARK: - 步骤 4: 打开排版面板

        let typographyButton = app.buttons["排版"]
        if typographyButton.waitForExistence(timeout: 4) {
            tapElementSafely(typographyButton)
            captureScreenshot(name: "reader_06_typography_panel")
        }
    }

    private func tapElementSafely(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func captureScreenshot(name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
