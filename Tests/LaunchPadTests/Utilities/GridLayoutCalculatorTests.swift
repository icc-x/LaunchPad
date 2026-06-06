import Testing
import CoreGraphics
@testable import LaunchPad

@Suite("GridLayoutCalculator 纯函数")
struct GridLayoutCalculatorTests {

    @Test("1440px 宽度 → 7 列")
    func columns_1440px() {
        let result = GridLayoutCalculator.calculate(screenWidth: 1440)
        #expect(result.columns == 7)
    }

    @Test("1728px 宽度 → 9 列")
    func columns_1728px() {
        let result = GridLayoutCalculator.calculate(screenWidth: 1728)
        #expect(result.columns == 9)
    }

    @Test("2560px 宽度 → 10 列")
    func columns_2560px() {
        let result = GridLayoutCalculator.calculate(screenWidth: 2560)
        #expect(result.columns == 10)
    }

    @Test("1280px 宽度（小屏）→ 7 列")
    func columns_smallScreen() {
        let result = GridLayoutCalculator.calculate(screenWidth: 1280)
        #expect(result.columns == 7)
    }

    @Test("1920px 宽度（中大屏）→ 10 列")
    func columns_1920px() {
        let result = GridLayoutCalculator.calculate(screenWidth: 1920)
        #expect(result.columns == 10)
    }

    @Test("所有宽度固定 5 行")
    func rows_always5() {
        for width: CGFloat in [1280, 1440, 1728, 1920, 2560, 3840] {
            let result = GridLayoutCalculator.calculate(screenWidth: width)
            #expect(result.rows == 5, "宽度 \(width) 应始终 5 行")
        }
    }

    @Test("每页数量 = 列数 × 行数")
    func itemsPerPage_equalsColumnsTimesRows() {
        for width: CGFloat in [1440, 1728, 2560] {
            let result = GridLayoutCalculator.calculate(screenWidth: width)
            #expect(result.itemsPerPage == result.columns * result.rows)
        }
    }

    @Test("1440px → 35 每页")
    func itemsPerPage_1440px() {
        #expect(GridLayoutCalculator.calculate(screenWidth: 1440).itemsPerPage == 35)
    }

    @Test("1728px → 45 每页")
    func itemsPerPage_1728px() {
        #expect(GridLayoutCalculator.calculate(screenWidth: 1728).itemsPerPage == 45)
    }

    @Test("2560px → 50 每页")
    func itemsPerPage_2560px() {
        #expect(GridLayoutCalculator.calculate(screenWidth: 2560).itemsPerPage == 50)
    }

    @Test("图标尺寸在 64~96pt 范围内")
    func iconSize_withinBounds() {
        for width: CGFloat in [1280, 1440, 1728, 1920, 2560, 3840] {
            let result = GridLayoutCalculator.calculate(screenWidth: width)
            #expect(result.iconSize >= 64, "宽度 \(width) 图标尺寸 \(result.iconSize) 应 >= 64")
            #expect(result.iconSize <= 96, "宽度 \(width) 图标尺寸 \(result.iconSize) 应 <= 96")
        }
    }

    @Test("未 clamp 时：总宽度 = 列数×图标 + (列数-1)×间距 + 2×边距")
    func spacing_mathChecksOut_noClamp() {
        let result = GridLayoutCalculator.calculate(screenWidth: 688)
        let totalWidth = CGFloat(result.columns) * result.iconSize
            + CGFloat(result.columns - 1) * result.spacing
            + 2 * result.horizontalMargin
        #expect(abs(totalWidth - 688) < 1.0, "总宽度应约等于屏幕宽度")
    }

    @Test("标准宽度下图标被 clamp 到 96pt，间距公式仍正确")
    func spacing_standardWidth_clampedIconSize() {
        let result = GridLayoutCalculator.calculate(screenWidth: 1440)
        #expect(result.iconSize == 96, "1440px 宽度下图标应被 clamp 到 96pt")
        let usedWidth = CGFloat(result.columns) * result.iconSize
            + CGFloat(result.columns - 1) * result.spacing
            + 2 * result.horizontalMargin
        #expect(usedWidth <= 1440, "使用的宽度不应超过屏幕宽度")
    }

    @Test("图标间距为 20pt")
    func spacing_default20() {
        let result = GridLayoutCalculator.calculate(screenWidth: 1440)
        #expect(result.spacing == 20)
    }
}
