import SwiftUI

private struct EditorSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
    }
}

extension View {
    /// Standard inset surface for the app's AppKit-backed text inputs.
    func editorSurface() -> some View {
        modifier(EditorSurfaceModifier())
    }
}
