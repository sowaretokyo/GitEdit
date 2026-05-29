import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(AppLanguage.storageKey) private var appLanguage: String = AppLanguage.system.rawValue
    @AppStorage(AppAppearance.storageKey) private var appAppearance: String = AppAppearance.system.rawValue

    var body: some View {
        Form {
            Section {
                appearancePicker
            } header: {
                Text(L("外観"))
            } footer: {
                Text(L("ウィンドウとサイドバーの配色を切り替えます。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

    private var appearancePicker: some View {
        HStack(spacing: DT.Space.md) {
            Text(L("テーマ"))
            Spacer()
            Picker("", selection: $appAppearance) {
                ForEach(AppAppearance.allCases) { appearance in
                    Label(appearance.displayName, systemImage: appearance.iconSystemName)
                        .labelStyle(.titleAndIcon)
                        .tag(appearance.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)
        }
    }
}
