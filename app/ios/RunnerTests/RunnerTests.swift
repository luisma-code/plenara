import Flutter
import Contacts
import ContactsUI
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testContactPickerCanBePresentedAgainAfterCancellation() throws {
    var presented: [CNContactPickerViewController] = []
    let bridge = ContactsBridge { picker in
      presented.append(picker)
      return true
    }
    var responses: [Any?] = []

    bridge.handle(FlutterMethodCall(methodName: "select", arguments: nil)) {
      responses.append($0)
    }
    XCTAssertEqual(presented.count, 1)
    bridge.contactPickerDidCancel(presented[0])

    bridge.handle(FlutterMethodCall(methodName: "select", arguments: nil)) {
      responses.append($0)
    }
    XCTAssertEqual(presented.count, 2, "The picker must reopen after the first selection flow finishes.")
    bridge.contactPickerDidCancel(presented[1])

    XCTAssertEqual(responses.count, 2)
    for response in responses {
      let payload = try XCTUnwrap(response as? [String: Any])
      XCTAssertEqual(payload["cancelled"] as? Bool, true)
      XCTAssertEqual((payload["contacts"] as? [[String: Any]])?.count, 0)
    }
  }

  func testContactPickerReturnsSelectedContactSnapshot() throws {
    var presented: CNContactPickerViewController?
    let bridge = ContactsBridge { picker in
      presented = picker
      return true
    }
    var response: Any?
    bridge.handle(FlutterMethodCall(methodName: "select", arguments: nil)) {
      response = $0
    }

    let contact = CNMutableContact()
    contact.givenName = "Bob"
    contact.familyName = "Rivera"
    contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "+15551212"))]
    contact.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: "bob@example.com" as NSString)]
    bridge.contactPicker(try XCTUnwrap(presented), didSelect: [contact])

    let payload = try XCTUnwrap(response as? [String: Any])
    XCTAssertEqual(payload["cancelled"] as? Bool, false)
    let contacts = try XCTUnwrap(payload["contacts"] as? [[String: Any]])
    XCTAssertEqual(contacts.count, 1)
    XCTAssertEqual(contacts[0]["displayName"] as? String, "Bob Rivera")
    XCTAssertEqual(contacts[0]["phone"] as? String, "+15551212")
    XCTAssertEqual(contacts[0]["email"] as? String, "bob@example.com")
  }

}
