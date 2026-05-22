import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.playback, mode: .default, options: [])
      try audioSession.setActive(true)
    } catch {
      NSLog("LEXO audio session setup failed: \(error.localizedDescription)")
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
