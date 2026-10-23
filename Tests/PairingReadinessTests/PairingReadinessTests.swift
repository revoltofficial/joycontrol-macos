import XCTest
@testable import JoycontrolMacos

final class PairingReadinessTests: XCTestCase {
    func testPublishedServiceDoesNotImplyRadioReady() {
        let state = PairingReadiness(name: "MacBook", deviceClass: 0x010c, scanReadStatus: 0, scanMode: 0)
        XCTAssertEqual(state.blockers.count, 3)
    }
    func testUnsupportedReadNeverPassesEvenWithStaleScanValue() {
        let state = PairingReadiness(name: "Pro Controller", deviceClass: 0x0508, scanReadStatus: -536870201, scanMode: 3)
        XCTAssertEqual(state.blockers, ["scan mode could not be verified"])
    }
    func testPageScanAloneIsInsufficient() {
        XCTAssertFalse(PairingReadiness(name: "Pro Controller", deviceClass: 0x0508, scanReadStatus: 0, scanMode: 2).blockers.isEmpty)
    }
    func testMatchingIdentityAndBothScansPass() {
        XCTAssertTrue(PairingReadiness(name: "Pro Controller", deviceClass: 0x0508, scanReadStatus: 0, scanMode: 3).blockers.isEmpty)
    }
    func testAdditionalServiceClassBitsAreAllowed() {
        XCTAssertTrue(PairingReadiness(name: "Pro Controller", deviceClass: 0x200508, scanReadStatus: 0, scanMode: 3).blockers.isEmpty)
    }
}
