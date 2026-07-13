import Flutter
import UIKit

/// iOS is not implemented yet (Android-only for now, per project scope).
/// Every method call resolves as not-implemented and every event stream
/// closes immediately with an error, rather than hanging silently — see the
/// plugin README for the follow-up work needed (AVAudioSession-based HFP/A2DP
/// routing and the DAT camera APIs).
public class FlutterMetaWearablesDatPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let notImplementedHandler: (FlutterMethodCall, @escaping FlutterResult) -> Void = { _, result in
      result(FlutterMethodNotImplemented)
    }
    let notImplementedStream = NotImplementedStreamHandler()

    let cameraChannel = FlutterMethodChannel(
      name: "flutter_meta_wearables_dat/camera", binaryMessenger: registrar.messenger())
    cameraChannel.setMethodCallHandler(notImplementedHandler)

    let audioChannel = FlutterMethodChannel(
      name: "flutter_meta_wearables_dat/audio", binaryMessenger: registrar.messenger())
    audioChannel.setMethodCallHandler(notImplementedHandler)

    FlutterEventChannel(
      name: "flutter_meta_wearables_dat/camera_frames", binaryMessenger: registrar.messenger()
    ).setStreamHandler(notImplementedStream)
    FlutterEventChannel(
      name: "flutter_meta_wearables_dat/camera_state", binaryMessenger: registrar.messenger()
    ).setStreamHandler(notImplementedStream)
    FlutterEventChannel(
      name: "flutter_meta_wearables_dat/mic_audio", binaryMessenger: registrar.messenger()
    ).setStreamHandler(notImplementedStream)
    FlutterEventChannel(
      name: "flutter_meta_wearables_dat/audio_state", binaryMessenger: registrar.messenger()
    ).setStreamHandler(notImplementedStream)
  }
}

private class NotImplementedStreamHandler: NSObject, FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    events(
      FlutterError(
        code: "unimplemented",
        message: "flutter_meta_wearables_dat is Android-only for now",
        details: nil))
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    return nil
  }
}
