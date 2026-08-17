import Sparkle
import Observation

// Trampoline ObjC pour éviter le cycle d'init : on ne peut pas passer `self`
// comme delegate avant que toutes les stored properties soient initialisées.
// Ce petit objet tient une référence faible vers UpdaterController et relaie.
private final class SparkleDelegate: NSObject, SPUUpdaterDelegate {
    weak var owner: UpdaterController?

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor [weak self] in self?.owner?.updateAvailable = true }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor [weak self] in self?.owner?.updateAvailable = false }
    }
}

extension SparkleDelegate: @unchecked Sendable {}

@Observable
@MainActor
final class UpdaterController {
    private let controller: SPUStandardUpdaterController
    private let sparkleDelegate: SparkleDelegate
    var updateAvailable = false

    init() {
        let del = SparkleDelegate()
        sparkleDelegate = del
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: del,
            userDriverDelegate: nil
        )
        // self est totalement initialisé à ce stade
        del.owner = self
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
