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

/// What happened when a stash was dropped.
public enum StashDropOutcome {
	/// The entry is off the list. The commit it named is still in the object
	/// database as an unreachable object, and `git stash store <oid>` puts it back,
	/// until git prunes it.
	case dropped

	/// No stash at that position. The list is shorter than the caller thought.
	case notFound
}

/// What happened when a stash was applied.
///
/// A conflict is an outcome rather than a failure: it is the expected answer
/// when the working tree has changes of its own, and the caller has to report it
/// either way.
public enum StashApplyOutcome {
	/// The stashed state is in the working tree. For a pop, the entry is gone.
	case applied

	/// Local changes conflicted. libgit2 leaves the index and every tracked file
	/// unmodified, and for a pop the entry stays in the list.
	///
	/// A stash carrying untracked or ignored files is the exception libgit2
	/// documents: those files can be left behind in the working directory even
	/// though the tracked half was abandoned.
	case conflicted

	/// No stash at that position. The list is shorter than the caller thought.
	case notFound
}

public extension Repository {

	/// Applies a stash, leaving it in the list.
	///
	/// `index` is positional and libgit2 renumbers the list on every add and
	/// remove, so it must come from a read taken now rather than one held from
	/// earlier. See `Stash.index`.
	func applyStash(at index: Int) -> Result<StashApplyOutcome, NSError> {
		return withApplyOptions("git_stash_apply") { options in
			git_stash_apply(self.pointer, index, &options)
		}
	}

	/// Applies a stash and removes it from the list, but only if applying worked.
	///
	/// The same warning about `index` applies, and more sharply: this one destroys
	/// the entry it acts on.
	func popStash(at index: Int) -> Result<StashApplyOutcome, NSError> {
		return withApplyOptions("git_stash_pop") { options in
			git_stash_pop(self.pointer, index, &options)
		}
	}

	/// GIT_STASH_APPLY_OPTIONS_INIT is a C macro and unavailable in Swift, so the
	/// options are initialised the way the status options already are.
	private func withApplyOptions(
		_ pointOfFailure: String,
		_ body: (inout git_stash_apply_options) -> Int32
	) -> Result<StashApplyOutcome, NSError> {
		var options = git_stash_apply_options()
		let initResult = git_stash_apply_options_init(&options,
		                                              UInt32(GIT_STASH_APPLY_OPTIONS_VERSION))
		guard initResult == GIT_OK.rawValue else {
			return .failure(NSError(gitError: initResult,
			                        pointOfFailure: "git_stash_apply_options_init"))
		}

		let result = body(&options)

		switch result {
		case GIT_OK.rawValue:
			return .success(.applied)
		// libgit2 documents GIT_EMERGECONFLICT here, and the checkout underneath can
		// report GIT_ECONFLICT for the same situation. Both mean nothing was applied.
		case GIT_EMERGECONFLICT.rawValue, GIT_ECONFLICT.rawValue:
			return .success(.conflicted)
		case GIT_ENOTFOUND.rawValue:
			return .success(.notFound)
		default:
			return .failure(NSError(gitError: result, pointOfFailure: pointOfFailure))
		}
	}

	/// Removes a stash from the list without applying it.
	///
	/// The same warning about `index` applies as for apply and pop: it is
	/// positional, so it must come from a read taken now.
	///
	/// This does not destroy the stashed work. It removes the entry from the reflog
	/// of `refs/stash`, leaving the commit unreachable but present, so a caller that
	/// kept the object id can restore it with `git stash store`.
	func dropStash(at index: Int) -> Result<StashDropOutcome, NSError> {
		let result = git_stash_drop(self.pointer, index)

		switch result {
		case GIT_OK.rawValue:
			return .success(.dropped)
		case GIT_ENOTFOUND.rawValue:
			return .success(.notFound)
		default:
			return .failure(NSError(gitError: result, pointOfFailure: "git_stash_drop"))
		}
	}
}
