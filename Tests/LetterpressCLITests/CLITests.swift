import Testing
import LetterpressTestSupport
import SystemPackage

// drives the built `letterpress-md` binary as a subprocess, so the checks cover
// the things a library test cannot: argument parsing, exit codes, and the
// stdout/stderr contract.
//
// this suite also owns the disk round trip the library no longer does: the
// exporter hands back bytes, so "did those bytes reach a file" is only
// answerable by running the program that writes them.

@Suite("letterpress-md cli")
struct LetterpressCLITests {
	/// the built binary, resolved from this file so the suite is cwd-independent.
	static let binaryPath: String = FilePath(#filePath)
		.removingLastComponent()   // CLITests.swift
		.removingLastComponent()   // LetterpressCLITests
		.removingLastComponent()   // Tests
		.appending(".build/debug/letterpress-md")
		.description

	// MARK: harness

	private struct CLIError: Error, CustomStringConvertible {
		let description: String
		init(_ description: String) { self.description = description }
	}

	private func run(_ arguments: [String], stdin: String? = nil) throws -> ChildResult {
		guard Spawn.isExecutable(Self.binaryPath) else {
			throw CLIError("no binary at \(Self.binaryPath) — run `swift build` first")
		}
		return try Spawn.run([Self.binaryPath] + arguments, stdin: stdin)
	}

	/// a markdown source in the scratch directory, plus a factory for the pdf
	/// paths a test wants the cli to write. both are torn down afterwards.
	///
	/// the source carries a unique basename, which is what lets the
	/// default-destination test prove the cli derived the output from the input
	/// path without the suite having to invent a directory for it.
	private func withScratch(
		markdown: String,
		_ body: (String, (String) -> String) throws -> Void
	) throws {
		let label = "cli-\(Int.random(in: 0 ..< 1_000_000_000))"
		let source = Scratch.path(label, ext: "md")
		try Scratch.write(markdown, to: source)
		defer { Scratch.remove(source) }

		var written: [FilePath] = []
		let destination: (String) -> String = { name in
			let path = Scratch.path("\(label)-\(name)", ext: "pdf")
			written.append(path)
			return path.description
		}
		defer { for path in written { Scratch.remove(path) } }

		try body(source.description, destination)
	}

	// MARK: option surface

	@Test("--version prints the version")
	func version() throws {
		let result = try run(["--version"])
		#expect(result.status == 0)
		#expect(result.output.contains("0.1.0"))
	}

	@Test("--help lists the command's options")
	func help() throws {
		let result = try run(["--help"])
		#expect(result.status == 0)
		#expect(result.output.contains("letterpress-md"))
		#expect(result.output.contains("--page-size"))
		#expect(result.output.contains("--typeface"))
		#expect(result.output.contains("--quiet"))
	}

	@Test("a missing input argument is a usage error")
	func missingInput() throws {
		let result = try run([])
		#expect(result.status != 0)
		#expect(result.output.contains("input"))
	}

	@Test("an unknown option is rejected without writing anything")
	func unknownOption() throws {
		let result = try run(["doc.md", "--nope"])
		#expect(result.status != 0)
	}

	@Test("an out-of-range page size is rejected by argument validation")
	func badPageSize() throws {
		let result = try run(["-", "--page-size", "a9"])
		#expect(result.status != 0)
	}

	@Test("an unreadable input exits non-zero with a message")
	func missingFile() throws {
		let missing = Scratch.path("absent", ext: "md")
		defer { Scratch.remove(missing) }
		let result = try run([missing.description])
		#expect(result.status != 0)
		#expect(result.output.contains("cannot read"))
	}

	// MARK: happy path

	@Test("a markdown file becomes a pdf with a compact json summary")
	func convertsFile() throws {
		try withScratch(markdown: "# Title\n\n- one\n- two\n") { source, destination in
			let pdf = destination("out")
			let result = try run([source, "-o", pdf])
			#expect(result.status == 0)
			#expect(result.stderr.isEmpty)
			#expect(result.stdout.contains("\"pages\":1"))
			#expect(result.stdout.contains("\"title\":\"Title\""))
			let bytes = try Scratch.read(FilePath(pdf))
			#expect(String(decoding: bytes.prefix(8), as: UTF8.self) == "%PDF-1.7")
		}
	}

	@Test("without --output the pdf lands beside the source")
	func defaultOutputPath() throws {
		try withScratch(markdown: "# Beside\n") { source, _ in
			let result = try run([source])
			#expect(result.status == 0)
			// the cli derives the output from the input path: same directory,
			// `.pdf` where the input said `.md`.
			let expected = FilePath(String(source.dropLast(3)) + ".pdf")
			defer { Scratch.remove(expected) }
			#expect(Scratch.exists(expected), "no pdf at \(expected)")
		}
	}

	@Test("`-` reads the markdown from stdin")
	func readsStdin() throws {
		let pdf = Scratch.path("stdin", ext: "pdf")
		defer { Scratch.remove(pdf) }
		let result = try run(
			["-", "-o", pdf.description], stdin: "# From stdin\n\nhello **world**\n")
		#expect(result.status == 0)
		#expect(result.stdout.contains("\"title\":\"From stdin\""))
	}

	@Test("--quiet suppresses the summary but still writes the pdf")
	func quiet() throws {
		try withScratch(markdown: "# Quiet\n") { source, destination in
			let pdf = destination("quiet")
			let result = try run([source, "-o", pdf, "--quiet"])
			#expect(result.status == 0)
			#expect(result.stdout.isEmpty)
			#expect(Scratch.exists(FilePath(pdf)))
		}
	}

	@Test("--page-size and --typeface reach the artifact")
	func styleOptions() throws {
		try withScratch(markdown: "# Title\n\nbody\n") { source, destination in
			let pdf = destination("letter")
			let result = try run([source, "-o", pdf, "--page-size", "letter", "--typeface", "serif"])
			#expect(result.status == 0)
			let text = try Scratch.text(FilePath(pdf))
			#expect(text.contains("/MediaBox [0 0 612 792]"))
			// the body face follows the flag.
			#expect(text.contains("/BaseFont /Times-Roman"))
		}
	}

	@Test("with no style flag the cli keeps the theme's own defaults")
	func styleDefaultsStand() throws {
		try withScratch(markdown: "# Title\n\nbody\n") { source, destination in
			let pdf = destination("default")
			let result = try run([source, "-o", pdf])
			#expect(result.status == 0)
			let text = try Scratch.text(FilePath(pdf))
			// the theme sets serif prose under sans heads; an unset flag must
			// leave that alone rather than pin the body back to a sans.
			#expect(text.contains("/BaseFont /Times-Roman"), "the cli overrode the theme's body face")
			#expect(text.contains("/BaseFont /Helvetica-Bold"), "the heading face left the theme")
		}
	}

	// MARK: overflow

	/// markdown whose single list item is far taller than the text column: the
	/// one shape no break policy can help, because an item is never split.
	private static let overflowing = "- " + String(repeating: "overflowing words ", count: 1000) + "\n"

	@Test("content that overflows the page box exits non-zero and names the page")
	func overflowFails() throws {
		try withScratch(markdown: Self.overflowing) { source, destination in
			let pdf = destination("over")
			let result = try run([source, "-o", pdf])
			#expect(result.status != 0)
			#expect(result.output.contains("overflows the page box"))
			#expect(result.output.contains("page 1"))
			// the artifact is still written — the exit code is what marks it
			#expect(Scratch.exists(FilePath(pdf)))
		}
	}

	@Test("the summary counts the overflow it reports")
	func overflowIsCounted() throws {
		try withScratch(markdown: Self.overflowing) { source, destination in
			let result = try run([source, "-o", destination("over")])
			#expect(result.stdout.contains("\"warnings\":"))
			#expect(!result.stdout.contains("\"warnings\":0"))
		}
	}

	@Test("a document that fits reports zero warnings and exits zero")
	func cleanDocument() throws {
		try withScratch(
			markdown: "# Title\n\n\(String(repeating: "body text ", count: 400))\n"
		) { source, destination in
			let result = try run([source, "-o", destination("long")])
			#expect(result.status == 0)
			#expect(result.stdout.contains("\"warnings\":0"))
			#expect(result.stdout.contains("\"pages\":"))
		}
	}
}