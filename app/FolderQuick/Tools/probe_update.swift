import AppKit
import Sparkle

// Tests Sparkle's actual signed-feed and version selection without installing an app.
final class Probe: NSObject, SPUUpdaterDelegate {
    let feedURL: String
    var foundVersion: String?
    var failure: Error?
    var finished = false

    init(feedURL: String) { self.feedURL = feedURL }

    func feedURLString(for updater: SPUUpdater) -> String? { feedURL }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        foundVersion = item.versionString
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error, (error as NSError).code != 1001 { failure = error }
        finished = true
    }
}

guard CommandLine.arguments.count == 4,
      let bundle = Bundle(path: CommandLine.arguments[1]) else {
    fatalError("Usage: probe_update /path/to/test.app http://localhost:port/appcast.xml expected-build|none|error")
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let probe = Probe(feedURL: CommandLine.arguments[2])
let driver = SPUStandardUserDriver(hostBundle: bundle, delegate: nil)
let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: probe)
try updater.start()
updater.checkForUpdateInformation()
let deadline = Date().addingTimeInterval(15)
while !probe.finished && Date() < deadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
}
guard probe.finished else { fatalError("Update probe timed out") }
let expected = CommandLine.arguments[3]
if expected == "error" {
    guard let error = probe.failure else { fatalError("Invalid feed was accepted") }
    print("PASS: rejected invalid feed: \(error.localizedDescription)")
} else {
    if let failure = probe.failure { fatalError("Update probe failed: \(failure)") }
    guard probe.foundVersion == (expected == "none" ? nil : expected) else {
        fatalError("Expected \(expected), found \(probe.foundVersion ?? "none")")
    }
    print("PASS: update probe found \(probe.foundVersion ?? "no newer version")")
}
