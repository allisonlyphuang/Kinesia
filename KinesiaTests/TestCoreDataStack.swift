import CoreData
import XCTest
@testable import Kinesia

/// One shared `NSManagedObjectModel` for the whole test target.
///
/// Loading `Kinesia.momd` produces a *new* model object every time, and each one registers its own
/// `NSEntityDescription` for `RawCapture`, `AkinesiaResult`, and every other entity. When Core Data
/// later resolves `RawCapture(context:)` or `RawCapture.fetchRequest()`, it looks through the
/// loaded models for the one matching that Swift class, finds several, and logs:
///
///     CoreData: error: +[RawCapture entity] Failed to find a unique match for an
///     NSEntityDescription to a managed object subclass
///
/// `setUpWithError` runs before *every* test, so four test classes each loading their own copy
/// meant dozens of duplicate models alive at once.
///
/// Sharing the model is safe: it is an immutable description of the schema. Test isolation comes
/// from each test getting its own in-memory **store**, which this still does.
enum TestCoreDataStack {
    /// The app hosts the test bundle (TEST_HOST is set), so `PersistenceController.shared` has
    /// already loaded the model before any test runs. Loading a second copy from the bundle is
    /// what produced:
    ///
    ///     CoreData: warning: Multiple NSEntityDescriptions claim the NSManagedObject subclass
    ///     'TestSession' so +entity is unable to disambiguate.
    ///
    /// Reusing the app's model guarantees exactly one `NSEntityDescription` per class in the
    /// process. Tests still get their own in-memory store, which is where isolation comes from.
    static let model: NSManagedObjectModel = PersistenceController.shared.container.managedObjectModel

    /// A fresh, empty, isolated store that shares the one model.
    static func makeInMemoryContainer() throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "Kinesia", managedObjectModel: model)

        let storeDescription = NSPersistentStoreDescription()
        storeDescription.type = NSInMemoryStoreType
        storeDescription.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [storeDescription]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return container
    }
}
