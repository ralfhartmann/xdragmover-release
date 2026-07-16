import XCTest
import CoreGraphics
@testable import XDragMover

final class GestureModifierTests: XCTestCase {

    func test_isValid_shiftAlone_isInvalid() {
        XCTAssertFalse(GestureModifier.shift.isValid)
    }

    func test_isValid_empty_isInvalid() {
        let empty: GestureModifier = []
        XCTAssertFalse(empty.isValid)
    }

    func test_isValid_commandAlone_isValid() {
        XCTAssertTrue(GestureModifier.command.isValid)
    }

    func test_isValid_optionAlone_isValid() {
        XCTAssertTrue(GestureModifier.option.isValid)
    }

    func test_isValid_controlAlone_isValid() {
        XCTAssertTrue(GestureModifier.control.isValid)
    }

    func test_isValid_shiftCombinedWithAnother_isValid() {
        let modifier: GestureModifier = [.shift, .command]
        XCTAssertTrue(modifier.isValid)
    }

    func test_isValid_multipleNonShift_isValid() {
        let modifier: GestureModifier = [.command, .option, .control]
        XCTAssertTrue(modifier.isValid)
    }

    func test_isSatisfied_matchingSingleModifier() {
        XCTAssertTrue(GestureModifier.command.isSatisfied(by: .maskCommand))
    }

    func test_isSatisfied_missingModifier_isFalse() {
        XCTAssertFalse(GestureModifier.command.isSatisfied(by: .maskAlternate))
    }

    func test_isSatisfied_extraUnrelatedFlagsStillMatch() {
        let flags: CGEventFlags = [.maskCommand, .maskAlphaShift]
        XCTAssertTrue(GestureModifier.command.isSatisfied(by: flags))
    }

    func test_isSatisfied_combinationRequiresAllBits() {
        let modifier: GestureModifier = [.command, .option]
        XCTAssertFalse(modifier.isSatisfied(by: .maskCommand))
        XCTAssertTrue(modifier.isSatisfied(by: [.maskCommand, .maskAlternate]))
    }

    func test_defaultValue_isCommand() {
        XCTAssertEqual(GestureModifier.defaultValue, .command)
    }
}
