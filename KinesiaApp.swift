//
//  KinesiaApp.swift
//  Kinesia
//
//  Created by Amanda Hon on 6/29/26.
//

import SwiftUI
import CoreData

@main
struct KinesiaApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
