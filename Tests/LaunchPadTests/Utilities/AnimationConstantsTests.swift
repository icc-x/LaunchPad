import Testing
import Foundation
import CoreGraphics
@testable import LaunchPad

@Suite("AnimationConstants animation parameters")
struct AnimationConstantsTests {

    // MARK: - All durations > 0

    @Test("Window expand animation duration > 0")
    func windowExpand_duration_positive() {
        #expect(AnimationConstants.windowExpand.duration > 0)
    }

    @Test("Window collapse animation duration > 0")
    func windowCollapse_duration_positive() {
        #expect(AnimationConstants.windowCollapse.duration > 0)
    }

    @Test("App launch animation duration > 0")
    func appLaunch_duration_positive() {
        #expect(AnimationConstants.appLaunch.duration > 0)
    }

    @Test("Page scroll animation duration > 0")
    func pageScroll_duration_positive() {
        #expect(AnimationConstants.pageScroll.duration > 0)
    }

    @Test("Icon entrance animation duration > 0")
    func iconEntrance_duration_positive() {
        #expect(AnimationConstants.iconEntrance.duration > 0)
    }

    @Test("Jiggle animation duration > 0")
    func jiggle_duration_positive() {
        #expect(AnimationConstants.jiggle.duration > 0)
    }

    @Test("Folder expand animation duration > 0")
    func folderExpand_duration_positive() {
        #expect(AnimationConstants.folderExpand.duration > 0)
    }

    @Test("Folder collapse animation duration > 0")
    func folderCollapse_duration_positive() {
        #expect(AnimationConstants.folderCollapse.duration > 0)
    }

    @Test("Delete animation duration > 0")
    func delete_duration_positive() {
        #expect(AnimationConstants.delete.duration > 0)
    }

    @Test("Drag displace animation duration > 0")
    func dragDisplace_duration_positive() {
        #expect(AnimationConstants.dragDisplace.duration > 0)
    }

    // MARK: - Exact match with design document section 12

    @Test("Window expand duration = 0.35s")
    func windowExpand_duration_exact() {
        #expect(AnimationConstants.windowExpand.duration == 0.35)
    }

    @Test("Window collapse duration = 0.25s")
    func windowCollapse_duration_exact() {
        #expect(AnimationConstants.windowCollapse.duration == 0.25)
    }

    @Test("App launch duration = 0.3s")
    func appLaunch_duration_exact() {
        #expect(AnimationConstants.appLaunch.duration == 0.3)
    }

    @Test("Page scroll duration = 0.35s")
    func pageScroll_duration_exact() {
        #expect(AnimationConstants.pageScroll.duration == 0.35)
    }

    @Test("Icon entrance duration = 0.3s")
    func iconEntrance_duration_exact() {
        #expect(AnimationConstants.iconEntrance.duration == 0.3)
    }

    @Test("Jiggle duration = 0.13s")
    func jiggle_duration_exact() {
        #expect(AnimationConstants.jiggle.duration == 0.13)
    }

    @Test("Folder expand duration = 0.25s")
    func folderExpand_duration_exact() {
        #expect(AnimationConstants.folderExpand.duration == 0.25)
    }

    @Test("Folder collapse duration = 0.2s")
    func folderCollapse_duration_exact() {
        #expect(AnimationConstants.folderCollapse.duration == 0.2)
    }

    @Test("Delete duration = 0.3s")
    func delete_duration_exact() {
        #expect(AnimationConstants.delete.duration == 0.3)
    }

    @Test("Drag displace duration = 0.25s")
    func dragDisplace_duration_exact() {
        #expect(AnimationConstants.dragDisplace.duration == 0.25)
    }

    // MARK: - Timing type verification

    @Test("Window expand uses Spring timing")
    func windowExpand_timing_spring() {
        #expect(AnimationConstants.windowExpand.timing == .spring(damping: 0.75))
    }

    @Test("Window collapse uses EaseOut timing")
    func windowCollapse_timing_easeOut() {
        #expect(AnimationConstants.windowCollapse.timing == .easeOut)
    }

    @Test("Page scroll uses EaseInOut timing")
    func pageScroll_timing_easeInOut() {
        #expect(AnimationConstants.pageScroll.timing == .easeInOut)
    }

    @Test("Jiggle uses Autoreverse timing")
    func jiggle_timing_autoreverse() {
        #expect(AnimationConstants.jiggle.timing == .autoreverse)
    }

    // MARK: - Reduce Motion fallback verification

