import UIKit
import XCTest

/// 设置中心与 WebDAV / 临时缓存 UI 自动化测试
final class SettingsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--tab-settings"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testSettingsSectionsAndStorageCenter() {
        let navTitle = app.navigationBars["设置"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 8), "设置页面导航标题应正常显示")
        captureScreenshot(name: "settings_01_main_view")

        let webdavRow = app.buttons["WebDAV 云备份同步"]
        if webdavRow.waitForExistence(timeout: 4) {
            captureScreenshot(name: "settings_02_webdav_row")
        }

        let clearCacheButton = app.buttons["清理临时章节缓存正文"]
        if clearCacheButton.waitForExistence(timeout: 4) {
            captureScreenshot(name: "settings_03_storage_section")
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
