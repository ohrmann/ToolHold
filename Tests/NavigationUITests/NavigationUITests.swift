import XCTest

@MainActor
final class NavigationUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = ["--navigation-ui-tests", "--reset-navigation-ui-tests"]
    app.launch()
    XCTAssertTrue(app.staticTexts["home-tagline"].waitForExistence(timeout: 10))
    showSidebar()
    activate(app.buttons["category-dataJSON"])
    activate(app.buttons["favorites-section"])
  }
  private func activate(_ element: XCUIElement) {
    #if os(macOS)
      element.click()
    #else
      element.tap()
    #endif
  }
  private func showSidebar() {
    if app.buttons["home-browse"].exists && app.buttons["home-browse"].isHittable {
      activate(app.buttons["home-browse"])
    } else {
      #if os(iOS)
        if !app.textFields["tool-search"].exists || !app.textFields["tool-search"].isHittable {
          activate(app.navigationBars.buttons.firstMatch)
        }
      #endif
    }
    XCTAssertTrue(app.textFields["tool-search"].waitForExistence(timeout: 5))
  }
  private func search(_ query: String) {
    let field = app.textFields["tool-search"]
    activate(field)
    field.typeText(query)
  }
  private func clearSearch() { activate(app.buttons["Clear search"]) }


  func testTextToolsGenerateExportAndSessionPrivacy() throws {
    search("T-039");activate(app.buttons["text-T-039"])
    activate(app.buttons["Generate"])
    let result=app.textViews.matching(NSPredicate(format:"label == %@","Output result")).firstMatch
    XCTAssertTrue(result.waitForExistence(timeout:8))
    expectation(for:NSPredicate(format:"value != ''"),evaluatedWith:result)
    waitForExpectations(timeout:10)
    let output=result.value as? String
    XCTAssertFalse(output?.isEmpty ?? true)
    activate(app.buttons["Copy"].firstMatch)
    chooseAppearance("Dark");XCTAssertEqual(result.value as? String,output)
    activate(app.buttons["Export"].firstMatch)
    let save=app.buttons["Save"].firstMatch
    XCTAssertTrue(save.waitForExistence(timeout:10));XCTAssertTrue(save.isEnabled)
    #if os(macOS)
    let filename=app.textFields.matching(NSPredicate(format:"value CONTAINS %@","lorem")).firstMatch
    XCTAssertTrue(filename.waitForExistence(timeout:5));activate(filename)
    filename.typeKey("a",modifierFlags:.command);filename.typeText("toolbox-text-test-"+UUID().uuidString+".txt")
    #endif
    activate(save)
    if app.buttons["Replace"].firstMatch.waitForExistence(timeout:2){activate(app.buttons["Replace"].firstMatch)}
    XCTAssertTrue(app.buttons["Generate"].waitForExistence(timeout:6))
    XCTAssertEqual(result.value as? String,output)
    attachScreenshot("Text tools Lorem Dark")
    chooseAppearance("Light");attachScreenshot("Text tools Lorem Light")
    app.terminate();app.launchArguments=["--navigation-ui-tests"];app.launch()
    XCTAssertTrue(app.buttons["Generate"].waitForExistence(timeout:10))
    XCTAssertEqual(app.textViews.matching(NSPredicate(format:"label == %@","Output result")).firstMatch.value as? String,"")
    XCTAssertFalse(app.buttons["Copy"].firstMatch.isEnabled)
  }

  func testCertificatePasswordJWTVerifierNativeFlows() throws {
    search("T-030"); activate(app.buttons["generators-T-030"])
    let pem = """
    -----BEGIN CERTIFICATE-----
    MIIEFjCCAv6gAwIBAgIUJInkoqUBujADUY8kob9+OEHCjmwwDQYJKoZIhvcNAQEL
    BQAwVzELMAkGA1UEBhMCQ1oxFTATBgNVBAoMDFRvb2xib3ggVGVzdDEMMAoGA1UE
    CwwDT25lMQwwCgYDVQQLDANUd28xFTATBgNVBAMMDGV4YW1wbGUudGVzdDAeFw0y
    NjEwMjIxMjM1MjVaFw0yNjExMjExMjM1MjVaMFcxCzAJBgNVBAYTAkNaMRUwEwYD
    VQQKDAxUb29sYm94IFRlc3QxDDAKBgNVBAsMA09uZTEMMAoGA1UECwwDVHdvMRUw
    EwYDVQQDDAxleGFtcGxlLnRlc3QwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
    AoIBAQDBF8YOXGteGzrT7ebo+iJoCHaYnn7OW1siC+nArWbWpPFIrJo7m/vUXSP8
    DmaNhY89rPuYnCcg3K4p+NEtjaJneOrUPmI83g1erONAuWHxO2ap3sCaZ3SS151s
    ojYOp9Vje7U7OnBDfgkU9z7poMI8mwN7SC5mZt4IDy5EsoYPUdbIvXPfOlblylct
    +Gjs0c37DamH+DOsAoO2Sfd+++HDzOI5MmwMnpuTppcQ2UV5OHiw8BorJ4qrA4OU
    KqBZewbrbkNH3jfDjR3udoWwGseIr4t02J7rfOgzUhbw4vhzTbVOdBOnwlSuEdU3
    7rtXiqCy81vhU1VqGsLNGUhwpYsXAgMBAAGjgdkwgdYwHQYDVR0OBBYEFODDDII+
    5HDPHhTEv/tupAoJ1l28MGgGA1UdEQRhMF+CDGV4YW1wbGUudGVzdIIOKi5leGFt
    cGxlLnRlc3SHBH8AAAGHEAAAAAAAAAAAAAAAAAAAAAGBEXRlc3RAZXhhbXBsZS50
    ZXN0hhRodHRwczovL2V4YW1wbGUudGVzdDAOBgNVHQ8BAf8EBAMCBaAwHQYDVR0l
    BBYwFAYIKwYBBQUHAwEGCCsGAQUFBwMCMAwGA1UdEwEB/wQCMAAwDgYDKgMEAQH/
    BAQEAgECMA0GCSqGSIb3DQEBCwUAA4IBAQBDY+1O17iEZrLpNcNj1x1OwxBbhYnz
    E8XxU/bdQR09hqowo+zABAUw6/Y3ZM49ofNk+0BjC12YCA85XvBc9hU0PqNonD4g
    E5cqqFEUENKmc1bN2ZcLyrYPw3T9ljrVoPKigXybAh63+GVvZSZO/Qde9mJ1qENv
    fQkVyek8g6xMDl0chDu+SP+oDxugOCjFOD87OE15CcLVIAjMnMfvxuGC83fNE7QH
    yweC9IeddeyqZinFyBKK3XNT79godujxG5KHpL3ulxcT8JKfwQCNZrT+eQe/d/Uh
    oj4aExYwyVamcKTnIWwEYZkE5edhqyNFRicMvt2dvw4RduTbALOAxn8+
    -----END CERTIFICATE-----
    """
    let certInput = app.textViews.matching(NSPredicate(format:"label == %@", "Certificate PEM input")).firstMatch
    XCTAssertTrue(certInput.waitForExistence(timeout:8)); activate(certInput); certInput.typeText(pem)
    activate(app.buttons["certificate-inspect"])
    XCTAssertTrue(app.staticTexts["1 of 1 inspected"].waitForExistence(timeout:10))
    chooseAppearance("Dark"); XCTAssertEqual(certInput.value as? String,pem)
    let certShot = XCTAttachment(screenshot:app.screenshot()); certShot.name = "T030 Dark"; certShot.lifetime = .keepAlways; add(certShot)
    activate(app.buttons["certificate-actions"])
    #if os(macOS)
    activate(app.menuItems["Export DER…"])
    #else
    activate(app.buttons["Export DER…"])
    #endif
    let save = app.buttons["Save"].firstMatch
    XCTAssertTrue(save.waitForExistence(timeout:10)); XCTAssertTrue(save.isEnabled)
    #if os(iOS)
    let cancel = app.buttons["Cancel"].firstMatch
    if cancel.exists && cancel.isHittable { activate(cancel) }
    else {
      let origin = app.coordinate(withNormalizedOffset:.zero)
      origin.withOffset(CGVector(dx:app.frame.width/2,dy:save.frame.midY-app.frame.minY)).press(forDuration:0.1,thenDragTo:origin.withOffset(CGVector(dx:app.frame.width/2,dy:app.frame.height-40)))
    }
    #else
    activate(app.buttons["Cancel"].firstMatch)
    #endif
    XCTAssertTrue(app.staticTexts["Export cancelled; result is unchanged."].waitForExistence(timeout:5))
    activate(app.buttons["certificate-actions"])
    #if os(macOS)
    activate(app.menuItems["Export DER…"])
    #else
    activate(app.buttons["Export DER…"])
    #endif
    XCTAssertTrue(save.waitForExistence(timeout:10)); activate(save)
    #if os(iOS)
    let springboard = XCUIApplication(bundleIdentifier:"com.apple.springboard")
    if springboard.buttons["Replace"].firstMatch.waitForExistence(timeout:2) { activate(springboard.buttons["Replace"].firstMatch) }
    #endif
    if app.buttons["Replace"].firstMatch.exists { activate(app.buttons["Replace"].firstMatch) }
    XCTAssertTrue(app.staticTexts["Certificate exported."].waitForExistence(timeout:12))
    showSidebar(); clearSearch(); search("T-031"); activate(app.buttons["generators-T-031"])
    let password = app.secureTextFields["password-strength-input"].firstMatch
    XCTAssertTrue(password.waitForExistence(timeout:8)); activate(password); password.typeText("password")
    activate(app.buttons["password-strength-estimate"])
    XCTAssertTrue(app.staticTexts["Very guessable"].waitForExistence(timeout:10))
    activate(app.buttons["password-strength-reveal"])
    XCTAssertEqual(app.textFields["password-strength-input"].firstMatch.value as? String,"password")
    chooseAppearance("Light")
    XCTAssertEqual(app.textFields["password-strength-input"].firstMatch.value as? String,"password")
    let strengthShot = XCTAttachment(screenshot:app.screenshot()); strengthShot.name = "T031 Light"; strengthShot.lifetime = .keepAlways; add(strengthShot)
    activate(app.buttons["password-strength-clear"])
    XCTAssertTrue(app.staticTexts["Enter a password to estimate."].waitForExistence(timeout:5))
    showSidebar(); clearSearch(); search("T-032"); activate(app.buttons["generators-T-032"])
    let token = app.textViews.matching(NSPredicate(format:"label == %@", "JWT Verifier token input")).firstMatch
    XCTAssertTrue(token.waitForExistence(timeout:8)); activate(token);token.typeText("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ0b29sYm94LXRlc3QiLCJuIjo5MDA3MTk5MjU0NzQwOTkzMTIzNDUsInMiOiJcdTAwNjEiLCJhdWQiOlsibG9jYWwiXX0.WiwCYe3ZrpMQ53vDPEg9zuINovNm5JWt8PnDGfyGmNc")
    activate(app.buttons["jwt-verifier-algorithm"])
    #if os(macOS)
    activate(app.menuItems["HS256"])
    #else
    activate(app.buttons["HS256"])
    #endif
    activate(app.buttons["jwt-verifier-key-source"])
    #if os(macOS)
    activate(app.menuItems["Secret · UTF-8"])
    #else
    activate(app.buttons["Secret · UTF-8"])
    #endif
    let key = app.textViews["jwt-verifier-key"].firstMatch
    XCTAssertTrue(key.waitForExistence(timeout:6)); activate(key);key.typeText("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
    activate(app.buttons["jwt-verifier-verify"])
    XCTAssertTrue(app.staticTexts["Signature matches supplied key"].firstMatch.waitForExistence(timeout:10))
    let verifierShot = XCTAttachment(screenshot:app.screenshot()); verifierShot.name = "T032"; verifierShot.lifetime = .keepAlways; add(verifierShot)
    chooseAppearance("Dark"); XCTAssertEqual(token.value as? String,"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ0b29sYm94LXRlc3QiLCJuIjo5MDA3MTk5MjU0NzQwOTkzMTIzNDUsInMiOiJcdTAwNjEiLCJhdWQiOlsibG9jYWwiXX0.WiwCYe3ZrpMQ53vDPEg9zuINovNm5JWt8PnDGfyGmNc")
    app.terminate(); app.launchArguments = ["--navigation-ui-tests"]; app.launch()
    let freshToken = app.textViews.matching(NSPredicate(format:"label == %@", "JWT Verifier token input")).firstMatch
    XCTAssertTrue(freshToken.waitForExistence(timeout:8)); XCTAssertEqual(freshToken.value as? String,"")
    XCTAssertEqual(app.textViews["jwt-verifier-key"].firstMatch.value as? String,"")
    XCTAssertFalse(app.staticTexts["Signature matches supplied key"].exists)
  }

  func testQRCodeDecoderPasteCopyExportAndPrivacy() throws {
    search("T-028"); activate(app.buttons["generators-T-028"])
    let input = app.textViews.matching(NSPredicate(format:"label == %@", "QR input")).firstMatch
    XCTAssertTrue(input.waitForExistence(timeout:8)); activate(input)
    let payload = "https://example.com/decoder?x=%2F&x=123"
    input.typeText(payload)
    #if os(iOS)
    if app.buttons["Done"].firstMatch.exists && app.buttons["Done"].firstMatch.isHittable { activate(app.buttons["Done"].firstMatch) }
    #endif
    expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:app.buttons["qr-copy"])
    waitForExpectations(timeout:12); activate(app.buttons["qr-copy"])
    showSidebar(); clearSearch(); search("T-029"); activate(app.buttons["generators-T-029"])
    XCTAssertFalse(app.buttons["qr-decoder-copy"].isEnabled)
    activate(app.buttons["qr-decoder-paste"])
    expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:app.buttons["qr-decoder-copy"])
    waitForExpectations(timeout:12)
    let result = app.textViews.matching(NSPredicate(format:"label == %@", "Decoded QR result")).firstMatch
    XCTAssertTrue(result.waitForExistence(timeout:6)); XCTAssertEqual(result.value as? String,payload)
    XCTAssertGreaterThan(result.frame.height,60)
    chooseAppearance("Dark"); XCTAssertEqual(result.value as? String,payload)
    activate(app.buttons["qr-decoder-reveal"])
    activate(app.buttons["qr-decoder-copy"])
    #if os(macOS)
    activate(app.menuItems["Copy Text"])
    #else
    activate(app.buttons["Copy Text"])
    #endif
    XCTAssertTrue(app.staticTexts["Text copied"].waitForExistence(timeout:5))
    activate(app.buttons["qr-decoder-export"])
    #if os(macOS)
    activate(app.menuItems["Decoded Bytes (.bin)"])
    #else
    activate(app.buttons["Decoded Bytes (.bin)"])
    #endif
    let save = app.buttons["Save"].firstMatch
    XCTAssertTrue(save.waitForExistence(timeout:10)); XCTAssertTrue(save.isEnabled);activate(save)
    if app.buttons["Replace"].firstMatch.waitForExistence(timeout:2) { activate(app.buttons["Replace"].firstMatch) }
    #if os(iOS)
    let systemReplace = XCUIApplication(bundleIdentifier:"com.apple.springboard").buttons["Replace"].firstMatch
    if systemReplace.exists && systemReplace.isHittable { activate(systemReplace) }
    #endif
    let exported = app.staticTexts["Payload exported"]
    let didExport = exported.waitForExistence(timeout:10)
    if !didExport {
      print("T029_EXPORT_APP_TREE \(app.debugDescription)")
      #if os(iOS)
      print("T029_EXPORT_SYSTEM_TREE \(XCUIApplication(bundleIdentifier:"com.apple.springboard").debugDescription)")
      #endif
      attachScreenshot("T029 Save diagnostic")
    }
    XCTAssertTrue(didExport)
    attachScreenshot("T029 Decoder Dark")
    chooseAppearance("Light"); XCTAssertEqual(result.value as? String,payload)
    activate(app.buttons["qr-decoder-image-disclosure"])
    XCTAssertGreaterThan(result.frame.height,60)
    activate(app.buttons["qr-decoder-reveal"])
    XCTAssertTrue(app.scrollViews["qr-decoder-viewport"].waitForExistence(timeout:4))
    attachScreenshot("T029 Decoder Light")
    app.terminate();app.launchArguments=["--navigation-ui-tests"];app.launch()
    XCTAssertTrue(app.buttons["qr-decoder-paste"].waitForExistence(timeout:8))
    XCTAssertFalse(app.buttons["qr-decoder-copy"].isEnabled)
    XCTAssertEqual(app.textViews.matching(NSPredicate(format:"label == %@", "Decoded QR result")).firstMatch.value as? String,"")
  }

  func testQRCodeContentForms() throws {
    search("T-028"); activate(app.buttons["generators-T-028"])
    func kind(_ value:String) {
      let picker=app.popUpButtons["qr-content-kind"].firstMatch
      #if os(macOS)
      activate(picker)
      #else
      activate(app.buttons["qr-content-kind"].firstMatch)
      #endif
      activate(app.buttons[value].exists ? app.buttons[value] : app.menuItems[value])
    }
    func done() {
      #if os(iOS)
      if app.buttons["Done"].firstMatch.exists && app.buttons["Done"].firstMatch.isHittable { activate(app.buttons["Done"].firstMatch); XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout:3)) }
      #endif
    }
    func enter(_ id:String,_ value:String) {
      let field=app.textFields["qr-field-"+id]; XCTAssertTrue(field.waitForExistence(timeout:5)); activate(field); field.typeText(value); done()
    }
    kind("URL"); enter("url","https://example.com/forms")
    expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:app.buttons["qr-copy"]); waitForExpectations(timeout:10)
    kind("Contact Card"); enter("first-name","Ada"); enter("last-name","Lovelace")
    expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:app.buttons["qr-copy"]); waitForExpectations(timeout:10)
    kind("URL"); XCTAssertEqual(app.textFields["qr-field-url"].value as? String,"https://example.com/forms")
    kind("Free Text")
    let input=app.textViews.matching(NSPredicate(format:"label == %@","QR input")).firstMatch
    XCTAssertTrue(input.waitForExistence(timeout:5)); activate(input); input.typeText("native free text"); done()
    expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:app.buttons["qr-copy"]); waitForExpectations(timeout:10)
    #if os(iOS)
    // Exercise the real local palette, including a black initial selection.
    let foreground=app.buttons["qr-foreground"]
    let controls=app.scrollViews["qr-controls"].firstMatch
    for _ in 0..<4 where !foreground.isHittable {
      controls.coordinate(withNormalizedOffset:CGVector(dx:0.99,dy:0.85)).press(forDuration:0.05,thenDragTo:controls.coordinate(withNormalizedOffset:CGVector(dx:0.99,dy:0.15)))
    }
    XCTAssertTrue(foreground.isHittable); activate(foreground)
    XCTAssertTrue(app.buttons["qr-foreground-swatch-10"].waitForExistence(timeout:3))
    activate(app.buttons["qr-foreground-swatch-10"])
    XCTAssertEqual(foreground.value as? String,"#1F52A6")
    XCTAssertEqual(input.value as? String,"native free text")
    attachScreenshot("T028 local RGB palette")
    #endif
    attachScreenshot("T028 content profiles")
    app.terminate(); app.launchArguments=["--navigation-ui-tests"]; app.launch()
    XCTAssertTrue(app.textViews.matching(NSPredicate(format:"label == %@","QR input")).firstMatch.waitForExistence(timeout:8))
    XCTAssertFalse(app.buttons["qr-copy"].isEnabled)
  }

  func testQRCodeGenerateCopyExportAndSessionPrivacy() throws {
    search("T-028"); activate(app.buttons["generators-T-028"])
    let input = app.textViews.matching(NSPredicate(format:"label == %@", "QR input")).firstMatch
    XCTAssertTrue(input.waitForExistence(timeout:8))
    XCTAssertFalse(app.buttons["qr-copy"].isEnabled)
    activate(input); input.typeText("https://example.com/qr?value=123")
    #if os(iOS)
    let done = app.buttons["Done"].firstMatch
    if done.exists && done.isHittable { activate(done) }
    #endif
    let ready = NSPredicate(format:"enabled == true")
    expectation(for:ready,evaluatedWith:app.buttons["qr-copy"])
    waitForExpectations(timeout:10)
    activate(app.buttons["qr-copy"])
    XCTAssertTrue(app.staticTexts["Image copied"].waitForExistence(timeout:10))
    activate(app.buttons["qr-export"])
    // The real first save sheet must open and complete an explicit local save.
    let save = app.buttons["Save"].firstMatch
    XCTAssertTrue(save.waitForExistence(timeout:10)); XCTAssertTrue(save.isEnabled); activate(save)
    let replace = app.buttons["Replace"].firstMatch
    if replace.waitForExistence(timeout:2) { activate(replace) }
    XCTAssertTrue(app.staticTexts["Image exported"].waitForExistence(timeout:10))
    XCTAssertTrue(app.buttons["qr-copy"].isEnabled)
    attachScreenshot("T028 QR Generator native workspace")
    activate(app.buttons["qr-clear"])
    XCTAssertEqual(input.value as? String, "")
    XCTAssertFalse(app.buttons["qr-copy"].isEnabled)
    activate(input); input.typeText("session only")
    #if os(iOS)
    if app.buttons["Done"].firstMatch.exists && app.buttons["Done"].firstMatch.isHittable { activate(app.buttons["Done"].firstMatch) }
    #endif
    app.terminate(); app.launchArguments = ["--navigation-ui-tests"]; app.launch()
    let fresh = app.textViews.matching(NSPredicate(format:"label == %@", "QR input")).firstMatch
    XCTAssertTrue(fresh.waitForExistence(timeout:8)); XCTAssertEqual(fresh.value as? String, "")
    XCTAssertFalse(app.buttons["qr-copy"].isEnabled)
  }

  func testTokenHashAndHMACWorkspaces() throws {
    func done() {
      #if os(iOS)
      let button = app.buttons["Done"].firstMatch
      if button.exists && button.isHittable { activate(button) }
      #endif
    }
    func open(_ id: String) {
      showSidebar(); if app.buttons["Clear search"].exists { clearSearch() }; search(id)
      activate(app.buttons["generators-" + id])
    }
    func reach(_ element: XCUIElement) {
      let scroll = app.scrollViews["digest-results-scroll"].firstMatch
      for _ in 0..<6 where !element.isHittable {
        let up = element.frame.midY > scroll.frame.midY
        let start = scroll.coordinate(withNormalizedOffset: .init(dx: 0.98, dy: up ? 0.85 : 0.2))
        let end = scroll.coordinate(withNormalizedOffset: .init(dx: 0.98, dy: up ? 0.2 : 0.85))
        start.press(forDuration: 0.05, thenDragTo: end)
      }
    }
    search("T-025"); activate(app.buttons["generators-T-025"])
    XCTAssertEqual(app.textFields["token-bytes"].value as? String, "32")
    XCTAssertFalse(app.buttons["token-copy-all"].isEnabled)
    activate(app.buttons["token-generate"])
    let token = app.staticTexts["token-value"]
    XCTAssertTrue(token.waitForExistence(timeout: 6)); let value = token.label
    XCTAssertEqual(value.count, 43)
    activate(app.buttons["token-copy-single"])
    activate(app.buttons["token-visibility"])
    XCTAssertFalse(app.staticTexts["token-value"].exists)
    activate(app.buttons["token-visibility"])
    XCTAssertEqual(app.staticTexts["token-value"].label, value)
    open("T-026")
    let message = app.textViews["digest-message"]
    XCTAssertTrue(message.waitForExistence(timeout: 6)); activate(message); message.typeText("abc"); done()
    activate(app.buttons["digest-run"])
    let hash = app.staticTexts["digest-value-sha256"]
    XCTAssertTrue(hash.waitForExistence(timeout: 6))
    XCTAssertEqual(hash.label, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    activate(app.buttons["digest-copy-sha256"])
    let compare = app.buttons["digest-compare-toggle"]; reach(compare); activate(compare)
    let expected = app.textFields["digest-expected"]; reach(expected); activate(expected)
    expected.typeText(hash.label); done()
    let comparison = app.staticTexts["digest-comparison"]; reach(comparison)
    XCTAssertEqual(comparison.label, "Match")
    open("T-027")
    XCTAssertTrue(app.textViews["digest-key"].waitForExistence(timeout: 6))
    let key = app.textViews["digest-key"]; reach(key); activate(key); key.typeText("key"); done()
    let hMessage = app.textViews["digest-message"]; activate(hMessage); hMessage.typeText("The quick brown fox jumps over the lazy dog"); done()
    activate(app.buttons["digest-run"])
    let tag = app.staticTexts["digest-value-sha256"]; reach(tag)
    XCTAssertTrue(tag.waitForExistence(timeout: 6))
    XCTAssertEqual(tag.label, "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8")
    let hide = app.buttons["digest-key-visibility"]; reach(hide); activate(hide)
    XCTAssertFalse(app.textViews["digest-key"].isHittable)
    activate(hide); reach(key); XCTAssertEqual(key.value as? String, "key")
    let copy = app.buttons["digest-copy-sha256"]; reach(copy); activate(copy)
    let clear = app.buttons["digest-clear"]; activate(clear)
    XCTAssertFalse(app.staticTexts["digest-value-sha256"].exists)
    app.terminate(); app.launchArguments = ["--navigation-ui-tests"]; app.launch()
    XCTAssertTrue(app.textViews["digest-message"].waitForExistence(timeout: 6))
    XCTAssertEqual(app.textViews["digest-message"].value as? String, "")
    XCTAssertEqual(app.textViews["digest-key"].value as? String, "")
    XCTAssertFalse(app.staticTexts["digest-value-sha256"].exists)
    attachScreenshot("T025 T026 T027 native workspaces")
  }

  func testJWTEncoderGeneratePrivacyDiagnosticsAndDecoderRoundtrip() throws {
    search("T-078"); activate(app.buttons["encoders-T-078"])
    #if os(iOS)
    chooseAppearance(app.frame.width < 600 ? "Dark" : "Light")
    #endif
    func choose(_ id: String, _ value: String) {
      activate(app.buttons[id])
      #if os(macOS)
      activate(app.menuItems[value])
      #else
      activate(app.buttons[value])
      #endif
    }
    func reach(_ element: XCUIElement) {
      let form = app.scrollViews["jwt-encoder-form"].firstMatch
      for _ in 0..<7 {
        if element.isHittable { return }
        let upwards = element.frame.midY > form.frame.midY
        let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: upwards ? 0.85 : 0.15))
        let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: upwards ? 0.2 : 0.8))
        start.press(forDuration: 0.05, thenDragTo: end)
      }
    }
    func section(_ value: String) {
      let field = value == "Signing key" ? app.textViews["jwt-encoder-key"] : app.textViews.matching(NSPredicate(format: "label == %@", "JWT Encoder \(value) input")).firstMatch
      reach(field)
    }
    func done() {
      #if os(iOS)
      let button = app.buttons["Done"].firstMatch
      if button.exists && button.isHittable { activate(button) }
      #endif
    }
    let status = app.staticTexts["jwt-encoder-status"]
    XCTAssertTrue(status.waitForExistence(timeout: 6))
    XCTAssertFalse(app.buttons["jwt-encoder-copy"].isEnabled)
    section("Signing key")
    #if os(iOS)
    XCTAssertGreaterThanOrEqual(app.buttons["jwt-encoder-paste-key"].frame.height, 44)
    XCTAssertGreaterThanOrEqual(app.buttons["jwt-encoder-reveal-key"].frame.height, 44)
    #endif
    let key = app.textViews["jwt-encoder-key"]
    XCTAssertTrue(key.waitForExistence(timeout: 5))
    activate(key); key.typeText(String(repeating: "0123456789abcdef", count: 4)); done()
    reach(app.buttons["jwt-encoder-generate"]); activate(app.buttons["jwt-encoder-generate"])
    expectation(for: NSPredicate(format: "label == 'JWT generated'"), evaluatedWith: status); waitForExpectations(timeout: 8)
    XCTAssertTrue(app.buttons["jwt-encoder-copy"].isEnabled)
    reach(app.buttons["jwt-encoder-copy"]); activate(app.buttons["jwt-encoder-copy"])
    let output = app.textViews.matching(NSPredicate(format: "label == 'Generated JWT result'")).firstMatch
    XCTAssertTrue(output.waitForExistence(timeout: 5))
    let token = try XCTUnwrap(output.value as? String)
    XCTAssertEqual(token.split(separator: ".", omittingEmptySubsequences: false).count, 3)
    activate(app.buttons["jwt-encoder-check"])
    expectation(for: NSPredicate(format: "label == 'Check complete'"), evaluatedWith: status); waitForExpectations(timeout: 8)
    XCTAssertEqual(output.value as? String, token)
    reach(app.buttons["jwt-encoder-reveal-key"]); activate(app.buttons["jwt-encoder-reveal-key"]); XCTAssertFalse(key.exists)
    attachScreenshot("T078 generated JWT native workspace")
    activate(app.buttons["jwt-encoder-mask"])
    XCTAssertFalse(output.exists); XCTAssertFalse(key.exists)
    XCTAssertFalse(app.buttons["jwt-encoder-copy"].isEnabled)
    activate(app.buttons["jwt-encoder-mask"])
    XCTAssertTrue(app.buttons["jwt-encoder-copy"].isEnabled)
    reach(app.buttons["jwt-encoder-copy"]); activate(app.buttons["jwt-encoder-copy"])
    showSidebar(); clearSearch(); search("T-020"); activate(app.buttons["encoders-T-020"])
    let decoderInput = app.textViews.matching(NSPredicate(format: "label == 'JWT input'")).firstMatch
    XCTAssertTrue(decoderInput.waitForExistence(timeout: 5))
    #if os(macOS)
    activate(decoderInput); decoderInput.typeKey("v", modifierFlags: .command)
    #else
    decoderInput.press(forDuration: 1.2)
    let paste = app.menuItems["Paste"].firstMatch
    if paste.waitForExistence(timeout: 3) { activate(paste) } else { activate(app.buttons["Paste"].firstMatch) }
    #endif
    let decoderStatus = app.staticTexts["jwt-status"]
    expectation(for: NSPredicate(format: "label CONTAINS 'Decoded'"), evaluatedWith: decoderStatus); waitForExpectations(timeout: 8)
    XCTAssertEqual(decoderInput.value as? String, token); done()
    showSidebar(); clearSearch(); search("T-078"); activate(app.buttons["encoders-T-078"])
    XCTAssertTrue(app.buttons["jwt-encoder-copy"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["jwt-encoder-copy"].isEnabled)
    section("Payload")
    let payload = app.textViews.matching(NSPredicate(format: "label == 'JWT Encoder Payload input'")).firstMatch
    XCTAssertTrue(payload.waitForExistence(timeout: 5))
    activate(payload); payload.typeText("!"); done()
    XCTAssertFalse(app.buttons["jwt-encoder-copy"].isEnabled)
    activate(app.buttons["jwt-encoder-check"])
    expectation(for: NSPredicate(format: "label == 'Input needs attention'"), evaluatedWith: status); waitForExpectations(timeout: 8)
    activate(app.buttons["jwt-encoder-show-detection"].firstMatch)
    choose("jwt-encoder-options", "Clear All")
    XCTAssertEqual(status.label, "Ready · not checked"); XCTAssertFalse(app.buttons["jwt-encoder-copy"].isEnabled)
    choose("jwt-encoder-options", "Enable Unsigned test token")
    reach(app.buttons["jwt-encoder-algorithm"]); choose("jwt-encoder-algorithm", "none · Unsigned test token")
    let header = app.textViews.matching(NSPredicate(format: "label == 'JWT Encoder Header input'")).firstMatch
    expectation(for: NSPredicate(format: "value CONTAINS 'none'"), evaluatedWith: header); waitForExpectations(timeout: 5)
    reach(app.buttons["jwt-encoder-generate"]); activate(app.buttons["jwt-encoder-generate"])
    expectation(for: NSPredicate(format: "label == 'JWT generated'"), evaluatedWith: status); waitForExpectations(timeout: 8)
    XCTAssertTrue((output.value as? String)?.hasSuffix(".") == true)
    app.terminate(); app.launchArguments = ["--navigation-ui-tests"]; app.launch()
    XCTAssertTrue(status.waitForExistence(timeout: 8)); XCTAssertEqual(status.label, "Ready · not checked")
    XCTAssertFalse(app.buttons["jwt-encoder-copy"].isEnabled)
    XCTAssertEqual(app.textViews["jwt-encoder-key"].value as? String, "")
  }

  func testJWTEncoderSeparateFieldsAndMenusDoNotHideDraft() throws {
    search("T-078"); activate(app.buttons["encoders-T-078"])
    let header = app.textViews.matching(NSPredicate(format: "label == 'JWT Encoder Header input'")).firstMatch
    let payload = app.textViews.matching(NSPredicate(format: "label == 'JWT Encoder Payload input'")).firstMatch
    let key = app.textViews["jwt-encoder-key"]
    XCTAssertTrue(header.waitForExistence(timeout: 5)); XCTAssertTrue(payload.exists); XCTAssertTrue(key.exists)
    XCTAssertFalse(app.buttons["jwt-encoder-input-section"].exists)
    activate(app.buttons["jwt-encoder-options"])
    #if os(macOS)
    app.typeKey(.escape, modifierFlags: [])
    #else
    // Tap outside the menu, without changing the draft or visibility preferences.
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.35)).tap()
    #endif
    XCTAssertTrue(header.exists); XCTAssertTrue(payload.exists); XCTAssertTrue(key.exists)
    XCTAssertNotEqual(app.staticTexts["jwt-encoder-status"].label, "Sensitive content hidden")
    let form = app.scrollViews["jwt-encoder-form"].firstMatch
    for _ in 0..<5 where !key.isHittable {
      form.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.85)).press(forDuration: 0.05, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.2)))
    }
    XCTAssertTrue(key.isHittable); activate(key); key.typeText(String(repeating: "0123456789abcdef", count: 4))
    #if os(iOS)
    if app.buttons["Done"].firstMatch.isHittable { activate(app.buttons["Done"].firstMatch) }
    #endif
    let generate = app.buttons["jwt-encoder-generate"]
    for _ in 0..<4 where !generate.isHittable {
      form.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.85)).press(forDuration: 0.05, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.2)))
    }
    activate(generate)
    let status = app.staticTexts["jwt-encoder-status"]
    expectation(for: NSPredicate(format: "label == 'JWT generated'"), evaluatedWith: status); waitForExpectations(timeout: 8)
    let output = app.textViews.matching(NSPredicate(format: "label == 'Generated JWT result'")).firstMatch
    XCTAssertTrue(output.exists)
    XCTAssertEqual((output.value as? String)?.split(separator: ".").count, 3)
    XCTAssertTrue(key.exists)
    attachScreenshot("T078 separate fields and visible generated token")
  }

  func testJWTEncoderAlgorithmChoiceUpdatesOnlyHeader() throws {
    search("T-078"); activate(app.buttons["encoders-T-078"])
    let header = app.textViews.matching(NSPredicate(format: "label == 'JWT Encoder Header input'")).firstMatch
    XCTAssertTrue(header.waitForExistence(timeout: 5))
    let original = try XCTUnwrap(header.value as? String)
    let form = app.scrollViews["jwt-encoder-form"].firstMatch
    func reach(_ element: XCUIElement) {
      for _ in 0..<7 where !element.isHittable {
        let down = element.frame.midY > form.frame.midY
        form.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: down ? 0.85 : 0.15)).press(forDuration: 0.05, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: down ? 0.2 : 0.8)))
      }
    }
    let picker = app.buttons["jwt-encoder-algorithm"]
    reach(picker); activate(picker)
    #if os(macOS)
    activate(app.menuItems["HS512"])
    #else
    activate(app.buttons["HS512"])
    #endif
    expectation(for: NSPredicate(format: "value CONTAINS 'HS512'"), evaluatedWith: header); waitForExpectations(timeout: 5)
    XCTAssertEqual(header.value as? String, original.replacingOccurrences(of: "HS256", with: "HS512"))
    XCTAssertFalse(app.buttons["jwt-encoder-apply-algorithm"].exists)
    let key = app.textViews["jwt-encoder-key"]
    reach(key); activate(key); key.typeText(String(repeating: "0123456789abcdef", count: 4))
    #if os(iOS)
    if app.buttons["Done"].firstMatch.isHittable { activate(app.buttons["Done"].firstMatch) }
    #endif
    let generate = app.buttons["jwt-encoder-generate"]
    reach(generate); activate(generate)
    let status = app.staticTexts["jwt-encoder-status"]
    expectation(for: NSPredicate(format: "label == 'JWT generated'"), evaluatedWith: status); waitForExpectations(timeout: 8)
    let output = app.textViews.matching(NSPredicate(format: "label == 'Generated JWT result'")).firstMatch
    let token = try XCTUnwrap(output.value as? String)
    let segment = try XCTUnwrap(token.split(separator: ".").first).description.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    let encoded = segment + String(repeating: "=", count: (4 - segment.count % 4) % 4)
    let decoded = try XCTUnwrap(Data(base64Encoded: encoded))
    XCTAssertEqual(String(decoding: decoded, as: UTF8.self), #"{"alg":"HS512","typ":"JWT"}"#)
    attachScreenshot("T078 Header determines selected algorithm and signature")
  }

  func testPasswordAndPassphraseGenerateCopySettingsAndPrivacy() throws {
    search("T-023"); activate(app.buttons["generators-T-023"])
    let status = app.staticTexts["secret-status"]
    XCTAssertTrue(status.waitForExistence(timeout: 6))
    XCTAssertEqual(app.textFields["secret-length"].value as? String, "13")
    XCTAssertFalse(app.buttons["secret-copy-all"].isEnabled)
    func generated(_ label: String) {
      activate(app.buttons["secret-generate"])
      expectation(for: NSPredicate(format: "label == %@", label), evaluatedWith: status)
      waitForExpectations(timeout: 8)
    }
    generated("Generated 1 password")
    let value = app.staticTexts["secret-single-value"]
    XCTAssertTrue(value.waitForExistence(timeout: 4))
    let password = value.label
    XCTAssertEqual(password.utf8.count, 13)
    activate(app.buttons["secret-copy-single"])
    activate(app.buttons["secret-visibility"])
    XCTAssertEqual(app.staticTexts["secret-single-value"].label, "Hidden result")
    activate(app.buttons["secret-visibility"])
    XCTAssertEqual(app.staticTexts["secret-single-value"].label, password)
    activate(app.buttons["secret-advanced"])
    let exclusions = app.textViews["secret-exclusions"]
    if !exclusions.isHittable { app.scrollViews.firstMatch.swipeUp() }
    XCTAssertTrue(exclusions.waitForExistence(timeout: 4))
    activate(exclusions)
    #if os(macOS)
    exclusions.typeKey("v", modifierFlags: .command)
    #else
    activate(exclusions); exclusions.press(forDuration: 1.2)
    if app.menuItems["Paste"].waitForExistence(timeout: 2) { activate(app.menuItems["Paste"]) }
    else { activate(app.buttons["Paste"] .firstMatch) }
    #endif
    XCTAssertEqual(exclusions.value as? String, password)
    #if os(iOS)
    let done = app.buttons["Done"].firstMatch
    if done.exists && done.isHittable { activate(done) }
    #endif
    activate(app.buttons["secret-clear"])
    XCTAssertFalse(app.buttons["secret-copy-all"].isEnabled)
    showSidebar(); clearSearch(); search("T-024"); activate(app.buttons["generators-T-024"])
    XCTAssertTrue(status.waitForExistence(timeout: 6))
    generated("Generated 1 phrase")
    let phrase = app.staticTexts["secret-single-value"].label
    XCTAssertGreaterThan(phrase.count, 10)
    activate(app.buttons["secret-copy-single"])
    activate(app.buttons["secret-advanced"])
    activate(app.descendants(matching: .any)["secret-append-digit"].firstMatch)
    XCTAssertEqual(app.staticTexts["secret-single-value"].label, phrase)
    generated("Generated 1 phrase")
    XCTAssertTrue(app.staticTexts["secret-single-value"].label.last?.isNumber == true)
    showSidebar(); clearSearch(); search("T-023"); activate(app.buttons["generators-T-023"])
    XCTAssertFalse(app.buttons["secret-copy-all"].isEnabled)
    generated("Generated 1 password")
    app.terminate()
    app.launchArguments = ["--navigation-ui-tests"]
    app.launch()
    XCTAssertTrue(app.buttons["secret-generate"].waitForExistence(timeout: 8))
    XCTAssertFalse(app.buttons["secret-copy-all"].isEnabled)
    XCTAssertEqual(app.textFields["secret-length"].value as? String, "13")
  }

  func testIdentifierFormatsCopyCustomAlphabetAndPrivacy() throws {
    search("T-022"); activate(app.buttons["generators-T-022"])
    #if os(iOS)
    chooseAppearance(app.frame.width < 600 ? "Dark" : "Light")
    #endif
    func choose(_ picker: String, _ value: String) {
      activate(app.buttons[picker])
      #if os(macOS)
      activate(app.menuItems[value])
      #else
      activate(app.buttons[value])
      #endif
    }
    func done() {
      #if os(iOS)
      let button = app.buttons["Done"].firstMatch
      if button.exists && button.isHittable { activate(button) }
      #endif
    }
    func replace(_ field: XCUIElement, _ value: String) {
      activate(field)
      let old = field.value as? String ?? ""
      field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + value)
      done()
    }
    let status = app.staticTexts["identifier-status"]
    func generate(_ count: Int) {
      activate(app.buttons["identifier-generate"])
      expectation(for: NSPredicate(format: "label == %@", "Generated \(count) identifier\(count == 1 ? "" : "s")"), evaluatedWith: status)
      waitForExpectations(timeout: 8)
    }
    func rowValue() -> String {
      let row = app.descendants(matching: .any)["identifier-row-0"].firstMatch
      XCTAssertTrue(row.waitForExistence(timeout: 4))
      return row.label.components(separatedBy: ", ").last ?? ""
    }
    XCTAssertTrue(status.waitForExistence(timeout: 6)); XCTAssertEqual(status.label, "Ready")
    XCTAssertFalse(app.buttons["identifier-copy-all"].isEnabled)
    generate(1)
    let uuid = rowValue()
    XCTAssertNotNil(UUID(uuidString: uuid)); XCTAssertEqual(Array(uuid)[14], "4")
    activate(app.buttons["identifier-copy-row-0"])
    choose("identifier-kind", "NanoID"); choose("identifier-alphabet", "Custom")
    let custom = app.textViews["identifier-custom-alphabet"]
    XCTAssertTrue(custom.waitForExistence(timeout: 4))
    #if os(macOS)
    activate(custom); custom.typeKey("v", modifierFlags: .command)
    #else
    custom.press(forDuration: 1.2)
    let paste = app.menuItems["Paste"].firstMatch
    if paste.waitForExistence(timeout: 3) { activate(paste) } else { activate(app.buttons["Paste"].firstMatch) }
    #endif
    XCTAssertEqual(custom.value as? String, uuid)
    done()
    XCTAssertTrue(app.staticTexts["identifier-option-error"].exists)
    XCTAssertFalse(app.buttons["identifier-generate"].isEnabled)
    activate(app.buttons["identifier-clear"])
    choose("identifier-alphabet", "Custom")
    activate(custom); custom.typeText("ab"); done()
    replace(app.textFields["identifier-count"], "3")
    replace(app.textFields["identifier-length"], "8")
    generate(3)
    let nano = rowValue(); XCTAssertEqual(nano.count, 8); XCTAssertTrue(nano.allSatisfy { $0 == "a" || $0 == "b" })
    let row = app.descendants(matching: .any)["identifier-row-0"].firstMatch
    activate(row); activate(app.buttons["identifier-details"])
    XCTAssertEqual(app.staticTexts["identifier-full-value"].label, nano)
    attachScreenshot("T022 NanoID native workspace")
    activate(app.buttons["identifier-copy-all"]); activate(app.buttons["One per line"])
    choose("identifier-kind", "ULID"); generate(3)
    let ulid = rowValue(); XCTAssertEqual(ulid.count, 26)
    choose("identifier-kind", "UUID v7"); generate(3)
    let v7 = rowValue(); XCTAssertNotNil(UUID(uuidString: v7)); XCTAssertEqual(Array(v7)[14], "7")
    choose("identifier-kind", "NanoID"); generate(3)
    activate(app.buttons["identifier-copy-all"]); activate(app.buttons["JSON array"])
    expectation(for: NSPredicate(format: "label == 'Generated 3 identifiers'"), evaluatedWith: status); waitForExpectations(timeout: 5)
    activate(app.buttons["identifier-clear"])
    choose("identifier-alphabet", "Custom")
    #if os(macOS)
    activate(custom); custom.typeKey("v", modifierFlags: .command)
    #else
    custom.press(forDuration: 1.2)
    let pasteJSON = app.menuItems["Paste"].firstMatch
    if pasteJSON.waitForExistence(timeout: 3) { activate(pasteJSON) } else { activate(app.buttons["Paste"].firstMatch) }
    #endif
    let json = try XCTUnwrap(custom.value as? String)
    let copied = try JSONDecoder().decode([String].self, from: Data(json.utf8))
    XCTAssertEqual(copied.count, 3); XCTAssertTrue(copied.allSatisfy { $0.count == 8 })
    done()
    app.terminate(); app.launchArguments = ["--navigation-ui-tests"]; app.launch()
    XCTAssertTrue(status.waitForExistence(timeout: 8)); XCTAssertEqual(status.label, "Ready")
    XCTAssertFalse(app.buttons["identifier-copy-all"].isEnabled)
    XCTAssertEqual(app.textFields["identifier-count"].value as? String, "3")
    XCTAssertEqual(app.textFields["identifier-length"].value as? String, "8")
    XCTAssertFalse(custom.exists)
  }

  func testBasicAuthBuildRevealCopyClearAndPrivacy() {
    search("T-021"); activate(app.buttons["encoders-T-021"])
    #if os(iOS)
    if app.frame.width < 600 { chooseAppearance("Dark") }
    #endif
    let username = app.textFields["basic-auth-username"]
    let password = app.secureTextFields["basic-auth-password"]
    XCTAssertTrue(username.waitForExistence(timeout: 6)); XCTAssertTrue(password.exists)
    activate(username); username.typeText("Aladdin")
    activate(password); password.typeText("open sesame")
    XCTAssertTrue(app.staticTexts["basic-auth-status"].label.contains("Ready"))
    activate(app.buttons["basic-auth-build"])
    let status = app.staticTexts["basic-auth-status"]
    expectation(for: NSPredicate(format: "label CONTAINS 'Header generated'"), evaluatedWith: status); waitForExpectations(timeout: 6)
    XCTAssertTrue(app.buttons["basic-auth-copy-header"].isEnabled)
    XCTAssertFalse(app.textViews.matching(NSPredicate(format: "label == 'Authorization header result'")).firstMatch.exists)
    XCTAssertFalse((password.value as? String ?? "").contains("open sesame"))
    activate(app.buttons["basic-auth-show-password"])
    XCTAssertTrue(app.staticTexts["basic-auth-password-preview"].label.contains("open sesame"))
    activate(app.buttons["basic-auth-show-password"])
    XCTAssertFalse(app.staticTexts["basic-auth-password-preview"].exists)
    activate(app.buttons["basic-auth-reveal-header"])
    let output = app.textViews.matching(NSPredicate(format: "label == 'Authorization header result'")).firstMatch
    XCTAssertTrue(output.waitForExistence(timeout: 4))
    XCTAssertEqual(output.value as? String, "Authorization: Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==")
    activate(app.buttons["basic-auth-reveal-header"])
    XCTAssertFalse(output.exists)
    activate(app.buttons["basic-auth-copy-value"])
    activate(app.buttons["basic-auth-clear"])
    XCTAssertFalse(app.buttons["basic-auth-copy-header"].isEnabled)
    #if os(macOS)
    activate(username); username.typeKey("v", modifierFlags: .command)
    #else
    username.press(forDuration: 1.2)
    let paste = app.menuItems["Paste"].firstMatch
    if paste.waitForExistence(timeout: 3) { activate(paste) } else { activate(app.buttons["Paste"].firstMatch) }
    #endif
    XCTAssertEqual(username.value as? String, "Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==")
    XCTAssertTrue(status.label.contains("Ready")) // No Build-on-Paste.
    attachScreenshot("T021 native form")
    app.terminate(); app.launchArguments = ["--navigation-ui-tests"]; app.launch()
    XCTAssertTrue(username.waitForExistence(timeout: 8))
    XCTAssertEqual(username.value as? String, "Enter username")
    XCTAssertTrue(status.label.contains("Ready"))
    XCTAssertFalse(app.buttons["basic-auth-copy-header"].isEnabled)
  }

  func testJWTInspectorPasteMaskDiagnosticsAndPrivacy() {
    search("T-020"); activate(app.buttons["encoders-T-020"])
    #if os(iOS)
    if app.frame.width < 600 { chooseAppearance("Dark") }
    #endif
    let input = app.textViews.matching(NSPredicate(format: "label == 'JWT input'")).firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    let token = "eyJhbGciOiJub25lIn0.eyJzdWIiOiJ0ZXN0In0."
    activate(input); input.typeText(token)
    let status = app.staticTexts["jwt-status"]
    XCTAssertTrue(status.label.contains("Ready"))
    activate(app.buttons["jwt-decode"])
    expectation(for: NSPredicate(format: "label CONTAINS 'Decoded'"), evaluatedWith: status); waitForExpectations(timeout: 8)
    func choose(_ value: String) {
      activate(app.buttons["jwt-section"])
      #if os(macOS)
      activate(app.menuItems[value])
      #else
      activate(app.buttons[value])
      #endif
    }
    choose("Payload")
    let output = app.textViews.matching(NSPredicate(format: "label == 'JWT Payload result'")).firstMatch
    XCTAssertTrue(output.waitForExistence(timeout: 5)); XCTAssertTrue((output.value as? String)?.contains("test") == true)
    activate(app.buttons["jwt-mask"])
    let maskTrace = XCTAttachment(string: app.debugDescription); maskTrace.name = "T020 masked AX hierarchy"; maskTrace.lifetime = .keepAlways; add(maskTrace)
    let maskShot = XCTAttachment(screenshot: app.screenshot()); maskShot.name = "T020 masked diagnostic frame"; maskShot.lifetime = .keepAlways; add(maskShot)
    XCTAssertTrue(app.buttons["jwt-mask"].label.contains("Reveal"), "Mask action must have completed")
    XCTAssertFalse(input.exists, "Input AX: \(input.debugDescription)"); XCTAssertFalse(output.exists)
    XCTAssertFalse(app.buttons["jwt-copy"].isEnabled)
    let masked = XCTAttachment(screenshot: app.screenshot()); masked.name = "T020 masked"; masked.lifetime = .keepAlways; add(masked)
    activate(app.buttons["jwt-mask"])
    XCTAssertEqual(input.value as? String, token)
    activate(app.buttons["jwt-copy"])
    #if os(macOS)
    activate(app.menuItems["Copy Raw JSON"])
    #else
    activate(app.buttons["Copy Raw JSON"])
    #endif
    activate(app.buttons["jwt-clear"])
    #if os(macOS)
    activate(input); input.typeKey("v", modifierFlags: .command)
    #else
    input.press(forDuration: 1.2)
    let paste = app.menuItems["Paste"].firstMatch
    if paste.waitForExistence(timeout: 3) { activate(paste) } else { activate(app.buttons["Paste"].firstMatch) }
    #endif
    // Pasted decoded JSON is not a compact token. Native Paste starts inspection.
    expectation(for: NSPredicate(format: "label CONTAINS 'Unable'"), evaluatedWith: status); waitForExpectations(timeout: 8)
    XCTAssertEqual(input.value as? String, "{\"sub\":\"test\"}")
    XCTAssertTrue(app.buttons["jwt-show-detection"].exists)
    activate(app.buttons["jwt-show-detection"])
    activate(app.buttons["jwt-clear"]); activate(input); input.typeText(token)
    activate(app.buttons["jwt-decode"])
    expectation(for: NSPredicate(format: "label CONTAINS 'Decoded'"), evaluatedWith: status); waitForExpectations(timeout: 8)
    choose("Claims")
    let screen = XCTAttachment(screenshot: app.screenshot()); screen.name = "T020 claims"; screen.lifetime = .keepAlways; add(screen)
    app.terminate(); app.launchArguments = ["--navigation-ui-tests"]; app.launch()
    XCTAssertTrue(input.waitForExistence(timeout: 8)); XCTAssertEqual(input.value as? String, "")
    XCTAssertTrue(app.staticTexts["jwt-status"].label.contains("Ready"))
  }

  func testBase64FileTextDataURLAndPrivacy() {
    search("T-013"); activate(app.buttons["encoders-T-013"])
    func choose(_ picker: String, _ value: String) {
      activate(app.buttons[picker])
      #if os(macOS)
      activate(app.menuItems[value])
      #else
      let item = app.buttons[value]
      if item.exists { activate(item) } else { activate(app.staticTexts[value]) }
      #endif
    }
    choose("b64file-direction", "Base64 → File")
    let input = app.textViews.matching(NSPredicate(format: "label == 'Base64 file input'")).firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    activate(input); input.typeText("YQ==")
    activate(app.buttons["b64file-convert"])
    let status = app.staticTexts["b64file-status"]
    expectation(for: NSPredicate(format: "label == 'Completed'"), evaluatedWith: status)
    waitForExpectations(timeout: 5)
    XCTAssertTrue(app.buttons["b64file-export"].isEnabled)
    XCTAssertFalse(app.buttons["b64file-copy"].isEnabled)
    activate(app.buttons["b64file-check"])
    expectation(for: NSPredicate(format: "label CONTAINS 'Valid'"), evaluatedWith: status)
    waitForExpectations(timeout: 5)
    if app.buttons["b64file-collapse-result"].exists && app.buttons["b64file-collapse-result"].label == "Expand Result" {
      activate(app.buttons["b64file-collapse-result"])
    }
    let output = app.textViews.matching(NSPredicate(format: "label == 'Base64 file result'")).firstMatch
    XCTAssertTrue((output.value as? String)?.contains("61") == true)
    choose("b64file-format", "Data URL")
    XCTAssertEqual(input.value as? String,"YQ==")
    activate(app.buttons["b64file-clear"]); activate(input)
    input.typeText("data:image/png;base64,YQ==")
    activate(app.buttons["b64file-convert"])
    expectation(for: NSPredicate(format: "label == 'Completed'"), evaluatedWith: status)
    waitForExpectations(timeout: 5)
    if app.buttons["b64file-image"].isHittable {
      activate(app.buttons["b64file-image"])
      XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'No supported raster image'")).firstMatch.waitForExistence(timeout: 5))
      activate(app.buttons["Done"])
    }
    activate(app.buttons["b64file-clear"]); activate(input); input.typeText("data:;base64,A")
    activate(app.buttons["b64file-check"])
    XCTAssertTrue(app.buttons["b64file-show-input"].waitForExistence(timeout: 5))
    activate(app.buttons["b64file-show-input"])
    let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "T013 Data URL EOF diagnostic"; capture.lifetime = .keepAlways; add(capture)
    activate(app.buttons["b64file-export"])
    // Real system folder selection is presented; cancellation must keep input.
    let cancel = app.buttons.matching(NSPredicate(format: "label == 'Cancel' OR label == 'Close'")).firstMatch
    XCTAssertTrue(cancel.waitForExistence(timeout: 5), app.debugDescription)
    let pickerCapture = XCTAttachment(screenshot: app.screenshot()); pickerCapture.name = "T013 system folder picker"; pickerCapture.lifetime = .keepAlways; add(pickerCapture)
    activate(cancel)
    XCTAssertEqual(input.value as? String,"data:;base64,A")
    app.terminate(); app.launchArguments = ["--navigation-ui-tests"]; app.launch()
    let restored = app.textViews.matching(NSPredicate(format: "label == 'Base64 file input'")).firstMatch
    XCTAssertTrue(restored.waitForExistence(timeout: 5)); XCTAssertEqual(restored.value as? String,"")
  }

  #if os(iOS)
  func testBase64FileExportToLocalFolder() {
    search("T-013"); activate(app.buttons["encoders-T-013"])
    activate(app.buttons["b64file-direction"]); activate(app.buttons["Base64 → File"])
    let input = app.textViews.matching(NSPredicate(format: "label == 'Base64 file input'")).firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5)); activate(input); input.typeText("YQ==")
    activate(app.buttons["b64file-convert"])
    let status = app.staticTexts["b64file-status"]
    expectation(for: NSPredicate(format: "label == 'Completed'"), evaluatedWith: status); waitForExpectations(timeout: 5)
    activate(app.buttons["b64file-export"])
    XCTAssertTrue(app.buttons["DOCPicker.actionButton"].waitForExistence(timeout: 12),app.debugDescription)
    let browse = app.buttons["Browse"].firstMatch
    if browse.waitForExistence(timeout: 3) { activate(browse) }
    let local = app.staticTexts.matching(NSPredicate(format: "label == 'On My iPhone' OR label == 'On My iPad'")).firstMatch
    XCTAssertTrue(local.waitForExistence(timeout: 8), app.debugDescription)
    activate(local)
    let choose = app.buttons.matching(NSPredicate(format: "label == 'Open' OR label == 'Choose' OR label == 'Select'")).firstMatch
    XCTAssertTrue(choose.waitForExistence(timeout: 5),app.debugDescription)
    expectation(for: NSPredicate(format: "enabled == true AND hittable == true"), evaluatedWith: choose)
    waitForExpectations(timeout: 8)
    activate(choose)
    let name = app.textFields["b64file-export-name"]
    XCTAssertTrue(name.waitForExistence(timeout: 10),app.debugDescription)
    activate(name)
    let stem = "t013-" + UUID().uuidString
    name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,count: 11) + stem + ".bin")
    activate(app.buttons["b64file-export-confirm"])
    expectation(for: NSPredicate(format: "label BEGINSWITH 'Saved '"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    // Import the exact file just exported through the real file picker, then encode its byte.
    activate(app.buttons["b64file-direction"]); activate(app.buttons["File → Base64"])
    activate(app.buttons["b64file-choose"])
    // Single-file picking opens on tap and has no folder-only Open button.
    XCTAssertTrue(app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].waitForExistence(timeout: 12),app.debugDescription)
    let sourceName = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@",stem)).firstMatch
    if !sourceName.exists {
      let browseAgain = app.buttons["Browse"].firstMatch
      if browseAgain.exists && browseAgain.isHittable { activate(browseAgain) }
      let localAgain = app.staticTexts.matching(NSPredicate(format: "label == 'On My iPhone' OR label == 'On My iPad'")).firstMatch
      if localAgain.waitForExistence(timeout: 5) && localAgain.isHittable { activate(localAgain) }
    }
    XCTAssertTrue(sourceName.waitForExistence(timeout: 8),app.debugDescription)
    let sourceCell = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@",stem)).firstMatch
    XCTAssertTrue(sourceCell.exists)
    sourceCell.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.25)).tap()
    let imported = app.descendants(matching: .any).matching(identifier: "b64file-name").firstMatch
    if !imported.waitForExistence(timeout: 2) {
      let open = app.buttons["DOCPicker.actionButton"]
      if open.exists && open.isEnabled && open.isHittable { activate(open) }
    }
    XCTAssertTrue(imported.waitForExistence(timeout: 8),app.debugDescription)
    activate(app.buttons["b64file-convert"])
    expectation(for: NSPredicate(format: "label == 'Completed'"), evaluatedWith: status); waitForExpectations(timeout: 5)
    XCTAssertTrue(app.buttons["b64file-copy"].isEnabled)
    let encoded = app.textViews.matching(NSPredicate(format: "label == 'Base64 file result'")).firstMatch
    XCTAssertEqual(encoded.value as? String,"YQ==")
  }
  #endif

  func testURLQueryProfilesAndStructuralUndo() {
    search("T-015"); activate(app.buttons["encoders-T-015"])
    let input = app.textViews.matching(NSPredicate(format: "label == 'URL input'")).firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5)); activate(input); input.typeText("?flag&x=a+b&x=two")
    activate(app.buttons["url-query-parse"]); activate(app.buttons["url-query-collapse-input"])
    let table = app.tables["url-query-list"]
    XCTAssertTrue(table.cells.element(boundBy: 1).waitForExistence(timeout: 5))
    activate(table.cells.element(boundBy: 1)); activate(app.buttons["url-query-row-actions"])
    #if os(macOS)
      activate(app.menuItems["Move Up"])
    #else
      activate(app.buttons["Move Up"])
    #endif
    XCTAssertTrue(table.cells.element(boundBy: 0).label.contains("a+b"))
    activate(app.buttons["url-query-profile"])
    #if os(macOS)
      activate(app.menuItems["Form · + means space"])
    #else
      activate(app.buttons["Form · + means space"])
    #endif
    activate(app.buttons["Discard Query Edits"])
    expectation(for: NSPredicate(format: "label CONTAINS 'a b'"), evaluatedWith: table.cells.element(boundBy: 1)); waitForExpectations(timeout: 5)
    activate(app.buttons["url-query-add"])
    let name = app.textFields["url-query-edit-name"]
    XCTAssertTrue(name.waitForExistence(timeout: 5)); activate(name); name.typeText("extra")
    let value = app.textViews["url-query-edit-value"]
    activate(value); value.typeText("hello world"); activate(app.buttons["url-query-edit-apply"])
    activate(app.buttons["url-query-build"])
    let output = app.textViews.matching(NSPredicate(format: "label == 'URL result'")).firstMatch
    expectation(for: NSPredicate(format: "value == '?flag&x=a+b&x=two&extra=hello+world'"), evaluatedWith: output); waitForExpectations(timeout: 5)
    for _ in 0..<2 {
      activate(app.buttons["url-query-actions"])
      #if os(macOS)
        activate(app.menuItems["Undo Query Change"])
      #else
        activate(app.buttons["Undo Query Change"])
      #endif
    }
    activate(app.buttons["url-query-build"])
    expectation(for: NSPredicate(format: "value == '?flag&x=a+b&x=two'"), evaluatedWith: output); waitForExpectations(timeout: 5)
    let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "T015 Profiles and Undo"; shot.lifetime = .keepAlways; add(shot)
  }

  #if os(iOS)
  func testGZipExportToLocalFolder() {
    search("T-019"); activate(app.buttons["encoders-T-019"])
    let input = app.textViews.matching(NSPredicate(format:"label == 'GZip input'")).firstMatch
    XCTAssertTrue(input.waitForExistence(timeout:5)); activate(input); input.typeText("hello\n")
    activate(app.buttons["gzip-convert"])
    let status = app.staticTexts["gzip-status"]
    expectation(for:NSPredicate(format:"label == 'Completed'"),evaluatedWith:status); waitForExpectations(timeout:5)
    func choose(_ picker:String,_ value:String) { activate(app.buttons[picker]); activate(app.buttons[value]) }
    func state(_ value:String) { expectation(for:NSPredicate(format:"label == %@",value),evaluatedWith:status); waitForExpectations(timeout:8) }
    let output = app.textViews.matching(NSPredicate(format:"label == 'GZip result'")).firstMatch
    func value(_ element:XCUIElement,_ expected:String) { expectation(for:NSPredicate(format:"value == %@",expected),evaluatedWith:element); waitForExpectations(timeout:5) }
      // Real explicit export, then choose the exact exported gzip as file input.
      activate(app.buttons["gzip-export"])
      let name = app.textFields["gzip-export-name"]
      XCTAssertTrue(name.waitForExistence(timeout:10),app.debugDescription)
      XCTAssertEqual(name.value as? String,"compressed.gz")
      XCTAssertTrue(app.buttons["gzip-export-confirm"].isEnabled,"Default valid filename must work without editing it")
      activate(name)
      let stem = "t019-" + UUID().uuidString
      name.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:13) + stem + ".gz")
      activate(app.buttons["gzip-export-confirm"])
      XCTAssertTrue(app.buttons["DOCPicker.actionButton"].waitForExistence(timeout:12),app.debugDescription)
      let browse = app.buttons["Browse"].firstMatch
      if browse.waitForExistence(timeout:3) { activate(browse) }
      let local = app.staticTexts.matching(NSPredicate(format:"label == 'On My iPhone' OR label == 'On My iPad'")).firstMatch
      XCTAssertTrue(local.waitForExistence(timeout:8),app.debugDescription); activate(local)
      let select = app.buttons.matching(NSPredicate(format:"label == 'Open' OR label == 'Choose' OR label == 'Select'")).firstMatch
      expectation(for:NSPredicate(format:"enabled == true AND hittable == true"),evaluatedWith:select); waitForExpectations(timeout:8)
      let before = XCTAttachment(screenshot:app.screenshot()); before.name="T019 folder before confirmation"; before.lifetime = .keepAlways; add(before)
      // Use the trailing side of the actual picker action; the iPhone glass bar's
      // AX center did not reliably dispatch the confirmation in prior runtime samples.
      select.coordinate(withNormalizedOffset:CGVector(dx:0.8,dy:0.5)).press(forDuration:0.2)
      if select.waitForNonExistence(timeout:3) == false && select.isHittable {
        select.coordinate(withNormalizedOffset:CGVector(dx:0.8,dy:0.5)).tap()
      }
      let after = XCTAttachment(screenshot:app.screenshot()); after.name="T019 folder after confirmation"; after.lifetime = .keepAlways; add(after)
      expectation(for:NSPredicate(format:"label BEGINSWITH 'Saved '"),evaluatedWith:status); waitForExpectations(timeout:10)
      choose("gzip-direction","Decompress"); choose("gzip-source","File"); activate(app.buttons["gzip-choose"])
      XCTAssertTrue(app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].waitForExistence(timeout:12),app.debugDescription)
      let sourceName = app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@",stem)).firstMatch
      if !sourceName.exists {
        let browseAgain = app.buttons["Browse"].firstMatch
        if browseAgain.exists && browseAgain.isHittable { activate(browseAgain) }
        let localAgain = app.staticTexts.matching(NSPredicate(format:"label == 'On My iPhone' OR label == 'On My iPad'")).firstMatch
        if localAgain.waitForExistence(timeout:5) && localAgain.isHittable { activate(localAgain) }
      }
      XCTAssertTrue(sourceName.waitForExistence(timeout:8),app.debugDescription)
      let cell = app.cells.matching(NSPredicate(format:"label BEGINSWITH %@",stem)).firstMatch
      XCTAssertTrue(cell.exists); cell.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.25)).tap()
      let imported = app.descendants(matching:.any).matching(identifier:"gzip-file-name").firstMatch
      if !imported.waitForExistence(timeout:2) {
        let open = app.buttons["DOCPicker.actionButton"]
        if open.exists && open.isEnabled && open.isHittable { activate(open) }
      }
      XCTAssertTrue(imported.waitForExistence(timeout:8),app.debugDescription)
      activate(app.buttons["gzip-convert"]); state("Completed"); value(output,"hello\n")
      choose("gzip-source","Base64")
  }
  #endif

  func testGZipTextPasteDiagnosticsExportAndPrivacy() {
    search("T-019"); activate(app.buttons["encoders-T-019"])
    func choose(_ picker: String, _ value: String) {
      activate(app.buttons[picker])
      #if os(macOS)
        activate(app.menuItems[value])
      #else
        activate(app.buttons[value])
      #endif
    }
    let input = app.textViews.matching(NSPredicate(format:"label == 'GZip input'")).firstMatch
    let output = app.textViews.matching(NSPredicate(format:"label == 'GZip result'")).firstMatch
    let status = app.staticTexts["gzip-status"]
    func value(_ field:XCUIElement,_ value:String) {
      XCTAssertTrue(field.waitForExistence(timeout:5))
      expectation(for:NSPredicate(format:"value == %@",value),evaluatedWith:field); waitForExpectations(timeout:5)
    }
    func state(_ label:String) {
      expectation(for:NSPredicate(format:"label == %@",label),evaluatedWith:status); waitForExpectations(timeout:8)
    }
    choose("gzip-direction","Decompress")
    XCTAssertTrue(input.waitForExistence(timeout:5)); activate(input)
    input.typeText("H4sIAAAAAAAC/8tIzcnJ5wIAIDA6NgYAAAA=")
    activate(app.buttons["gzip-convert"]); state("Completed"); value(output,"hello\n")
    activate(app.buttons["gzip-check"]); state("Valid gzip · checked"); value(output,"hello\n")
    choose("gzip-copy","Copy Text")
    choose("gzip-direction","Compress"); activate(app.buttons["gzip-clear"])
    #if os(macOS)
      activate(input); input.typeKey("v",modifierFlags:.command)
    #else
      input.press(forDuration:1.2)
      let paste = app.menuItems["Paste"].firstMatch
      if paste.waitForExistence(timeout:3) { activate(paste) } else { activate(app.buttons["Paste"].firstMatch) }
    #endif
    state("Ready to compress"); value(input,"hello\n")
    XCTAssertFalse(app.buttons["gzip-copy"].isEnabled)
    activate(app.buttons["gzip-convert"]); state("Completed")
    XCTAssertTrue(app.buttons["gzip-copy"].isEnabled)
    let conversion = XCTAttachment(screenshot:app.screenshot()); conversion.name="T019 gzip workspace"; conversion.lifetime = .keepAlways; add(conversion)
    choose("gzip-direction","Decompress")
    activate(app.buttons["gzip-clear"]); activate(input); input.typeText("YQ=")
    activate(app.buttons["gzip-check"]); state("Invalid Base64"); activate(app.buttons["gzip-show-input"])
    let error = XCTAttachment(screenshot:app.screenshot()); error.name="T019 Base64 EOF diagnostic"; error.lifetime = .keepAlways; add(error)
    app.terminate(); app.launchArguments=["--navigation-ui-tests"]; app.launch()
    value(input,""); XCTAssertFalse(app.buttons["gzip-copy"].isEnabled); XCTAssertFalse(app.buttons["gzip-export"].isEnabled)
  }

  func testHexBytesProfilesPasteDiagnosticsAndPrivacy() {
    search("T-018"); activate(app.buttons["encoders-T-018"])
    func choose(_ picker: String, _ value: String) {
      activate(app.buttons[picker])
      #if os(macOS)
        activate(app.menuItems[value])
      #else
        activate(app.buttons[value])
      #endif
    }
    func editor(_ name: String) -> XCUIElement { app.textViews.matching(NSPredicate(format:"label == %@",name)).firstMatch }
    func expectValue(_ name: String, _ value: String) {
      let field = editor(name); XCTAssertTrue(field.waitForExistence(timeout:5))
      expectation(for:NSPredicate(format:"value == %@",value),evaluatedWith:field); waitForExpectations(timeout:5)
    }
    let input = editor("Hex input")
    XCTAssertTrue(input.waitForExistence(timeout:5))
    activate(app.buttons["hex-bytes-convert"])
    expectValue("Text result", "")
    activate(input); input.typeText("48 69")
    activate(app.buttons["hex-bytes-convert"]); expectValue("Text result", "Hi")
    activate(app.buttons["hex-bytes-check"])
    choose("hex-bytes-copy", "Copy Text")
    choose("hex-bytes-direction", "Text → Hex")
    activate(app.buttons["hex-bytes-clear"])
    let text = editor("Text input")
    #if os(macOS)
      activate(text); text.typeKey("v",modifierFlags:.command)
    #else
      text.press(forDuration:1.2)
      let paste = app.menuItems["Paste"].firstMatch
      if paste.waitForExistence(timeout:3) { activate(paste) } else { activate(app.buttons["Paste"].firstMatch) }
    #endif
    let status = app.staticTexts["hex-bytes-status"]
    expectation(for:NSPredicate(format:"label BEGINSWITH 'Checked'"),evaluatedWith:status); waitForExpectations(timeout:5)
    expectValue("Text input", "Hi")
    XCTAssertFalse(app.buttons["hex-bytes-copy"].isEnabled)
    activate(app.buttons["hex-bytes-convert"]); expectValue("Hex result", "48 69")
    choose("hex-bytes-output-view", "Bytes")
    XCTAssertTrue(app.otherElements["hex-bytes-row-0"].firstMatch.waitForExistence(timeout:3) || app.scrollViews["hex-bytes-inspector"].exists || app.tables.firstMatch.exists || app.collectionViews.firstMatch.exists)
    let conversion = XCTAttachment(screenshot:app.screenshot()); conversion.name="T018 bytes inspector"; conversion.lifetime = .keepAlways; add(conversion)
    choose("hex-bytes-output-view", "Hex")
    expectValue("Hex result", "48 69")
    choose("hex-bytes-direction", "Hex → UTF-8 / Bytes")
    activate(app.buttons["hex-bytes-clear"]); activate(input); input.typeText("F0 9F 98")
    activate(app.buttons["hex-bytes-convert"])
    expectation(for:NSPredicate(format:"label CONTAINS 'Not valid UTF-8'"),evaluatedWith:status); waitForExpectations(timeout:5)
    activate(app.buttons["hex-bytes-show-input"]); activate(app.buttons["hex-bytes-show-related"])
    let diagnostic = XCTAttachment(screenshot:app.screenshot()); diagnostic.name="T018 UTF8 EOF related"; diagnostic.lifetime = .keepAlways; add(diagnostic)
    choose("hex-bytes-copy", "Copy Hex")
    choose("hex-bytes-input-format", "0x bytes")
    activate(app.buttons["hex-bytes-clear"]); activate(input); input.typeText("0x48, 0x69")
    activate(app.buttons["hex-bytes-convert"]); expectValue("Text result", "Hi")
    choose("hex-bytes-input-format", "\\x bytes")
    activate(app.buttons["hex-bytes-clear"]); activate(input); input.typeText(#"\xF0\x9F\x98\x80"#)
    activate(app.buttons["hex-bytes-convert"]); expectValue("Text result", "😀")
    activate(app.buttons["hex-bytes-clear"]); activate(input); input.typeText(#"\x4"#)
    activate(app.buttons["hex-bytes-check"])
    expectation(for:NSPredicate(format:"label == 'Invalid hex'"),evaluatedWith:status); waitForExpectations(timeout:5)
    XCTAssertFalse(app.buttons["hex-bytes-copy"].isEnabled)
    app.terminate(); app.launchArguments=["--navigation-ui-tests"]; app.launch()
    XCTAssertTrue(input.waitForExistence(timeout:8)); XCTAssertEqual(input.value as? String, "")
    XCTAssertFalse(app.buttons["hex-bytes-copy"].isEnabled)
    activate(input); input.typeText(#"\x41"#)
    activate(app.buttons["hex-bytes-convert"]); expectValue("Text result", "A")
  }

  func testStringEscapeProfilesPasteDiagnosticsAndPrivacy() {
    search("T-017"); activate(app.buttons["encoders-T-017"])
    func choose(_ picker: String, _ value: String) {
      activate(app.buttons[picker])
      #if os(macOS)
        activate(app.menuItems[value])
      #else
        activate(app.buttons[value])
      #endif
    }
    func expectValue(_ label: String, _ value: String) {
      let editor = app.textViews.matching(NSPredicate(format: "label == %@", label)).firstMatch
      XCTAssertTrue(editor.waitForExistence(timeout: 5))
      expectation(for: NSPredicate(format:"value == %@",value),evaluatedWith:editor)
      waitForExpectations(timeout:5)
    }
    let input = app.textViews.matching(NSPredicate(format:"label == 'Text input'")).firstMatch
    XCTAssertTrue(input.waitForExistence(timeout:5))
    activate(app.buttons["string-escape-convert"])
    expectValue("String literal result", "\"\"")
    activate(input); input.typeText("a\nb")
    activate(app.buttons["string-escape-convert"])
    expectValue("String literal result", #""a\nb""#)
    activate(app.buttons["string-escape-check"])
    XCTAssertTrue(app.buttons["string-escape-copy"].isEnabled)
    activate(app.buttons["string-escape-copy"])
    choose("string-escape-direction", "Unescape")
    activate(app.buttons["string-escape-clear"])
    let literal = app.textViews.matching(NSPredicate(format:"label == 'String literal input'")).firstMatch
    #if os(macOS)
      activate(literal); literal.typeKey("v",modifierFlags:.command)
    #else
      literal.press(forDuration:1.2)
      let paste = app.menuItems["Paste"].firstMatch
      if paste.waitForExistence(timeout:3) { activate(paste) } else { activate(app.buttons["Paste"].firstMatch) }
    #endif
    let status = app.staticTexts["string-escape-status"]
    expectation(for:NSPredicate(format:"label BEGINSWITH 'Checked'"),evaluatedWith:status); waitForExpectations(timeout:5)
    XCTAssertFalse(app.buttons["string-escape-copy"].isEnabled)
    activate(app.buttons["string-escape-convert"])
    expectValue("Text result", "a\nb")
    choose("string-escape-language", "Swift")
    choose("string-escape-representation", "String contents")
    activate(app.buttons["string-escape-clear"]); activate(literal); literal.typeText(#"\u{1F600}"#)
    activate(app.buttons["string-escape-convert"]); expectValue("Text result", "😀")
    choose("string-escape-language", "JavaScript")
    activate(app.buttons["string-escape-clear"]); activate(literal); literal.typeText(#"\x41\u{1F600}"#)
    activate(app.buttons["string-escape-convert"]); expectValue("Text result", "A😀")
    let conversion = XCTAttachment(screenshot:app.screenshot()); conversion.name="T017 JavaScript conversion"; conversion.lifetime = .keepAlways; add(conversion)
    choose("string-escape-representation", "Quoted literal")
    choose("string-escape-settings", "Single quotes")
    activate(app.buttons["string-escape-clear"]); activate(literal); literal.typeText("'it\\'s'")
    activate(app.buttons["string-escape-convert"]); expectValue("Text result", "it's")
    activate(app.buttons["string-escape-clear"]); activate(literal); literal.typeText("'a\\u12")
    activate(app.buttons["string-escape-convert"])
    expectation(for:NSPredicate(format:"label CONTAINS 'Invalid string syntax'"),evaluatedWith:status); waitForExpectations(timeout:5)
    XCTAssertFalse(app.buttons["string-escape-copy"].isEnabled)
    XCTAssertTrue(app.buttons["string-escape-show-input"].waitForExistence(timeout:3))
    activate(app.buttons["string-escape-show-input"])
    activate(app.buttons["string-escape-show-related"])
    let diagnostic = XCTAttachment(screenshot:app.screenshot()); diagnostic.name="T017 EOF and related diagnostic"; diagnostic.lifetime = .keepAlways; add(diagnostic)
    app.terminate(); app.launchArguments=["--navigation-ui-tests"]; app.launch()
    XCTAssertTrue(literal.waitForExistence(timeout:8)); XCTAssertEqual(literal.value as? String, "")
    XCTAssertFalse(app.buttons["string-escape-copy"].isEnabled)
    // Last language, direction, representation and single-quote choice are restored, not the source.
    activate(literal); literal.typeText("'ok'")
    activate(app.buttons["string-escape-convert"]); expectValue("Text result", "ok")
  }

  func testHTMLEntityContextsPasteStrictDiagnosticsAndPrivacy() {
    search("T-016"); activate(app.buttons["encoders-T-016"])
    func choose(_ picker: String, _ value: String) {
      activate(app.buttons[picker])
      #if os(macOS)
        activate(app.menuItems[value])
      #else
        activate(app.buttons[value])
      #endif
    }
    let input = app.textViews.matching(NSPredicate(format: "label == 'Text input'")).firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    let source = "A&B <C> \"'"
    activate(input); input.typeText(source)
    activate(app.buttons["html-entity-convert"])
    let encoded = app.textViews.matching(NSPredicate(format: "label == 'HTML references result'")).firstMatch
    expectation(for: NSPredicate(format: "value == %@", "A&amp;B &lt;C&gt; \"'"), evaluatedWith: encoded)
    waitForExpectations(timeout: 5)
    activate(app.buttons["html-entity-check"])
    XCTAssertTrue(app.buttons["html-entity-copy"].isEnabled)
    choose("html-entity-context", "Double-quoted attribute")
    XCTAssertFalse(app.buttons["html-entity-copy"].isEnabled)
    activate(app.buttons["html-entity-convert"])
    expectation(for: NSPredicate(format: "value == %@", "A&amp;B &lt;C&gt; &quot;'"), evaluatedWith: encoded)
    waitForExpectations(timeout: 5)
    activate(app.buttons["html-entity-copy"])
    choose("html-entity-direction", "Decode")
    activate(app.buttons["html-entity-clear"])
    let references = app.textViews.matching(NSPredicate(format: "label == 'HTML references input'")).firstMatch
    #if os(macOS)
      activate(references); references.typeKey("v", modifierFlags: .command)
    #else
      references.press(forDuration: 1.2)
      let paste = app.menuItems["Paste"].firstMatch
      if paste.waitForExistence(timeout: 3) { activate(paste) } else { activate(app.buttons["Paste"].firstMatch) }
    #endif
    let status = app.staticTexts["html-entity-status"]
    expectation(for: NSPredicate(format: "label BEGINSWITH 'Checked'"), evaluatedWith: status)
    waitForExpectations(timeout: 5)
    XCTAssertFalse(app.buttons["html-entity-copy"].isEnabled)
    activate(app.buttons["html-entity-convert"])
    let output = app.textViews.matching(NSPredicate(format: "label == 'Text result'")).firstMatch
    expectation(for: NSPredicate(format: "value == %@", source), evaluatedWith: output)
    waitForExpectations(timeout: 5)
    let firstShot = XCTAttachment(screenshot: app.screenshot()); firstShot.name = "T016 Entity conversion"; firstShot.lifetime = .keepAlways; add(firstShot)
    activate(app.buttons["html-entity-clear"]); activate(references); references.typeText("&amp;lt; &copy")
    activate(app.buttons["html-entity-convert"])
    expectation(for: NSPredicate(format: "value == '&lt; ©'"), evaluatedWith: output)
    waitForExpectations(timeout: 5)
    XCTAssertTrue(app.buttons["html-entity-copy"].isEnabled)
    activate(app.buttons["html-entity-settings"])
    #if os(macOS)
      activate(app.menuItems["Strict references"])
    #else
      activate(app.buttons["Strict references"])
    #endif
    activate(app.buttons["html-entity-convert"])
    expectation(for: NSPredicate(format: "label CONTAINS 'Cannot convert'"), evaluatedWith: status)
    waitForExpectations(timeout: 5)
    XCTAssertFalse(app.buttons["html-entity-copy"].isEnabled)
    XCTAssertTrue(app.buttons["html-entity-show-input"].waitForExistence(timeout: 3))
    activate(app.buttons["html-entity-show-input"])
    let errorShot = XCTAttachment(screenshot: app.screenshot()); errorShot.name = "T016 Strict EOF diagnostic"; errorShot.lifetime = .keepAlways; add(errorShot)
    app.terminate(); app.launchArguments = ["--navigation-ui-tests"]; app.launch()
    XCTAssertTrue(references.waitForExistence(timeout: 8)); XCTAssertEqual(references.value as? String, "")
    XCTAssertFalse(app.buttons["html-entity-copy"].isEnabled)
    XCTAssertFalse(app.buttons["html-entity-convert"].isEnabled)
  }

  func testURLQueryUnicodeIDNAAndASCIIRepresentation() {
    search("T-014"); activate(app.buttons["encoders-T-014"])
    activate(app.buttons["url-percent-direction"])
    #if os(macOS)
      activate(app.menuItems["Decode"])
    #else
      activate(app.buttons["Decode"])
    #endif
    let percent = app.textViews.matching(NSPredicate(format: "label == 'Percent-encoded text input'")).firstMatch
    XCTAssertTrue(percent.waitForExistence(timeout: 5))
    activate(percent); percent.typeText("https://%E4%BE%8B%E3%81%88.%E3%83%86%E3%82%B9%E3%83%88/%D0%BF%D1%83%D1%82%D1%8C?q=%F0%9F%98%80#%D1%80")
    activate(app.buttons["url-percent-convert"])
    XCTAssertTrue(app.buttons["url-percent-copy"].isEnabled); activate(app.buttons["url-percent-copy"])
    showSidebar(); clearSearch(); search("T-015"); activate(app.buttons["encoders-T-015"])
    let input = app.textViews.matching(NSPredicate(format: "label == 'URL input'")).firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    #if os(macOS)
      activate(input); input.typeKey("v", modifierFlags: .command)
    #else
      input.press(forDuration: 1.2)
      let paste = app.menuItems["Paste"].firstMatch
      if paste.waitForExistence(timeout: 3) { activate(paste) } else { activate(app.buttons["Paste"].firstMatch) }
    #endif
    let status = app.staticTexts["url-query-status"]
    expectation(for: NSPredicate(format: "label CONTAINS 'IRI'"), evaluatedWith: status); waitForExpectations(timeout: 5)
    XCTAssertEqual(input.value as? String, "https://例え.テスト/путь?q=😀#р")
    activate(app.buttons["url-query-build"])
    activate(app.buttons["url-query-output-form"])
    #if os(macOS)
      activate(app.menuItems["ASCII URI"])
    #else
      activate(app.buttons["ASCII URI"])
    #endif
    let output = app.textViews.matching(NSPredicate(format: "label == 'ASCII URI result'")).firstMatch
    expectation(for: NSPredicate(format: "value == 'https://xn--r8jz45g.xn--zckzah/%D0%BF%D1%83%D1%82%D1%8C?q=%F0%9F%98%80#%D1%80'"), evaluatedWith: output)
    waitForExpectations(timeout: 5)
    let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "T015 Unicode IDNA"; shot.lifetime = .keepAlways; add(shot)
  }

  func testURLQueryEditBuildPasteDiagnosticsAndPrivacy() {
    search("T-015"); activate(app.buttons["encoders-T-015"])
    let input = app.textViews.matching(NSPredicate(format: "label == 'URL input'")).firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    let source = "https://EXAMPLE.test/a?tag=one&tag=two&flag#f"
    activate(input); input.typeText(source)
    activate(app.buttons["url-query-parse"])
    let status = app.staticTexts["url-query-status"]
    expectation(for: NSPredicate(format: "label CONTAINS '3 parameters'"), evaluatedWith: status); waitForExpectations(timeout: 5)
    XCTAssertFalse(app.buttons["url-query-copy"].isEnabled)
    activate(app.buttons["url-query-collapse-input"])
    let table = app.tables["url-query-list"]
    XCTAssertTrue(table.waitForExistence(timeout: 5))
    activate(table.cells.element(boundBy: 1))
    activate(app.buttons["url-query-edit"])
    let value = app.textViews["url-query-edit-value"]
    XCTAssertTrue(value.waitForExistence(timeout: 5))
    activate(value); value.typeText(" +")
    let editedValue = (value.value as? String ?? "").replacingOccurrences(of: " ", with: "%20").replacingOccurrences(of: "+", with: "%2B")
    XCTAssertTrue(editedValue.contains("two"))
    activate(app.buttons["url-query-edit-apply"])
    activate(app.buttons["url-query-build"])
    let output = app.textViews.matching(NSPredicate(format: "label == 'URL result'")).firstMatch
    expectation(for: NSPredicate(format: "value == %@", "https://EXAMPLE.test/a?tag=one&tag=" + editedValue + "&flag#f"), evaluatedWith: output)
    waitForExpectations(timeout: 5)
    let resultShot = XCTAttachment(screenshot: app.screenshot()); resultShot.name = "T015 Query result"; resultShot.lifetime = .keepAlways; add(resultShot)
    activate(app.buttons["url-query-copy"])
    activate(app.buttons["url-query-collapse-input"])
    activate(app.buttons["url-query-clear"])
    #if os(macOS)
      activate(input); input.typeKey("v", modifierFlags: .command)
    #else
      input.press(forDuration: 1.2)
      let paste = app.menuItems["Paste"].firstMatch
      if paste.waitForExistence(timeout: 3) { activate(paste) }
      else { activate(app.buttons["Paste"].firstMatch) }
    #endif
    expectation(for: NSPredicate(format: "label CONTAINS '3 parameters'"), evaluatedWith: status); waitForExpectations(timeout: 5)
    XCTAssertFalse(app.buttons["url-query-copy"].isEnabled)
    activate(app.buttons["url-query-clear"]); activate(input); input.typeText("https://h/?a=%A")
    activate(app.buttons["url-query-parse"])
    XCTAssertTrue(app.buttons["url-query-show-input"].waitForExistence(timeout: 5))
    activate(app.buttons["url-query-show-input"])
    XCTAssertTrue((app.staticTexts["url-query-message"].label).contains("Incomplete percent"))
    let errorShot = XCTAttachment(screenshot: app.screenshot()); errorShot.name = "T015 Source diagnostic"; errorShot.lifetime = .keepAlways; add(errorShot)
    app.terminate(); app.launchArguments = ["--navigation-ui-tests"]; app.launch()
    XCTAssertTrue(input.waitForExistence(timeout: 8)); XCTAssertEqual(input.value as? String, "")
    XCTAssertFalse(app.buttons["url-query-copy"].isEnabled)
  }

  func testURLPercentNativePasteChecksWithoutOutput() {
    search("T-014")
    activate(app.buttons["encoders-T-014"])
    let input = app.textViews.matching(NSPredicate(format: "label == 'Text input'")).firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    activate(input); input.typeText("a b+")
    activate(app.buttons["url-percent-convert"])
    XCTAssertTrue(app.buttons["url-percent-copy"].isEnabled)
    activate(app.buttons["url-percent-copy"])
    activate(app.buttons["url-percent-direction"])
    #if os(macOS)
      activate(app.menuItems["Decode"])
    #else
      activate(app.buttons["Decode"])
    #endif
    activate(app.buttons["url-percent-clear"])
    let encoded = app.textViews.matching(NSPredicate(format: "label == 'Percent-encoded text input'")).firstMatch
    #if os(macOS)
      activate(encoded); encoded.typeKey("v", modifierFlags: .command)
    #else
      encoded.press(forDuration: 1.2)
      let paste = app.menuItems["Paste"].firstMatch
      if paste.waitForExistence(timeout: 3) { activate(paste) }
      else { activate(app.buttons["Paste"].firstMatch) }
    #endif
    let status = app.staticTexts["url-percent-status"]
    expectation(for: NSPredicate(format: "label CONTAINS 'Percent encoding checked'"), evaluatedWith: status)
    waitForExpectations(timeout: 5)
    XCTAssertEqual(encoded.value as? String,"a%20b%2B")
    XCTAssertFalse(app.buttons["url-percent-copy"].isEnabled)
    activate(app.buttons["url-percent-convert"])
    let output = app.textViews.matching(NSPredicate(format: "label == 'Text result'")).firstMatch
    expectation(for: NSPredicate(format: "value == 'a b+'"), evaluatedWith: output)
    waitForExpectations(timeout: 5)
    XCTAssertTrue(app.buttons["url-percent-copy"].isEnabled)
  }

  func testURLPercentProfilesDiagnosticsAndPrivacy() {
    search("T-014")
    activate(app.buttons["encoders-T-014"])
    func input(_ name: String = "Text") -> XCUIElement {
      app.textViews.matching(NSPredicate(format: "label == %@", name + " input")).firstMatch
    }
    func choose(_ picker: String, _ value: String) {
      activate(app.buttons[picker])
      #if os(macOS)
      activate(app.menuItems[value])
      #else
      let option = app.buttons[value]
      if option.exists { activate(option) } else { activate(app.staticTexts[value]) }
      #endif
    }
    func result(_ expected: String, name: String) {
      let output = app.textViews.matching(NSPredicate(format: "label == %@", name + " result")).firstMatch
      expectation(for: NSPredicate(format: "value == %@", expected), evaluatedWith: output)
      waitForExpectations(timeout: 5)
    }
    let field = input()
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    activate(field); field.typeText("a b+c~*")
    activate(app.buttons["url-percent-convert"])
    XCTAssertTrue(app.buttons["url-percent-copy"].isEnabled)
    if app.buttons["url-percent-collapse"].exists && app.buttons["url-percent-collapse"].label == "Expand Output" {
      activate(app.buttons["url-percent-collapse"])
    }
    result("a%20b%2Bc~%2A",name:"Percent-encoded text")
    activate(app.buttons["url-percent-check"])
    XCTAssertTrue(app.buttons["url-percent-copy"].isEnabled)
    choose("url-percent-profile","Form field")
    XCTAssertFalse(app.buttons["url-percent-copy"].isEnabled)
    activate(app.buttons["url-percent-convert"])
    result("a+b%2Bc%7E*",name:"Percent-encoded text")
    choose("url-percent-direction","Decode")
    activate(app.buttons["url-percent-clear"])
    let encoded = input("Percent-encoded text")
    activate(encoded); encoded.typeText("a+b%2Bc")
    activate(app.buttons["url-percent-convert"])
    result("a b+c",name:"Text")
    choose("url-percent-profile","URI text · keep delimiters")
    activate(app.buttons["url-percent-convert"])
    result("a+b+c",name:"Text")
    activate(app.buttons["url-percent-clear"]); activate(encoded); encoded.typeText("%FF")
    activate(app.buttons["url-percent-convert"])
    XCTAssertTrue(app.staticTexts["url-percent-message"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["url-percent-copy"].isEnabled)
    activate(app.buttons["url-percent-clear"]); activate(encoded); encoded.typeText("%A")
    activate(app.buttons["url-percent-check"])
    XCTAssertTrue(app.buttons["url-percent-show-input"].waitForExistence(timeout: 3))
    activate(app.buttons["url-percent-show-input"])
    let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "T014 EOF diagnostic"; shot.lifetime = .keepAlways; add(shot)
    app.terminate(); app.launchArguments = ["--navigation-ui-tests"]; app.launch()
    let restored = input("Percent-encoded text")
    XCTAssertTrue(restored.waitForExistence(timeout: 5))
    XCTAssertEqual(restored.value as? String, "")
    XCTAssertFalse(app.buttons["url-percent-copy"].isEnabled)
  }

  func testBase64TextProfilesAndPrivacy() {
    search("T-012")
    activate(app.buttons["encoders-T-012"])
    func input(_ name: String) -> XCUIElement {
      app.textViews.matching(NSPredicate(format: "label == %@", name + " input")).firstMatch
    }
    func choose(_ picker: String, _ value: String) {
      activate(app.buttons[picker])
      let button = app.buttons[value]
      if button.exists { activate(button) } else { activate(app.staticTexts[value]) }
    }
    let field = input("Base64")
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    activate(field); field.typeText("YQ==")
    activate(app.buttons["base64-convert"])
    let status = app.staticTexts["base64-status"]
    XCTAssertTrue(status.waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["base64-copy"].isEnabled)
    let decoded = XCTAttachment(screenshot: app.screenshot()); decoded.name = "Base64 decoded text"; decoded.lifetime = .keepAlways; add(decoded)
    activate(app.buttons["base64-check"])
    XCTAssertTrue(app.buttons["base64-copy"].isEnabled)
    choose("base64-alphabet", "Base64URL")
    XCTAssertEqual(input("Base64URL").value as? String, "YQ==")
    XCTAssertFalse(app.buttons["base64-copy"].isEnabled)
    choose("base64-direction", "Encode")
    activate(app.buttons["base64-clear"])
    let text = input("Text"); activate(text); text.typeText("Hello")
    activate(app.buttons["base64-convert"])
    XCTAssertTrue(app.buttons["base64-copy"].isEnabled)
    if app.buttons["base64-collapse"].exists && app.buttons["base64-collapse"].label == "Expand Output" {
      activate(app.buttons["base64-collapse"])
    }
    let encoded = app.textViews.matching(NSPredicate(format: "label == 'Base64URL result'")).firstMatch
    XCTAssertEqual(encoded.value as? String, "SGVsbG8")
    choose("base64-encoding", "UTF-16 LE")
    XCTAssertEqual(text.value as? String, "Hello")
    activate(app.buttons["base64-convert"])
    XCTAssertTrue(app.buttons["base64-copy"].isEnabled)
    choose("base64-encoding", "UTF-8")
    choose("base64-direction", "Decode")
    activate(app.buttons["base64-clear"])
    let url = input("Base64URL"); activate(url); url.typeText("_w")
    activate(app.buttons["base64-convert"])
    XCTAssertTrue(app.staticTexts["base64-message"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["base64-copy"].isEnabled)
    activate(app.buttons["base64-clear"]); activate(url); url.typeText("A")
    activate(app.buttons["base64-check"])
    XCTAssertTrue(app.buttons["base64-show-input"].waitForExistence(timeout: 3))
    activate(app.buttons["base64-show-input"])
    let invalid = XCTAttachment(screenshot: app.screenshot()); invalid.name = "Base64 EOF diagnostic"; invalid.lifetime = .keepAlways; add(invalid)
    app.terminate()
    app.launchArguments = ["--navigation-ui-tests"]
    app.launch()
    let restored = input("Base64URL")
    XCTAssertTrue(restored.waitForExistence(timeout: 5))
    XCTAssertEqual(restored.value as? String, "")
    XCTAssertFalse(app.buttons["base64-copy"].isEnabled)
  }

  func testJSONModelsLanguagesDiagnosticsAndPrivacy() {
    search("T-011")
    activate(app.buttons["dataJSON-T-011"])
    let input = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'JSON input'")).firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    let source = #"{"id":1,"name":"Ada","child":{"active":true}}"#
    activate(input); input.typeText(source)
    activate(app.buttons["models-generate"])
    let status = app.staticTexts["models-status"]
    expectation(for: NSPredicate(format: "label CONTAINS 'Models generated'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    for language in ["Kotlin", "C#", "Java", "TypeScript", "Swift"] {
      activate(app.buttons["models-language"])
      #if os(macOS)
      activate(app.menuItems[language])
      #else
      activate(app.buttons[language])
      #endif
      expectation(for: NSPredicate(format: "label CONTAINS 'Models generated'"), evaluatedWith: status)
      waitForExpectations(timeout: 10)
      XCTAssertEqual(input.value as? String, source)
      XCTAssertTrue(app.buttons["models-copy"].isEnabled)
    }
    if app.buttons["Expand Models"].exists { activate(app.buttons["Expand Models"]) }
    let output = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'Generated code result'")).firstMatch
    XCTAssertTrue(output.waitForExistence(timeout: 5))
    XCTAssertTrue((output.value as? String)?.contains("struct RootModel: Codable") == true)
    activate(app.buttons["models-usage"])
    XCTAssertTrue(app.buttons["Copy Usage"].waitForExistence(timeout: 5))
    activate(app.buttons["Done"])
    attachScreenshot("JSON Models generated Swift")
    activate(app.buttons["models-clear"])
    activate(input); input.typeText(#"{"missing": [1,}"#)
    activate(app.buttons["models-generate"])
    let detection = app.buttons["Show Detection"]
    XCTAssertTrue(detection.waitForExistence(timeout: 10))
    activate(detection)
    XCTAssertFalse(app.buttons["models-copy"].isEnabled)
    attachScreenshot("JSON Models invalid source")
    app.terminate(); app.launchArguments = ["--navigation-ui-tests"]; app.launch()
    let fresh = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'JSON input'")).firstMatch
    XCTAssertTrue(fresh.waitForExistence(timeout: 10))
    XCTAssertEqual(fresh.value as? String, "")
    XCTAssertFalse(app.buttons["models-copy"].isEnabled)
  }

  func testCSVTableDoubleActivationRevealsInput() {
    search("T-010")
    activate(app.buttons["dataJSON-T-010"])
    let input = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'CSV input'")).firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    activate(input); input.typeText("name,value\nAda,\"quoted value\"")
    activate(app.buttons["table-build"])
    expectation(for: NSPredicate(format: "label CONTAINS 'Loaded'"), evaluatedWith: app.staticTexts["table-status"])
    waitForExpectations(timeout: 10)
    activate(app.buttons["table-toggle-input"])
    let grid = app.descendants(matching: .any).matching(identifier: "table-grid").firstMatch
    XCTAssertTrue(grid.waitForExistence(timeout: 5))
    let cell = grid.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 264, dy: 64))
    #if os(macOS)
    cell.doubleClick()
    #else
    cell.doubleTap()
    #endif
    expectation(for: NSPredicate(format: "label == 'Hide Input'"), evaluatedWith: app.buttons["table-toggle-input"])
    waitForExpectations(timeout: 10)
    XCTAssertTrue(input.isHittable)
    XCTAssertEqual(input.value as? String, "name,value\nAda,\"quoted value\"")
    XCTAssertTrue(app.staticTexts["table-selection"].label.contains("Data row 1 · column 2"))
  }

  func testCSVTableViewerFilteringSelectionDiagnosticsAndPrivacy() {
    search("T-010")
    activate(app.buttons["dataJSON-T-010"])
    let input = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'CSV input'")).firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    activate(input); input.typeText("name,value\nAda,9007199254740993\nBen,2")
    activate(app.buttons["table-build"])
    let status = app.staticTexts["table-status"]
    expectation(for: NSPredicate(format: "label CONTAINS 'Loaded'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    activate(app.buttons["table-toggle-input"])
    let filter = app.textFields["table-search"]
    activate(filter); filter.typeText("Ada")
    expectation(for: NSPredicate(format: "label == '1 row'"), evaluatedWith: app.staticTexts["table-row-count"])
    waitForExpectations(timeout: 10)
    activate(app.buttons["table-go"])
    activate(app.buttons["table-go-confirm"])
    expectation(for: NSPredicate(format: "label CONTAINS 'Data row 1'"), evaluatedWith: app.staticTexts["table-selection"])
    waitForExpectations(timeout: 10)
    activate(app.buttons["table-details"])
    let value = app.textViews.matching(NSPredicate(format: "value == 'Ada'")).firstMatch
    XCTAssertTrue(value.waitForExistence(timeout: 5))
    activate(app.buttons["Done"])
    attachScreenshot("CSV table viewer filtered selection")
    activate(app.buttons["table-show-source"])
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    activate(app.buttons["table-clear"])
    activate(input); input.typeText("header\n\"unfinished")
    activate(app.buttons["table-build"])
    expectation(for: NSPredicate(format: "label CONTAINS 'Invalid CSV'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    activate(app.buttons["table-show-detection"])
    attachScreenshot("CSV table viewer diagnostics")
    app.terminate(); app.launchArguments = ["--navigation-ui-tests"]; app.launch()
    let fresh = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'CSV input'")).firstMatch
    XCTAssertTrue(fresh.waitForExistence(timeout: 10))
    XCTAssertEqual(fresh.value as? String, "")
    XCTAssertEqual(app.textFields["table-search"].value as? String, "Filter rows…")
  }

  func testJSONTOMLConversionDirectionsDiagnosticsAndPrivacy() {
    search("T-009")
    activate(app.buttons["dataJSON-T-009"])
    let input = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'JSON input'")).firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    activate(input); input.typeText(#"{"number":9007199254740993,"user":{"name":"Ada"}}"#)
    activate(app.buttons["toml-convert"])
    let status = app.staticTexts["toml-status"]
    expectation(for: NSPredicate(format: "label CONTAINS 'Converted'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    let output = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'TOML result'")).firstMatch
    XCTAssertTrue((output.value as? String)?.contains("9007199254740993") == true)
    XCTAssertTrue((output.value as? String)?.contains("[\"user\"]") == true)
    let original = output.value as? String
    activate(app.buttons["toml-check"])
    expectation(for: NSPredicate(format: "label CONTAINS 'Converted'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    XCTAssertEqual(output.value as? String, original)
    activate(app.buttons["toml-table-style"])
    #if os(macOS)
    activate(app.menuItems["Inline tables"])
    #else
    activate(app.buttons["Inline tables"])
    #endif
    XCTAssertFalse(app.buttons["toml-copy"].isEnabled)
    activate(app.buttons["toml-convert"])
    expectation(for: NSPredicate(format: "label CONTAINS 'Converted'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    XCTAssertTrue((output.value as? String)?.contains("\"user\" = {") == true)
    activate(app.buttons["toml-clear"])
    activate(app.buttons["toml-direction"])
    #if os(macOS)
    activate(app.menuItems["TOML → JSON"])
    #else
    activate(app.buttons["TOML → JSON"])
    #endif
    let toml = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'TOML input'")).firstMatch
    activate(toml); toml.typeText("number=9007199254740993\ndate=1979-05-27")
    activate(app.buttons["toml-convert"])
    expectation(for: NSPredicate(format: "label CONTAINS 'Converted with warnings'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    let json = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'JSON result'")).firstMatch
    XCTAssertTrue((json.value as? String)?.contains("9007199254740993") == true)
    XCTAssertTrue((json.value as? String)?.contains("\"1979-05-27\"") == true)
    activate(app.buttons["toml-clear"])
    activate(toml); toml.typeText("value=[1")
    activate(app.buttons["toml-check"])
    expectation(for: NSPredicate(format: "label CONTAINS 'Invalid TOML'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    activate(app.buttons["toml-show-detection"])
    attachScreenshot("TOML converter diagnostics")
    app.terminate(); app.launchArguments = ["--navigation-ui-tests"]; app.launch()
    let fresh = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'JSON input'")).firstMatch
    XCTAssertTrue(fresh.waitForExistence(timeout: 10))
    XCTAssertEqual(fresh.value as? String, "")
    XCTAssertFalse(app.buttons["toml-copy"].isEnabled)
  }

  func testJSONXMLConversionProfilesDiagnosticsAndPrivacy() {
    search("T-008")
    activate(app.buttons["dataJSON-T-008"])
    let input = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'JSON input'")).firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    activate(input); input.typeText(#"{"root":{"number":9007199254740993,"name":"Ada"}}"#)
    activate(app.buttons["xml-convert"])
    let status = app.staticTexts["xml-status"]
    expectation(for: NSPredicate(format: "label CONTAINS 'Converted'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    let xmlOutput = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'XML result'")).firstMatch
    XCTAssertTrue((xmlOutput.value as? String)?.contains("9007199254740993") == true)
    let original = xmlOutput.value as? String
    activate(app.buttons["xml-check"])
    expectation(for: NSPredicate(format: "label CONTAINS 'Converted'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    XCTAssertEqual(xmlOutput.value as? String, original)
    activate(app.buttons["xml-mapping"])
    #if os(macOS)
    activate(app.menuItems["Typed JSON"])
    #else
    activate(app.buttons["Typed JSON"])
    #endif
    XCTAssertFalse(app.buttons["xml-copy"].isEnabled)
    activate(app.buttons["xml-convert"])
    expectation(for: NSPredicate(format: "label CONTAINS 'Converted'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    let typed = xmlOutput.value as? String ?? ""
    XCTAssertTrue(typed.contains("urn:developer-toolbox:json-xml:1"))
    activate(app.buttons["xml-clear"])
    activate(app.buttons["xml-direction"])
    #if os(macOS)
    activate(app.menuItems["XML → JSON"])
    #else
    activate(app.buttons["XML → JSON"])
    #endif
    let xmlInput = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'XML input'")).firstMatch
    activate(xmlInput); xmlInput.typeText(typed)
    activate(app.buttons["xml-convert"])
    expectation(for: NSPredicate(format: "label CONTAINS 'Converted'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    let jsonOutput = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'JSON result'")).firstMatch
    XCTAssertTrue((jsonOutput.value as? String)?.contains("9007199254740993") == true)
    activate(app.buttons["xml-clear"])
    activate(xmlInput); xmlInput.typeText("<root>")
    activate(app.buttons["xml-check"])
    expectation(for: NSPredicate(format: "label CONTAINS 'Invalid XML'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    activate(app.buttons["xml-show-detection"])
    attachScreenshot("XML converter diagnostics")
    app.terminate(); app.launchArguments = ["--navigation-ui-tests"]; app.launch()
    let fresh = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'JSON input'")).firstMatch
    XCTAssertTrue(fresh.waitForExistence(timeout: 10))
    XCTAssertEqual(fresh.value as? String, "")
    XCTAssertFalse(app.buttons["xml-copy"].isEnabled)
  }

  func testJSONCSVConversionSettingsDiagnosticsAndPrivacy() {
    activate(app.buttons["dataJSON-T-007"])
    let input = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'JSON input'")).firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    activate(input); input.typeText(#"[{"id":9007199254740993,"name":"hello"}]"#)
    activate(app.buttons["csv-convert"])
    let status = app.staticTexts["csv-status"]
    expectation(for: NSPredicate(format: "label CONTAINS 'Converted'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    XCTAssertTrue(app.buttons["csv-copy"].isEnabled)
    let csvOutput = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'CSV result'")).firstMatch
    XCTAssertTrue((csvOutput.value as? String)?.contains("9007199254740993") == true)
    activate(app.buttons["csv-check"])
    expectation(for: NSPredicate(format: "label CONTAINS 'Converted'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    XCTAssertTrue(app.buttons["csv-copy"].isEnabled)
    activate(app.buttons["csv-clear"])
    activate(app.buttons["csv-direction"])
    #if os(macOS)
    activate(app.menuItems["CSV → JSON"])
    #else
    activate(app.buttons["CSV → JSON"])
    #endif
    let csv = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'CSV input'")).firstMatch
    activate(csv); csv.typeText("id,name\n001,hello")
    activate(app.buttons["csv-convert"])
    expectation(for: NSPredicate(format: "label CONTAINS 'Converted'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    let json = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'JSON result'")).firstMatch
    XCTAssertTrue((json.value as? String)?.contains("\"001\"") == true)
    activate(app.buttons["csv-settings"])
    #if os(macOS)
    activate(app.menuItems["Cell representation"])
    activate(app.menuItems["JSON cells"])
    #else
    activate(app.buttons["Cell representation"])
    activate(app.buttons["JSON cells"])
    #endif
    XCTAssertFalse(app.buttons["csv-copy"].isEnabled)
    XCTAssertTrue(app.staticTexts["csv-profile"].label.contains("JSON cells"))
    activate(app.buttons["csv-clear"])
    activate(app.segmentedControls["csv-format"].buttons["TSV"])
    let tsv = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'TSV input'")).firstMatch
    activate(tsv); tsv.typeText("value\n9007199254740993")
    activate(app.buttons["csv-convert"])
    expectation(for: NSPredicate(format: "label CONTAINS 'Converted'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    XCTAssertTrue((json.value as? String)?.contains("9007199254740993") == true)
    XCTAssertFalse((json.value as? String)?.contains("\"9007199254740993\"") == true)
    activate(app.buttons["csv-clear"])
    activate(tsv); tsv.typeText("value\n\"unfinished")
    activate(app.buttons["csv-convert"])
    expectation(for: NSPredicate(format: "label CONTAINS 'Invalid TSV'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    activate(app.buttons["csv-show-detection"])
    attachScreenshot("CSV TSV diagnostics")
    app.terminate(); app.launchArguments = ["--navigation-ui-tests"]; app.launch()
    let fresh = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'JSON input'")).firstMatch
    XCTAssertTrue(fresh.waitForExistence(timeout: 10))
    XCTAssertEqual(fresh.value as? String, "")
    XCTAssertFalse(app.buttons["csv-copy"].isEnabled)
  }

  func testJSONYAMLConversionDirectionsDiagnosticsAndPrivacy() {
    activate(app.buttons["dataJSON-T-006"])
    let input = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'JSON input'")).firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    activate(input); input.typeText(#"{"number":9007199254740993,"text":"yes"}"#)
    activate(app.buttons["yaml-convert"])
    let status = app.staticTexts["yaml-status"]
    expectation(for: NSPredicate(format: "label CONTAINS 'Converted'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    XCTAssertTrue(app.buttons["yaml-copy"].isEnabled)
    activate(app.buttons["yaml-check"])
    expectation(for: NSPredicate(format: "label CONTAINS 'Converted'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    XCTAssertTrue(app.buttons["yaml-copy"].isEnabled)
    activate(app.buttons["yaml-clear"])
    XCTAssertFalse(app.buttons["yaml-copy"].isEnabled)
    activate(app.buttons["yaml-direction"])
    #if os(macOS)
    activate(app.menuItems["YAML → JSON"])
    #else
    activate(app.buttons["YAML → JSON"])
    #endif
    let yaml = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'YAML input'")).firstMatch
    XCTAssertTrue(yaml.waitForExistence(timeout: 5))
    activate(yaml); yaml.typeText("count: 9007199254740993\nword: yes\n")
    activate(app.buttons["yaml-convert"])
    expectation(for: NSPredicate(format: "label CONTAINS 'Converted'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    XCTAssertTrue(app.buttons["yaml-copy"].isEnabled)
    let output = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'JSON result'")).firstMatch
    XCTAssertTrue((output.value as? String)?.contains("9007199254740993") == true)
    XCTAssertTrue((output.value as? String)?.contains("\"yes\"") == true)
    activate(app.buttons["yaml-clear"])
    activate(yaml); yaml.typeText("bad: [1,")
    activate(app.buttons["yaml-convert"])
    expectation(for: NSPredicate(format: "label CONTAINS 'Invalid YAML'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    activate(app.buttons["yaml-show-detection"])
    XCTAssertEqual(yaml.value as? String, "bad: [1,")
    attachScreenshot("JSON YAML conversion diagnostics")
    app.terminate(); app.launchArguments = ["--navigation-ui-tests"]; app.launch()
    let fresh = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'JSON input'")).firstMatch
    XCTAssertTrue(fresh.waitForExistence(timeout: 10))
    XCTAssertEqual(fresh.value as? String, "")
    XCTAssertFalse(app.buttons["yaml-copy"].isEnabled)
  }

  func testJSONSchemaExtendedDraftFormatsAndResourceControls() {
    activate(app.buttons["dataJSON-T-005"])
    let data = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'JSON instance input'")).firstMatch
    let schema = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'JSON Schema input'")).firstMatch
    XCTAssertTrue(data.waitForExistence(timeout: 5))
    activate(data); data.typeText(#""bad-email""#)
    activate(app.buttons["schema-toggle-json"])
    activate(schema); schema.typeText(#"{"$schema":"http://json-schema.org/draft-07/schema#","format":"email"}"#)
    activate(app.buttons["schema-toggle-schema"])
    activate(app.buttons["schema-validate"])
    let status = app.staticTexts["schema-status"]
    expectation(for: NSPredicate(format: "label CONTAINS 'Matches schema'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    activate(app.buttons["schema-validation-options"])
    #if os(macOS)
    activate(app.menuItems["Validate formats"])
    #else
    activate(app.switches["Validate formats"].exists ? app.switches["Validate formats"] : app.buttons["Validate formats"])
    #endif
    activate(app.buttons["schema-validate"])
    expectation(for: NSPredicate(format: "label CONTAINS 'Does not match schema'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    activate(app.buttons["schema-show-schema"])
    XCTAssertEqual(schema.value as? String, #"{"$schema":"http://json-schema.org/draft-07/schema#","format":"email"}"#)
    activate(app.buttons["schema-references"])
    XCTAssertTrue(app.buttons["schema-add-references"].waitForExistence(timeout: 5))
    activate(app.buttons["schema-add-references"])
    let pickerCancel = app.buttons["Cancel"].firstMatch
    XCTAssertTrue(pickerCancel.waitForExistence(timeout: 8))
    activate(pickerCancel)
    XCTAssertTrue(app.buttons["schema-add-references"].waitForExistence(timeout: 5))
    activate(app.buttons["Done"])
    attachScreenshot("Schema Draft-07 format validation")
    app.terminate(); app.launchArguments = ["--navigation-ui-tests"]; app.launch()
    XCTAssertTrue(data.waitForExistence(timeout: 10))
    XCTAssertEqual(data.value as? String, "")
    XCTAssertEqual(schema.value as? String, "")
  }

  func testJSONSchemaValidateNavigationAppearanceAndPrivacy() {
    activate(app.buttons["dataJSON-T-005"])
    let data = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'JSON instance input'")).firstMatch
    let schema = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'JSON Schema input'")).firstMatch
    XCTAssertTrue(data.waitForExistence(timeout: 5))
    let source = #"{"age":"bad"}"#
    let rules = #"{"properties":{"age":{"type":"integer"}},"required":["age"]}"#
    activate(data); data.typeText(source)
    activate(app.buttons["schema-toggle-json"])
    activate(schema); schema.typeText(rules)
    activate(app.buttons["schema-toggle-schema"])
    activate(app.buttons["schema-validate"])
    let status = app.staticTexts["schema-status"]
    expectation(for: NSPredicate(format: "label CONTAINS 'Does not match schema'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    XCTAssertTrue(app.buttons["schema-show-json"].isEnabled)
    activate(app.buttons["schema-details"])
    XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 4))
    activate(app.buttons["Done"])
    activate(app.buttons["Actions"])
    #if os(macOS)
    activate(app.menuItems["Show Both"])
    #else
    activate(app.buttons["Show Both"])
    #endif
    expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: data)
    expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: schema)
    waitForExpectations(timeout: 4)
    activate(app.buttons["schema-toggle-json"])
    activate(app.buttons["schema-toggle-schema"])
    activate(app.buttons["schema-show-json"])
    expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: data)
    waitForExpectations(timeout: 4)
    XCTAssertEqual(data.value as? String, source)
    #if os(iOS)
    XCTAssertFalse(app.keyboards.firstMatch.exists)
    #endif
    activate(app.buttons["schema-toggle-json"])
    activate(app.buttons["schema-show-schema"])
    expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: schema)
    waitForExpectations(timeout: 4)
    XCTAssertEqual(schema.value as? String, rules)
    attachScreenshot("JSON Schema rule navigation")
    activate(app.buttons["schema-toggle-schema"])
    activate(app.buttons["schema-copy-report"])
    XCTAssertTrue(app.staticTexts["Copied"].waitForExistence(timeout: 3))
    for appearance in ["Light", "Dark"] {
      chooseAppearance(appearance)
      XCTAssertTrue(status.label.contains("Does not match schema"))
      attachScreenshot("JSON Schema " + appearance)
    }
    #if os(iOS)
    XCUIDevice.shared.orientation = .landscapeLeft
    XCUIDevice.shared.orientation = .portrait
    #endif
    activate(app.buttons["schema-toggle-json"])
    XCTAssertEqual(data.value as? String, source)
    activate(app.buttons["Clear JSON"])
    activate(data); data.typeText(#"{"age":12}"#)
    activate(app.buttons["schema-toggle-json"])
    activate(app.buttons["schema-validate"])
    expectation(for: NSPredicate(format: "label CONTAINS 'Matches schema'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    activate(app.buttons["schema-toggle-schema"])
    activate(app.buttons["Clear Schema"])
    activate(schema); schema.typeText(#"{"type":5}"#)
    activate(app.buttons["schema-toggle-schema"])
    activate(app.buttons["schema-validate"])
    expectation(for: NSPredicate(format: "label CONTAINS 'Invalid schema'"), evaluatedWith: status)
    waitForExpectations(timeout: 10)
    activate(app.buttons["schema-show-schema"])
    expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: schema)
    waitForExpectations(timeout: 4)
    activate(app.buttons["Clear Schema"])
    activate(schema); schema.typeText("true")
    activate(app.buttons["schema-toggle-schema"])
    activate(app.buttons["schema-toggle-json"])
    activate(app.buttons["Clear JSON"])
    activate(data); data.typeText("[1,]")
    activate(app.buttons["schema-validate"])
    XCTAssertTrue(app.staticTexts["Invalid JSON"].firstMatch.waitForExistence(timeout: 5))
    activate(app.buttons["json-show-detection"])
    XCTAssertEqual(data.value as? String, "[1,]")
    attachScreenshot("JSON Schema invalid JSON diagnostic")
    app.terminate()
    app.launchArguments = ["--navigation-ui-tests"]
    app.launch()
    XCTAssertTrue(data.waitForExistence(timeout: 10))
    XCTAssertEqual(data.value as? String, "")
    XCTAssertEqual(schema.value as? String, "")
  }

  func testJSONPathRunSourceCopyAppearanceAndPrivacy() {
    activate(app.buttons["dataJSON-T-004"])
    let input = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'JSON input'")).firstMatch
    let query = app.textFields["path-query"]
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    let source = #"{"users":[{"name":"Ada","active":true},{"name":"Bob","active":false}],"huge":123456789012345678901234567890}"#
    activate(input); input.typeText(source)
    activate(query); query.typeText("$.users[?@.active == true].name")
    activate(app.buttons["path-run"])
    let first = app.descendants(matching: .any)["path-result-0"].firstMatch
    XCTAssertTrue(first.waitForExistence(timeout: 10))
    XCTAssertTrue(first.label.contains("Ada"))
    XCTAssertTrue(app.staticTexts["path-status"].label.contains("1 match"))
    activate(app.buttons["path-input-toggle"])
    activate(first)
    expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["path-show-source"])
    waitForExpectations(timeout: 4)
    #if os(iOS)
      XCTAssertFalse(app.keyboards.firstMatch.exists)
      first.doubleTap()
    #else
      first.doubleClick()
    #endif
    expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: input)
    waitForExpectations(timeout: 4)
    XCTAssertEqual(input.value as? String, source)
    attachScreenshot("JSONPath source attention")
    activate(first)
    activate(app.buttons["Actions"])
    activate(app.buttons["Copy JSON Fragment"])
    XCTAssertTrue(app.staticTexts["Copied"].waitForExistence(timeout: 3))
    activate(app.buttons["path-copy-results"])
    for appearance in ["Light", "Dark"] {
      chooseAppearance(appearance)
      XCTAssertTrue(first.exists)
      attachScreenshot("JSONPath " + appearance)
    }
    #if os(iOS)
      XCUIDevice.shared.orientation = .landscapeLeft
      XCUIDevice.shared.orientation = .portrait
    #endif
    XCTAssertEqual(input.value as? String, source)
    activate(query)
    let oldQuery = query.value as? String ?? ""
    query.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldQuery.count) + "$[")
    activate(app.buttons["path-run"])
    XCTAssertTrue(app.descendants(matching: .any)["path-diagnostic"].firstMatch.waitForExistence(timeout: 5))
    XCTAssertFalse(first.exists)
    activate(app.buttons["Show in Query"])
    activate(app.buttons["Clear Input"])
    activate(input); input.typeText("[1,]")
    activate(app.buttons["path-run"])
    XCTAssertTrue(app.staticTexts["Invalid JSON"].firstMatch.waitForExistence(timeout: 5))
    activate(app.buttons["Show Detection"])
    XCTAssertEqual(input.value as? String, "[1,]")
    app.terminate()
    app.launchArguments = ["--navigation-ui-tests"]
    app.launch()
    XCTAssertTrue(app.textFields["path-query"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.textFields["path-query"].value as? String, "JSONPath, e.g. $.users[*].name")
    XCTAssertEqual(app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'JSON input'")).firstMatch.value as? String, "")
  }

  func testJSONDiffCompareDiagnosticsAppearanceAndResize() {
    activate(app.buttons["dataJSON-T-003"])
    let inputs = app.textViews.matching(NSPredicate(format: "label CONTAINS[c] 'JSON input'"))
    XCTAssertTrue(inputs.firstMatch.waitForExistence(timeout: 5))
    XCTAssertEqual(inputs.count, 2)
    let before = inputs.element(boundBy: 0), after = inputs.element(boundBy: 1)
    let sourceA = #"{"price":1,"old":true}"#
    let sourceB = #"{"price":1.0,"new":null}"#
    activate(before); before.typeText(sourceA)
    activate(after); after.typeText(sourceB)
    activate(app.buttons["diff-compare"])
    let summary = app.staticTexts["diff-summary"]
    let changed = NSPredicate(format: "label CONTAINS '3 changes'")
    expectation(for: changed, evaluatedWith: summary)
    waitForExpectations(timeout: 10)
    activate(app.buttons["diff-input-toggle"])
    let first = app.descendants(matching: .any)["diff-change-0"].firstMatch
    XCTAssertTrue(first.waitForExistence(timeout: 5))
    #if os(macOS)
      first.doubleClick()
    #else
      first.doubleTap()
    #endif
    XCTAssertTrue(before.isHittable && after.isHittable)
    XCTAssertEqual(before.value as? String, sourceA)
    XCTAssertEqual(after.value as? String, sourceB)
    activate(app.buttons["diff-input-toggle"])
    activate(first)
    #if os(iOS)
      XCTAssertFalse(app.keyboards.firstMatch.exists, "Result selection must not summon the software keyboard")
    #endif
    activate(app.buttons["Actions"])
    activate(app.buttons["Copy JSON Pointer"])
    for appearance in ["Light", "Dark"] {
      chooseAppearance(appearance)
      XCTAssertTrue(first.exists)
      attachScreenshot("JSON Diff " + appearance)
    }
    #if os(iOS)
      XCUIDevice.shared.orientation = .landscapeLeft
      XCUIDevice.shared.orientation = .portrait
    #endif
    activate(app.buttons["Actions"])
    activate(app.buttons["Show Before"])
    XCTAssertTrue(before.isHittable)
    XCTAssertEqual(before.value as? String, sourceA)
    XCTAssertEqual(after.value as? String, sourceB)
    activate(app.buttons["Clear Before"])
    activate(before); before.typeText(#"{"a":[1,]}"#)
    activate(app.buttons["diff-compare"])
    let compactDiagnostics = app.buttons["diff-before-diagnostics"]
    if compactDiagnostics.waitForExistence(timeout: 2) { activate(compactDiagnostics) }
    XCTAssertTrue(app.staticTexts["Invalid JSON"].waitForExistence(timeout: 5))
    activate(app.buttons["json-show-detection"])
    XCTAssertTrue(before.isHittable)
    XCTAssertGreaterThanOrEqual(before.frame.height, 64, "Diagnostics must leave room to edit the invalid source")
    if compactDiagnostics.exists { activate(compactDiagnostics) }
    activate(app.buttons["json-show-related"])
    #if os(macOS)
      activate(app.menuItems.matching(NSPredicate(format: "label CONTAINS %@", "offset")).firstMatch)
    #else
      activate(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "offset")).firstMatch)
    #endif
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    XCTAssertFalse(app.descendants(matching: .any)["diff-change-0"].firstMatch.exists)
    attachScreenshot("JSON Diff invalid input")
  }

  func testJSONTreeDiagnosticsAppearanceAndResize() {
    activate(app.buttons["dataJSON-T-002"])
    let input = app.textViews["JSON input"].firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    activate(input); input.typeText(#"{"a":[1,]}"#)
    activate(app.buttons["tree-build"])
    XCTAssertTrue(app.staticTexts["Invalid JSON"].waitForExistence(timeout: 5))
    activate(app.buttons["tree-input-toggle"])
    activate(app.buttons["json-show-detection"])
    XCTAssertTrue(input.isHittable)
    activate(app.buttons["Clear Input"])
    let source = #"{"user":{"roles":["admin"]},"enabled":true}"#
    activate(input); input.typeText(source)
    activate(app.buttons["tree-build"])
    activate(app.buttons["tree-input-toggle"])
    let search = app.textFields["tree-search"]
    activate(search); search.typeText("admin")
    let match = app.descendants(matching: .any)["tree-row-3"].firstMatch
    XCTAssertTrue(match.waitForExistence(timeout: 5))
    for appearance in ["Light", "Dark"] {
      chooseAppearance(appearance)
      XCTAssertTrue(match.exists)
      attachScreenshot("JSON Tree " + appearance)
    }
    #if os(iOS)
      XCUIDevice.shared.orientation = .landscapeLeft
      XCUIDevice.shared.orientation = .portrait
    #endif
    activate(app.buttons["tree-input-toggle"])
    XCTAssertEqual(input.value as? String, source)
    XCTAssertTrue(app.staticTexts["tree-search-count"].label.contains("1 / 1"))
  }

  func testJSONTreeMaximumArrayContinuousScroll() {
    app.terminate()
    app.launchArguments = ["--navigation-ui-tests", "--reset-navigation-ui-tests", "--tree-stress-array"]
    app.launch()
    activate(app.buttons["tree-build"])
    let root = app.descendants(matching: .any)["tree-row-0"].firstMatch
    XCTAssertTrue(root.waitForExistence(timeout: 10))
    let field = app.textFields["tree-search"]
    activate(field); field.typeText("9")
    let last = app.descendants(matching: .any)["tree-row-131071"].firstMatch
    XCTAssertTrue(last.waitForExistence(timeout: 10))
    XCTAssertTrue(last.isHittable)
    XCTAssertTrue(app.staticTexts["tree-search-count"].label.contains("1 / 1"))
    #if os(iOS)
    let table = app.tables["json-tree"]
    table.swipeDown(); table.swipeDown()
    #endif
    activate(app.buttons["tree-collapse-all"])
    XCTAssertEqual(root.value as? String, "Collapsed")
    activate(app.buttons["tree-expand-all"])
    XCTAssertTrue(root.waitForExistence(timeout: 10))
    activate(app.buttons["Next match"])
    XCTAssertTrue(last.waitForExistence(timeout: 10))
    attachScreenshot("Maximum JSON array continuous tree at final match")
  }

  func testJSONTreeBuildSearchFoldingAndCopy() {
    activate(app.buttons["dataJSON-T-002"])
    let input = app.textViews["JSON input"].firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    activate(input)
    let source = #"{"user":{"roles":["admin","guest"]},"other":{"v":1}}"#
    input.typeText(source)
    activate(app.buttons["tree-build"])
    let root = app.descendants(matching: .any)["tree-row-0"].firstMatch
    XCTAssertTrue(root.waitForExistence(timeout: 5))
    activate(app.buttons["tree-input-toggle"])
    activate(app.buttons["tree-collapse-all"])
    XCTAssertEqual(root.value as? String, "Collapsed")
    // Both folding hit zones belong to the same accessibility row.
    root.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 43, dy: 0)).tap()
    XCTAssertEqual(root.value as? String, "Expanded")
    root.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 90, dy: 0)).tap()
    XCTAssertEqual(root.value as? String, "Collapsed")
    let field = app.textFields["tree-search"]
    activate(field); field.typeText("admin")
    let match = app.descendants(matching: .any)["tree-row-3"].firstMatch
    XCTAssertTrue(match.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["tree-search-count"].label.contains("1 / 1"))
    activate(app.buttons["tree-collapse-all"])
    XCTAssertTrue(app.staticTexts["tree-search-count"].label.contains("Hidden"))
    activate(app.buttons["Next match"])
    XCTAssertTrue(match.waitForExistence(timeout: 5))
    activate(app.buttons["tree-copy"])
    activate(app.buttons["Copy JSON Fragment"])
    activate(app.buttons["tree-input-toggle"])
    XCTAssertEqual(input.value as? String, source)
    activate(app.buttons["Clear Input"])
    #if os(macOS)
      activate(input); input.typeKey("v", modifierFlags: .command)
    #else
      input.press(forDuration: 1.2)
      let paste = app.menuItems["Paste"].firstMatch
      if paste.waitForExistence(timeout: 3) { activate(paste) }
      else { activate(app.buttons["Paste"].firstMatch) }
    #endif
    XCTAssertEqual(input.value as? String, #""admin""#)
    XCTAssertTrue(root.waitForExistence(timeout: 5))
    attachScreenshot("JSON Tree search and native Paste")
    showSidebar(); activate(app.buttons["dataJSON-T-001"])
    XCTAssertEqual(app.textViews["JSON input"].firstMatch.value as? String, "")
    showSidebar(); activate(app.buttons["dataJSON-T-002"])
    XCTAssertEqual(input.value as? String, #""admin""#)
    app.terminate(); app.launchArguments = ["--navigation-ui-tests"]; app.launch()
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    XCTAssertEqual(input.value as? String, "")
  }

  func testIndependentDisclosure() {
    activate(app.buttons["category-dataJSON"])
    XCTAssertFalse(app.buttons["dataJSON-T-001"].exists)
    activate(app.buttons["category-text"])
    XCTAssertTrue(app.buttons["text-T-033"].exists)
    activate(app.buttons["category-dataJSON"])
    XCTAssertTrue(app.buttons["dataJSON-T-001"].exists)
    scrollTo(app.buttons["category-text"])
    XCTAssertEqual(app.buttons["category-text"].value as? String, "Expanded")
    attachScreenshot("Multiple expanded categories")
  }

  func testFavoritesSearchAndImplementedToolSelection() {
    search("guid")
    XCTAssertTrue(app.buttons["generators-T-022"].exists)
    activate(app.buttons["star-generators-T-022"])
    XCTAssertTrue(app.buttons["favorite-T-022"].exists)
    XCTAssertTrue(app.buttons["generators-T-022"].exists)
    activate(app.buttons["favorite-T-022"])
    let generate = app.buttons["identifier-generate"]
    XCTAssertTrue(generate.waitForExistence(timeout: 5))
    activate(generate)
    XCTAssertTrue(app.buttons["identifier-copy-row-0"].waitForExistence(timeout: 5))
    showSidebar()
    activate(app.buttons["star-favorite-T-022"])
    XCTAssertFalse(app.buttons["favorite-T-022"].exists)
    XCTAssertTrue(app.buttons["generators-T-022"].exists)
    XCTAssertTrue(app.buttons["star-generators-T-022"].label.contains("Add to"))
  }

  func testReleaseHomeNavigationCopyAndCatalogFooter() {
    activate(app.buttons["sidebar-home"])
    #if os(iOS)
    if app.frame.width < 600 {
      XCTAssertTrue(app.staticTexts["Browse tools by category or search by name."].exists)
    } else {
      XCTAssertTrue(app.staticTexts["Search by name or browse the categories in the sidebar."].exists)
    }
    #endif
    showSidebar()
    XCTAssertTrue(app.staticTexts["78 tools"].exists)
    XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "working")).firstMatch.exists)
    search("JWT Decoder & Claims Inspector")
    XCTAssertTrue(app.buttons["encoders-T-020"].exists)
    XCTAssertEqual(app.buttons["encoders-T-020"].label, "JWT Decoder & Claims Inspector")
  }

  func testReleaseHomeCopyTitlesAndAX5Actions() {
    app.terminate()
    app.launchArguments = ["--navigation-ui-tests", "--reset-navigation-ui-tests", "--accessibility5", "--reduce-motion"]
    app.launch()
    showSidebar()
    search("T-020")
    let route = app.buttons["encoders-T-020"]
    scrollTo(route); activate(route)
    let title = app.staticTexts["tool-navigation-title"]
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    XCTAssertEqual(title.label, "JWT Decoder & Claims Inspector")
    for identifier in ["jwt-mask", "jwt-options"] {
      let control = app.buttons[identifier]
      scrollWorkspaceTo(control, identifier: "jwt-workspace-scroll")
      XCTAssertTrue(control.isHittable, identifier)
      XCTAssertGreaterThanOrEqual(control.frame.minX, app.frame.minX - 1)
      XCTAssertLessThanOrEqual(control.frame.maxX, app.frame.maxX + 1)
    }
    let trust = app.staticTexts["jwt-trust"]
    scrollWorkspaceTo(trust, identifier: "jwt-workspace-scroll"); XCTAssertEqual(trust.label, "Signature not verified")
    attachScreenshot("JWT AX5 Reduce Motion")
    showSidebar(); clearSearch(); search("T-069")
    let pkiRoute = app.buttons["certificates-T-069"]
    scrollTo(pkiRoute); activate(pkiRoute)
    let generate = app.buttons["pki-run"]
    #if os(iOS)
    expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
    waitForExpectations(timeout: 5)
    #endif
    scrollWorkspaceTo(generate, identifier: "pki-workspace-scroll")
    XCTAssertTrue(generate.isHittable && generate.isEnabled)
    XCTAssertLessThanOrEqual(generate.frame.maxX, app.frame.maxX + 1)
    activate(generate)
    let export = app.buttons["pki-export-private"]
    XCTAssertTrue(export.waitForExistence(timeout: 10))
    scrollWorkspaceTo(export, identifier: "pki-workspace-scroll"); XCTAssertTrue(export.isHittable)
    // Result contains only public data; never capture a revealed private source.
    attachScreenshot("PKI AX5 public result")
  }

  private func scrollWorkspaceTo(_ element: XCUIElement, identifier: String) {
    let scroll = app.scrollViews[identifier]
    for _ in 0..<16 {
      if element.exists && element.isHittable { return }
      let result = app.scrollViews["pki-generated-result"]
      if identifier == "pki-workspace-scroll", result.exists {
        let visible = result.frame.intersection(app.frame)
        if visible.height > 150, element.frame.minY >= visible.maxY {
          // The public summary can itself span several screens at AX5.
          let origin = app.coordinate(withNormalizedOffset: .zero)
          origin.withOffset(CGVector(dx: visible.midX - app.frame.minX, dy: visible.maxY - app.frame.minY - 40))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: visible.midX - app.frame.minX, dy: visible.minY - app.frame.minY + 40)))
          continue
        }
      }
      // The right gutter stays in the workspace when iPad exposes a scroll
      // accessibility frame spanning the adjacent sidebar as well.
      scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.85))
        .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.2)))
    }
    XCTAssertTrue(element.exists && element.isHittable)
  }

  func testPKIProtectedExportConfirmationAndCancel() {
    search("T-069"); activate(app.buttons["certificates-T-069"])
    activate(app.buttons["pki-run"])
    let export = app.buttons["pki-export-private"]
    XCTAssertTrue(export.waitForExistence(timeout: 10)); scrollTo(export); activate(export)
    let first = app.secureTextFields["New export password"]
    let confirmation = app.secureTextFields["Confirm export password"]
    XCTAssertTrue(first.waitForExistence(timeout: 5))
    activate(first); first.typeText("synthetic-\u{00E9}")
    activate(confirmation); confirmation.typeText("synthetic-e\u{0301}")
    let confirm = app.buttons["pki-export-confirm"]
    XCTAssertFalse(confirm.isEnabled)
    activate(app.buttons["Cancel"].firstMatch)
    XCTAssertTrue(export.waitForExistence(timeout: 5)); activate(export)
    // Reopening retains exact drafts, and remains disabled until they match.
    XCTAssertFalse(confirm.isEnabled)
    activate(app.buttons["Cancel"].firstMatch)
    XCTAssertTrue(export.waitForExistence(timeout: 5))
  }

  #if os(iOS)
  func testPKIPlaintextExportNeedsExplicitConsentAndCancels() {
    search("T-069"); activate(app.buttons["certificates-T-069"]); activate(app.buttons["pki-run"])
    let export = app.buttons["pki-export-private"]
    XCTAssertTrue(export.waitForExistence(timeout: 10)); scrollTo(export); activate(export)
    activate(app.switches["Unencrypted export"])
    activate(app.buttons["pki-export-confirm"])
    let consent = app.buttons["Export unencrypted private key"]
    XCTAssertTrue(consent.waitForExistence(timeout: 5)); activate(consent)
    let save = app.buttons["Save"].firstMatch; XCTAssertTrue(save.waitForExistence(timeout: 10))
    let cancel = app.buttons["Cancel"].firstMatch
    if cancel.exists && cancel.isHittable { activate(cancel) }
    else {
      let origin = app.coordinate(withNormalizedOffset: .zero)
      origin.withOffset(CGVector(dx:app.frame.width/2,dy:save.frame.midY-app.frame.minY)).press(forDuration:0.1,thenDragTo:origin.withOffset(CGVector(dx:app.frame.width/2,dy:app.frame.height-40)))
    }
    XCTAssertTrue(app.staticTexts["Export cancelled; result is unchanged."].waitForExistence(timeout: 5))
    XCTAssertTrue(export.isEnabled)
  }

  func testPKIBackgroundConcealsVisualAndAccessibilityContent() {
    search("T-075"); activate(app.buttons["certificates-T-075"])
    activate(app.buttons["Reveal"].firstMatch)
    let input = app.textViews.matching(identifier: "Input input").firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5)); activate(input)
    input.typeText("PUBLIC-NONSECRET-BACKGROUND-MARKER")
    XCUIDevice.shared.press(.home)
    let system = XCUIApplication(bundleIdentifier:"com.apple.springboard")
    system.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.995))
      .press(forDuration:0.05,thenDragTo:system.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.45)),withVelocity:.slow,thenHoldForDuration:1)
    let snapshot = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
    snapshot.name = "System switcher attempt — public nonsecret marker only"
    snapshot.lifetime = .keepAlways; add(snapshot)
    app.activate()
    XCTAssertTrue(app.buttons["Reveal"].firstMatch.waitForExistence(timeout: 5))
    XCTAssertFalse(input.exists)
    XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "PUBLIC-NONSECRET-BACKGROUND-MARKER", "PUBLIC-NONSECRET-BACKGROUND-MARKER")).firstMatch.exists)
    attachScreenshot("PKI background concealed public marker")
    activate(app.buttons["Reveal"].firstMatch)
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    XCTAssertEqual(input.value as? String, "PUBLIC-NONSECRET-BACKGROUND-MARKER")
    showSidebar(); activate(app.buttons["sidebar-home"])
    XCUIDevice.shared.press(.home); app.activate()
    showSidebar(); activate(app.buttons["certificates-T-075"])
    XCTAssertTrue(app.buttons["Reveal"].firstMatch.waitForExistence(timeout: 5))
    XCTAssertFalse(input.exists)
  }
  #endif

  func testPKIExportSystemSaveCancelAndOverwrite() {
    search("T-069"); activate(app.buttons["certificates-T-069"])
    activate(app.buttons["pki-run"])
    let export = app.buttons["pki-export-private"]
    XCTAssertTrue(export.waitForExistence(timeout: 10)); scrollTo(export); activate(export)
    for label in ["New export password", "Confirm export password"] {
      let field = app.secureTextFields[label]
      XCTAssertTrue(field.waitForExistence(timeout: 5)); activate(field); field.typeText("synthetic-release-password")
    }
    activate(app.buttons["pki-export-confirm"])
    let save = app.buttons["Save"].firstMatch
    XCTAssertTrue(save.waitForExistence(timeout: 10))
    #if os(iOS)
    let cancel = app.buttons["Cancel"].firstMatch
    if cancel.exists && cancel.isHittable {
      activate(cancel)
    } else {
      // Compact iOS 27 exposes no Cancel button; its Other named Cancel is
      // actually View Options. Use the sheet's native interactive cancellation.
      let origin = app.coordinate(withNormalizedOffset: .zero)
      origin.withOffset(CGVector(dx: app.frame.width / 2, dy: save.frame.midY - app.frame.minY))
        .press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: app.frame.width / 2, dy: app.frame.height - 40)))
    }
    #else
    let cancel = app.buttons["Cancel"].firstMatch
    XCTAssertTrue(cancel.waitForExistence(timeout: 8)); activate(cancel)
    #endif
    XCTAssertTrue(export.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Export cancelled; result is unchanged."].waitForExistence(timeout: 5))
    let stem = "dt-release-" + UUID().uuidString
    for overwrite in [false, true] {
      scrollTo(export); activate(export); activate(app.buttons["pki-export-confirm"])
      XCTAssertTrue(save.waitForExistence(timeout: 10))
      let name = app.textFields.matching(NSPredicate(format: "value CONTAINS %@", "private-key")).firstMatch
      XCTAssertTrue(name.waitForExistence(timeout: 5))
      activate(name)
      #if os(macOS)
      name.typeKey("a", modifierFlags: .command)
      name.typeText(stem + ".pem")
      #else
      name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 100) + stem)
      #endif
      activate(save)
      if overwrite {
        #if os(iOS)
        let systemReplace = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Replace"].firstMatch
        if systemReplace.waitForExistence(timeout: 3) { activate(systemReplace) }
        else { let replace = app.buttons["Replace"].firstMatch; XCTAssertTrue(replace.waitForExistence(timeout: 5)); activate(replace) }
        #else
        let replace = app.buttons["Replace"].firstMatch; XCTAssertTrue(replace.waitForExistence(timeout: 5)); activate(replace)
        #endif
      }
      XCTAssertTrue(app.staticTexts["Export completed."].waitForExistence(timeout: 12))
      XCTAssertTrue(export.isEnabled)
    }
    // Only a unique synthetic encrypted artifact is written; no working keys enter logs.
    print("PKI_RELEASE_EXPORT_TEST_FILE " + stem + ".pem")
  }

  func testReorderMenuAndReset() {
    activate(app.buttons["catalog-reorder"])
    activate(app.buttons["move-T-003"])
    activate(app.buttons["Move up"])
    XCTAssertLessThan(
      app.buttons["dataJSON-T-003"].frame.minY, app.buttons["dataJSON-T-002"].frame.minY)
    activate(app.buttons["catalog-options"])
    activate(app.buttons["Reset to Default Order"])
    XCTAssertLessThan(
      app.buttons["dataJSON-T-002"].frame.minY, app.buttons["dataJSON-T-003"].frame.minY)
  }

  func testSearchDisablesReorderingAndRestoresExpansion() {
    activate(app.buttons["catalog-reorder"])
    search("json minify")
    XCTAssertTrue(app.buttons["dataJSON-T-001"].exists)
    XCTAssertFalse(app.buttons["catalog-reorder"].isEnabled)
    XCTAssertFalse(app.buttons["move-T-001"].exists)
    clearSearch()
    XCTAssertTrue(app.buttons["catalog-reorder"].isEnabled)
    XCTAssertTrue(app.buttons["move-T-001"].exists)
    XCTAssertEqual(app.buttons["category-dataJSON"].value as? String, "Expanded")
    activate(app.buttons["category-dataJSON"])
    XCTAssertEqual(app.buttons["category-encoders"].value as? String, "Collapsed")
  }

  func testPreferencesSurviveRelaunch() {
    activate(app.buttons["star-dataJSON-T-001"])
    activate(app.buttons["category-dataJSON"])
    app.terminate()
    app.launchArguments = ["--navigation-ui-tests"]
    app.launch()
    showSidebar()
    XCTAssertTrue(app.buttons["favorite-T-001"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["dataJSON-T-001"].exists)
    XCTAssertEqual(app.buttons["category-dataJSON"].value as? String, "Collapsed")
  }

  private func scrollTo(_ element: XCUIElement) {
    let scroll =
      app.collectionViews.firstMatch.exists
      ? app.collectionViews.firstMatch : app.scrollViews.firstMatch
    for _ in 0..<8 {
      if element.exists && element.isHittable { return }
      scroll.swipeUp()
    }
    XCTAssertTrue(element.exists)
  }

  func testNativeDragReordersTools() {
    activate(app.buttons["catalog-reorder"])
    let source = app.descendants(matching: .any)["drag-T-003"].firstMatch
    let target = app.buttons["dataJSON-T-001"]
    let start = source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    // Aim at the insertion boundary above the target, not a row action.
    let destination = target.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.05))
    #if os(macOS)
      start.click(forDuration: 0.7, thenDragTo: destination)
    #else
      start.press(forDuration: 0.7, thenDragTo: destination)
    #endif
    waitUntilReorderCompletes()
    XCTAssertLessThan(
      app.buttons["dataJSON-T-003"].frame.minY, app.buttons["dataJSON-T-001"].frame.minY)
    attachScreenshot("Reordered using native drag")
  }

  func testFavoriteOrderAndCategoryOrderMenus() {
    activate(app.buttons["star-dataJSON-T-001"])
    activate(app.buttons["star-dataJSON-T-002"])
    activate(app.buttons["catalog-reorder"])
    activate(app.buttons.matching(identifier: "move-T-002").firstMatch)
    activate(app.buttons["Move up"])
    XCTAssertLessThan(
      app.buttons["favorite-T-002"].frame.minY, app.buttons["favorite-T-001"].frame.minY)
    activate(app.buttons["category-dataJSON"])
    scrollTo(app.buttons["move-text"])
    activate(app.buttons["move-text"])
    activate(app.buttons["Move up"])
    XCTAssertLessThan(
      app.buttons["category-text"].frame.minY, app.buttons["category-generators"].frame.minY)
  }

  func testToolDragCannotReorderCategories() {
    activate(app.buttons["catalog-reorder"])
    let source = app.descendants(matching: .any)["drag-T-003"].firstMatch
    let start = source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    let end = app.buttons["category-dataJSON"].coordinate(
      withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    #if os(macOS)
      start.click(forDuration: 0.7, thenDragTo: end)
    #else
      start.press(forDuration: 0.7, thenDragTo: end)
    #endif
    waitUntilReorderCompletes()
    XCTAssertLessThan(
      app.buttons["dataJSON-T-001"].frame.minY, app.buttons["dataJSON-T-003"].frame.minY)
    XCTAssertEqual(app.buttons["category-dataJSON"].value as? String, "Expanded")
  }

  func testFirstLaunchHomeAndCollapsedSections() {
    app.terminate()
    app.launch()
    XCTAssertTrue(app.staticTexts["home-tagline"].waitForExistence(timeout: 10))
    attachScreenshot("First launch Home")
    showSidebar()
    XCTAssertEqual(app.buttons["favorites-section"].value as? String, "Collapsed")
    for category in [
      "dataJSON", "encoders", "generators", "text", "dateNetwork", "formatters", "colorFiles",
      "certificates",
    ] {
      scrollTo(app.buttons["category-" + category])
      XCTAssertEqual(app.buttons["category-" + category].value as? String, "Collapsed")
    }
    XCTAssertFalse(app.buttons["dataJSON-T-001"].exists)
  }

  func testFavoritesDisclosureAndHomeRestore() {
    activate(app.buttons["star-dataJSON-T-001"])
    activate(app.buttons["favorites-section"])
    XCTAssertFalse(app.buttons["favorite-T-001"].exists)
    search("json minify")
    XCTAssertTrue(app.buttons["favorite-T-001"].exists)
    clearSearch()
    XCTAssertFalse(app.buttons["favorite-T-001"].exists)
    activate(app.buttons["dataJSON-T-001"])
    showSidebar()
    activate(app.buttons["sidebar-home"])
    app.terminate()
    app.launchArguments = ["--navigation-ui-tests"]
    app.launch()
    XCTAssertTrue(app.staticTexts["home-tagline"].waitForExistence(timeout: 10))
    showSidebar()
    XCTAssertEqual(app.buttons["favorites-section"].value as? String, "Collapsed")
    activate(app.buttons["favorites-section"])
    XCTAssertTrue(app.buttons["favorite-T-001"].exists)
  }

  func testWorkspaceLivesOnlyUntilProcessEnds() {
    activate(app.buttons["dataJSON-T-001"])
    let input = app.textViews.matching(identifier: "JSON input").firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    activate(input)
    let source = #"{"private":"session-only"}"#
    input.typeText(source)
    activate(app.buttons["Format"])
    if app.buttons["Expand Output"].exists { activate(app.buttons["Expand Output"]) }
    let output = app.textViews.matching(identifier: "JSON result").firstMatch
    let rendered = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value CONTAINS %@", "session-only"), object: output)
    XCTAssertEqual(XCTWaiter.wait(for: [rendered], timeout: 5), .completed)
    showSidebar()
    activate(app.buttons["sidebar-home"])
    showSidebar()
    activate(app.buttons["dataJSON-T-001"])
    XCTAssertEqual(input.value as? String, source)
    XCTAssertTrue((output.value as? String ?? "").contains("session-only"))
    #if os(iOS)
      XCUIDevice.shared.press(.home)
      app.activate()
      XCTAssertEqual(input.value as? String, source)
    #endif
    app.terminate()
    app.launchArguments = ["--navigation-ui-tests"]
    app.launch()
    XCTAssertTrue(input.waitForExistence(timeout: 10))
    XCTAssertEqual(input.value as? String, "")
    XCTAssertEqual(output.value as? String, "")
    attachScreenshot("Restored JSON tool with empty editors")
  }

  func testNavigationWithReduceMotion() {
    app.terminate()
    app.launchArguments = [
      "--navigation-ui-tests", "--reset-navigation-ui-tests", "--reduce-motion",
    ]
    app.launch()
    showSidebar()
    activate(app.buttons["category-dataJSON"])
    activate(app.buttons["favorites-section"])
    activate(app.buttons["star-dataJSON-T-001"])
    XCTAssertTrue(app.buttons["favorite-T-001"].exists)
    activate(app.buttons["favorites-section"])
    XCTAssertFalse(app.buttons["favorite-T-001"].exists)
    XCTAssertTrue(app.buttons["dataJSON-T-001"].exists)
  }


  func testJSONDiagnosticsNavigationAndWrap() {
    activate(app.buttons["dataJSON-T-001"])
    let input = app.textViews["JSON input"].firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    activate(input)
    let source = #"{"a":[1,2"#
    input.typeText(source)
    let frame = input.frame
    activate(app.buttons["Validate"])
    XCTAssertTrue(app.staticTexts["Invalid JSON"].waitForExistence(timeout: 5))
    XCTAssertGreaterThan(input.frame.minY, frame.minY + 20) // error details expand above the editors
    XCTAssertLessThan(input.frame.height, frame.height)
    let context = app.staticTexts["json-diagnostic-context"]
    XCTAssertTrue(context.waitForExistence(timeout: 5))
    XCTAssertTrue(context.label.contains("EOF"))
    activate(app.buttons["json-show-detection"])
    XCTAssertEqual(input.value as? String, source)
    activate(app.buttons["JSON options"])
    #if os(macOS)
      activate(app.menuItems["Word Wrap"])
    #else
      activate(app.buttons["Word Wrap"])
    #endif
    activate(app.buttons["json-show-detection"])
    XCTAssertEqual(input.value as? String, source)
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "JSON diagnostics framebuffer"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    activate(app.buttons["json-show-related"])
    #if os(macOS)
      activate(app.menuItems.matching(NSPredicate(format: "label BEGINSWITH %@", "Container start")).firstMatch)
    #else
      activate(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Container start")).firstMatch)
    #endif
    input.typeText(" ")
    XCTAssertTrue(app.staticTexts["Not checked"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["json-show-detection"].exists)
    XCTAssertFalse(app.staticTexts["Invalid JSON"].exists)
    activate(app.buttons["Clear Input"])
    activate(input)
    input.typeText("[1 2]")
    activate(app.buttons["Validate"])
    XCTAssertTrue(app.staticTexts["Invalid JSON"].waitForExistence(timeout: 5))
    activate(app.buttons["json-show-detection"])
    XCTAssertEqual(input.value as? String, "[1 2]")
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    let token = XCTAttachment(screenshot: app.screenshot())
    token.name = "JSON diagnostic token underline"
    token.lifetime = .keepAlways
    add(token)
  }

  func testJSONOperationsKeepPanelFramesStable() {
    activate(app.buttons["dataJSON-T-001"])
    let input = app.textViews["JSON input"].firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    activate(input)
    input.typeText(#"{"number":123,"items":[true,null]}"#)
    XCTAssertTrue(app.staticTexts["Not checked"].waitForExistence(timeout: 3))
    XCTAssertLessThan(app.staticTexts["Not checked"].frame.maxY, input.frame.minY)
    XCTAssertLessThan(input.frame.minY - app.staticTexts["Not checked"].frame.maxY, 80)
    let initial = input.frame
    for action in ["Format", "Minify", "Validate", "Format", "Validate"] {
      activate(app.buttons[action])
      XCTAssertTrue(app.staticTexts["Valid JSON"].waitForExistence(timeout: 5))
      let frame = input.frame
      XCTAssertEqual(frame.minY, initial.minY, accuracy: 1, "Input moved after \(action)")
      XCTAssertEqual(frame.height, initial.height, accuracy: 1, "Input resized after \(action)")
      XCTAssertEqual(input.value as? String, #"{"number":123,"items":[true,null]}"#)
    }
    activate(app.buttons["Clear Input"])
    activate(input)
    input.typeText("[1 2]")
    activate(app.buttons["Validate"])
    XCTAssertTrue(app.staticTexts["Invalid JSON"].waitForExistence(timeout: 5))
    XCTAssertLessThan(app.staticTexts["Invalid JSON"].frame.maxY, input.frame.minY)
    XCTAssertGreaterThan(input.frame.minY, initial.minY + 20)
    XCTAssertLessThan(input.frame.height, initial.height)
    XCTAssertEqual(input.value as? String, "[1 2]")
    activate(app.buttons["Clear Input"])
    XCTAssertTrue(app.staticTexts["Ready"].waitForExistence(timeout: 3))
    XCTAssertEqual(input.frame.minY, initial.minY, accuracy: 1)
    XCTAssertEqual(input.frame.height, initial.height, accuracy: 1)
  }

  func testJSONPasteValidationAndOutputLifecycle() {
    activate(app.buttons["dataJSON-T-001"])
    let input = app.textViews["JSON input"].firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    activate(input)
    input.typeText(#"{"number":9007199254740993}"#)
    XCTAssertFalse(app.staticTexts["Valid JSON"].exists)
    activate(app.buttons["Format"])
    XCTAssertTrue(app.staticTexts["Valid JSON"].waitForExistence(timeout: 5))
    if app.buttons["Expand Output"].exists { activate(app.buttons["Expand Output"]) }
    let output = app.textViews["JSON result"].firstMatch
    let formatted = output.value as? String
    XCTAssertTrue(formatted?.contains("9007199254740993") == true)
    activate(app.buttons["Validate"])
    XCTAssertTrue(app.staticTexts["Valid JSON"].waitForExistence(timeout: 5))
    XCTAssertEqual(output.value as? String, formatted)
    activate(app.buttons["Copy Output"])
    activate(app.buttons["Clear Input"])
    XCTAssertFalse(app.buttons["Copy Output"].isEnabled)
    #if os(macOS)
      activate(input)
      input.typeKey("v", modifierFlags: .command)
    #else
      input.press(forDuration: 1.2)
      let paste = app.menuItems["Paste"].firstMatch
      if paste.waitForExistence(timeout: 3) { activate(paste) }
      else { activate(app.buttons["Paste"].firstMatch) }
    #endif
    XCTAssertTrue(app.staticTexts["Valid JSON"].waitForExistence(timeout: 5))
    XCTAssertEqual(input.value as? String, formatted)
    #if os(iOS)
      XCUIDevice.shared.orientation = .landscapeLeft
      XCTAssertEqual(input.value as? String, formatted)
      XCUIDevice.shared.orientation = .portrait
      XCTAssertEqual(input.value as? String, formatted)
    #endif
    XCTAssertFalse(app.buttons["Copy Output"].isEnabled)
    input.typeText("x")
    XCTAssertFalse(app.staticTexts["Valid JSON"].exists)
    XCTAssertFalse(app.staticTexts["Invalid JSON"].exists)
    activate(app.buttons["JSON options"])
    #if os(macOS)
      activate(app.menuItems["Validate automatically on paste"].firstMatch)
    #else
      activate(app.buttons["Validate automatically on paste"].firstMatch)
    #endif
    // Dismiss the native menu, then explicitly paste again with automatic validation off.
    activate(input)
    activate(app.buttons["Clear Input"])
    #if os(macOS)
      input.typeKey("v", modifierFlags: .command)
    #else
      input.press(forDuration: 1.2)
      let secondPaste = app.menuItems["Paste"].firstMatch
      if secondPaste.waitForExistence(timeout: 3) { activate(secondPaste) }
      else { activate(app.buttons["Paste"].firstMatch) }
    #endif
    XCTAssertEqual(input.value as? String, formatted)
    XCTAssertFalse(app.staticTexts["Valid JSON"].exists)
    XCTAssertFalse(app.staticTexts["Invalid JSON"].exists)
  }

  private func chooseAppearance(_ name: String) {
    activate(app.buttons["appearance-menu"])
    #if os(macOS)
      activate(app.menuItems[name])
    #else
      activate(app.buttons[name])
    #endif
    XCTAssertEqual(app.buttons["appearance-menu"].label, "Appearance: " + name)
  }

  func testAppearancePersistsWithoutLosingWorkspaceOrNavigation() {
    activate(app.buttons["star-dataJSON-T-001"])
    activate(app.buttons["catalog-reorder"])
    activate(app.buttons["move-T-003"])
    activate(app.buttons["Move up"])
    activate(app.buttons["dataJSON-T-001"])
    let input = app.textViews.matching(identifier: "JSON input").firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    activate(input)
    let source = #"{"theme":"session-only"}"#
    input.typeText(source)
    activate(app.buttons["Format"])
    if app.buttons["Expand Output"].exists { activate(app.buttons["Expand Output"]) }
    let output = app.textViews.matching(identifier: "JSON result").firstMatch
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "session-only"), object: output)
        ], timeout: 5), .completed)
    for appearance in ["Light", "Dark", "System", "Dark"] {
      chooseAppearance(appearance)
      XCTAssertEqual(input.value as? String, source)
      XCTAssertTrue((output.value as? String ?? "").contains("session-only"))
      XCTAssertTrue(app.staticTexts["JSON Formatter"].firstMatch.exists)
      attachScreenshot("JSON Formatter appearance " + appearance)
    }
    app.terminate()
    app.launchArguments = ["--navigation-ui-tests"]
    app.launch()
    XCTAssertTrue(input.waitForExistence(timeout: 10))
    XCTAssertEqual(app.buttons["appearance-menu"].label, "Appearance: Dark")
    XCTAssertEqual(input.value as? String, "")
    showSidebar()
    XCTAssertTrue(app.buttons["favorite-T-001"].exists)
    XCTAssertLessThan(
      app.buttons["dataJSON-T-003"].frame.minY, app.buttons["dataJSON-T-002"].frame.minY)
    activate(app.buttons["sidebar-home"])
    XCTAssertTrue(app.staticTexts["Developer Tools"].firstMatch.exists)
    chooseAppearance("System")
    attachScreenshot("Developer Tools Home with Appearance")
  }

  private func waitUntilReorderCompletes() {
    let ended = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label == %@", "Done reordering"),
      object: app.buttons["catalog-reorder"])
    XCTAssertEqual(XCTWaiter.wait(for: [ended], timeout: 8), .completed)
  }

  private func drag(_ source: XCUIElement, to target: XCUIElement, hold: TimeInterval = 0.5) {
    let start = source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    // Keep the pointer over the handle column, as in a normal vertical sidebar drag.
    let destination = start.withOffset(
      CGVector(
        dx: 0, dy: target.frame.minY + target.frame.height * 0.1 - start.screenPoint.y))
    #if os(macOS)
      start.click(
        forDuration: 0.7, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: hold)
    #else
      start.press(
        forDuration: 0.7, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: hold)
    #endif
    waitUntilReorderCompletes()
  }

  func testDragCancellationRestoresOriginalOrder() {
    activate(app.buttons["catalog-reorder"])
    drag(app.descendants(matching: .any)["drag-T-003"].firstMatch, to: app.buttons["sidebar-home"])
    XCTAssertLessThan(
      app.buttons["dataJSON-T-001"].frame.minY, app.buttons["dataJSON-T-003"].frame.minY)
    app.terminate()
    app.launchArguments = ["--navigation-ui-tests"]
    app.launch()
    showSidebar()
    XCTAssertLessThan(
      app.buttons["dataJSON-T-001"].frame.minY, app.buttons["dataJSON-T-003"].frame.minY)
  }

  func testNativeFavoriteAndExpandedCategoryDragsPersist() {
    activate(app.buttons["star-dataJSON-T-001"])
    activate(app.buttons["star-dataJSON-T-002"])
    activate(app.buttons["catalog-reorder"])
    drag(
      app.descendants(matching: .any)["drag-T-002"].firstMatch, to: app.buttons["favorite-T-001"])
    XCTAssertLessThan(
      app.buttons["favorite-T-002"].frame.minY, app.buttons["favorite-T-001"].frame.minY)
    activate(app.buttons["category-dataJSON"])
    scrollTo(app.buttons["category-encoders"])
    activate(app.buttons["category-encoders"])
    drag(
      app.descendants(matching: .any)["drag-encoders"].firstMatch,
      to: app.buttons["category-dataJSON"])
    XCTAssertLessThan(
      app.buttons["category-encoders"].frame.minY, app.buttons["category-dataJSON"].frame.minY)
    XCTAssertEqual(app.buttons["category-encoders"].value as? String, "Expanded")
    XCTAssertTrue(app.buttons["encoders-T-012"].exists)
    attachScreenshot("Dragged category with contents")
    app.terminate()
    app.launchArguments = ["--navigation-ui-tests"]
    app.launch()
    showSidebar()
    XCTAssertLessThan(
      app.buttons["favorite-T-002"].frame.minY, app.buttons["favorite-T-001"].frame.minY)
    XCTAssertLessThan(
      app.buttons["category-encoders"].frame.minY, app.buttons["category-dataJSON"].frame.minY)
  }

  /// Hold long enough to inspect/capture the actual simulator before the finger is released.
  func testLiveDragPreviewInspection() {
    activate(app.buttons["catalog-reorder"])
    drag(
      app.descendants(matching: .any)["drag-T-003"].firstMatch,
      to: app.buttons["dataJSON-T-001"], hold: 8)
    XCTAssertLessThan(
      app.buttons["dataJSON-T-003"].frame.minY, app.buttons["dataJSON-T-001"].frame.minY)
  }

  private func attachScreenshot(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
