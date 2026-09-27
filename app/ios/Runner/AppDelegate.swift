import EventKit
import AppIntents
import Security
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
  private let guideSources = GuideSourcesBridge()
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
    let guideChannel = FlutterMethodChannel(name: "com.plenara/guide-sources", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    guideChannel.setMethodCallHandler { [weak self] call, result in
      self?.guideSources.handle(call, result: result)
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


/// Read-only, bounded user-initiated browsing. No background ingestion.
private final class GuideSourcesBridge {
  private let store = EKEventStore()
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "draft" {
      let draft = GuideCapture.read()
      result(draft); return
    }
    if call.method == "clearDraft" {
      GuideCapture.clear(); result(nil); return
    }
    guard call.method == "select", let args = call.arguments as? [String: Any], let kind = args["kind"] as? String,
      kind == "calendar" || kind == "reminders" else { result(FlutterMethodNotImplemented); return }
    let receive: (Bool, Error?) -> Void = { [weak self] granted, error in
      DispatchQueue.main.async {
        guard let self, granted else { result(FlutterError(code: "permission", message: "Source access was not granted.", details: nil)); return }
        let formatter = ISO8601DateFormatter()
        if kind == "calendar" {
          let start = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
          let end = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
          let predicate = self.store.predicateForEvents(withStart: start, end: end, calendars: nil)
          let events = self.store.events(matching: predicate).sorted { $0.startDate < $1.startDate }.prefix(100)
          result(events.map { event -> [String: Any] in
            ["kind": "calendar", "title": event.title ?? "", "calendar": event.calendar.title,
             "start": formatter.string(from: event.startDate), "end": formatter.string(from: event.endDate),
             "allDay": event.isAllDay, "location": event.location ?? ""]
          })
        } else {
          let predicate = self.store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
          self.store.fetchReminders(matching: predicate) { reminders in
            let items = (reminders ?? []).prefix(100).map { reminder -> [String: Any] in
              var item: [String: Any] = ["kind": "reminder", "title": reminder.title ?? "", "calendar": reminder.calendar.title, "completed": reminder.isCompleted]
              if let components = reminder.dueDateComponents, let date = Calendar.current.date(from: components) { item["due"] = formatter.string(from: date) }
              return item
            }
            DispatchQueue.main.async { result(items) }
          }
        }
      }
    }
    if #available(iOS 17.0, *) {
      if kind == "calendar" { store.requestFullAccessToEvents(completion: receive) }
      else { store.requestFullAccessToReminders(completion: receive) }
    } else { store.requestAccess(to: kind == "calendar" ? .event : .reminder, completion: receive) }
  }
}

@available(iOS 16.0, *)
struct CaptureWithPlenara: AppIntent {
  static var title: LocalizedStringResource = "Capture with Plenara"
  static var description = IntentDescription("Bring selected text to a draft in Plena. Nothing is sent or applied automatically.")
  static var openAppWhenRun = true
  @Parameter(title: "Selected text") var text: String
  func perform() async throws -> some IntentResult {
    // A single draft is kept only until explicitly reviewed. Existing draft is
    // retained rather than overwritten by a second automation.
    guard GuideCapture.read() == nil else {
      throw CaptureError.pendingDraft
    }
    try GuideCapture.write(text)
    return .result()
  }
  enum CaptureError: Error, CustomLocalizedStringResourceConvertible {
    case pendingDraft
    var localizedStringResource: LocalizedStringResource { "Review the existing Plenara capture before adding another." }
  }
}
@available(iOS 16.0, *)
struct OpenPlena: AppIntent {
  static var title: LocalizedStringResource = "Open Plena"
  static var openAppWhenRun = true
  func perform() async throws -> some IntentResult {
    if GuideCapture.read() == nil { try GuideCapture.write("") }
    return .result()
  }
}
@available(iOS 16.0, *)
struct PlenaraShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(intent: OpenPlena(), phrases: ["Open Plena in \(.applicationName)"], shortTitle: "Open Plena", systemImageName: "bubble.left.and.bubble.right")
    AppShortcut(intent: CaptureWithPlenara(), phrases: ["Capture with \(.applicationName)"], shortTitle: "Capture a thought", systemImageName: "square.and.pencil")
  }
}

enum GuideCapture {
  static var query: [String: Any] { [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"com.plenara.selected-capture", kSecAttrAccount as String:"draft"] }
  static func read() -> String? {
    var request = query; request[kSecReturnData as String] = true
    var value: CFTypeRef?
    guard SecItemCopyMatching(request as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return nil }
    return String(data:data, encoding:.utf8)
  }
  static func clear() { SecItemDelete(query as CFDictionary) }
  static func write(_ value: String) throws {
    var request = query
    request[kSecValueData as String] = Data(value.utf8)
    request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    let status = SecItemAdd(request as CFDictionary, nil)
    guard status == errSecSuccess else { throw NSError(domain:NSOSStatusErrorDomain, code:Int(status)) }
  }
}
