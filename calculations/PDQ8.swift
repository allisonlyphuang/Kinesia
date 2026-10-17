import Foundation
nonisolated enum PDQ8Item: Int, CaseIterable, Codable, Identifiable {
    case publicMobility = 0
    case dressing
    case depression
    case relationships
    case concentration
    case communication
    case cramps
    case embarrassment

    var id: Int { rawValue }

    var prompt: String {
        switch self {
        case .publicMobility: return "Have you had difficulty getting around in public?"
        case .dressing:       return "Have you had difficulty dressing yourself?"
        case .depression:     return "Have you felt depressed?"
        case .relationships:  return "Have you had problems with your close personal relationships?"
        case .concentration:  return "Have you had problems with your concentration, for example when reading or watching television?"
        case .communication:  return "Have you felt unable to communicate with people properly?"
        case .cramps:         return "Have you had painful muscle cramps or spasms?"
        case .embarrassment:  return "Have you felt embarrassed in public?"
        }
    }

 
    var dimension: String {
        switch self {
        case .publicMobility: return "Mobility"
        case .dressing:       return "Activities of daily living"
        case .depression:     return "Emotional well-being"
        case .relationships:  return "Social support"
        case .concentration:  return "Cognition"
        case .communication:  return "Communication"
        case .cramps:         return "Bodily discomfort"
        case .embarrassment:  return "Stigma"
        }
    }
}


nonisolated enum PDQ8Response: Int, CaseIterable, Codable, Identifiable {
    case never = 0
    case occasionally
    case sometimes
    case often
    case always

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .never:        return "Never"
        case .occasionally: return "Occasionally"
        case .sometimes:    return "Sometimes"
        case .often:        return "Often"
        case .always:       return "Always"
        }
    }
}

nonisolated enum PDQ8Error: Error, Equatable {
    case incompleteResponses(answered: Int, expected: Int)
    case itemScoreOutOfRange(item: Int, score: Int)
}

nonisolated struct PDQ8Score: Equatable {
    // 8 values 0-4
    let itemScores: [Int16]
    // sum of the 8 items, 0-32
    let rawSum: Int
    // rawSum / 32 * 100
    // higher = worse QOL
    let scoreIndex: Double

    static let itemCount = PDQ8Item.allCases.count
    static let maximumItemScore = 4
    static var maximumRawSum: Int { itemCount * maximumItemScore }

    static func compute(from responses: [PDQ8Item: PDQ8Response]) throws -> PDQ8Score {
        let ordered = PDQ8Item.allCases.compactMap { responses[$0] }
        guard ordered.count == itemCount else {
            throw PDQ8Error.incompleteResponses(answered: ordered.count, expected: itemCount)
        }
        return try compute(itemScores: ordered.map { Int16($0.rawValue) })
    }

    static func compute(itemScores: [Int16]) throws -> PDQ8Score {
        guard itemScores.count == itemCount else {
            throw PDQ8Error.incompleteResponses(answered: itemScores.count, expected: itemCount)
        }
        for (index, score) in itemScores.enumerated() {
            guard (0...Int16(maximumItemScore)).contains(score) else {
                throw PDQ8Error.itemScoreOutOfRange(item: index, score: Int(score))
            }
        }

        let rawSum = itemScores.reduce(0) { $0 + Int($1) }
        return PDQ8Score(
            itemScores: itemScores,
            rawSum: rawSum,
            scoreIndex: Double(rawSum) / Double(maximumRawSum) * 100
        )
    }
}
