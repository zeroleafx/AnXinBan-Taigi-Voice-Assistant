import AVFoundation
import Flutter
import UIKit
import UserNotifications
import Network
import AuthenticationServices

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, ASWebAuthenticationPresentationContextProviding {
  private var authSession: ASWebAuthenticationSession?
  private var authWindow: UIWindow?

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    return authWindow!
  }
  private let recognizer = BreezeRecognizer()
  private var torchWatch: NSKeyValueObservation?
  private var torchDeactivating: NSObjectProtocol?

  override func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
    super.applicationDidReceiveMemoryWarning(application)
    speechQueue.async { self.recognizer.releaseModel() }
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BreezeSpeech") else { return }
    let authChannel = FlutterMethodChannel(name: "anxinban/auth", binaryMessenger: registrar.messenger())
    authChannel.setMethodCallHandler { [weak self] call, reply in
      guard call.method == "signIn" else { reply(FlutterMethodNotImplemented); return }
      guard let self else { return }
      guard self.authSession == nil else {
        reply(FlutterError(code: "auth_busy", message: "登入正在進行中", details: nil)); return
      }
      guard let args = call.arguments as? [String: Any],
            let raw = args["url"] as? String, let url = URL(string: raw),
            url.scheme == "https",
            url.host == "ewiszwajtzaamswjoosb.supabase.co",
            let window = UIApplication.shared.connectedScenes
              .compactMap({ $0 as? UIWindowScene })
              .filter({ $0.activationState == .foregroundActive })
              .flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) else {
        reply(FlutterError(code: "auth_unavailable", message: "無法開啟登入視窗", details: nil)); return
      }
      self.authWindow = window
      let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "com.anxinban.app") { [weak self] callback, error in
        DispatchQueue.main.async {
          self?.authSession = nil
          self?.authWindow = nil
          if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
            reply(nil)
          } else if error != nil {
            reply(FlutterError(code: "auth_failed", message: "登入未完成，請再試一次", details: nil))
          } else if let callback, callback.host == "login-callback" {
            reply(callback.absoluteString)
          } else {
            reply(FlutterError(code: "auth_callback", message: "登入回傳網址不正確", details: nil))
          }
        }
      }
      session.presentationContextProvider = self
      self.authSession = session
      if !session.start() {
        self.authSession = nil
        self.authWindow = nil
        reply(FlutterError(code: "auth_start", message: "無法開始登入", details: nil))
      }
    }
    registerTorch(registrar.messenger())
    let channel = FlutterMethodChannel(name: "anxinban/breeze", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, reply in
      if call.method == "downloadEnvironment" {
        do {
          let url = try self.recognizer.modelURL().deletingLastPathComponent()
          let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
          let available = values.volumeAvailableCapacityForImportantUsage ?? 0
          let monitor = NWPathMonitor()
          monitor.pathUpdateHandler = { path in
            monitor.pathUpdateHandler = nil
            monitor.cancel()
            let network = path.status != .satisfied ? "none" :
              (path.isExpensive || path.isConstrained ? "metered" : "unmetered")
            reply(["network": network, "availableBytes": available])
          }
          monitor.start(queue: .main)
        } catch {
          reply(FlutterError(code: "storage", message: "無法檢查手機儲存空間。", details: nil))
        }
        return
      }
      if call.method == "modelPath" {
        do { reply(try self.recognizer.modelURL().path) }
        catch { reply(FlutterError(code: "storage", message: error.localizedDescription, details: nil)) }
        return
      }
      guard call.method == "transcribe", let path = call.arguments as? String else {
        reply(FlutterMethodNotImplemented)
        return
      }
      let asset = AVURLAsset(url: URL(fileURLWithPath: path))
      asset.loadTracks(withMediaType: .audio) { tracks, error in
        speechQueue.async {
          do {
            if let error { throw error }
            guard let track = tracks?.first else { throw SpeechError("錄音沒有音軌。") }
            let text = try self.recognizer.transcribe(asset, track: track)
            DispatchQueue.main.async { reply(text) }
          } catch {
            DispatchQueue.main.async { reply(FlutterError(code: "speech", message: error.localizedDescription, details: nil)) }
          }
        }
      }
    }
  }

  // The flashlight on "anxinban/torch". Every call is answered exactly once,
  // and "isOn" reads the light itself, so a switch from the control centre
  // shows up in the app.
  private func registerTorch(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "anxinban/torch", binaryMessenger: messenger)
    if let device = AVCaptureDevice.default(for: .video), device.hasTorch {
      // While the app still asks for the light, iOS lights it again when the
      // app comes back. So when it goes dark outside the app (control centre)
      // or the app leaves the screen, stop asking: off then stays off.
      torchWatch = device.observe(\.isTorchActive, options: [.new]) { device, change in
        guard change.newValue == false else { return }
        DispatchQueue.main.async {
          if device.torchMode == .on && !device.isTorchActive {
            AppDelegate.stopAskingForTorch(device)
          }
        }
      }
      // System panels can deactivate the app without backgrounding it.
      // Turn off our torch request before the system UI takes control.
      // This also turns our light off for other interruptions, such as locking.
      if let old = torchDeactivating { NotificationCenter.default.removeObserver(old) }
      torchDeactivating = NotificationCenter.default.addObserver(
        forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
      ) { _ in
        if device.torchMode == .on { AppDelegate.stopAskingForTorch(device) }
      }
    }
    channel.setMethodCallHandler { call, reply in
      guard call.method == "set" || call.method == "isOn" else {
        reply(FlutterMethodNotImplemented)
        return
      }
      guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
        reply(call.method == "set" ? false : nil)
        return
      }
      if call.method == "isOn" {
        // The light itself, which also follows the control centre; torchMode
        // is only what this app last asked for.
        reply(device.isTorchActive)
        return
      }
      let on = call.arguments as? Bool ?? false
      do {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        if on {
          // Unavailable while the phone is too hot or the camera is busy.
          guard device.isTorchAvailable else {
            reply(false)
            return
          }
          try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
        } else {
          device.torchMode = .off
        }
        reply(true)
      } catch {
        reply(false)
      }
    }
  }

  private static func stopAskingForTorch(_ device: AVCaptureDevice) {
    do {
      try device.lockForConfiguration()
      device.torchMode = .off
      device.unlockForConfiguration()
    } catch {
      // Left as it is; the app's next switch reports any problem.
    }
  }
}

private let speechQueue = DispatchQueue(label: "anxinban.breeze", qos: .userInitiated)
