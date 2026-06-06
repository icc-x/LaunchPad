import Foundation

/// Keyboard navigator — manages key behavior for idle/search/edit three-state modes
/// Pure logic, no UI framework dependency
public final class KeyboardNavigator {

    // MARK: - Mode (corresponds to section 13 three states)

    public enum Mode: Equatable {
        case idle
        case search(query: String)
        case edit
    }

    // MARK: - Key (abstract key)

    public enum Key: Equatable {
        case escape
        case leftArrow
        case rightArrow
        case upArrow
        case downArrow
        case enter
        case tab
        case delete
    }

    // MARK: - Action (navigator output)

    public enum Action: Equatable {
        case closeWindow
        case clearSearch
        case exitEditMode
        case previousPage
        case nextPage
        case moveUp
        case moveDown
        case launchSelected
        case launchFirstMatch
        case selectNext
        case enterSearchMode(String)
        case appendToQuery(String)
        case deleteLastCharacter
        case ignored
    }

    public var mode: Mode = .idle

    public init() {}

    // MARK: - Key Handling

    public func handleKey(_ key: Key) -> Action {
        switch mode {
        case .idle:
            return handleKeyInIdle(key)
        case .search:
            let action = handleKeyInSearch(key)
            // ESC-twice behavior: clear search and return to idle
            // so next ESC returns closeWindow
            if action == .clearSearch {
                mode = .idle
            }
            return action
        case .edit:
            return handleKeyInEdit(key)
        }
    }

    public func handleCharacter(_ char: String) -> Action {
        switch mode {
        case .idle:
            return .enterSearchMode(char)
        case .search(_):
            return .appendToQuery(char)
        case .edit:
            return .ignored
        }
    }

    // MARK: - Idle State

    private func handleKeyInIdle(_ key: Key) -> Action {
        switch key {
        case .escape: return .closeWindow
        case .leftArrow: return .previousPage
        case .rightArrow: return .nextPage
        case .upArrow: return .moveUp
        case .downArrow: return .moveDown
        case .enter: return .launchSelected
        case .tab: return .selectNext
        case .delete: return .ignored
        }
    }

    // MARK: - Search State

    private func handleKeyInSearch(_ key: Key) -> Action {
        switch key {
        case .escape: return .clearSearch
        case .enter: return .launchFirstMatch
        case .delete: return .deleteLastCharacter
        case .leftArrow, .rightArrow, .upArrow, .downArrow: return .ignored
        case .tab: return .ignored
        }
    }

    // MARK: - Edit State

    private func handleKeyInEdit(_ key: Key) -> Action {
        switch key {
        case .escape: return .exitEditMode
        default: return .ignored
        }
    }
}
