import XCTest
@testable import GitEdit

/// Each test pairs a realistic chunk of `git` stderr with the kind we expect
/// the classifier to bucket it into. The stderr blobs are quoted verbatim from
/// stock `git` 2.39+ output so the regression coverage matches what users will
/// see in the wild.
final class GitErrorClassifierTests: XCTestCase {

    // MARK: - Push: non-fast-forward & remote rejects

    func test_push_nonFastForward_isClassified() {
        let stderr = """
        To github.com:owner/repo.git
         ! [rejected]        main -> main (non-fast-forward)
        error: failed to push some refs to 'github.com:owner/repo.git'
        hint: Updates were rejected because the tip of your current branch is behind
        hint: its remote counterpart. Integrate the remote changes (e.g.
        hint: 'git pull ...') before pushing again.
        """
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .push)
        XCTAssertEqual(err.kind, .nonFastForward)
        XCTAssertTrue(err.suggestions.contains { $0.action == .pull })
    }

    func test_push_fetchFirstHint_isNonFastForward() {
        let stderr = """
        hint: Updates were rejected because the remote contains work that you do not
        hint: have locally. This is usually caused by another repository pushing to
        hint: the same ref. If you want to integrate the remote changes, use
        hint: 'git pull' before pushing again.
        """
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .push)
        XCTAssertEqual(err.kind, .nonFastForward)
    }

    func test_push_protectedBranch_isClassified() {
        let stderr = """
        remote: error: GH006: Protected branch update failed for refs/heads/main.
        remote: error: Required status check "ci" is expected.
        To github.com:owner/repo.git
         ! [remote rejected] main -> main (protected branch hook declined)
        """
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .push)
        XCTAssertEqual(err.kind, .protectedBranch)
    }

    func test_push_remoteRejected_genericFallback() {
        let stderr = """
        remote: pre-receive hook declined
        To example.com:owner/repo.git
         ! [remote rejected] main -> main (pre-receive hook declined)
        error: failed to push some refs to 'example.com:owner/repo.git'
        """
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .push)
        XCTAssertEqual(err.kind, .remoteRejected)
    }

    func test_push_srcRefspecMissing_isClassified() {
        let stderr = "error: src refspec feature-branch does not match any\nerror: failed to push some refs to 'origin'"
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .push)
        XCTAssertEqual(err.kind, .srcRefspecMissing)
    }

    func test_push_shallowUpdate_isClassified() {
        let stderr = "remote: error: shallow update not allowed"
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .push)
        XCTAssertEqual(err.kind, .shallowUpdate)
    }

    func test_push_noUpstream_isClassified() {
        let stderr = """
        fatal: The current branch feature/x has no upstream branch.
        To push the current branch and set the remote as upstream, use

            git push --set-upstream origin feature/x
        """
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .push)
        XCTAssertEqual(err.kind, .noUpstream)
    }

    // MARK: - Authentication & SSH

    func test_authenticationFailed_isClassified() {
        let stderr = """
        remote: Invalid username or password.
        fatal: Authentication failed for 'https://github.com/owner/repo.git/'
        """
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .push)
        XCTAssertEqual(err.kind, .authFailed)
        XCTAssertTrue(err.suggestions.contains { $0.action == .openAccountSettings })
    }

    func test_passwordAuthRemovedNotice_isClassified() {
        let stderr = """
        remote: Support for password authentication was removed on August 13, 2021.
        remote: Please see https://docs.github.com/.../ for more information.
        fatal: Authentication failed for 'https://github.com/owner/repo.git/'
        """
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .push)
        XCTAssertEqual(err.kind, .authFailed)
    }

    func test_sshPermissionDenied_isAuthFailed() {
        let stderr = """
        git@github.com: Permission denied (publickey).
        fatal: Could not read from remote repository.
        """
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .push)
        XCTAssertEqual(err.kind, .authFailed)
    }

    func test_hostKeyVerification_isClassified() {
        let stderr = """
        Host key verification failed.
        fatal: Could not read from remote repository.
        """
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .fetch)
        XCTAssertEqual(err.kind, .hostKeyVerification)
    }

    // MARK: - Network

    func test_dnsFailure_isNetworkUnreachable() {
        let stderr = """
        fatal: unable to access 'https://github.com/owner/repo.git/': Could not resolve host: github.com
        """
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .fetch)
        XCTAssertEqual(err.kind, .networkUnreachable)
    }

    func test_connectionTimeout_isNetworkUnreachable() {
        let stderr = """
        fatal: unable to access 'https://github.com/owner/repo.git/': Failed to connect to github.com port 443: Operation timed out
        """
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .push)
        XCTAssertEqual(err.kind, .networkUnreachable)
    }

    func test_rpcFailed_isNetworkUnreachable() {
        let stderr = """
        error: RPC failed; HTTP 500 curl 22 The requested URL returned error: 500
        fatal: the remote end hung up unexpectedly
        """
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .push)
        XCTAssertEqual(err.kind, .networkUnreachable)
    }

    // MARK: - Pull / merge

    func test_pullDivergedBranches_isDivergedHistory() {
        let stderr = """
        fatal: Not possible to fast-forward, aborting.
        """
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .pull)
        XCTAssertEqual(err.kind, .divergedHistory)
    }

    func test_mergeConflict_isClassified() {
        let stderr = """
        Auto-merging README.md
        CONFLICT (content): Merge conflict in README.md
        Automatic merge failed; fix conflicts and then commit the result.
        """
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .pull)
        XCTAssertEqual(err.kind, .mergeConflict)
        XCTAssertTrue(err.suggestions.contains { $0.action == .openCommitTab })
    }

    func test_pullDirtyTree_isLocalChangesOverwrite() {
        let stderr = """
        error: Your local changes to the following files would be overwritten by merge:
            src/Main.swift
        Please commit your changes or stash them before you merge.
        Aborting
        """
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .pull)
        XCTAssertEqual(err.kind, .localChangesWouldBeOverwritten)
    }

    func test_pullUnrelatedHistories_isClassified() {
        let stderr = "fatal: refusing to merge unrelated histories"
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .pull)
        XCTAssertEqual(err.kind, .unrelatedHistories)
    }

    // MARK: - Commit

    func test_commitMissingIdentity_isClassified() {
        let stderr = """
        Author identity unknown

        *** Please tell me who you are.

        Run

          git config --global user.email "you@example.com"
          git config --global user.name "Your Name"

        to set your account's default identity.
        """
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .commit)
        XCTAssertEqual(err.kind, .missingIdentity)
    }

    func test_commitNothingToCommit_isClassified() {
        let stderr = "nothing to commit, working tree clean"
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .commit)
        XCTAssertEqual(err.kind, .nothingToCommit)
    }

    // MARK: - Switch / checkout

    func test_switchDirtyTree_isLocalChangesOverwrite() {
        let stderr = """
        error: Your local changes to the following files would be overwritten by checkout:
            src/Main.swift
        Please commit your changes or stash them before you switch branches.
        Aborting
        """
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .switchBranch)
        XCTAssertEqual(err.kind, .localChangesWouldBeOverwritten)
    }

    func test_switchUntrackedConflict_isUntrackedOverwrite() {
        let stderr = """
        error: The following untracked working tree files would be overwritten by checkout:
            generated.txt
        Please move or remove them before you switch branches.
        Aborting
        """
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .switchBranch)
        XCTAssertEqual(err.kind, .untrackedWouldBeOverwritten)
    }

    // MARK: - Branch operations

    func test_createBranchAlreadyExists_isClassified() {
        let stderr = "fatal: A branch named 'feature/login' already exists."
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .createBranch)
        XCTAssertEqual(err.kind, .branchAlreadyExists)
    }

    func test_deleteBranchNotFullyMerged_isClassified() {
        let stderr = """
        error: The branch 'feature/login' is not fully merged.
        If you are sure you want to delete it, run 'git branch -D feature/login'.
        """
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .deleteBranch)
        XCTAssertEqual(err.kind, .branchNotFullyMerged)
    }

    func test_deleteBranchCheckedOut_isClassified() {
        let stderr = "error: Cannot delete branch 'feature/login' checked out at '/Users/test/repo'"
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .deleteBranch)
        XCTAssertEqual(err.kind, .branchCheckedOut)
    }

    // MARK: - Locks / repo state

    func test_lockFile_isClassified() {
        let stderr = """
        fatal: Unable to create '/Users/test/repo/.git/index.lock': File exists.

        Another git process seems to be running in this repository, e.g.
        an editor opened by 'git commit'. Please make sure all processes
        are terminated then try again.
        """
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .stage)
        XCTAssertEqual(err.kind, .lockFileExists)
        XCTAssertTrue(err.suggestions.contains { $0.action == .retry })
    }

    func test_repositoryNotFound_isClassified() {
        let stderr = """
        remote: Repository not found.
        fatal: repository 'https://github.com/owner/missing.git/' not found
        """
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .clone)
        XCTAssertEqual(err.kind, .repositoryUnavailable)
    }

    // MARK: - Fallbacks

    func test_unknownStderr_fallsBackToUnknown() {
        let stderr = "some unrecognized message"
        let err = GitErrorClassifier.classify(stderr: stderr, operation: .push)
        XCTAssertEqual(err.kind, .unknown)
        // Unknown errors still surface a retry suggestion so the user has a
        // path forward.
        XCTAssertTrue(err.suggestions.contains { $0.action == .retry })
    }

    func test_emptyStderr_fallsBackToUnknown() {
        let err = GitErrorClassifier.classify(stderr: "", operation: .push)
        XCTAssertEqual(err.kind, .unknown)
    }

    // MARK: - Operation context

    func test_titleAndOperationLabel_areLocalizedStrings() {
        let err = GitErrorClassifier.classify(stderr: "non-fast-forward", operation: .push)
        XCTAssertFalse(err.title.isEmpty)
        XCTAssertFalse(err.summary.isEmpty)
        XCTAssertFalse(err.operation.label.isEmpty)
    }

    func test_classifyWrapsGitClientError() throws {
        // Simulate the actual GitClient.GitError path so we know the catch
        // branch unwraps stderr the same way the production VM does.
        let underlying = GitClient.GitError.commandFailed(
            status: 1,
            stderr: "fatal: Authentication failed",
            command: ["push", "origin", "main"]
        )
        let err = GitErrorClassifier.classify(underlying, operation: .push)
        XCTAssertEqual(err.kind, .authFailed)
        XCTAssertTrue(err.command.contains("push"))
    }

    func test_classifyPassesThroughAlreadyClassifiedError() {
        let original = GitErrorClassifier.classify(stderr: "non-fast-forward", operation: .push)
        let passed = GitErrorClassifier.classify(original, operation: .pull)
        // Re-classification must not change the kind; the original wins.
        XCTAssertEqual(passed.kind, original.kind)
        XCTAssertEqual(passed.operation, .push)
    }
}
