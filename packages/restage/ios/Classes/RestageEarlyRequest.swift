import CryptoKit
import Flutter
import Foundation
import Security
import UIKit

/// One buffered startup request, sent at app launch and handed to Dart once.
@objc(RestageEarlyRequest)
public final class RestageEarlyRequest: NSObject {
  struct Result {
    let status: Int
    let body: Data
    let headers: [String: String]
    let sentAtMicros: Int64
    let answeredAtMicros: Int64
  }

  private static let contractRequired = 409
  private static let done = DispatchSemaphore(value: 0)
  private static let configured = DispatchSemaphore(value: 0)
  private static let lock = NSLock()
  private static var result: Result?
  private static var sent: Data?
  private static var templateJson: String?
  private static var taken = false
  private static var sentAtMicros: Int64 = 0
  private static var doneSignalled = false
  private static var configuredSignalled = false

  @objc public static func start() {
    Thread.detachNewThread { run() }
  }

  static func supportDirectory() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
  }

  private static func lastFile() -> URL { supportDirectory().appendingPathComponent("restage_early_last.json") }

  // No file is no choice; a file that can't be read fails closed: no analytics.
  private static func readChoice() -> (hosted: Bool?, analytics: Bool?, measurement: Bool?) {
    guard FileManager.default.fileExists(atPath: choiceFile().path) else { return (nil, nil, nil) }
    guard let data = try? Data(contentsOf: choiceFile()),
      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return (nil, false, false) }
    return (json["hosted"] as? Bool, json["analytics"] as? Bool, json["measurement"] as? Bool)
  }

  private static func choiceFile() -> URL { supportDirectory().appendingPathComponent("restage_early_choice.json") }

  /// Keeps what the app configured, for the request at the next launch;
  /// [analytics] is nil when the app left it to the build.
  static func saveChoice(hosted: Bool, analytics: Bool?, measurement: Bool) {
    var choice: [String: Any] = ["hosted": hosted, "measurement": measurement]
    if let analytics { choice["analytics"] = analytics }
    guard let data = try? JSONSerialization.data(withJSONObject: choice, options: .sortedKeys) else { return }
    if (try? Data(contentsOf: choiceFile())) == data { return }
    try? data.write(to: choiceFile(), options: .atomic)
  }

  private static func run() {
    defer {
      signalConfigured()
      lock.lock()
      if !doneSignalled { doneSignalled = true; done.signal() }
      lock.unlock()
    }
    let persisted = try? Data(contentsOf: lastFile())
    let persistedJSON = persisted.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
    let disabled = persistedJSON?["disabled"] as? Bool == true
    // A kept template describes the build that wrote it.
    let kept = !disabled && persistedJSON?["builtFor"] as? String == EarlyFacts.buildStamp() ? persisted : nil
    let sources: [() -> Data?] = [{ kept }, bundledTemplate, flutterAssetTemplate]
    let data = sources.lazy.compactMap { $0() }.first { EarlyTemplate($0) != nil }
    guard let data, let template = EarlyTemplate(data) else { return }
    // The text stays readable even when no request goes out.
    lock.lock()
    templateJson = String(data: data, encoding: .utf8)
    lock.unlock()
    if disabled { return }
    let choice = readChoice()
    // An app last configured offline sends nothing.
    if choice.hosted == false { return }
    let analytics = choice.analytics ?? template.analyticsDefault
    // Either the build or the last launch turning measurement off is enough.
    let measurement = template.measurementDefault && choice.measurement != false
    guard let text = template.text(full: false, analytics: analytics, measurement: measurement) else { return }
    // The registration is made only for a request that carries it.
    if text.contains(EarlyTemplate.nonceToken) {
      guard (try? EarlyFacts.registration(supportDirectory())) != nil else { return }
    }
    guard var facts = try? EarlyFacts.read() else { return }
    facts["mountedSince"] = EarlyFacts.mountedSince(supportDirectory(), authorization: template.authorization)
    guard let body = template.body(text: text, facts: facts) else { return }
    lock.lock()
    sent = body
    lock.unlock()
    signalConfigured()
    sentAtMicros = Int64(Date().timeIntervalSince1970 * 1_000_000)
    var (status, bytes, headers) = post(template, body)
    if status == contractRequired, let fullText = template.text(full: true, analytics: analytics, measurement: measurement),
      let full = template.body(text: fullText, facts: facts) {
      (status, bytes, headers) = post(template, full)
    }
    lock.lock()
    result = Result(status: status, body: bytes, headers: headers, sentAtMicros: sentAtMicros, answeredAtMicros: Int64(Date().timeIntervalSince1970 * 1_000_000))
    lock.unlock()
  }

  // The template added to the Runner target's resources.
  private static func bundledTemplate() -> Data? {
    Bundle.main.url(forResource: "restage_early", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
  }

  // The template pubspec.yaml lists under `flutter: assets:`.
  private static func flutterAssetTemplate() -> Data? {
    let key = FlutterDartProject.lookupKey(forAsset: "ios/Runner/restage_early.json")
    guard let path = Bundle.main.path(forResource: key, ofType: nil) else { return nil }
    return try? Data(contentsOf: URL(fileURLWithPath: path))
  }

  private static func signalConfigured() {
    lock.lock()
    if !configuredSignalled { configuredSignalled = true; configured.signal() }
    lock.unlock()
  }

  private static func post(_ template: EarlyTemplate, _ body: Data) -> (Int, Data, [String: String]) {
    guard let url = URL(string: template.url) else { return (0, Data(), [:]) }
    var request = URLRequest(url: url, timeoutInterval: 8)
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue(template.authorization, forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let finished = DispatchSemaphore(value: 0)
    var out: (Int, Data, [String: String]) = (0, Data(), [:])
    URLSession.shared.dataTask(with: request) { data, response, _ in
      let http = response as? HTTPURLResponse
      var headers: [String: String] = [:]
      for (key, value) in http?.allHeaderFields ?? [:] {
        headers["\(key)".lowercased()] = "\(value)"
      }
      out = (http?.statusCode ?? 0, data ?? Data(), headers)
      finished.signal()
    }.resume()
    finished.wait()
    return out
  }

  /// The request the platform sent and its answer, whether or not it equals
  /// Dart's: waits for the request to finish, and marks the answer taken.
  static func inFlight(timeout: TimeInterval) -> (Data, Result?)? {
    lock.lock()
    if taken { lock.unlock(); return nil }
    lock.unlock()
    awaitSignal(configured, timeout)
    lock.lock()
    guard let early = sent else { lock.unlock(); return nil }
    taken = true
    lock.unlock()
    awaitSignal(done, timeout)
    lock.lock()
    defer { lock.unlock() }
    return (early, result)
  }

  // Waits for a one-time signal and passes it on, so every later waiter sees it.
  private static func awaitSignal(_ semaphore: DispatchSemaphore, _ timeout: TimeInterval) {
    if semaphore.wait(timeout: .now() + timeout) == .success { semaphore.signal() }
  }

  /// The template text in use, for a debug comparison.
  static func templateText() -> String? {
    lock.lock()
    defer { lock.unlock() }
    return templateJson
  }

  /// The request the platform sent, once it is configured; nil when it sent none.
  static func sentBytes(timeout: TimeInterval) -> Data? {
    awaitSignal(configured, timeout)
    lock.lock()
    defer { lock.unlock() }
    return sent
  }

  /// Keeps Dart's startup template for the next launch.
  static func remember(_ template: String) {
    let temp = supportDirectory().appendingPathComponent("restage_early_last.json.tmp")
    guard var json = (try? JSONSerialization.jsonObject(with: Data(template.utf8))) as? [String: Any] else { return }
    json["builtFor"] = EarlyFacts.buildStamp()
    guard let data = try? JSONSerialization.data(withJSONObject: json), (try? data.write(to: temp)) != nil else { return }
    _ = try? FileManager.default.replaceItemAt(lastFile(), withItemAt: temp)
  }

  /// Clears startup authority without falling back to a bundled template.
  static func invalidateStartup() throws {
    let disabled: [String: Any] = ["builtFor": EarlyFacts.buildStamp(), "disabled": true]
    let data = try JSONSerialization.data(withJSONObject: disabled)
    try data.write(to: lastFile(), options: .atomic)
    lock.lock()
    templateJson = nil
    lock.unlock()
  }

  static func registration() throws -> (String, Int64) { try EarlyFacts.registration(supportDirectory()) }
}

/// The startup request as data: canonical body strings with value tokens, plus
/// the facts native fills in.
struct EarlyTemplate {
  let url: String
  let authorization: String
  private let json: [String: Any]
  private let fills: Set<String>

  static let nonceToken = "@@registrationNonce@@"

  /// The build's analytics default; true for a template that names none.
  var analyticsDefault: Bool { json["analytics"] as? Bool ?? true }

  /// The app's measurement setting; true for a template that names none.
  var measurementDefault: Bool { json["measurement"] as? Bool ?? true }

  /// The body to send for the two switches; nil when this template has none.
  func text(full: Bool, analytics: Bool, measurement: Bool) -> String? {
    let source: [String: Any]?
    if !analytics {
      source = json["analyticsOff"] as? [String: Any]
    } else if !measurement {
      source = json["measurementOff"] as? [String: Any]
    } else {
      source = json
    }
    guard let text = source?[full ? "fullBody" : "body"] as? String, !text.isEmpty else { return nil }
    return text
  }

  init?(_ data: Data) {
    guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let url = json["url"] as? String, let authorization = json["authorization"] as? String
    else { return nil }
    self.json = json
    self.url = url
    self.authorization = authorization
    self.fills = Set((json["fills"] as? [String]) ?? [])
  }

  func body(text body: String, facts: [String: Any?]) -> Data? {
    var text = body
    if text.contains("@@buildContract@@") || text.contains("@@appBuildContractHash@@") {
      let ordinal = facts["appBuildOrdinal"].flatMap { $0 }.map { "\($0)" } ?? "null"
      let contract = ((json["contract"] as? String) ?? "").replacingOccurrences(of: "@@buildOrdinal@@", with: ordinal)
      let digest = SHA256.hash(data: Data(("restage.placement-build-contract.v1\u{0}" + contract).utf8))
      text = text.replacingOccurrences(of: "@@buildContract@@", with: contract)
        .replacingOccurrences(of: "@@appBuildContractHash@@", with: "sha256:" + digest.map { String(format: "%02x", $0) }.joined())
    }
    text = text.replacingOccurrences(of: "@@meteringKey@@", with: "\(facts["meteringKey"].flatMap { $0 } ?? "")")
      .replacingOccurrences(of: "@@analyticsAnonymousId@@", with: "\(facts["analyticsAnonymousId"].flatMap { $0 } ?? "")")
    text = text.replacingOccurrences(of: "@@mountedSince@@", with: "\(facts["mountedSince"].flatMap { $0 } ?? "")")
    text = text.replacingOccurrences(of: "@@registrationNonce@@", with: "\(facts["registrationNonce"].flatMap { $0 } ?? "")")
      .replacingOccurrences(of: "@@registrationCreatedAtMicros@@", with: "\(facts["registrationCreatedAtMicros"].flatMap { $0 } ?? 0)")
    text = text.replacingOccurrences(of: "@@utcOffsetMinutes@@", with: "\(facts["utcOffsetMinutes"].flatMap { $0 } ?? 0)")
    if text.contains("@@sdkBuiltIns@@") {
      text = text.replacingOccurrences(of: "@@sdkBuiltIns@@", with: carrier("builtIns", facts))
    }
    if text.contains("@@sdkInstalledLibraries@@") {
      text = text.replacingOccurrences(of: "@@sdkInstalledLibraries@@", with: carrier("installedLibraries", facts))
    }
    return text.data(using: .utf8)
  }

  private func carrier(_ name: String, _ facts: [String: Any?]) -> String {
    var tree = (json[name] as? [String: Any]) ?? [:]
    for key in fills where key != "utcOffsetMinutes" && key != "buildOrdinal" && (key == "appVersion") == (name == "installedLibraries") {
      if let value = facts[key].flatMap({ $0 }) { tree[key] = value } else { tree.removeValue(forKey: key) }
    }
    let bytes = Data(Canonical.encode(tree).utf8)
    return bytes.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

/// Canonical JSON: keys sorted, no whitespace, integers only.
enum Canonical {
  static func encode(_ value: Any) -> String {
    var out = ""
    write(&out, value)
    return out
  }

  private static func write(_ out: inout String, _ value: Any) {
    switch value {
    case let number as NSNumber:
      if CFGetTypeID(number) == CFBooleanGetTypeID() { out += number.boolValue ? "true" : "false" } else { out += "\(number.int64Value)" }
    case let string as String:
      writeString(&out, string)
    case let array as [Any]:
      out += "["
      for (index, item) in array.enumerated() {
        if index > 0 { out += "," }
        write(&out, item)
      }
      out += "]"
    case let object as [String: Any]:
      out += "{"
      for (index, key) in object.keys.sorted(by: { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }).enumerated() {
        if index > 0 { out += "," }
        writeString(&out, key)
        out += ":"
        write(&out, object[key]!)
      }
      out += "}"
    default:
      out += "null"
    }
  }

  private static func writeString(_ out: inout String, _ value: String) {
    out += "\""
    for scalar in value.unicodeScalars {
      switch scalar {
      case "\"": out += "\\\""
      case "\\": out += "\\\\"
      case "\u{08}": out += "\\b"
      case "\t": out += "\\t"
      case "\n": out += "\\n"
      case "\u{0C}": out += "\\f"
      case "\r": out += "\\r"
      default:
        if scalar.value < 0x20 {
          out += "\\u00" + String(format: "%02x", scalar.value)
        } else {
          out.unicodeScalars.append(scalar)
        }
      }
    }
    out += "\""
  }
}

/// Device facts native knows at launch, in the forms the Dart client sends.
enum EarlyFacts {
  static func read() throws -> [String: Any?] {
    let dir = RestageEarlyRequest.supportDirectory()
    let registration = existingRegistration(dir)
    let parts = Locale.preferredLanguages.first.map { NSLocale.components(fromLocaleIdentifier: $0) } ?? [:]
    let bounds = UIScreen.main.bounds
    let shortest = min(bounds.width, bounds.height)
    let info = Bundle.main.infoDictionary
    let build = info?["CFBundleVersion"] as? String
    let version = (info?["CFBundleShortVersionString"] as? String)?.trimmingCharacters(in: .whitespaces)
    return [
      "country": twoLetter(parts[NSLocale.Key.countryCode.rawValue])?.lowercased(),
      "language": twoLetter(parts[NSLocale.Key.languageCode.rawValue])?.lowercased(),
      "platform": "ios",
      "osVersion": Int(UIDevice.current.systemVersion.split(separator: ".").first ?? ""),
      "deviceClass": shortest > 0 ? (shortest < 600 ? "phone" : "tablet") : nil,
      "appBuildOrdinal": build.flatMap { $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) ? Int($0) : nil },
      "appVersion": version.flatMap { $0.isEmpty || $0.count > 64 || $0.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7f } ? nil : $0 },
      "utcOffsetMinutes": TimeZone.current.secondsFromGMT() / 60,
      "daysSinceInstall": daysSinceInstall(dir),
      "firstLaunchMicros": firstLaunchMicros(dir),
      "meteringKey": identity(dir).0,
      "analyticsAnonymousId": identity(dir).1,
      "registrationNonce": registration?.0,
      "registrationCreatedAtMicros": registration?.1,
    ]
  }

  /// Names the installed build, so a template kept by an older one is not reused.
  static func buildStamp() -> String {
    let info = Bundle.main.infoDictionary
    return "\(info?["CFBundleVersion"] ?? ""):\(info?["CFBundleShortVersionString"] ?? "")"
  }

  private static func twoLetter(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespaces), value.count == 2,
      value.allSatisfy({ $0.isASCII && $0.isLetter })
    else { return nil }
    return value
  }

  private static let mountedPrefix = ",\"mountedSince\":["
  private static let mountedMaximum = 32 * 1024

  /// Names the API key a report belongs to: the start of the key's SHA-256.
  static func reportScope(_ authorization: String) -> String {
    let key = authorization.hasPrefix("Bearer ") ? String(authorization.dropFirst("Bearer ".count)) : authorization
    return SHA256.hash(data: Data(key.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
  }

  /// The report text Dart keeps for the early request: empty, or `,"mountedSince":[...]`.
  /// The file holds the key scope on its first line, and a report of another key is not sent.
  static func mountedSince(_ directory: URL, authorization: String) -> String {
    let file = directory.appendingPathComponent("restage_mounted_since")
    guard let text = try? String(contentsOf: file, encoding: .utf8),
      let newline = text.firstIndex(of: "\n")
    else { return "" }
    let scope = String(text[..<newline])
    let fragment = String(text[text.index(after: newline)...])
    guard scope == reportScope(authorization), fragment.hasPrefix(mountedPrefix), fragment.utf8.count <= mountedMaximum
    else { return "" }
    return fragment
  }

  /// Keeps the report text Dart gives for the key [scope]; anything but empty or a report fragment is dropped.
  static func setMountedSince(_ directory: URL, scope: String, fragment: String) -> Bool {
    guard scope.count == 16, scope.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
      fragment.isEmpty || (fragment.hasPrefix(mountedPrefix) && fragment.utf8.count <= mountedMaximum)
    else { return false }
    let file = directory.appendingPathComponent("restage_mounted_since")
    return (try? "\(scope)\n\(fragment)".write(to: file, atomically: true, encoding: .utf8)) != nil
  }

  /// Replaces the stored identity, after the app reset its own. Refuses anything but two UUIDs.
  static func setIdentity(_ directory: URL, metering: String, anonymous: String) -> Bool {
    guard UUID(uuidString: metering) != nil, UUID(uuidString: anonymous) != nil,
      metering.count == 36, anonymous.count == 36
    else { return false }
    let file = directory.appendingPathComponent("restage_install_identity")
    return (try? "\(metering):\(anonymous)".write(to: file, atomically: true, encoding: .utf8)) != nil
  }

  /// The metering key and anonymous id, made once at the first launch and kept in app storage.
  static func identity(_ directory: URL) -> (String, String) {
    let file = directory.appendingPathComponent("restage_install_identity")
    if let text = try? String(contentsOf: file, encoding: .utf8) {
      let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
      if parts.count == 2, parts[0].count == 36, parts[1].count == 36 { return (String(parts[0]), String(parts[1])) }
    }
    let metering = UUID().uuidString.lowercased()
    let anonymous = UUID().uuidString.lowercased()
    try? "\(metering):\(anonymous)".write(to: file, atomically: true, encoding: .utf8)
    return (metering, anonymous)
  }

  /// When the first launch happened, made once and kept in app storage.
  static func firstLaunchMicros(_ directory: URL) -> Int64 {
    let file = directory.appendingPathComponent("restage_first_launch")
    if let text = try? String(contentsOf: file, encoding: .utf8), let value = Int64(text.trimmingCharacters(in: .whitespacesAndNewlines)) { return value }
    let now = Int64(Date().timeIntervalSince1970 * 1_000_000)
    try? String(now).write(to: file, atomically: true, encoding: .utf8)
    return now
  }

  /// Whole elapsed UTC days since the first launch.
  static func daysSinceInstall(_ directory: URL) -> Int64 {
    max(0, (Int64(Date().timeIntervalSince1970 * 1_000_000) - firstLaunchMicros(directory)) / 86_400_000_000)
  }

  /// Starts a new registration identity, after the service refused the old one.
  static func resetRegistration(_ directory: URL) throws -> (String, Int64) {
    let file = directory.appendingPathComponent("restage_install_registration")
    if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    return try registration(directory)
  }

  enum RegistrationError: Error { case unavailable }

  /// The install's registration identity if one was made, without making one.
  static func existingRegistration(_ directory: URL) -> (String, Int64)? {
    let file = directory.appendingPathComponent("restage_install_registration")
    guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
    let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
    guard parts.count == 2, parts[0].count == 43, let created = Int64(parts[1]) else { return nil }
    return (String(parts[0]), created)
  }

  /// The install's registration identity: made once before the first request, kept in app storage.
  static func registration(
    _ directory: URL,
    entropy: (inout [UInt8]) -> Bool = { bytes in
      SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess
    },
    persist: (String, URL) throws -> Void = { text, file in
      try text.write(to: file, atomically: true, encoding: .utf8)
    }
  ) throws -> (String, Int64) {
    let file = directory.appendingPathComponent("restage_install_registration")
    if let existing = existingRegistration(directory) { return existing }
    var bytes = [UInt8](repeating: 0, count: 32)
    guard entropy(&bytes) else { throw RegistrationError.unavailable }
    let nonce = Data(bytes).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    let created = Int64(Date().timeIntervalSince1970 * 1_000_000)
    try persist("\(nonce):\(created)", file)
    return (nonce, created)
  }
}

public final class RestageEarlyPlugin: NSObject, FlutterPlugin {
  private static let queue = DispatchQueue(label: "dev.restage.early.channel")

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "restage/early_request", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(RestageEarlyPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "inFlight":
      let timeout = ((args?["timeoutMs"] as? NSNumber)?.doubleValue ?? 20000) / 1000
      Self.queue.async {
        let flight = RestageEarlyRequest.inFlight(timeout: timeout)
        DispatchQueue.main.async {
          result(flight.map { sent, early in
            var map: [String: Any] = ["sent": FlutterStandardTypedData(bytes: sent)]
            if let early {
              map["status"] = early.status
              map["body"] = FlutterStandardTypedData(bytes: early.body)
              map["headers"] = early.headers
              map["sentAtMicros"] = early.sentAtMicros
              map["answeredAtMicros"] = early.answeredAtMicros
            }
            return map
          })
        }
      }
    case "remember":
      guard let template = args?["template"] as? String else { return result(nil) }
      Self.queue.async {
        RestageEarlyRequest.remember(template)
        DispatchQueue.main.async { result(nil) }
      }
    case "saveChoice":
      let hosted = args?["hosted"] as? Bool ?? true
      let analytics = args?["analytics"] as? Bool
      let measurement = args?["measurement"] as? Bool ?? true
      Self.queue.async {
        RestageEarlyRequest.saveChoice(hosted: hosted, analytics: analytics, measurement: measurement)
        DispatchQueue.main.async { result(nil) }
      }
    case "invalidateStartup":
      Self.queue.async {
        do {
          try RestageEarlyRequest.invalidateStartup()
          DispatchQueue.main.async { result(nil) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "storage", message: "Startup authority could not be cleared.", details: nil))
          }
        }
      }
    case "setIdentity":
      guard let metering = args?["meteringKey"] as? String, let anonymous = args?["analyticsAnonymousId"] as? String
      else { return result(FlutterError(code: "invalid", message: "Both ids are required.", details: nil)) }
      Self.queue.async {
        let stored = EarlyFacts.setIdentity(RestageEarlyRequest.supportDirectory(), metering: metering, anonymous: anonymous)
        DispatchQueue.main.async {
          result(stored ? nil : FlutterError(code: "invalid", message: "Both ids must be UUIDs.", details: nil))
        }
      }
    case "setMountedSince":
      let fragment = (args?["fragment"] as? String) ?? ""
      let scope = (args?["scope"] as? String) ?? ""
      Self.queue.async {
        let stored = EarlyFacts.setMountedSince(RestageEarlyRequest.supportDirectory(), scope: scope, fragment: fragment)
        DispatchQueue.main.async {
          result(stored ? nil : FlutterError(code: "invalid", message: "Not a mounted-surface report.", details: nil))
        }
      }
    case "resetRegistration":
      Self.queue.async {
        do {
          let (nonce, created) = try EarlyFacts.resetRegistration(RestageEarlyRequest.supportDirectory())
          DispatchQueue.main.async { result(["registrationNonce": nonce, "registrationCreatedAtMicros": created]) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "registration_unavailable", message: "Registration could not be stored.", details: nil)) }
        }
      }
    case "registration":
      Self.queue.async {
        do {
          let (nonce, created) = try RestageEarlyRequest.registration()
          DispatchQueue.main.async { result(["registrationNonce": nonce, "registrationCreatedAtMicros": created]) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "registration_unavailable", message: "Registration could not be stored.", details: nil)) }
        }
      }
    case "template":
      result(RestageEarlyRequest.templateText())
    case "sent":
      Self.queue.async {
        let sent = RestageEarlyRequest.sentBytes(timeout: 2)
        DispatchQueue.main.async { result(sent.map { FlutterStandardTypedData(bytes: $0) }) }
      }
    case "facts":
      do { result(try EarlyFacts.read().compactMapValues { $0 }) }
      catch { result(FlutterError(code: "registration_unavailable", message: "Registration could not be stored.", details: nil)) }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
