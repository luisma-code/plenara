import Flutter
import UIKit
import UniformTypeIdentifiers

private final class DataFolderBridge: NSObject, UIDocumentPickerDelegate {
  private static let bookmarkKey = "plenara.dataFolderBookmark"
  private var pendingResult: FlutterResult?
  private var activeURL: URL?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "restore":
      result(restore()?.path)
    case "choose":
      guard pendingResult == nil else {
        result(FlutterError(code: "picker_busy", message: "A folder picker is already open.", details: nil))
        return
      }
      pendingResult = result
      let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
      picker.allowsMultipleSelection = false
      picker.delegate = self
      guard let presenter = Self.presenter else {
        pendingResult = nil
        result(FlutterError(code: "no_presenter", message: "The folder picker could not open.", details: nil))
        return
      }
      presenter.present(picker, animated: true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else {
      finish(nil)
      return
    }
    do {
      activeURL?.stopAccessingSecurityScopedResource()
      guard url.startAccessingSecurityScopedResource() else {
        throw NSError(domain: "PlenaraDataFolder", code: 1, userInfo: [NSLocalizedDescriptionKey: "The selected folder did not grant access."])
      }
      let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
      UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
      activeURL = url
      finish(url.path)
    } catch {
      finish(FlutterError(code: "bookmark_failed", message: error.localizedDescription, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(nil)
  }

  private func restore() -> URL? {
    guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
    do {
      var stale = false
      let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
      guard url.startAccessingSecurityScopedResource() else { return nil }
      activeURL?.stopAccessingSecurityScopedResource()
      activeURL = url
      if stale {
        let refreshed = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(refreshed, forKey: Self.bookmarkKey)
      }
      return url
    } catch {
      return nil
    }
  }

  private func finish(_ value: Any?) {
    let result = pendingResult
    pendingResult = nil
    result?(value)
  }

  private static var presenter: UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    var controller = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
    while let presented = controller?.presentedViewController { controller = presented }
    return controller
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let dataFolderBridge = DataFolderBridge()
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "com.plenara/data-folder",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.dataFolderBridge.handle(call, result: result)
    }
  }
}
