//
//  Stash.swift
//  SwiftGit2
//

import Foundation
import Clibgit2

/// A single entry in a repository's stash list.
public struct Stash {
	/// The entry's position in the stash list, 0 being the most recent.
	///
	/// Positional rather than stable. libgit2 renumbers the list whenever an
	/// entry is added or removed, so an index held across such a change
	/// addresses a different stash than the one it was read from.
	public let index: Int

	/// The message the state was stashed with.
	public let message: String

	/// The commit holding the stashed state.
	public let oid: OID

	public init(index: Int, message: String, oid: OID) {
		self.index = index
		self.message = message
		self.oid = oid
	}
}

/// Helper used as the libgit2 callback in `git_stash_foreach`.
/// This is a function with a type signature of `git_stash_cb`.
private func stashCallback(index: Int, message: UnsafePointer<CChar>?,
                           stashID: UnsafePointer<git_oid>?,
                           payload: UnsafeMutableRawPointer?) -> Int32 {
	guard let payload = payload, let stashID = stashID else {
		return 0
	}

	let entries = payload.assumingMemoryBound(to: [Stash].self)
	entries.pointee.append(Stash(index: index,
	                             message: message.map(String.init(cString:)) ?? "",
	                             oid: OID(stashID.pointee)))
	return 0
}

public extension Repository {

	// MARK: - Stashes

	/// Lists the repository's stash entries, most recent first.
	///
	/// A repository with nothing stashed succeeds with an empty array. The list
	/// lives in the reflog of `refs/stash`, which is why reading `refs/stash`
	/// directly would only ever find the newest entry.
	func stashes() -> Result<[Stash], NSError> {
		var entries = [Stash]()

		let result = withUnsafeMutablePointer(to: &entries) { pointer in
			git_stash_foreach(self.pointer, stashCallback, pointer)
		}

		guard result == GIT_OK.rawValue else {
			return .failure(NSError(gitError: result, pointOfFailure: "git_stash_foreach"))
		}

		return .success(entries)
	}
}
