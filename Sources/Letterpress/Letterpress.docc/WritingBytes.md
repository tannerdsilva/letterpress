# writing the bytes

letterpress produces bytes and nothing else. getting them onto a disk, a
socket, or a response body is the caller's job.

## the contract

`PDFDocument/render()` returns `[UInt8]` — the complete pdf, from `%PDF-1.7`
through the trailing `%%EOF`. it is byte-deterministic: the same page tree
renders the same bytes on every run, on every platform, under every locale.

the library stops there, deliberately.

- **no file api.** there is no `write(to:)` on `PDFDocument`, no path
  handling, no `URL`. the exporter has no opinion about where its output goes,
  so it never takes a lock, never truncates a file, and never needs a
  directory to exist.
- **no imports at all.** the `Letterpress` module imports nothing — not
  Foundation, not a platform shim. the two places a dependency would otherwise
  appear are `pow` in `PDFNumber`, replaced with integer arithmetic, and the
  write itself, which belongs to the caller.
- **no hidden state.** rendering is a pure function of the page tree, which is
  what lets the output be compared byte-for-byte between runs and between
  machines.

the payoff is portability: nothing in the core pins the package to a platform
that ships Foundation, so the exporter can be dropped into any Swift target
that can hold an array of bytes.

## getting them to a file

`letterpress-md` is the worked example. it writes through
[swift-system](https://github.com/apple/swift-system) rather than Foundation:

```swift
import SystemPackage

let bytes = document.render()
let file = try FileDescriptor.open(
    FilePath("out.pdf"), .writeOnly, options: [.create, .truncate],
    permissions: .ownerReadWrite)
defer { try? file.close() }
try file.writeAll(bytes)
```

nothing here is special to letterpress. a caller that already has Foundation
can use `Data(bytes)` and `write(to:)`; a caller serving http can hand the
array straight to a response body; a caller writing to a socket can write it in
whatever slices it likes. the exporter does not care, and does not need to
know.

## what the design costs

the convenience is gone with the dependency. `PDFDocument` cannot write a file
by itself, so every caller repeats four lines of file handling, and the two
executables in this package each carry their own copy. that is the trade: four
lines per caller, in exchange for a core module with an empty import list.