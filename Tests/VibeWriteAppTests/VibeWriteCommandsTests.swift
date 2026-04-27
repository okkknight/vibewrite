import XCTest
@testable import VibeWriteApp

@MainActor
final class VibeWriteCommandsTests: XCTestCase {
    @MainActor
    private final class UndoableBox: NSObject {
        private(set) var value = 0

        @MainActor
        func setValue(_ newValue: Int, using undoManager: UndoManager) {
            let oldValue = value
            value = newValue
            undoManager.registerUndo(withTarget: self) { target in
                target.setValue(oldValue, using: undoManager)
            }
        }
    }

    func testPerformNativeUndoUsesUndoManagerWhenUndoIsAvailable() {
        let undoManager = UndoManager()
        var didUndo = false

        undoManager.registerUndo(withTarget: self) { _ in
            didUndo = true
        }

        let handled = VibeWriteCommands.performNativeUndo {
            undoManager
        }

        XCTAssertTrue(handled)
        XCTAssertTrue(didUndo)
    }

    func testPerformNativeUndoReturnsFalseWhenUndoIsUnavailable() {
        XCTAssertFalse(VibeWriteCommands.performNativeUndo { UndoManager() })
        XCTAssertFalse(VibeWriteCommands.performNativeUndo { nil })
    }

    func testPerformNativeRedoUsesUndoManagerWhenRedoIsAvailable() {
        let undoManager = UndoManager()
        let box = UndoableBox()

        box.setValue(1, using: undoManager)
        undoManager.undo()

        let handled = VibeWriteCommands.performNativeRedo {
            undoManager
        }

        XCTAssertTrue(handled)
        XCTAssertEqual(box.value, 1)
    }

    func testPerformNativeRedoReturnsFalseWhenRedoIsUnavailable() {
        XCTAssertFalse(VibeWriteCommands.performNativeRedo { UndoManager() })
        XCTAssertFalse(VibeWriteCommands.performNativeRedo { nil })
    }
}
