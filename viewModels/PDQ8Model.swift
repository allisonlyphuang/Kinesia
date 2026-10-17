import Combine
import CoreData
import Foundation

@MainActor
final class PDQ8Model: ObservableObject {

    @Published private(set) var currentIndex = 0
    @Published private(set) var responses: [PDQ8Item: PDQ8Response] = [:]
    @Published private(set) var saveError: Error?
    @Published private(set) var savedScore: PDQ8Score?

    private let context: NSManagedObjectContext
    private let now: () -> Date

    init(context: NSManagedObjectContext, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.now = now
    }

    let items = PDQ8Item.allCases

    var currentItem: PDQ8Item { items[currentIndex] }
    var currentResponse: PDQ8Response? { responses[currentItem] }
    var isLastItem: Bool { currentIndex == items.count - 1 }
    var isComplete: Bool { responses.count == items.count }
    var answeredCount: Int { responses.count }

    func response(for item: PDQ8Item) -> PDQ8Response? {
        responses[item]
    }

    func select(_ response: PDQ8Response) {
        responses[currentItem] = response
    }

    func advance() {
        guard currentIndex < items.count - 1 else { return }
        currentIndex += 1
    }

    func goBack() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }


    @discardableResult
    func submit() -> Bool {
        do {
            let score = try PDQ8Score.compute(from: responses)
            try PDQ8Store.save(score: score, completedAt: now(), in: context)
            savedScore = score
            saveError = nil
            return true
        } catch {
            saveError = error
            savedScore = nil
            return false
        }
    }

    func reset() {
        currentIndex = 0
        responses = [:]
        savedScore = nil
        saveError = nil
    }
}
