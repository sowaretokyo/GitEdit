import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: DT.Space.lg) {
            Spacer()

            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.accentColor, .accentColor.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: DT.Space.xs) {
                Text(verbatim: "GitEdit")
                    .font(.title.weight(.bold))
                Text(L("Git をもっとシンプルに、もっと安心に。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Text(L("バージョン %@", appVersion))
                    .font(.caption)
                Text(L("Made with ☕️ in Tokyo"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.4.0"
        return short
    }
}
