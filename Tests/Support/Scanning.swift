// string scanning the suites share, spelled with nothing but the standard
// library.
//
// the pdf grammar the suites grep is ascii and their patterns are often more
// than one character, which is exactly the case the standard library leaves
// open: `range(of:)` and `components(separatedBy:)` are Foundation's, and this
// tree imports no Foundation at all. `firstRange(of:)` and `ranges(of:)` came
// to the standard library and are used directly; the "split on a multi-
// character separator, keeping empty pieces" shape is the one still missing,
// so it lives here.

extension StringProtocol {
	/// the pieces of `self` between occurrences of `separator`, with empty
	/// pieces kept — the shape Foundation's `components(separatedBy:)` returns,
	/// which is what the call sites count and index into.
	///
	/// the standard library's `split(separator:)` takes a single `Character` and
	/// drops empty subsequences, so neither half of this fits.
	public func separated(by separator: String) -> [String] {
		guard !separator.isEmpty else { return [String(self)] }
		var pieces: [String] = []
		var rest = self[...]
		while let found = rest.firstRange(of: separator) {
			pieces.append(String(rest[rest.startIndex ..< found.lowerBound]))
			rest = rest[found.upperBound...]
		}
		pieces.append(String(rest))
		return pieces
	}
}