import SystemPackage

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// the harness the suites share: scratch files for artifacts, and a subprocess
// runner for the two external parsers a self-referential test cannot replace
// (`letterpress-md` itself, and poppler).
//
// it is Foundation-free on purpose. Foundation would be the short path to
// `Process` and `FileManager`, but the package's core law is that no part of
// this tree imports it, and a test harness is part of the tree.
//
// the C library is reached directly for the three things `SystemPackage` does
// not cover: `posix_spawn`, `unlink`, and reading `TMPDIR` out of the
// environment. the conditional import is the module *name*, not the logic —
// both platforms are POSIX and both spell these the same way.

// MARK: - failures

/// a harness-level failure: a missing binary, a file that would not open.
public struct HarnessFailure: Error, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}

// MARK: - scratch

/// files under the host's temporary directory, removed by the caller.
///
/// every path carries a label — so a leaked file names the test that made it —
/// and a random suffix, so tests running in parallel never collide.
public enum Scratch {
	/// the host's temporary directory: `TMPDIR` when the environment sets it
	/// (macOS always does), `/tmp` otherwise.
	public static var directory: FilePath {
		guard let raw = getenv("TMPDIR"), let value = String(validatingCString: raw), !value.isEmpty else {
			return FilePath("/tmp")
		}
		// macOS sets TMPDIR with a trailing separator, which `FilePath` would
		// read as a trailing empty component.
		let trimmed = value.count > 1 && value.hasSuffix("/") ? String(value.dropLast()) : value
		return FilePath(trimmed)
	}

	/// a fresh path for `label`, with `ext` as its extension.
	public static func path(_ label: String, ext: String = "pdf") -> FilePath {
		directory.appending("letterpress-\(label)-\(Int.random(in: 0 ..< 1_000_000_000)).\(ext)")
	}

	/// write `bytes` to `path`, creating or replacing it.
	public static func write(_ bytes: [UInt8], to path: FilePath) throws {
		let fd = try FileDescriptor.open(
			path, .writeOnly, options: [.create, .truncate], permissions: .ownerReadWrite)
		defer { try? fd.close() }
		try fd.writeAll(bytes)
	}

	/// write `text` to `path` as UTF-8.
	public static func write(_ text: String, to path: FilePath) throws {
		try write(Array(text.utf8), to: path)
	}

	/// every byte of `path`.
	public static func read(_ path: FilePath) throws -> [UInt8] {
		let fd = try FileDescriptor.open(path, .readOnly)
		defer { try? fd.close() }
		return try readToEnd(fd)
	}

	/// every byte of `path`, decoded as UTF-8.
	public static func text(_ path: FilePath) throws -> String {
		String(decoding: try read(path), as: UTF8.self)
	}

	/// whether `path` can be opened for reading.
	public static func exists(_ path: FilePath) -> Bool {
		guard let fd = try? FileDescriptor.open(path, .readOnly) else { return false }
		defer { try? fd.close() }
		return true
	}

	/// remove `path`, ignoring a file that is already gone.
	public static func remove(_ path: FilePath) {
		path.withPlatformString { _ = unlink($0) }
	}

	/// drain `fd` to end of file.
	private static func readToEnd(_ fd: FileDescriptor) throws -> [UInt8] {
		var bytes: [UInt8] = []
		var buffer = [UInt8](repeating: 0, count: 32 * 1024)
		while true {
			let count = try buffer.withUnsafeMutableBytes { try fd.read(into: $0) }
			if count == 0 { return bytes }
			bytes.append(contentsOf: buffer[0 ..< count])
		}
	}
}

// MARK: - subprocess

/// what a child process left behind.
public struct ChildResult: Sendable {
	/// the child's exit status; a signal-terminated child reports its raw wait
	/// status instead, so a crash can never read as success.
	public let status: Int32
	/// everything the child wrote to stdout.
	public let stdout: String
	/// everything the child wrote to stderr.
	public let stderr: String
	/// both streams, for assertions that do not care which carried a line.
	public var output: String { stdout + stderr }
	/// whether the child exited zero.
	public var succeeded: Bool { status == 0 }
}

