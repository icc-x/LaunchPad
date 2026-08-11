import Testing
import Foundation
@testable import LaunchPad

@MainActor @Suite("生命周期安全：未安装服务时的安全行为")
struct LifecycleSafetyTests {

    private func makeBareDelegate() -> AppDelegate {
        let sut = AppDelegate()
        sut.activationPolicySetter = { _ in }
        sut.appTerminator = {}
        sut.mainAsyncRunner = { $0() }
        sut.workspaceURLOpener = { _ in }
        return sut
    }

    @Test("未安装 windowController 时 statusItemClicked 安全返回")
    func statusItemClicked_withoutWindowController_noCrash() {
        let sut = makeBareDelegate()
        sut.statusItemClicked()
    }

    @Test("未安装 hotkeyManager 时 setupHotkey 安全返回")
    func setupHotkey_withoutHotkeyManager_noCrash() {
        let sut = makeBareDelegate()
        sut.setupHotkey()
    }

    @Test("未安装 layoutRepository/iconCache 时 setupControllers 安全返回")
    func setupControllers_withoutServices_noCrash() {
        let sut = makeBareDelegate()
        sut.setupControllers()
        #expect(sut.viewController == nil)
    }

    @Test("databasePath 返回以 launchpad.db 结尾的确定性路径")
    func databasePath_deterministicSuffix() {
        let sut = makeBareDelegate()
        let path = sut.databasePath()
        #expect(path.hasSuffix("launchpad.db"))
        #expect(!path.isEmpty)
    }
}
