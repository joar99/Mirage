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

            VStack {
                makeCaptureButtonView()
                    .padding(.bottom, 64)
            }
            .frame(maxHeight: 200)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.6))
        }
        .background(Color.black)
        .onAppear {
            viewModel.startSession()
        }
        .onDisappear {
            viewModel.stopSession()
        }
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
