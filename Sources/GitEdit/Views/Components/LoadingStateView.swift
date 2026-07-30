import SwiftUI

/// Full-area loading state for list and detail content.
struct LoadingStateView: View {
    var background: Color = .clear

    var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background)
    }
}
