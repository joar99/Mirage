import SwiftUI

@main
struct MirageApp: App {
    @StateObject private var appCoordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView(appCoordinator: appCoordinator)
        }
    }
}
