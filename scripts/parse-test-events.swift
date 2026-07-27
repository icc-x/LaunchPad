import Foundation
import CoreFoundation

enum ParserError: Error, CustomStringConvertible {
    case invalidArguments
    case invalidEvent(Int)
    case invalidTestID(String)
    case duplicateIdentity(String)
    case identityMismatch(String)
    case emptyStream

    var description: String {
        switch self {
        case .invalidArguments:
            return "usage: event-parser EVENTS EXECUTED VERSION IDENTITY"
        case .invalidEvent(let line):
            return "invalid event schema at line \(line)"
        case .invalidTestID(let id):
            return "invalid test ID: \(id)"
        case .duplicateIdentity(let identity):
            return "duplicate identity: \(identity)"
        case .identityMismatch(let kind):
            return "event identity mismatch: \(kind)"
        case .emptyStream:
            return "event stream is empty"
        }
    }
}

func parseEvents() throws {
    guard CommandLine.arguments.count == 5 else {
        throw ParserError.invalidArguments
    }

    let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let executedURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let versionURL = URL(fileURLWithPath: CommandLine.arguments[3])
    let identityURL = URL(fileURLWithPath: CommandLine.arguments[4])
    let data = try Data(contentsOf: inputURL)
    guard let stream = String(data: data, encoding: .utf8) else {
        throw ParserError.invalidEvent(1)
    }

    let lines = stream.split(whereSeparator: \Character.isNewline)
    guard !lines.isEmpty else {
        throw ParserError.emptyStream
    }

    let sourceSuffix = try NSRegularExpression(
        pattern: "/[^/]+\\.swift:[0-9]+:[0-9]+$"
    )
    var functionRecords = Set<String>()
    var functionStarts = Set<String>()
    var functionEnds = Set<String>()
    var caseRecords = Set<String>()
    var caseStarts = Set<String>()
    var caseEnds = Set<String>()

    func insertUnique(_ identity: String, into set: inout Set<String>) throws {
        guard set.insert(identity).inserted else {
            throw ParserError.duplicateIdentity(identity)
        }
    }

    func caseIdentity(testID: String, payload: [String: Any]) throws -> String {
        guard let testCase = payload["_testCase"] as? [String: Any],
              let caseID = testCase["id"] as? String,
              !caseID.isEmpty else {
            throw ParserError.invalidTestID(testID)
        }
        return "\(testID)\t\(caseID)"
    }

    func requiredTestID(payload: [String: Any], line: Int) throws -> String {
        guard let testID = payload["testID"] as? String,
              !testID.isEmpty,
              testID.contains("/") else {
            throw ParserError.invalidEvent(line)
        }
        return testID
    }

    /// Returns function lifecycle IDs while excluding non-empty suite lifecycle IDs.
    func functionTestID(payload: [String: Any], line: Int) throws -> String? {
        guard let testID = payload["testID"] as? String, !testID.isEmpty else {
            throw ParserError.invalidEvent(line)
        }
        guard testID.contains("/") else {
            return nil
        }
        return testID
    }

    for (index, line) in lines.enumerated() {
        let object = try JSONSerialization.jsonObject(with: Data(line.utf8))
        guard let event = object as? [String: Any],
              let kind = event["kind"] as? String,
              let payload = event["payload"] as? [String: Any],
              let versionValue = event["version"],
              CFGetTypeID(versionValue as CFTypeRef) == CFNumberGetTypeID(),
              let version = versionValue as? NSNumber,
              !CFNumberIsFloatType(version),
              version.int64Value == 0 else {
            throw ParserError.invalidEvent(index + 1)
        }

        if kind == "test" {
            guard let recordKind = payload["kind"] as? String else {
                throw ParserError.invalidEvent(index + 1)
            }
            guard recordKind == "function" else {
                continue
            }
            guard let testID = payload["id"] as? String,
                  !testID.isEmpty,
                  testID.contains("/") else {
                throw ParserError.invalidEvent(index + 1)
            }
            try insertUnique(testID, into: &functionRecords)
            if payload.keys.contains("_testCases") {
                guard let testCases = payload["_testCases"] as? [[String: Any]] else {
                    throw ParserError.invalidEvent(index + 1)
                }
                for testCase in testCases {
                    guard let caseID = testCase["id"] as? String, !caseID.isEmpty else {
                        throw ParserError.invalidEvent(index + 1)
                    }
                    try insertUnique("\(testID)\t\(caseID)", into: &caseRecords)
                }
            }
            continue
        }

        guard kind == "event", let eventKind = payload["kind"] as? String else {
            throw ParserError.invalidEvent(index + 1)
        }

        switch eventKind {
        case "testStarted":
            if let testID = try functionTestID(payload: payload, line: index + 1) {
                try insertUnique(testID, into: &functionStarts)
            }
        case "testEnded":
            guard let testID = try functionTestID(payload: payload, line: index + 1) else {
                continue
            }
            guard let messages = payload["messages"] as? [[String: Any]],
                  messages.contains(where: { $0["symbol"] as? String == "pass" }) else {
                continue
            }
            try insertUnique(testID, into: &functionEnds)
        case "testCaseStarted":
            let testID = try requiredTestID(payload: payload, line: index + 1)
            try insertUnique(
                try caseIdentity(testID: testID, payload: payload),
                into: &caseStarts
            )
        case "testCaseEnded":
            let testID = try requiredTestID(payload: payload, line: index + 1)
            try insertUnique(
                try caseIdentity(testID: testID, payload: payload),
                into: &caseEnds
            )
        default:
            continue
        }
    }

    guard !functionRecords.isEmpty else {
        throw ParserError.emptyStream
    }
    guard !caseRecords.isEmpty else {
        throw ParserError.identityMismatch("parameter case records are empty")
    }
    guard functionRecords == functionStarts else {
        throw ParserError.identityMismatch("function records vs starts")
    }
    guard functionRecords == functionEnds else {
        throw ParserError.identityMismatch("function records vs passed ends")
    }
    guard caseRecords == caseStarts else {
        throw ParserError.identityMismatch("case records vs starts")
    }
    guard caseRecords == caseEnds else {
        throw ParserError.identityMismatch("case records vs ends")
    }

    var executed = Set<String>()
    for testID in functionRecords {
        let range = NSRange(testID.startIndex..<testID.endIndex, in: testID)
        guard let match = sourceSuffix.firstMatch(in: testID, range: range),
              match.range.location + match.range.length == range.length else {
            throw ParserError.invalidTestID(testID)
        }
        let canonicalID = (testID as NSString).replacingCharacters(
            in: match.range,
            with: ""
        )
        guard executed.insert(canonicalID).inserted else {
            throw ParserError.duplicateIdentity(canonicalID)
        }
    }

    let sortedFunctionRecords = functionRecords.sorted()
    let sortedFunctionStarts = functionStarts.sorted()
    let sortedFunctionEnds = functionEnds.sorted()
    let sortedCaseRecords = caseRecords.sorted()
    let sortedCaseStarts = caseStarts.sorted()
    let sortedCaseEnds = caseEnds.sorted()
    let identity: [String: Any] = [
        "version": 0,
        "functionRecords": sortedFunctionRecords,
        "functionStarts": sortedFunctionStarts,
        "functionPassedEnds": sortedFunctionEnds,
        "caseRecords": sortedCaseRecords,
        "caseStarts": sortedCaseStarts,
        "caseEnds": sortedCaseEnds,
    ]
    let identityData = try JSONSerialization.data(
        withJSONObject: identity,
        options: [.prettyPrinted, .sortedKeys]
    )
    try identityData.write(to: identityURL, options: .atomic)

    let executedOutput = executed.sorted().joined(separator: "\n") + "\n"
    try Data(executedOutput.utf8).write(to: executedURL, options: .atomic)
    try Data("0\n".utf8).write(to: versionURL, options: .atomic)
}

do {
    try parseEvents()
} catch {
    FileHandle.standardError.write(Data("event parser: \(error)\n".utf8))
    exit(1)
}