/// run a child process to completion.
public enum Spawn {
	/// run `arguments` — `arguments[0]` being an absolute path to the
	/// executable — and capture both streams.
	///
	/// `stdin` is delivered through a file, and a child with no `stdin` reads
	/// `/dev/null`, so nothing a suite runs can block on the terminal that
	/// started it.
	///
	/// stdout and stderr land in files rather than pipes: a child that writes
	/// more than a pipe buffer would deadlock against a parent that is not
	/// draining it, and `pdftotext -bbox` on a full page is past that size.
	public static func run(_ arguments: [String], stdin: String? = nil) throws -> ChildResult {
		let stdoutPath = Scratch.path("stdout", ext: "txt")
		let stderrPath = Scratch.path("stderr", ext: "txt")
		let stdinPath = stdin == nil ? nil : Scratch.path("stdin", ext: "txt")
		defer {
			Scratch.remove(stdoutPath)
			Scratch.remove(stderrPath)
			if let stdinPath { Scratch.remove(stdinPath) }
		}

		if let stdinPath, let stdin { try Scratch.write(stdin, to: stdinPath) }

		let null = try FileDescriptor.open("/dev/null", .readOnly)
		defer { try? null.close() }
		let input = try stdinPath.map { try FileDescriptor.open($0, .readOnly) }
		defer { try? input?.close() }

		let status = try spawn(
			arguments,
			stdin: input ?? null,
			stdout: try FileDescriptor.open(
				stdoutPath, .writeOnly, options: [.create, .truncate], permissions: .ownerReadWrite),
			stderr: try FileDescriptor.open(
				stderrPath, .writeOnly, options: [.create, .truncate], permissions: .ownerReadWrite)
		)

		return ChildResult(
			status: status,
			stdout: String(decoding: try Scratch.read(stdoutPath), as: UTF8.self),
			stderr: String(decoding: try Scratch.read(stderrPath), as: UTF8.self)
		)
	}

	/// whether `path` is an executable file, so a suite can say why it is about
	/// to fail instead of failing opaquely.
	public static func isExecutable(_ path: String) -> Bool {
		access(path, X_OK) == 0
	}

	// MARK: the spawn itself

	/// `posix_spawn` the executable, wiring the three standard streams through
	/// `fileActions`, and wait for it.
	private static func spawn(
		_ arguments: [String],
		stdin: FileDescriptor,
		stdout: FileDescriptor,
		stderr: FileDescriptor
	) throws -> Int32 {
		// Glibc models the file actions as a struct and Darwin as a pointer, so this
		// local's type really does differ by platform. it is the only conditional
		// in the package, and it is a type difference in the c library rather
		// than a branch in the logic.
		#if canImport(Darwin)
		var actions: posix_spawn_file_actions_t?
		#else
		var actions = posix_spawn_file_actions_t()
		#endif
		try check(posix_spawn_file_actions_init(&actions), "posix_spawn_file_actions_init")
		defer { posix_spawn_file_actions_destroy(&actions) }

		try check(
			posix_spawn_file_actions_adddup2(&actions, stdin.rawValue, STDIN_FILENO),
			"dup2 stdin")
		try check(
			posix_spawn_file_actions_adddup2(&actions, stdout.rawValue, STDOUT_FILENO),
			"dup2 stdout")
		try check(
			posix_spawn_file_actions_adddup2(&actions, stderr.rawValue, STDERR_FILENO),
			"dup2 stderr")

		let argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
		defer { for pointer in argv { free(pointer) } }
		// a deliberately small environment: PATH is what lets `/usr/bin/env`
		// find poppler, and nothing else about the test runner's environment
		// should be able to change what a child does.
		let envp: [UnsafeMutablePointer<CChar>?] = [
			strdup("PATH=\(environment("PATH") ?? "/usr/bin:/bin")"),
			strdup("HOME=\(environment("HOME") ?? "/")"),
			nil,
		]
		defer { for pointer in envp { free(pointer) } }

		var pid: pid_t = 0
		try argv.withUnsafeBufferPointer { argvBuffer in
			guard let argvPointer = argvBuffer.baseAddress else {
				throw HarnessFailure("argv is empty")
			}
			try envp.withUnsafeBufferPointer { envpBuffer in
				guard let envpPointer = envpBuffer.baseAddress else {
					throw HarnessFailure("envp is empty")
				}
				try check(
					posix_spawn(&pid, arguments[0], &actions, nil, argvPointer, envpPointer),
					"posix_spawn(\(arguments[0]))")
			}
		}

		var status: Int32 = 0
		while waitpid(pid, &status, 0) == -1 {
			guard errno == EINTR else {
				throw HarnessFailure("waitpid(\(pid)) failed with errno \(errno)")
			}
		}
		// the C `WIFEXITED`/`WEXITSTATUS` macros are not importable. the low
		// seven bits are zero when a child exited rather than being signalled;
		// a signalled child reports the raw status so it cannot read as zero.
		return (status & 0x7f) == 0 ? (status >> 8) & 0xff : status
	}

	/// read an environment variable by name.
	private static func environment(_ name: String) -> String? {
		guard let raw = getenv(name) else { return nil }
		return String(validatingCString: raw)
	}

	/// throw unless a POSIX call reported success.
	private static func check(_ result: Int32, _ what: String) throws {
		guard result == 0 else {
			throw HarnessFailure("\(what) failed with errno \(result)")
		}
	}
}