import SwiftUI

enum PresentedModal: Identifiable {
    case modal(AnyView)
    case fullScreen(AnyView)

    var id: String { "modal" }
    var view: AnyView {
        switch self {
        case .modal(let view): return view
        case .fullScreen(let view): return view
        }
    }

    var isFullScreen: Bool {
        switch self {
        case .modal: return false
        case .fullScreen: return true
        }
    }
}

enum PresentedAlert: Identifiable {
    case message(title: String, message: String, dismiss: () -> Void)

    var id: String { UUID().uuidString }

    @MainActor
    var alert: Alert {
        switch self {
        case let .message(title, message, dismiss):
            return Alert(
                title: Text(title),
                message: Text(message),
                dismissButton: .default(Text("OK"), action: dismiss)
            )
        }
    }
}
