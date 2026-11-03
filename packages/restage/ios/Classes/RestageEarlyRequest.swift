import CryptoKit
import Flutter
import Foundation
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
  private static var target: String?
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

  private static func run() {
    defer {
      signalConfigured()
      lock.lock()
      if !doneSignalled { doneSignalled = true; done.signal() }
      lock.unlock()
    }
    _ = EarlyFacts.registration(supportDirectory())
    // A kept template describes the build that wrote it.
    let kept = (try? Data(contentsOf: lastFile())).flatMap { data in
      ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["builtFor"] as? String == EarlyFacts.buildStamp() ? data : nil
    }
    let data = kept
      ?? Bundle.main.url(forResource: "restage_early", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
    guard let data, let template = EarlyTemplate(data) else { return }
    lock.lock()
    templateJson = String(data: data, encoding: .utf8)
    lock.unlock()
    var facts = EarlyFacts.read()
    facts["mountedSince"] = EarlyFacts.mountedSince(supportDirectory(), authorization: template.authorization)
    guard let body = template.body(facts: facts, full: false) else { return }
    lock.lock()
    sent = body
    target = template.url + "\n" + template.authorization
    lock.unlock()
    signalConfigured()
    sentAtMicros = Int64(Date().timeIntervalSince1970 * 1_000_000)
    var (status, bytes, headers) = post(template, body)
    if status == contractRequired, let full = template.body(facts: facts, full: true) {
      (status, bytes, headers) = post(template, full)
    }
    lock.lock()
    result = Result(status: status, body: bytes, headers: headers, sentAtMicros: sentAtMicros, answeredAtMicros: Int64(Date().timeIntervalSince1970 * 1_000_000))
    lock.unlock()
  }

  private static func signalConfigured() {
    lock.lock()
    if !configuredSignalled { configuredSignalled = true; configured.signal() }
    lock.unlock()
  }

  private static func post(_ template: EarlyTemplate, _ body: Data) -> (Int, Data, [String: String]) {
    guard let url = URL(string: template.url) else { return (0, Data()) }
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

  /// The buffered answer to exactly `request` sent to `url`; once.
  static func take(request: Data, url: String, authorization: String, timeout: TimeInterval) -> Result? {
    lock.lock()
    if taken { lock.unlock(); return nil }
    lock.unlock()
    _ = configured.wait(timeout: .now() + timeout)
    lock.lock()
    guard let early = sent, request == early, target == url + "\n" + authorization else {
      let early = sent
      lock.unlock()
      NSLog("RestageEarly mismatch sent=%@/%d dart=%@/%d differing=%@", digest(early), early?.count ?? 0, digest(request), request.count, differingKeys(early, request))
      return nil
    }
    taken = true
    lock.unlock()
    _ = done.wait(timeout: .now() + timeout)
    lock.lock()
    defer { lock.unlock() }
    return result
  }

  /// The request the platform sent and its answer, whether or not it equals
  /// Dart's: waits for the request to finish, and marks the answer taken.
  static func inFlight(timeout: TimeInterval) -> (Data, Result?)? {
    lock.lock()
    if taken { lock.unlock(); return nil }
    lock.unlock()
    _ = configured.wait(timeout: .now() + timeout)
    lock.lock()
    guard let early = sent else { lock.unlock(); return nil }
    taken = true
    lock.unlock()
    _ = done.wait(timeout: .now() + timeout)
    lock.lock()
    defer { lock.unlock() }
    return (early, result)
  }

  /// The template text in use, for a debug comparison.
  static func templateText() -> String? {
    lock.lock()
    defer { lock.unlock() }
    return templateJson
  }

  /// The request the platform sent, for a debug comparison.
  static func sentBytes() -> Data? {
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

  static func registration() -> (String, Int64) { EarlyFacts.registration(supportDirectory()) }

  // Names of the top-level members that differ, never their values.
  private static func differingKeys(_ sent: Data?, _ request: Data) -> String {
    guard let sent, let a = (try? JSONSerialization.jsonObject(with: sent)) as? [String: Any],
      let b = (try? JSONSerialization.jsonObject(with: request)) as? [String: Any]
    else { return "unreadable" }
    return Set(a.keys).union(b.keys).sorted().filter { "\(a[$0] ?? "")" != "\(b[$0] ?? "")" }.joined(separator: ",")
  }

  private static func digest(_ data: Data?) -> String {
    guard let data else { return "none" }
    return SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
  }
}

/// The startup request as data: canonical body strings with value tokens, plus
/// the facts native fills in.
struct EarlyTemplate {
  let url: String
  let authorization: String
  private let json: [String: Any]
  private let fills: Set<String>

  init?(_ data: Data) {
    guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let url = json["url"] as? String, let authorization = json["authorization"] as? String
    else { return nil }
    self.json = json
    self.url = url
    self.authorization = authorization
    self.fills = Set((json["fills"] as? [String]) ?? [])
  }

  func body(facts: [String: Any?], full: Bool) -> Data? {
    guard var text = json[full ? "fullBody" : "body"] as? String, !text.isEmpty else { return nil }
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
  static func read() -> [String: Any?] {
    let dir = RestageEarlyRequest.supportDirectory()
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
      "registrationNonce": registration(dir).0,
      "registrationCreatedAtMicros": registration(dir).1,
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
  static func resetRegistration(_ directory: URL) -> (String, Int64) {
    try? FileManager.default.removeItem(at: directory.appendingPathComponent("restage_install_registration"))
    return registration(directory)
  }

  /// The install's registration identity: made once before the first request, kept in app storage.
  static func registration(_ directory: URL) -> (String, Int64) {
    let file = directory.appendingPathComponent("restage_install_registration")
    if let text = try? String(contentsOf: file, encoding: .utf8) {
      let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
      if parts.count == 2, parts[0].count == 43, let created = Int64(parts[1]) { return (String(parts[0]), created) }
    }
    var bytes = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    let nonce = Data(bytes).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    let created = Int64(Date().timeIntervalSince1970 * 1_000_000)
    try? "\(nonce):\(created)".write(to: file, atomically: true, encoding: .utf8)
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
    case "take":
      guard let request = (args?["request"] as? FlutterStandardTypedData)?.data,
        let url = args?["url"] as? String, let authorization = args?["authorization"] as? String
      else { return result(nil) }
      let timeout = ((args?["timeoutMs"] as? NSNumber)?.doubleValue ?? 4000) / 1000
      Self.queue.async {
        let early = RestageEarlyRequest.take(request: request, url: url, authorization: authorization, timeout: timeout)
        DispatchQueue.main.async {
          result(early.map { ["status": $0.status, "body": FlutterStandardTypedData(bytes: $0.body), "headers": $0.headers, "sentAtMicros": $0.sentAtMicros, "answeredAtMicros": $0.answeredAtMicros] as [String: Any] })
        }
      }
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
        let (nonce, created) = EarlyFacts.resetRegistration(RestageEarlyRequest.supportDirectory())
        DispatchQueue.main.async { result(["registrationNonce": nonce, "registrationCreatedAtMicros": created]) }
      }
    case "registration":
      Self.queue.async {
        let (nonce, created) = RestageEarlyRequest.registration()
        DispatchQueue.main.async { result(["registrationNonce": nonce, "registrationCreatedAtMicros": created]) }
      }
    case "template":
      result(RestageEarlyRequest.templateText())
    case "sent":
      result(RestageEarlyRequest.sentBytes().map { FlutterStandardTypedData(bytes: $0) })
    case "facts":
      result(EarlyFacts.read().compactMapValues { $0 })
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
