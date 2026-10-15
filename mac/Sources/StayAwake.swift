import Foundation
import IOKit.pwr_mgt

/// Stepped out: the Mac never goes to sleep and the screen never goes off,
/// the same as `caffeinate -di`, for as long as the mode is on.
///
/// Two power assertions, held by this process. `pmset -g assertions` lists
/// them under "Screen Cat: stepped out". The kernel drops them when the app
/// quits or crashes, so a dead cat can never keep the Mac awake.
///
/// Closing the lid still sleeps the Mac on battery. Only a charger plus an
/// external display keeps a closed MacBook awake, and that is macOS, not us.
enum StayAwake {
    private static var held: [IOPMAssertionID] = []

    static var isOn: Bool { !held.isEmpty }

    static func set(_ on: Bool) {
        guard on != isOn else { return }
        guard on else {
            held.forEach { IOPMAssertionRelease($0) }
            held = []
            return
        }
        let reason = "Screen Cat: stepped out" as CFString
        for type in [kIOPMAssertionTypePreventUserIdleSystemSleep,
                     kIOPMAssertionTypePreventUserIdleDisplaySleep] {
            var id = IOPMAssertionID(0)
            if IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                           reason, &id) == kIOReturnSuccess {
                held.append(id)
            }
        }
    }
}
