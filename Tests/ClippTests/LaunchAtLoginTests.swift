import ServiceManagement
import XCTest
@testable import Clipp

final class LaunchAtLoginTests: XCTestCase {
    @MainActor
    func testDefaultRegistrationRunsOnceAndRespectsAppAndSystemChoices() throws {
        let suite = "ClippTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var status: SMAppService.Status = .notRegistered
        var registrations = 0
        var removals = 0
        func makeModel() -> LaunchAtLogin {
            LaunchAtLogin(defaults: defaults, readStatus: { status }, register: {
                registrations += 1
                status = .enabled
            }, unregister: {
                removals += 1
                status = .notRegistered
            })
        }

        let model = makeModel()
        model.configureOnFirstLaunch()
        XCTAssertTrue(model.isEnabled)
        XCTAssertEqual(registrations, 1)
        model.configureOnFirstLaunch()
        XCTAssertEqual(registrations, 1)

        model.setEnabled(false)
        XCTAssertFalse(model.isEnabled)
        XCTAssertEqual(removals, 1)
        let reopened = makeModel()
        reopened.configureOnFirstLaunch()
        XCTAssertFalse(reopened.isEnabled)
        XCTAssertEqual(registrations, 1)

        reopened.setEnabled(true)
        XCTAssertEqual(registrations, 2)
        status = .requiresApproval // Revoked in System Settings.
        let revoked = makeModel()
        revoked.configureOnFirstLaunch()
        XCTAssertTrue(revoked.requiresApproval)
        XCTAssertEqual(registrations, 2)
        status = .notRegistered // Removed entirely in System Settings.
        revoked.configureOnFirstLaunch()
        XCTAssertFalse(revoked.isEnabled)
        XCTAssertEqual(registrations, 2)
    }

    @MainActor
    func testInertModeAndFailedRegistrationDoNotMarkSetupComplete() throws {
        let suite = "ClippTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let inert = LaunchAtLogin(defaults: defaults, enabled: false)
        inert.configureOnFirstLaunch()
        inert.setEnabled(true)
        inert.setEnabled(false)
        inert.refreshStatus()
        inert.openSystemSettings()
        XCTAssertFalse(inert.isEnabled)
        XCTAssertFalse(inert.requiresApproval)
        XCTAssertNil(defaults.object(forKey: "launchAtLoginConfigured"))

        var status: SMAppService.Status = .notRegistered
        var attempts = 0
        let model = LaunchAtLogin(defaults: defaults, readStatus: { status }, register: {
            attempts += 1
            if attempts == 1 { throw NSError(domain: "LaunchAtLoginTest", code: 1) }
            if attempts == 2 { status = .notFound }
            if attempts == 3 { status = .requiresApproval }
        }, unregister: {})
        model.configureOnFirstLaunch()
        XCTAssertFalse(model.isEnabled)
        XCTAssertTrue(model.statusMessage.contains("Não foi possível"))
        XCTAssertNil(defaults.object(forKey: "launchAtLoginConfigured"))
        model.configureOnFirstLaunch()
        XCTAssertFalse(model.isEnabled)
        XCTAssertTrue(model.statusMessage.contains("não confirmou"))
        XCTAssertNil(defaults.object(forKey: "launchAtLoginConfigured"))
        model.configureOnFirstLaunch()
        XCTAssertTrue(model.requiresApproval)
        XCTAssertTrue(defaults.bool(forKey: "launchAtLoginConfigured"))
        model.configureOnFirstLaunch()
        XCTAssertEqual(attempts, 3)
    }
}
