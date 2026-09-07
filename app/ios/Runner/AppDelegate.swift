import Flutter
import Contacts
import ContactsUI
import UIKit
import UniformTypeIdentifiers

private final class DataFolderBridge: NSObject, UIDocumentPickerDelegate {
  private static let bookmarkKey = "plenara.dataFolderBookmark"
  private var pendingResult: FlutterResult?
  private var activeURL: URL?
  private var pendingURL: URL?
  private var pendingBookmark: Data?
  private var rollbackURL: URL?
  private var rollbackBookmark: Data?
  private var hasCommittedRollback = false

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
      discardPendingSelection()
      let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
      picker.allowsMultipleSelection = false
      picker.delegate = self
      guard let presenter = Self.presenter else {
        pendingResult = nil
        result(FlutterError(code: "no_presenter", message: "The folder picker could not open.", details: nil))
        return
      }
      presenter.present(picker, animated: true)
    case "commit":
      guard let url = pendingURL, let bookmark = pendingBookmark else {
        result(FlutterError(code: "no_pending_selection", message: "No folder selection is waiting to be committed.", details: nil))
        return
      }
      rollbackURL = activeURL
      rollbackBookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey)
      hasCommittedRollback = true
      activeURL = url
      pendingURL = nil
      pendingBookmark = nil
      UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
      result(nil)
    case "finalize":
      rollbackURL?.stopAccessingSecurityScopedResource()
      rollbackURL = nil
      rollbackBookmark = nil
      hasCommittedRollback = false
      result(nil)
    case "rollback":
      rollbackSelection()
      result(nil)
    case "reset":
      discardPendingSelection()
      rollbackURL?.stopAccessingSecurityScopedResource()
      rollbackURL = nil
      rollbackBookmark = nil
      hasCommittedRollback = false
      activeURL?.stopAccessingSecurityScopedResource()
      activeURL = nil
      UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
      result(nil)
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
      guard url.startAccessingSecurityScopedResource() else {
        throw NSError(domain: "PlenaraDataFolder", code: 1, userInfo: [NSLocalizedDescriptionKey: "The selected folder did not grant access."])
      }
      pendingURL = url
      let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
      pendingBookmark = bookmark
      finish(url.path)
    } catch {
      discardPendingSelection()
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

  private func discardPendingSelection() {
    pendingURL?.stopAccessingSecurityScopedResource()
    pendingURL = nil
    pendingBookmark = nil
  }

  private func rollbackSelection() {
    discardPendingSelection()
    guard hasCommittedRollback else { return }
    activeURL?.stopAccessingSecurityScopedResource()
    activeURL = rollbackURL
    rollbackURL = nil
    if let bookmark = rollbackBookmark {
      UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
    } else {
      UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
    }
    rollbackBookmark = nil
    hasCommittedRollback = false
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

final class ContactsBridge: NSObject, CNContactPickerDelegate {
  typealias PresentPicker = (CNContactPickerViewController) -> Bool

  private var pendingResult: FlutterResult?
  private let presentPicker: PresentPicker?

  init(presentPicker: PresentPicker? = nil) {
    self.presentPicker = presentPicker
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "status" {
      result(["authorizationStatus": Self.authorizationStatusName])
      return
    }
    guard call.method == "select" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard pendingResult == nil else {
      result(FlutterError(code: "picker_busy", message: "The contact picker is already open.", details: nil))
      return
    }
    let picker = CNContactPickerViewController()
    picker.delegate = self
    if let presentPicker {
      guard presentPicker(picker) else {
        result(FlutterError(code: "no_presenter", message: "The contact picker could not open.", details: nil))
        return
      }
    } else if let presenter = Self.presenter {
      presenter.present(picker, animated: true)
    } else {
      result(FlutterError(code: "no_presenter", message: "The contact picker could not open.", details: nil))
      return
    }
    pendingResult = result
  }

  func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
    finish(contacts.compactMap(Self.serialize), cancelled: false)
  }

  func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
    finish([], cancelled: true)
  }

  private func finish(_ contacts: [[String: Any]], cancelled: Bool) {
    let result = pendingResult
    pendingResult = nil
    result?([
      "authorizationStatus": Self.authorizationStatusName,
      "cancelled": cancelled,
      "contacts": contacts,
    ])
  }

  private static func serialize(_ contact: CNContact) -> [String: Any]? {
    let name = CNContactFormatter.string(from: contact, style: .fullName)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !name.isEmpty else { return nil }
    var item: [String: Any] = [
      "identifier": contact.identifier,
      "displayName": name,
    ]
    if contact.isKeyAvailable(CNContactPhoneNumbersKey),
       let phone = contact.phoneNumbers.first?.value.stringValue,
       !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      item["phone"] = phone
    }
    if contact.isKeyAvailable(CNContactEmailAddressesKey),
       let emailValue = contact.emailAddresses.first?.value {
      let email = emailValue as String
      if !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        item["email"] = email
      }
    }
    return item
  }

  private static var authorizationStatusName: String {
    let status = CNContactStore.authorizationStatus(for: .contacts)
    switch status {
    case .notDetermined: return "notDetermined"
    case .restricted: return "restricted"
    case .denied: return "denied"
    case .authorized: return "authorized"
    case .limited: return "limited"
    @unknown default: return "unknown"
    }
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
  private let contactsBridge = ContactsBridge()
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
    let contactsChannel = FlutterMethodChannel(
      name: "com.plenara/contacts",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    contactsChannel.setMethodCallHandler { [weak self] call, result in
      self?.contactsBridge.handle(call, result: result)
    }
  }
}
