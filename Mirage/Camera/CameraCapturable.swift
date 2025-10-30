import AVFoundation

/// Defines the types of objects that may be "captured" and focused by the camera
enum CameraCapturable {
    case person(depthData: AVDepthData, personMask: CVPixelBuffer)
    case inanimateObject(depthData: AVDepthData)
}
