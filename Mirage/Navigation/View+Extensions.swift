import SwiftUI

extension View {
    /// Applies either `.sheet` or `.fullScreenCover` depending on the type of `PresentedModal`.
    ///
    /// - Keeps view code clean by centralizing conditional logic for modal vs full-screen.
    /// - Requires that `.modal` and `.fullScreen` cases are declared in the `PresentedModal` enum.
    ///
    /// Example usage:
    /// ```swift
    /// .applyModal(presentedModal: $coordinator.presentedModal)
    /// ```
    func applyModal(presentedModal: Binding<PresentedModal?>) -> some View {
        let modal = Binding<PresentedModal?>(
            get: { presentedModal.wrappedValue?.isFullScreen == false ? presentedModal.wrappedValue : nil },
            set: { newValue in
                presentedModal.wrappedValue = newValue
            }
        )

        let fullScreen = Binding<PresentedModal?>(
            get: { presentedModal.wrappedValue?.isFullScreen == true ? presentedModal.wrappedValue : nil },
            set: { newValue in
                presentedModal.wrappedValue = newValue
            }
        )

        return self
            .sheet(item: modal) { item in
                NavigationStack {
                    item.view
                }
            }
            .fullScreenCover(item: fullScreen) { item in
                NavigationStack {
                    item.view
                }
            }
    }
}

extension View {
    /// Applies a single `.alert(item:)` using a `PresentedAlert` enum with a computed `.alert` property.
    ///
    /// Keeps presentation logic clean and reusable across views.
    func applyAlert(presentedAlert: Binding<PresentedAlert?>) -> some View {
        self.alert(item: presentedAlert) { $0.alert }
    }
}
