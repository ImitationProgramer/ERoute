import Flutter
import UIKit
import MessageUI

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, MFMessageComposeViewControllerDelegate {
  private var smsComposer: MFMessageComposeViewController?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ERouteEmergencyDialer")!
    let privacyChannel = FlutterMethodChannel(name: "eroute/privacy", binaryMessenger: registrar.messenger())
    privacyChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "setSensitive":
        if call.arguments as? Bool == true { ERoutePrivacy.sensitiveCount += 1 }
        else { ERoutePrivacy.sensitiveCount = max(0, ERoutePrivacy.sensitiveCount - 1) }
        if !ERoutePrivacy.sensitive { ERoutePrivacy.reveal() }
        result(nil)
      case "allowDisplay": ERoutePrivacy.reveal(); result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    let smsChannel = FlutterMethodChannel(name: "eroute/emergency_sms", binaryMessenger: registrar.messenger())
    smsChannel.setMethodCallHandler { [weak self] call, result in
      if call.method == "canCompose" { result(MFMessageComposeViewController.canSendText()); return }
      guard call.method == "compose" else { result(FlutterMethodNotImplemented); return }
      guard let self = self, self.smsComposer == nil,
            UIApplication.shared.applicationState == .active,
            MFMessageComposeViewController.canSendText(),
            let args = call.arguments as? [String: Any],
            let encoded = args["encodedBody"] as? String,
            let body = encoded.removingPercentEncoding,
            var presenter = (UIApplication.shared.connectedScenes
              .compactMap { $0 as? UIWindowScene }
              .filter { $0.activationState == .foregroundActive }
              .flatMap { $0.windows }
              .first { $0.isKeyWindow })?.rootViewController else { result(false); return }
      while let presented = presenter.presentedViewController { presenter = presented }
      guard presenter.viewIfLoaded?.window != nil,
            !presenter.isBeingDismissed, !presenter.isBeingPresented,
            presenter.transitionCoordinator == nil else { result(false); return }
      let composer = MFMessageComposeViewController()
      composer.messageComposeDelegate = self
      composer.recipients = ["119"]
      composer.body = body
      self.smsComposer = composer
      // Exactly one channel reply on successful presentation. The delegate only
      // clears/dismisses; it never replies a second time on cancel or completion.
      presenter.present(composer, animated: true) { result(true) }
    }
    let channel = FlutterMethodChannel(name: "eroute/emergency_dialer", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(false); return }
      switch call.method {
      case "isSystemDialerAllowed": result(self.systemDialerAllowed())
      case "openEmergencyDialScreen":
        guard self.systemDialerAllowed(), let url = URL(string: "tel:119") else {
          result(false); return
        }
        // Reached only after the ERoute confirmation. iOS owns the final call prompt.
        UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                    didFinishWith result: MessageComposeResult) {
    controller.body = nil
    controller.recipients = nil
    controller.dismiss(animated: true) { [weak self] in self?.smsComposer = nil }
  }

  private func systemDialerAllowed() -> Bool {
    #if targetEnvironment(simulator) || DEBUG
    return false
    #else
    let info = Bundle.main.infoDictionary ?? [:]
    let env = ProcessInfo.processInfo.environment
    return info["ERouteDistribution"] as? String == "production" &&
      info["ERouteBuildMode"] as? String == "release" &&
      info["ERouteEmergencyEnabled"] as? String == "true" &&
      info["ERouteAutomation"] as? String == "false" &&
      env["XCTestConfigurationFilePath"] == nil && env["CI"] == nil &&
      NSClassFromString("XCTestCase") == nil
    #endif
  }
}
