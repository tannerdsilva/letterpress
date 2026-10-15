import ArgumentParser
import Letterpress
import LetterpressMarkdown
import SystemPackage

// letterpress-md — typeset a markdown file into an informative pdf.
//
//     letterpress-md INPUT.md [-o OUTPUT.pdf] [--page-size a4|letter|a5]
//                    [--typeface sans|serif] [--quiet]
//
// a `-` input reads the markdown from stdin. the summary goes to stdout as
// compact json so the tool composes with other commands.
//
// the cli is the one place in the package that touches the filesystem, and it
// does so through `SystemPackage` rather than Foundation: the exporter hands
// back `[UInt8]` and the markdown layer composes marks, so the bytes meet a
// file descriptor exactly once — here.

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
			try write(bytes, to: destination)
		} catch {
			throw LetterpressMDError("cannot write '\(destination)'")
		}

		if !quiet {
			print(
				Summary(
					input: input,
					output: destination,
					title: document.title,
					blocks: document.blocks.count,
					pages: pdf.pages.count,
					bytes: bytes.count,
					warnings: result.warnings.count
				).json
			)
		}

		// the pdf is written either way: the exit code is what says it is wrong.
		if let failure = LetterpressMDError.overflow(result.warnings) {
			throw failure
		}
	}

	// MARK: helpers

	/// the markdown source: from the file named by `input`, or from stdin when
	/// `input` is `-`.
	private func readSource() throws -> String {
		guard input != "-" else {
			return String(decoding: try read(toEnd: .standardInput), as: UTF8.self)
		}
		guard let bytes = try? read(toEnd: FilePath(input)) else {
			throw LetterpressMDError("cannot read '\(input)'")
		}
		return String(decoding: bytes, as: UTF8.self)
	}

	/// every byte of `path`.
	private func read(toEnd path: FilePath) throws -> [UInt8] {
		let file = try FileDescriptor.open(path, .readOnly)
		defer { try? file.close() }
		return try read(toEnd: file)
	}

	/// drain `file` to end of file.
	private func read(toEnd file: FileDescriptor) throws -> [UInt8] {
		var bytes: [UInt8] = []
		var buffer = [UInt8](repeating: 0, count: 32 * 1024)
		while true {
			let count = try buffer.withUnsafeMutableBytes { try file.read(into: $0) }
			if count == 0 { return bytes }
			bytes.append(contentsOf: buffer[0 ..< count])
		}
	}

	/// write `bytes` to `path`, creating or replacing it.
	private func write(_ bytes: [UInt8], to path: String) throws {
		let file = try FileDescriptor.open(
			FilePath(path), .writeOnly, options: [.create, .truncate], permissions: .ownerReadWrite)
		defer { try? file.close() }
		try file.writeAll(bytes)
	}

	/// where the pdf goes: `--output`, else the input path with a `.pdf`
	/// suffix, else `out.pdf` for a stdin run.
	private func resolveDestination() -> String {
		if let output { return output }
		guard input != "-" else { return "out.pdf" }
		let path = FilePath(input)
		return path.removingLastComponent().appending("\(path.stem ?? "out").pdf").description
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
struct Summary {
	let input: String
	let output: String
	let title: String?
	let blocks: Int
	let pages: Int
	let bytes: Int
	/// how many flow marks ran past the content box; non-zero means exit 1.
	let warnings: Int

	/// the summary as one line of json, keys in alphabetical order.
	///
	/// written by hand rather than through `JSONEncoder`, which lives in
	/// Foundation; the field set is fixed and small, so the writer is a dozen
	/// lines instead of a codec.
	var json: String {
		var fields: [String] = []
		fields.append("\"blocks\":\(blocks)")
		fields.append("\"bytes\":\(bytes)")
		fields.append("\"input\":\(JSONText.string(input))")
		fields.append("\"output\":\(JSONText.string(output))")
		fields.append("\"pages\":\(pages)")
		fields.append("\"title\":\(title.map(JSONText.string) ?? "null")")
		fields.append("\"warnings\":\(warnings)")
		return "{\(fields.joined(separator: ","))}"
	}
}

/// the slice of the json grammar a summary line needs.
enum JSONText {
	/// `value` as a json string literal, with the escapes the grammar requires.
	static func string(_ value: String) -> String {
		var out = "\""
		for scalar in value.unicodeScalars {
			switch scalar {
			case "\"": out += "\\\""
			case "\\": out += "\\\\"
			case "\n": out += "\\n"
			case "\r": out += "\\r"
			case "\t": out += "\\t"
			default:
				if scalar.value < 0x20 {
					out += "\\u" + pad(String(scalar.value, radix: 16))
				} else {
					out.unicodeScalars.append(scalar)
				}
			}
		}
		return out + "\""
	}

	/// a `\u` escape body, left-padded to the four hex digits json requires.
	private static func pad(_ digits: String) -> String {
		String(repeating: "0", count: max(0, 4 - digits.count)) + digits
	}
}