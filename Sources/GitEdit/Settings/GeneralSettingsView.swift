import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(AppLanguage.storageKey) private var appLanguage: String = AppLanguage.system.rawValue

    var body: some View {
        Form {
            Section {
                Picker(selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang.rawValue)
                    }
                } label: {
                    Text(L("言語"))
                }
                .pickerStyle(.menu)
            } header: {
                Text(L("表示"))
            } footer: {
                Text(L("選択した言語は即座に反映されます。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
