import Flutter
import UIKit

class ERoutePrivacy {
  static var sensitiveCount = 0
  static var sensitive: Bool { sensitiveCount > 0 }
  static var covers: [UIView] = []
  static func cover(_ window: UIWindow?) {
    guard sensitive, let window = window else { return }
    let view = UIView(frame: window.bounds)
    view.backgroundColor = UIColor.systemBackground
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(view)
    covers.append(view)
  }
  static func reveal() { covers.forEach { $0.removeFromSuperview() }; covers.removeAll() }
}
class SceneDelegate: FlutterSceneDelegate {
  override func sceneWillResignActive(_ scene: UIScene) {
    ERoutePrivacy.cover(window)
    super.sceneWillResignActive(scene)
  }
}
