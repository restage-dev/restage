"""Emit a Swift probe containing the unmodified production registration helper."""
from pathlib import Path

source = (Path(__file__).parents[2] / 'ios/Classes/RestageEarlyRequest.swift').read_text()
start = source.index('  enum RegistrationError:')
end = source.index('\n}\n\npublic final class RestageEarlyPlugin', start)
helper = source[start:end]
print('''import Foundation
let kSecRandomDefault = 0
let errSecSuccess: Int32 = 0
var entropyStatus: Int32 = 1
func SecRandomCopyBytes(_ source: Int, _ count: Int, _ bytes: inout [UInt8]) -> Int32 {
  if entropyStatus == 0 { bytes = Array(repeating: 7, count: count) }
  return entropyStatus
}
enum EarlyFacts {
''' + helper + '''
}
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let file = directory.appendingPathComponent("restage_install_registration")
var wrote = false
var acknowledged = false
do {
  _ = try EarlyFacts.registration(directory, persist: { _, _ in wrote = true })
  acknowledged = true
} catch {}
precondition(!acknowledged && !wrote && !FileManager.default.fileExists(atPath: file.path))
print("entropy failure refused before persistence and acknowledgement")
entropyStatus = 0
do {
  _ = try EarlyFacts.registration(directory, persist: { _, _ in throw EarlyFacts.RegistrationError.unavailable })
  acknowledged = true
} catch {}
precondition(!acknowledged && !FileManager.default.fileExists(atPath: file.path))
print("write failure refused before acknowledgement")
let first = try EarlyFacts.registration(directory)
precondition(first.0.count == 43 && first.0 != String(repeating: "A", count: 43))
entropyStatus = 1
let second = try EarlyFacts.registration(directory)
precondition(first == second)
let persisted = try String(contentsOf: file, encoding: .utf8)
precondition(persisted == "\\(first.0):\\(first.1)")
print("success persisted and reused without fresh entropy")
''')
