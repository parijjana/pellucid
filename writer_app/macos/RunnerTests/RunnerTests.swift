import Cocoa
import FlutterMacOS
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testRtfKeepsFormatting() throws {
    let html = "<p><strong>b</strong> <em>i</em> <s>x</s></p><ul><li>one</li></ul><a href=\"https://example.com\">l</a>"
    let data = try XCTUnwrap(pellucidRtfData(fromHtml: html))
    let rtf = try XCTUnwrap(String(data: data, encoding: .utf8))
    for key in ["\\b", "\\i", "\\strike", "\\listtext", "HYPERLINK"] {
      XCTAssertTrue(rtf.contains(key), key)
    }
  }

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

}
