import AVFoundation

enum CameraPosition: String, CaseIterable, Identifiable, Sendable {
    case front
    case back

    var id: String {
        rawValue
    }

    var avPosition: AVCaptureDevice.Position {
        switch self {
        case .front:
            return .front
        case .back:
            return .back
        }
    }

    var iconName: String {
        switch self {
        case .front:
            return "camera.rotate"
        case .back:
            return "camera.rotate.fill"
        }
    }
}
