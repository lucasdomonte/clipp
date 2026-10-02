import XCTest
import UserNotifications
@testable import Clipp

final class CopyFeedbackTests: XCTestCase {
    @MainActor
    func testOnlyUndeterminedAuthorizationRequestsPermissionAgain() {
        XCTAssertTrue(CopyFeedback.shouldRequestAuthorization(for: .notDetermined))
        for status in [UNAuthorizationStatus.denied, .authorized, .provisional] {
            XCTAssertFalse(CopyFeedback.shouldRequestAuthorization(for: status))
        }
    }

    @MainActor
    func testNotificationPreviewRespectsPreferenceAndCharacterLimit() {
        XCTAssertEqual(CopyFeedback.notificationBody(kind: .text, text: "Texto copiado", showCopiedText: true), "Texto copiado")
        let hiddenPreviews: [(ClipboardKind, String?, Bool)] = [
            (.text, "Texto privado", false), (.image, "Imagem", true),
            (.text, nil, true), (.text, "", true)
        ]
        for (kind, text, showCopiedText) in hiddenPreviews {
            XCTAssertEqual(CopyFeedback.notificationBody(kind: kind, text: text, showCopiedText: showCopiedText), "Disponível para colar.")
        }
        let preview = String(repeating: "👨‍👩‍👧‍👦", count: 300)
        XCTAssertEqual(CopyFeedback.notificationBody(kind: .text, text: preview, showCopiedText: true), preview)
        XCTAssertEqual(CopyFeedback.notificationBody(kind: .text, text: preview + "á", showCopiedText: true), preview + "…")
    }

    @MainActor
    func testDisabledAndUnbundledFeedbackNeverRequestsPermissionOrPlaysSound() async {
        XCTAssertNotEqual(Bundle.main.bundleIdentifier, "br.com.clipp.app")
        for enabled in [false, true] {
            let feedback = CopyFeedback(enabled: enabled)
            let description = feedback.authorizationDescription
            await feedback.refreshAuthorization()
            await feedback.requestAuthorization()
            await feedback.notify(kind: .text, text: "Texto copiado", showCopiedText: true, notifications: true, sound: true)
            await feedback.notify(kind: .image, text: nil, showCopiedText: true, notifications: true, sound: true)
            XCTAssertFalse(feedback.notificationsAllowed)
            XCTAssertFalse(feedback.needsSystemSettings)
            XCTAssertEqual(feedback.authorizationDescription, description)
        }
    }
}
