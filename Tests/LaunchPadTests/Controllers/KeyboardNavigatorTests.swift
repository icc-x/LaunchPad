import Testing
@testable import LaunchPad

@Suite("KeyboardNavigator keyboard navigation")
struct KeyboardNavigatorTests {

    private func makeSUT() -> KeyboardNavigator {
        KeyboardNavigator()
    }

    // MARK: - Idle state

    @Test("Idle state — ESC returns closeWindow action")
    func idle_esc_closeWindow() {
        let sut = makeSUT()
        sut.mode = .idle
        let action = sut.handleKey(.escape)
        #expect(action == .closeWindow)
    }

    @Test("Idle state — left arrow returns previousPage action")
    func idle_leftArrow_previousPage() {
        let sut = makeSUT()
        sut.mode = .idle
        let action = sut.handleKey(.leftArrow)
        #expect(action == .previousPage)
    }

    @Test("Idle state — right arrow returns nextPage action")
    func idle_rightArrow_nextPage() {
        let sut = makeSUT()
        sut.mode = .idle
        let action = sut.handleKey(.rightArrow)
        #expect(action == .nextPage)
    }

    @Test("Idle state — up arrow returns moveUp action")
    func idle_upArrow_moveUp() {
        let sut = makeSUT()
        sut.mode = .idle
        let action = sut.handleKey(.upArrow)
        #expect(action == .moveUp)
    }

    @Test("Idle state — down arrow returns moveDown action")
    func idle_downArrow_moveDown() {
        let sut = makeSUT()
        sut.mode = .idle
        let action = sut.handleKey(.downArrow)
        #expect(action == .moveDown)
    }

    @Test("Idle state — Enter returns launchSelected action")
    func idle_enter_launchSelected() {
        let sut = makeSUT()
        sut.mode = .idle
        let action = sut.handleKey(.enter)
        #expect(action == .launchSelected)
    }

    @Test("Idle state — Tab returns selectNext action")
    func idle_tab_selectNext() {
        let sut = makeSUT()
        sut.mode = .idle
        let action = sut.handleKey(.tab)
        #expect(action == .selectNext)
    }

    @Test("Idle state — character key returns enterSearchMode action")
    func idle_character_enterSearchMode() {
        let sut = makeSUT()
        sut.mode = .idle
        let action = sut.handleCharacter("s")
        #expect(action == .enterSearchMode("s"))
    }

    @Test("idle 首字符进入搜索态，后续字符追加")
    func firstAndFollowingCharactersUpdateMode() {
        let sut = KeyboardNavigator()
        #expect(sut.handleCharacter("s") == .enterSearchMode("s"))
        #expect(sut.mode == .search(query: "s"))
        #expect(sut.handleCharacter("a") == .appendToQuery("a"))
        #expect(sut.mode == .search(query: "sa"))
    }

    @Test("搜索态 Delete 同步缩短查询")
    func deleteUpdatesQuery() {
        let sut = KeyboardNavigator()
        sut.mode = .search(query: "saf")
        #expect(sut.handleKey(.delete) == .deleteLastCharacter)
        #expect(sut.mode == .search(query: "sa"))
    }

    @Test("空字符串输入被忽略且不改变模式")
    func emptyCharacterIsIgnored() {
        let sut = KeyboardNavigator()
        #expect(sut.handleCharacter("") == .ignored)
        #expect(sut.mode == .idle)
    }

    // MARK: - Search state

    @Test("Search state — ESC returns clearSearch action")
    func search_esc_clearSearch() {
        let sut = makeSUT()
        sut.mode = .search(query: "test")
        let action = sut.handleKey(.escape)
        #expect(action == .clearSearch)
    }

    @Test("Search state — character key returns appendToQuery action")
    func search_character_appendToQuery() {
        let sut = makeSUT()
        sut.mode = .search(query: "te")
        let action = sut.handleCharacter("s")
        #expect(action == .appendToQuery("s"))
    }

    @Test("Search state — Delete returns deleteLastCharacter action")
    func search_delete_deleteLastCharacter() {
        let sut = makeSUT()
        sut.mode = .search(query: "test")
        let action = sut.handleKey(.delete)
        #expect(action == .deleteLastCharacter)
    }

    @Test("Search state — Enter returns launchFirstMatch action")
    func search_enter_launchFirstMatch() {
        let sut = makeSUT()
        sut.mode = .search(query: "saf")
        let action = sut.handleKey(.enter)
        #expect(action == .launchFirstMatch)
    }

    @Test("Search state — Space returns appendSpace action")
    func search_space_appendSpace() {
        let sut = makeSUT()
        sut.mode = .search(query: "final")
        let action = sut.handleCharacter(" ")
        #expect(action == .appendToQuery(" "))
    }

    @Test("Search state — arrow keys are ignored")
    func search_arrows_ignored() {
        let sut = makeSUT()
        sut.mode = .search(query: "test")
        #expect(sut.handleKey(.leftArrow) == .ignored)
        #expect(sut.handleKey(.rightArrow) == .ignored)
        #expect(sut.handleKey(.upArrow) == .ignored)
        #expect(sut.handleKey(.downArrow) == .ignored)
    }

    @Test("Search state — Tab is ignored")
    func search_tab_ignored() {
        let sut = makeSUT()
        sut.mode = .search(query: "test")
        let action = sut.handleKey(.tab)
        #expect(action == .ignored)
    }

    @Test("Search state — ESC twice: first clearSearch, second closeWindow")
    func search_escTwice_closeWindow() {
        let sut = makeSUT()
        sut.mode = .search(query: "test")
        let firstEsc = sut.handleKey(.escape)
        #expect(firstEsc == .clearSearch)
        #expect(sut.mode == .idle)
        let secondEsc = sut.handleKey(.escape)
        #expect(secondEsc == .closeWindow)
    }

    // MARK: - Edit mode

    @Test("Edit mode — ESC returns exitEditMode action")
    func edit_esc_exitEditMode() {
        let sut = makeSUT()
        sut.mode = .edit
        let action = sut.handleKey(.escape)
        #expect(action == .exitEditMode)
    }

    @Test("Edit mode — most keys are ignored")
    func edit_mostKeys_ignored() {
        let sut = makeSUT()
        sut.mode = .edit
        #expect(sut.handleCharacter("a") == .ignored)
        #expect(sut.handleKey(.enter) == .ignored)
        #expect(sut.handleKey(.leftArrow) == .ignored)
    }
}
