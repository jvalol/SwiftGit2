//
//  BranchSwitch.swift
//  SwiftGit2
//

import Foundation
import Clibgit2

/// What happened when a branch switch was attempted.
public enum BranchSwitchOutcome {
	/// HEAD is on the branch and the working tree matches it.
	case switched

	/// Uncommitted changes would have been overwritten, so nothing happened.
	/// HEAD is where it was and the working tree is untouched.
	case blocked
}

public extension Repository {

	/// Switches to a branch, the way `git switch` does.
	///
	/// Uses the safe strategy, so uncommitted changes that do not collide with the
	/// files being written are carried across, and a switch that would overwrite
	/// them is refused before anything is written.
	///
	/// The working tree is written first and HEAD moves second, which is the order
	/// git uses and the reason this exists. `checkout(_ reference:strategy:)` does
	/// the opposite:
	///
	///     setHEAD(reference).flatMap { self.checkout(strategy: strategy) }
	///
	/// `git_checkout_head` takes its baseline from HEAD when none is given, so
	/// moving HEAD first makes the baseline equal the target. The diff between them
	/// is empty, nothing is written, and the call reports success. That leaves HEAD
	/// on the new branch with the old branch's content on disk and no error to say
	/// so. Checking out the tree first compares against the branch being left, so
	/// there is something to write, and a refusal happens before HEAD has moved.
	func switchTo(branch: Branch) -> Result<BranchSwitchOutcome, NSError> {
		var options = git_checkout_options()
		let initResult = git_checkout_options_init(&options, UInt32(GIT_CHECKOUT_OPTIONS_VERSION))
		guard initResult == GIT_OK.rawValue else {
			return .failure(NSError(gitError: initResult,
			                        pointOfFailure: "git_checkout_options_init"))
		}
		options.checkout_strategy = CheckoutStrategy.safe.gitCheckoutStrategy.rawValue

		var oid = branch.oid.oid
		var target: OpaquePointer? = nil
		let lookup = git_object_lookup(&target, self.pointer, &oid, GIT_OBJECT_COMMIT)
		guard lookup == GIT_OK.rawValue else {
			return .failure(NSError(gitError: lookup, pointOfFailure: "git_object_lookup"))
		}
		defer { git_object_free(target) }

		let result = git_checkout_tree(self.pointer, target, &options)

		// The checkout refused rather than broke. libgit2 reports the conflict two
		// ways depending on how far it got. HEAD has not moved either way.
		if result == GIT_ECONFLICT.rawValue || result == GIT_EMERGECONFLICT.rawValue {
			return .success(.blocked)
		}
		guard result == GIT_OK.rawValue else {
			return .failure(NSError(gitError: result, pointOfFailure: "git_checkout_tree"))
		}

		if case .failure(let error) = setHEAD(branch) {
			return .failure(error)
		}
		return .success(.switched)
	}
}
