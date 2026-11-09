import Foundation

public func fold(_ text: String) -> String {
    text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
}

/// Lower is better: exact, prefix, word prefix / camel initials, substring, then fuzzy.
public struct FieldMatch: Equatable, Sendable {
    public var tier: Int
    public var score: Double

    public init(tier: Int, score: Double) {
        self.tier = tier
        self.score = score
    }
}

/// CamelCase / spaced word initials, e.g. "Host Pane" / "HostPane" → "hp".
public func camelInitials(_ text: String) -> String {
    var initials: [Character] = []
    let scalars = Array(text)
    for (index, character) in scalars.enumerated() {
        guard character.isLetter || character.isNumber else { continue }
        if index == 0 {
            initials.append(Character(character.lowercased()))
            continue
        }
        let previous = scalars[index - 1]
        let boundary = !previous.isLetter && !previous.isNumber
        let camel = character.isUppercase && previous.isLowercase
        if boundary || camel {
            initials.append(Character(character.lowercased()))
        }
    }
    return String(initials)
}

/// Mandarin Latin pinyin (full spelling + initials) for Chinese display names.
public func pinyinVariants(_ text: String) -> [String] {
    guard text.unicodeScalars.contains(where: { $0.value >= 0x4E00 && $0.value <= 0x9FFF }) else {
        return []
    }
    let mutable = NSMutableString(string: text)
    CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
    CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
    let latin = fold(String(mutable))
        .replacingOccurrences(of: "'", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !latin.isEmpty else { return [] }
    let compact = latin.replacingOccurrences(of: " ", with: "")
    let words = latin.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    let initials = words.compactMap(\.first).map(String.init).joined()
    var variants: [String] = []
    for candidate in [latin, compact, initials] where !candidate.isEmpty {
        if !variants.contains(candidate) { variants.append(candidate) }
    }
    return variants
}

public func matchFields(forName name: String, aliases: [String] = []) -> [String] {
    var fields = [name]
    for alias in aliases where !alias.isEmpty {
        if !fields.contains(where: { $0.caseInsensitiveCompare(alias) == .orderedSame }) {
            fields.append(alias)
        }
    }
    for variant in pinyinVariants(name) {
        if !fields.contains(where: { fold($0) == fold(variant) }) {
            fields.append(variant)
        }
    }
    let initials = camelInitials(name)
    if initials.count >= 2, !fields.contains(where: { fold($0) == fold(initials) }) {
        fields.append(initials)
    }
    return fields
}

public func fieldMatch(query: String, target: String) -> FieldMatch? {
    let q = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
    let t = fold(target)
    if q.isEmpty || t.isEmpty { return nil }
    if t == q { return FieldMatch(tier: 0, score: 1) }

    var tier: Int?
    var score = 0.0
    if t.hasPrefix(q) {
        tier = 1
        score = 0.97
    }
    let words = t.split { !$0.isLetter && !$0.isNumber }
    if words.contains(where: { $0.hasPrefix(q) }) {
        if tier == nil { tier = 2 }
        score = max(score, 0.93)
    }
    let initials = camelInitials(target)
    if !initials.isEmpty, fold(initials).hasPrefix(q), q.count >= 2 {
        if tier == nil { tier = 2 }
        score = max(score, 0.91)
    }
    if t.contains(q) {
        if tier == nil { tier = 3 }
        score = max(score, 0.84)
    }

    var index = t.startIndex
    var streak = 0
    var raw = 0.0
    var fuzzy = true
    for character in q {
        guard let found = t[index...].firstIndex(of: character) else {
            fuzzy = false
            break
        }
        let distance = t.distance(from: index, to: found)
        let atBoundary = found == t.startIndex || !t[t.index(before: found)].isLetter
        streak = distance == 0 ? streak + 1 : 1
        raw += 1 + Double(streak) * 0.18 + (atBoundary ? 0.25 : 0) - Double(distance) * 0.03
        index = t.index(after: found)
    }
    if fuzzy {
        let subsequence = min(0.9, raw / (Double(q.count) * 2.1))
        if tier == nil {
            guard subsequence > 0 else { return nil }
            tier = 4
            score = subsequence
        } else {
            score = max(score, subsequence)
        }
    }
    guard let tier, score > 0 else { return nil }
    return FieldMatch(tier: tier, score: score - Double(t.count) * 0.0015)
}

public func bestFieldMatch(query: String, fields: [String]) -> FieldMatch? {
    fields.compactMap { fieldMatch(query: query, target: $0) }.min { lhs, rhs in
        if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
        return lhs.score > rhs.score
    }
}

public func fuzzyScore(query: String, target: String) -> Double? {
    fieldMatch(query: query, target: target)?.score
}

public func bestFuzzyScore(query: String, fields: [String]) -> Double? {
    bestFieldMatch(query: query, fields: fields)?.score
}

/// Continuous frecency used in launcher ranking.
public func selectionFrecency(count: Int, lastSelected: Date, now: Date) -> Double {
    guard count > 0 else { return 0 }
    let age = max(0, now.timeIntervalSince(lastSelected))
    let halfLife: TimeInterval = 14 * 24 * 3600
    let decay = pow(0.5, age / halfLife)
    return Double(count) * decay
}
