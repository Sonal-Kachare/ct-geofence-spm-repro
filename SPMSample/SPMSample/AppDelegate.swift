
import UIKit
import CleverTapGeofence

// The import above is the point of this sample. It forces the CleverTapGeofence
// SPM product to be resolved, compiled, and linked into the app binary, so a
// green build here proves the whole SPM consumption path works and not merely
// that dependency resolution succeeded.
//
// Note: actually *running* this app would additionally need CleverTap
// credentials in Info.plist and a call to CleverTap.autoIntegrate(). CI only
// builds, so none of that is required here.

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        CleverTapGeofence.logLevel = .debug
        CleverTapGeofence.monitor.start(didFinishLaunchingWithOptions: launchOptions)

        return true
    }

    func someScenarioWhereLocationMonitoringShouldBeOff() {
        CleverTapGeofence.monitor.stop()
    }
}
