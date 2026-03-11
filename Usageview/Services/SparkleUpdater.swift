import Foundation
import SwiftUI

#if !MAS
import Sparkle

/// Wraps Sparkle's `SPUStandardUpdaterController` so
/// SwiftUI views can trigger "Check for Updates" with a simple binding.
@Observable
@MainActor
final class SparkleUpdater {
    private let controller: SPUStandardUpdaterController

    var canCheckForUpdates: Bool = false
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        // Sparkle needs a tick to initialise; observe real property
        canCheckForUpdates = controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
#else
/// No-op stub used for Mac App Store builds (Sparkle not permitted on MAS).
@Observable
@MainActor
final class SparkleUpdater {
    var canCheckForUpdates: Bool = false
    var automaticallyChecksForUpdates: Bool = false
    init() {}
    func checkForUpdates() {}
}
#endif
