import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label(L("一般"), systemImage: "gearshape")
                }

            AccountsSettingsView()
                .tabItem {
                    Label(L("アカウント"), systemImage: "person.crop.circle")
                }

            AboutSettingsView()
                .tabItem {
                    Label(L("情報"), systemImage: "info.circle")
                }
        }
        .frame(width: 540, height: 380)
    }
}
