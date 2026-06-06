import Testing
@testable import LaunchPad

@Suite("Smoke Test")
struct SmokeTest {
    @Test("项目可编译，测试可运行")
    func projectCompiles() {
        #expect(LaunchPadApp.version == "0.1.0")
    }
}
