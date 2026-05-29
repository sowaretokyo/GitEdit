import SwiftUI

struct CreateBranchSheet: View {
    @ObservedObject var repoVM: RepositoryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var startingPoint: String = ""
    @State private var checkout: Bool = true
    @State private var isCreating: Bool = false

    private var startingOptions: [String] {
        var options: [String] = []
        if let current = repoVM.currentBranchName, !current.isEmpty {
            options.append(current)
        }
        options.append(contentsOf:
            repoVM.localBranches.map(\.name).filter { $0 != repoVM.currentBranchName }
        )
        options.append(contentsOf: repoVM.remoteBranches.map(\.name))
        // de-dup keeping order
        var seen = Set<String>()
        return options.filter { seen.insert($0).inserted }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        !trimmedName.isEmpty && !isCreating
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.lg) {
            VStack(alignment: .leading, spacing: DT.Space.xs) {
                Text(L("新しいブランチ"))
                    .font(.title2.weight(.semibold))
                Text(L("ブランチ名を入力し、起点を選択してください"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: DT.Space.sm) {
                Text(L("ブランチ名"))
                    .font(.callout.weight(.medium))
                TextField(L("例: feature/login"), text: $name)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isCreating)
            }

            VStack(alignment: .leading, spacing: DT.Space.sm) {
                Text(L("起点"))
                    .font(.callout.weight(.medium))
                Picker("", selection: $startingPoint) {
                    ForEach(startingOptions, id: \.self) { opt in
                        Text(opt).tag(opt)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Toggle(isOn: $checkout) {
                Text(L("作成して切替"))
                    .font(.callout)
            }
            .toggleStyle(.checkbox)
            .disabled(isCreating)

            Spacer(minLength: 0)

            HStack {
                if isCreating {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button(L("キャンセル")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isCreating)
                Button {
                    Task { await perform() }
                } label: {
                    Text(L("作成"))
                        .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
            }
        }
        .padding(DT.Space.xl)
        .frame(width: 480)
        .onAppear {
            if startingPoint.isEmpty {
                startingPoint = startingOptions.first ?? ""
            }
        }
    }

    private func perform() async {
        isCreating = true
        defer { isCreating = false }
        await repoVM.createBranch(
            name: trimmedName,
            startingFrom: startingPoint.isEmpty ? nil : startingPoint,
            checkout: checkout
        )
        dismiss()
    }
}
