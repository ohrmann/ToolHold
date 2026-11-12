#if os(iOS)
  import UIKit

  /// Route/preferences have an explicit allowlist; UIKit must not archive editor views.
  final class SessionRestorationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, shouldSaveSecureApplicationState coder: NSCoder)
      -> Bool
    { false }
    func application(
      _ application: UIApplication, shouldRestoreSecureApplicationState coder: NSCoder
    ) -> Bool { false }
  }
#endif
