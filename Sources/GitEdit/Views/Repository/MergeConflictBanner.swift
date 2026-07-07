import SwiftUI

/// Banner shown atop the Changes detail pane while a merge is in progress —
/// whether started from GitEdit's branch picker or an external terminal.
struct MergeConflictBanner: View {
    @ObservedObject var repoVM: RepositoryViewModel
    @ObservedObject var viewModel: ChangesViewModel
    @State private var showingAbortConfirm = false

    private var conflictCount: Int { viewModel.conflictedFiles.count }

    private var mergingTitle: String {
        if let name = repoVM.mergingBranchName {
            return L("「%@」をマージ中", name)
        }
        return L("マージ競合の解決")
    }

    private var statusText: String {
        if conflictCount > 0 {
            return L("%d 件のファイルが競合しています", conflictCount)
        }
        return L("すべての競合が解決されました。マージを続行できます。")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            HStack(alignment: .top, spacing: DT.Space.sm) {
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .imageScale(.medium)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mergingTitle)
                        .font(.callout.weight(.semibold))
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: DT.Space.sm) {
                Button {
                    Task { await repoVM.continueMerge() }
                } label: {
                    Text(L("マージを続行"))
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(conflictCount > 0)

                Button(role: .destructive) {
                    showingAbortConfirm = true
                } label: {
                    Text(L("マージを中止"))
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer(minLength: 0)
            }
        }
        .padding(DT.Space.md)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                .fill(Color(nsColor: .systemOrange).opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                        .strokeBorder(Color(nsColor: .systemOrange).opacity(0.4), lineWidth: 0.5)
                )
        )
        .padding([.horizontal, .top], DT.Space.md)
        .confirmationDialog(
            L("マージを中止しますか？"),
            isPresented: $showingAbortConfirm
        ) {
            Button(L("マージを中止"), role: .destructive) {
                Task { await repoVM.abortMerge() }
            }
            Button(L("キャンセル"), role: .cancel) {}
        } message: {
            Text(L("マージ前の状態に戻ります。競合の解決内容は失われます。"))
        }
    }
}

/// Inline action bar shown above the diff/editor when the selected file is
/// still an unresolved merge conflict.
struct ConflictResolutionBar: View {
    let change: FileChange
    @ObservedObject var viewModel: ChangesViewModel

    var body: some View {
        HStack(spacing: DT.Space.sm) {
            Label(L("競合"), systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(nsColor: .systemOrange))

            Spacer(minLength: DT.Space.sm)

            Button {
                Task { await viewModel.resolveUsingOurs(change) }
            } label: {
                Text(L("自分の変更を採用"))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                Task { await viewModel.resolveUsingTheirs(change) }
            } label: {
                Text(L("相手の変更を採用"))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if viewModel.selectedFileIsEditable {
                Button {
                    Task { await viewModel.setEditorViewMode(.edit) }
                } label: {
                    Text(L("エディタで編集"))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                Task { await viewModel.markResolved(change) }
            } label: {
                Text(L("解決済みにする"))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, DT.Space.md)
        .padding(.vertical, DT.Space.sm)
        .background(Color(nsColor: .systemOrange).opacity(0.08))
    }
}
