//
//  DatabaseViewerFactory.swift
//  DebugSwift
//
//  Factory for creating database table viewers based on user preference
//

import UIKit

@MainActor
enum DatabaseViewerFactory {

    /// Creates the appropriate table viewer based on the current viewer mode setting
    /// - Parameters:
    ///   - database: The database file to view
    ///   - table: The table to display
    /// - Returns: A view controller for viewing the table contents
    static func makeTableViewer(database: DatabaseFile, table: DatabaseTable) -> UIViewController {
        switch DebugSwift.Database.shared.viewerMode {
        case .classic:
            return DatabaseTableViewController(database: database, table: table)
        case .modern:
            return ModernDatabaseTableViewController(database: database, table: table)
        }
    }

    /// Creates a viewer mode selection alert
    /// - Parameter completion: Called with the selected mode
    /// - Returns: An alert controller for mode selection
    static func makeViewerModeSelector(currentMode: DatabaseViewerMode, completion: @escaping (DatabaseViewerMode) -> Void) -> UIAlertController {
        let alert = UIAlertController(
            title: "Database Viewer Mode",
            message: "Select your preferred viewer interface",
            preferredStyle: .actionSheet
        )

        for mode in DatabaseViewerMode.allCases {
            let title = mode == currentMode ? "✓ \(mode.displayName)" : mode.displayName
            alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                completion(mode)
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        return alert
    }
}