    @Test("All animations have Reduce Motion fallback defined")
    func allAnimations_haveReduceMotionFallback() {
        let allAnimations: [(String, AnimationConstants.Animation)] = [
            ("windowExpand", AnimationConstants.windowExpand),
            ("windowCollapse", AnimationConstants.windowCollapse),
            ("appLaunch", AnimationConstants.appLaunch),
            ("pageScroll", AnimationConstants.pageScroll),
            ("iconEntrance", AnimationConstants.iconEntrance),
            ("jiggle", AnimationConstants.jiggle),
            ("folderExpand", AnimationConstants.folderExpand),
            ("folderCollapse", AnimationConstants.folderCollapse),
            ("delete", AnimationConstants.delete),
            ("dragDisplace", AnimationConstants.dragDisplace),
        ]

        for (name, animation) in allAnimations {
            #expect(animation.reduceMotionFallback != nil,
                    "\(name) missing Reduce Motion fallback definition")
        }
    }

    @Test("Reduce Motion fallback durations all > 0 (except instant)")
    func reduceMotionFallbacks_positiveDuration() {
        let animations = [
            AnimationConstants.windowExpand,
            AnimationConstants.windowCollapse,
            AnimationConstants.folderExpand,
            AnimationConstants.folderCollapse,
        ]

        for animation in animations {
            if case .fade(let duration) = animation.reduceMotionFallback {
                #expect(duration > 0)
            }
        }
    }

    @Test("Window expand Reduce Motion fallback is Fade 0.2s")
    func windowExpand_reduceMotion_fade02() {
        #expect(AnimationConstants.windowExpand.reduceMotionFallback == .fade(duration: 0.2))
    }

    @Test("Window collapse Reduce Motion fallback is Fade 0.2s")
    func windowCollapse_reduceMotion_fade02() {
        #expect(AnimationConstants.windowCollapse.reduceMotionFallback == .fade(duration: 0.2))
    }

    @Test("App launch Reduce Motion fallback is instant")
    func appLaunch_reduceMotion_instant() {
        #expect(AnimationConstants.appLaunch.reduceMotionFallback == .instant)
    }

    @Test("Page scroll Reduce Motion fallback is instant")
    func pageScroll_reduceMotion_instant() {
        #expect(AnimationConstants.pageScroll.reduceMotionFallback == .instant)
    }

    @Test("Icon entrance Reduce Motion fallback is direct display")
    func iconEntrance_reduceMotion_instant() {
        #expect(AnimationConstants.iconEntrance.reduceMotionFallback == .instant)
    }

    @Test("Jiggle Reduce Motion fallback is scale pulse")
    func jiggle_reduceMotion_scalePulse() {
        #expect(AnimationConstants.jiggle.reduceMotionFallback == .scalePulse)
    }

    @Test("Folder expand Reduce Motion fallback is Fade 0.15s")
    func folderExpand_reduceMotion_fade015() {
        #expect(AnimationConstants.folderExpand.reduceMotionFallback == .fade(duration: 0.15))
    }

    @Test("Folder collapse Reduce Motion fallback is Fade 0.15s")
    func folderCollapse_reduceMotion_fade015() {
        #expect(AnimationConstants.folderCollapse.reduceMotionFallback == .fade(duration: 0.15))
    }

    @Test("Delete Reduce Motion fallback is instant")
    func delete_reduceMotion_instant() {
        #expect(AnimationConstants.delete.reduceMotionFallback == .instant)
    }

    @Test("Drag displace Reduce Motion fallback is instant")
    func dragDisplace_reduceMotion_instant() {
        #expect(AnimationConstants.dragDisplace.reduceMotionFallback == .instant)
    }

    // MARK: - Spring parameter verification

    @Test("Window expand Spring damping = 0.75")
    func windowExpand_springDamping() {
        if case .spring(let damping) = AnimationConstants.windowExpand.timing {
            #expect(damping == 0.75)
        } else {
            Issue.record("Window expand should use Spring timing")
        }
    }

    @Test("Icon entrance Spring damping = 0.8")
    func iconEntrance_springDamping() {
        if case .spring(let damping) = AnimationConstants.iconEntrance.timing {
            #expect(damping == 0.8)
        } else {
            Issue.record("Icon entrance should use Spring timing")
        }
    }

    @Test("Drag displace Spring damping = 0.85")
    func dragDisplace_springDamping() {
        if case .spring(let damping) = AnimationConstants.dragDisplace.timing {
            #expect(damping == 0.85)
        } else {
            Issue.record("Drag displace should use Spring timing")
        }
    }

    // MARK: - Jiggle parameter verification

    @Test("Jiggle rotation range 2~3 degrees")
    func jiggle_rotationRange() {
        #expect(AnimationConstants.jiggleMinRotation == 2.0)
        #expect(AnimationConstants.jiggleMaxRotation == 3.0)
    }

    @Test("Icon entrance delay coefficient > 0")
    func iconEntrance_delayPerColumn_positive() {
        #expect(AnimationConstants.iconEntranceDelayPerColumn > 0)
    }

    @Test("Icon entrance delay coefficient = 0.02s")
    func iconEntrance_delayPerColumn_exact() {
        #expect(AnimationConstants.iconEntranceDelayPerColumn == 0.02)
    }
}
