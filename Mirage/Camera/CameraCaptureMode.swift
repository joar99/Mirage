
/// Defines the different modes of camera capture.
enum CameraCaptureMode: String, CaseIterable, Identifiable, Equatable, Sendable {
    case normal
    case portrait

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .normal:
            return "Normal"
        case .portrait:
            return "Portrait"
        }
    }

    /// An appropriate SF Symbol.
    var iconName: String {
        switch self {
        case .normal:
            return "camera"
        case .portrait:
            return "person.crop.rectangle"
        }
    }
}
