import ArgumentParser
import Foundation
import Letterpress
import LetterpressMarkdown

// letterpress-md — typeset a markdown file into an informative pdf.
//
//     letterpress-md INPUT.md [-o OUTPUT.pdf] [--page-size a4|letter|a5]
//                    [--typeface sans|serif] [--quiet]
//
// a `-` input reads the markdown from stdin. the summary goes to stdout as
// compact json so the tool composes with other commands.

// MARK: - command

@main
struct LetterpressMD: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "letterpress-md",
		abstract: "Typeset a markdown file into an informative pdf.",
		discussion: """
			Reads markdown from a file, or from stdin when the input is `-`, and
			writes a paginated pdf. Progress is reported on stdout as compact json.
			Content that cannot fit the page box is reported on stderr and exits 1.
			""",
		version: "0.1.0"
	)

	@Argument(help: ArgumentHelp("The markdown file to typeset, or `-` to read from stdin.", valueName: "input"))
	var input: String

	@Option(
		name: [.short, .long],
		help: ArgumentHelp("Write the pdf here.", discussion: "Defaults to the input path with a .pdf suffix.", valueName: "path")
	)
	var output: String?

	// both style flags are optional: the theme owns its own defaults, and a
	// flag replaces one only when it is actually given, so the cli never
	// silently overrides the shipped look.
	@Option(
		name: .customLong("page-size"),
		help: ArgumentHelp("Page size.", discussion: "Defaults to the theme's own.", valueName: "a4|letter|a5")
	)
	var pageSize: PageSizeOption?

	@Option(
		name: .customLong("typeface"),
		help: ArgumentHelp("Body typeface.", valueName: "sans|serif")
	)
	var typeface: TypefaceOption?

	@Flag(inversion: .prefixedNo, help: "Suppress the json summary on stdout.")
	var quiet = false

	// MARK: run

	mutating func run() throws {
		let source = try readSource()

		var style = MarkdownStyle()
		if let pageSize { style.pageSize = pageSize.pageSize }
		if let typeface { style.typeface = typeface.typeface }

		let document = MarkdownDocument(parsing: source)
		let result = document.pagination(style: style)
		let pdf = PDFDocument { result.pages }
		let bytes = pdf.render()
		let destination = resolveDestination()

		do {
			try Data(bytes).write(to: URL(fileURLWithPath: destination))
		} catch {
			throw LetterpressMDError("cannot write '\(destination)'")
		}

		if !quiet {
			let summary = Summary(
				input: input,
				output: destination,
				title: document.title,
				blocks: document.blocks.count,
				pages: pdf.pages.count,
				bytes: bytes.count,
				warnings: result.warnings.count
			)
			let encoder = JSONEncoder()
			encoder.outputFormatting = [.sortedKeys]
			if let data = try? encoder.encode(summary) {
				print(String(decoding: data, as: UTF8.self))
			}
		}

		// the pdf is written either way: the exit code is what says it is wrong.
		if let failure = LetterpressMDError.overflow(result.warnings) {
			throw failure
		}
	}

	// MARK: helpers

	private func readSource() throws -> String {
		guard input == "-" else {
			do {
				return try String(contentsOfFile: input, encoding: .utf8)
			} catch {
				throw LetterpressMDError("cannot read '\(input)'")
			}
		}
		return String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
	}

	private func resolveDestination() -> String {
		if let output { return output }
		guard input != "-" else { return "out.pdf" }
		let url = URL(fileURLWithPath: input)
		let base = url.deletingPathExtension().lastPathComponent
		return url.deletingLastPathComponent().appendingPathComponent("\(base).pdf").path
	}
}

// MARK: - options

/// `--page-size`, mapped onto the exporter's `PageSize`.
enum PageSizeOption: String, CaseIterable, ExpressibleByArgument {
	case a4
	case letter
	case a5

	var pageSize: PageSize {
		switch self {
		case .a4: .a4
		case .letter: .letter
		case .a5: .a5
		}
	}
}

/// `--typeface`, mapped onto the body face of `MarkdownStyle`.
enum TypefaceOption: String, CaseIterable, ExpressibleByArgument {
	case sans
	case serif

	var typeface: MarkdownTypeface {
		switch self {
		case .sans: .sans
		case .serif: .serif
		}
	}
}

// MARK: - errors

/// a runtime failure: reported as `Error: <message>` on stderr, exit code 1.
struct LetterpressMDError: Error, CustomStringConvertible {
	let description: String

	init(_ description: String) {
		self.description = description
	}

	/// the failure a page box the content does not fit deserves — or nothing,
	/// when every mark landed inside its page.
	///
	/// the pdf is still written before this fires: the file is a faithful
	/// rendering of the overflow, and the exit code is what says it is wrong.
	static func overflow(_ warnings: [PaginationWarning]) -> LetterpressMDError? {
		guard !warnings.isEmpty else { return nil }
		let named = warnings.prefix(3).map(\.description).joined(separator: "; ")
		let rest = warnings.count > 3 ? " (+\(warnings.count - 3) more)" : ""
		return LetterpressMDError("content overflows the page box — \(named)\(rest)")
	}
}

// MARK: - summary

/// the compact json line the tool prints before it reports overflow.
struct Summary: Encodable {
	let input: String
	let output: String
	let title: String?
	let blocks: Int
	let pages: Int
	let bytes: Int
	/// how many flow marks ran past the content box; non-zero means exit 1.
	let warnings: Int
}