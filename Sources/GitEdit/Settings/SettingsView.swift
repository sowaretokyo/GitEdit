import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label(L("一般"), systemImage: "gearshape")
                }

            AboutSettingsView()
                .tabItem {
                    Label(L("情報"), systemImage: "info.circle")
                }
        }
        .frame(width: 520, height: 360)
    }
}
