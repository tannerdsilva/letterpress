import Foundation
import Testing

// drives the built `letterpress-md` binary as a subprocess, so the checks cover
// the things a library test cannot: argument parsing, exit codes, and the
// stdout/stderr contract.

@Suite("letterpress-md cli")
struct LetterpressCLITests {
	/// the built binary, resolved from this file so the suite is cwd-independent.
	static let binaryPath: String = {
		let root = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()   // LetterpressCLITests
			.deletingLastPathComponent()   // Tests
			.deletingLastPathComponent()   // package root
		return root.appendingPathComponent(".build/debug/letterpress-md").path
	}()

	// MARK: harness

	struct Run {
		let exit: Int32
		let stdout: String
		let stderr: String
		/// both streams, for assertions that do not care which carried a line.
		var output: String { stdout + stderr }
	}

	private func run(_ arguments: [String], stdin: String? = nil) throws -> Run {
		guard FileManager.default.isExecutableFile(atPath: Self.binaryPath) else {
			throw CLIError("no binary at \(Self.binaryPath) — run `swift build` first")
		}
		let process = Process()
		process.executableURL = URL(fileURLWithPath: Self.binaryPath)
		process.arguments = arguments

		let outPipe = Pipe()
		let errPipe = Pipe()
		let inPipe = Pipe()
		process.standardOutput = outPipe
		process.standardError = errPipe
		process.standardInput = inPipe

		try process.run()
		if let stdin { inPipe.fileHandleForWriting.write(Data(stdin.utf8)) }
		try? inPipe.fileHandleForWriting.close()

		let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
		let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		return Run(
			exit: process.terminationStatus,
			stdout: String(decoding: outData, as: UTF8.self),
			stderr: String(decoding: errData, as: UTF8.self)
		)
	}

	private struct CLIError: Error, CustomStringConvertible {
		let description: String
		init(_ description: String) { self.description = description }
	}

	/// a scratch directory holding a markdown source, torn down after the test.
	private func withScratch(
		markdown: String,
		_ body: (String, String) throws -> Void
	) throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("letterpress-cli-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let source = directory.appendingPathComponent("doc.md")
		try markdown.write(to: source, atomically: true, encoding: .utf8)
		try body(source.path, directory.path)
	}

	// MARK: option surface

	@Test("--version prints the version")
	func version() throws {
		let result = try run(["--version"])
		#expect(result.exit == 0)
		#expect(result.output.contains("0.1.0"))
	}

	@Test("--help lists the command's options")
	func help() throws {
		let result = try run(["--help"])
		#expect(result.exit == 0)
		#expect(result.output.contains("letterpress-md"))
		#expect(result.output.contains("--page-size"))
		#expect(result.output.contains("--typeface"))
		#expect(result.output.contains("--quiet"))
	}

	@Test("a missing input argument is a usage error")
	func missingInput() throws {
		let result = try run([])
		#expect(result.exit != 0)
		#expect(result.output.contains("input"))
	}

	@Test("an unknown option is rejected without writing anything")
	func unknownOption() throws {
		let result = try run(["doc.md", "--nope"])
		#expect(result.exit != 0)
	}

	@Test("an out-of-range page size is rejected by argument validation")
	func badPageSize() throws {
		let result = try run(["-", "--page-size", "a9"])
		#expect(result.exit != 0)
	}

	@Test("an unreadable input exits non-zero with a message")
	func missingFile() throws {
		let missing = FileManager.default.temporaryDirectory
			.appendingPathComponent("letterpress-absent-\(UUID().uuidString).md")
		let result = try run([missing.path])
		#expect(result.exit != 0)
		#expect(result.output.contains("cannot read"))
	}

	// MARK: happy path

	@Test("a markdown file becomes a pdf with a compact json summary")
	func convertsFile() throws {
		try withScratch(markdown: "# Title\n\n- one\n- two\n") { source, directory in
			let pdf = "\(directory)/out.pdf"
			let result = try run([source, "-o", pdf])
			#expect(result.exit == 0)
			#expect(result.stderr.isEmpty)
			#expect(result.stdout.contains("\"pages\":1"))
			#expect(result.stdout.contains("\"title\":\"Title\""))
			let bytes = try Data(contentsOf: URL(fileURLWithPath: pdf))
			#expect(String(decoding: bytes.prefix(8), as: UTF8.self) == "%PDF-1.7")
		}
	}

	@Test("without --output the pdf lands beside the source")
	func defaultOutputPath() throws {
		try withScratch(markdown: "# Beside\n") { source, directory in
			let result = try run([source])
			#expect(result.exit == 0)
			let expected = "\(directory)/doc.pdf"
			let bytes = try Data(contentsOf: URL(fileURLWithPath: expected))
			#expect(!bytes.isEmpty)
		}
	}

	@Test("`-` reads the markdown from stdin")
	func readsStdin() throws {
		let result = try run(["-", "-o", FileManager.default.temporaryDirectory
			.appendingPathComponent("letterpress-stdin-\(UUID().uuidString).pdf").path],
			stdin: "# From stdin\n\nhello **world**\n")
		#expect(result.exit == 0)
		#expect(result.stdout.contains("\"title\":\"From stdin\""))
	}

	@Test("--quiet suppresses the summary but still writes the pdf")
	func quiet() throws {
		try withScratch(markdown: "# Quiet\n") { source, directory in
			let pdf = "\(directory)/quiet.pdf"
			let result = try run([source, "-o", pdf, "--quiet"])
			#expect(result.exit == 0)
			#expect(result.stdout.isEmpty)
			#expect(FileManager.default.fileExists(atPath: pdf))
		}
	}

	@Test("--page-size and --typeface reach the artifact")
	func styleOptions() throws {
		try withScratch(markdown: "# Title\n\nbody\n") { source, directory in
			let pdf = "\(directory)/letter.pdf"
			let result = try run([source, "-o", pdf, "--page-size", "letter", "--typeface", "serif"])
			#expect(result.exit == 0)
			let text = String(decoding: try Data(contentsOf: URL(fileURLWithPath: pdf)), as: UTF8.self)
			#expect(text.contains("/MediaBox [0 0 612 792]"))
			#expect(text.contains("/BaseFont /Times-Bold"))
		}
	}
}