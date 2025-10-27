import SwiftUI

struct CameraPreviewView: UIViewRepresentable {
    let viewModel: CameraViewModel

    func makeUIView(context: Context) -> UIView {
        let view = viewModel.cameraView
        // Force layout on next run loop
        DispatchQueue.main.async {
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        viewModel.updateCameraViewFrame(uiView.bounds)
        if uiView.bounds.width == 0 || uiView.bounds.height == 0 {
            DispatchQueue.main.async {
                viewModel.updateCameraViewFrame(uiView.bounds)
            }
        } else {
            viewModel.updateCameraViewFrame(uiView.bounds)
        }
    }
}

struct CameraView: View {
    @ObservedObject var viewModel: CameraViewModel

    var body: some View {
        VStack(spacing: 0) {

            makeHeaderMenuView()
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.6))

            makeCameraPreview()

            ZStack {
                makeCaptureButtonView()
                    .padding(.bottom, 64)

                HStack {
                    Spacer()
                    makeCameraFlipButton()
                        .padding(.bottom, 64)
                        .padding(.trailing, 32)
                }
            }
            .frame(maxHeight: 200)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.6))
        }
        .background(Color.black)
        .ignoresSafeArea(edges: .all)
    }

    @ViewBuilder
    private func makeCameraPreview() -> some View {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            // Running in Xcode canvas previews → show mock
            Color.red
                .overlay(
                    Text("Camera Preview Area")
                        .font(.headline)
                        .foregroundColor(.white)
                        .opacity(0.6)
                )
                .aspectRatio(3/4, contentMode: .fit)
                .clipped()
        } else {
            // Running normally (simulator or real device) → show real camera
            CameraPreviewView(viewModel: viewModel)
                .aspectRatio(3/4, contentMode: .fit)
                .clipped()
        }
    }

    private func makeHeaderMenuView() -> some View {
        HStack {
            Menu {
                ForEach(CameraCaptureMode.allCases) { mode in
                    Button {
                        viewModel.captureMode = mode
                    } label: {
                        HStack {
                            Image(systemName: mode.iconName)
                            Text(mode.title)
                        }
                    }
                    .tint(viewModel.captureMode == mode ? .yellow : .primary)
                }
            } label: {
                Label(viewModel.captureMode.title, systemImage: viewModel.captureMode.iconName)
                    .labelStyle(.titleAndIcon)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black)
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.top, 16)
        .padding(.horizontal)
    }

    private func makeCameraFlipButton() -> some View {
        CameraFlipButton {
            viewModel.didTapToggleCameraPosition()
        }
        .disabled(viewModel.isReconfiguring)
    }

    private func makeCaptureButtonView() -> some View {
        Button {

        } label: {
            Circle()
                .fill(Color.white)
                .frame(width: 70, height: 70)
                .shadow(radius: 4)
        }
    }
}

#Preview {
    let cameraViewModel = CameraViewModel.mockModel()
    CameraView(viewModel: cameraViewModel)
}

struct CameraFlipButton: View {
    @State private var isAnimating = false
    var action: () -> Void

    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            withAnimation(.easeInOut(duration: 0.25)) {
                isAnimating = true
            }

            // reset the animation after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isAnimating = false
                }
            }

            // perform the actual camera flip
            action()

        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
                .rotationEffect(.degrees(isAnimating ? 180 : 0))
                .scaleEffect(isAnimating ? 1.2 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isAnimating)
        }
    }
}
