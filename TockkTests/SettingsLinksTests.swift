import XCTest
@testable import Tockk

final class SettingsLinksTests: XCTestCase {
    func testSiteURLUsesHTTPSAndPointsAtAppsSomee4() {
        XCTAssertEqual(SettingsLinks.site.scheme, "https")
        XCTAssertEqual(SettingsLinks.site.host, "apps.somee4.com")
        XCTAssertTrue(SettingsLinks.site.path.contains("/apps/tockk"))
    }

    func testGithubURLPointsAtSomee4TockkRepo() {
        XCTAssertEqual(SettingsLinks.github.scheme, "https")
        XCTAssertEqual(SettingsLinks.github.host, "github.com")
        XCTAssertEqual(SettingsLinks.github.path, "/somee4/tockk")
    }

    func testSponsorURLPointsAtKoFiYonyonhee() {
        XCTAssertEqual(SettingsLinks.sponsor.scheme, "https")
        XCTAssertEqual(SettingsLinks.sponsor.host, "ko-fi.com")
        XCTAssertEqual(SettingsLinks.sponsor.path, "/yonyonhee")
    }
}
