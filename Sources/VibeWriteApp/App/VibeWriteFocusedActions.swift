import SwiftUI

struct VibeWriteUndoActionKey: FocusedValueKey {
    typealias Value = () -> Bool
}

extension FocusedValues {
    var vibeWriteUndoAction: (() -> Bool)? {
        get { self[VibeWriteUndoActionKey.self] }
        set { self[VibeWriteUndoActionKey.self] = newValue }
    }
}
