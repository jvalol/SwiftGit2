//
//  DiffsSpec.swift
//  SwiftGit2
//

import Foundation
import Testing
import SwiftGit2

/// A repository whose second commit adds one file, modifies another, and deletes
/// a third, so that a single diff carries one delta of each kind.
@Suite("Diff.Delta.status") final class DiffDeltaStatusSpec {

    private let directory: URL

    init() throws {
        _ = SwiftGit2Init()
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SwiftGit2DiffsSpec.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        git(["init", "-q", "-b", "main"])
        git(["config", "user.email", "t@e.st"])
        git(["config", "user.name", "Tester"])

        write("keep.txt", "one\n")
        write("gone.txt", "bye\n")
        git(["add", "-A"])
        git(["commit", "-q", "-m", "first"])

        write("keep.txt", "two\n")
        write("fresh.txt", "new\n")
        try FileManager.default.removeItem(at: directory.appendingPathComponent("gone.txt"))
        git(["add", "-A"])
        git(["commit", "-q", "-m", "second"])
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
        _ = SwiftGit2Shutdown()
    }

    @Test("Is modified for a file whose contents changed") func modified() throws {
        #expect(try delta(for: "keep.txt").status == .modified)
    }

    @Test("Is added for a file the commit introduced") func added() throws {
        #expect(try delta(for: "fresh.txt").status == .added)
    }

    @Test("Is deleted for a file the commit removed") func deleted() throws {
        #expect(try delta(for: "gone.txt").status == .deleted)
    }

    // MARK: - Helpers

    /// The HEAD commit's delta for a path.
    private func delta(for path: String) throws -> Diff.Delta {
        let repo = try Repository.at(directory).get()
        let head = try repo.HEAD().get()
        let commit = try repo.commit(head.oid).get()
        let diff = try repo.diff(for: commit).get()
        return try #require(diff.deltas.first { ($0.newFile ?? $0.oldFile)?.path == path })
    }

    private func git(_ arguments: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = arguments
        task.currentDirectoryURL = directory
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
    }

    private func write(_ name: String, _ contents: String) {
        try? Data(contents.utf8).write(to: directory.appendingPathComponent(name))
    }
}
