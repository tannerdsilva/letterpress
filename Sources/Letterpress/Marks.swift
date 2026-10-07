import Foundation

// MARK: - text emission helper

/// emit one BT/ET text object containing `lines`, each placed absolutely.
///
/// user coordinates are y-down: `topY` is the top of the first line, and
/// each subsequent line sits `lineHeight * size` below it. the baseline is
/// approximated at 0.8em below the line top, which reads correctly for the
/// standard 14 fonts at typical sizes.
internal func emitTextLines(
	_ lines: [String],
	font: Font,
	size: Double,
	x: Double,
	topY: Double,
	alignment: TextAlignment,
	lineHeight: Double,
	renderer: inout Renderer
) {
	let tag = renderer.useFont(font)
	renderer.append("BT\n")
	renderer.append("\(tag) \(PDFNumber(size)) Tf\n")
	let baselineOffset = size * 0.80
	for (index, line) in lines.enumerated() {
		let width = font.width(of: line, size: size)
		let startX: Double
		switch alignment {
		case .leading: startX = x
		case .center: startX = x - width / 2
		case .trailing: startX = x - width
		}
		let lineTop = topY + Double(index) * size * lineHeight
		let baseline = renderer.flippedY(lineTop + baselineOffset)
		// `Tm` is the six-argument text matrix — identity with a translation
		// places each line absolutely (no accumulation across lines).
		renderer.append("1 0 0 1 \(PDFNumber(startX)) \(PDFNumber(baseline)) Tm\n")
		renderer.append("(\(pdfEscape(line))) Tj\n")
	}
	renderer.append("ET\n")
}

/// split `text` into lines that fit `frameWidth` (points), breaking on spaces.
///
/// a single word longer than the frame keeps its full width rather than
/// being split mid-word. an unbounded frame width returns the text as one
/// line per '\n'.
internal func wrappedLines(_ text: String, frameWidth: Double, font: Font, size: Double) -> [String] {
	let paragraphs = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
	guard frameWidth.isFinite else { return paragraphs }
	var lines: [String] = []
	let spaceWidth = font.width(of: " ", size: size)
	for paragraph in paragraphs {
		var current = ""
		var currentWidth = 0.0
		for word in paragraph.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
			let wordWidth = font.width(of: word, size: size)
			let gap = current.isEmpty ? 0 : spaceWidth
			if current.isEmpty || currentWidth + gap + wordWidth <= frameWidth {
				if !current.isEmpty { current += " " }
				current += word
				currentWidth += gap + wordWidth
			} else {
				lines.append(current)
				current = word
				currentWidth = wordWidth
			}
		}
		if !current.isEmpty { lines.append(current) }
	}
	return lines
}

// MARK: - Text

/// a single run of text, positioned and styled by modifiers.
///
///     Text("hello, pdf")
///         .font(.helveticaBold, size: 28)
///         .foregroundColor(.ink)
///         .at(x: 72, y: 72)
///
/// `.at(x:y:)` anchors the top-left of the first line; `.alignment` re-anchors
/// the given point (center / trailing) using the measured text width. an
/// embedded '\n' starts a new line below the previous one.
public struct Text: Mark {
	public let content: String

	public init(_ content: String) {
		self.content = content
	}

	public func write(to renderer: inout Renderer) {
		let state = renderer.text
		let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		emitTextLines(
			lines,
			font: state.font,
			size: state.size,
			x: state.position.x,
			topY: state.position.y,
			alignment: state.alignment,
			lineHeight: state.lineHeight,
			renderer: &renderer
		)
	}

	public func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		let style = context.text
		let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		let width = lines.map { style.font.width(of: $0, size: style.size) }.max() ?? 0
		let height = Double(lines.count) * style.size * style.lineHeight
		return Size(width: width, height: height)
	}
}

// MARK: - Paragraph

/// a word-wrapped block of text.
///
///     Paragraph("long narrative text ...")
///         .font(.times, size: 12)
///         .frame(maxWidth: 420)
///         .lineHeight(1.5)
///         .at(x: 72, y: 200)
///
/// lines break on spaces to fit `.frame(maxWidth:)`; without a frame the text is
/// one line per '\n'. `lineHeight` is a multiple of the font size.
public struct Paragraph: Mark {
	public let content: String

	public init(_ content: String) {
		self.content = content
	}

	public func write(to renderer: inout Renderer) {
		let state = renderer.text
		let effectiveWidth = renderer.proposedSize.width ?? .greatestFiniteMagnitude
		let lines = wrappedLines(content, frameWidth: effectiveWidth, font: state.font, size: state.size)
		emitTextLines(
			lines,
			font: state.font,
			size: state.size,
			x: state.position.x,
			topY: state.position.y,
			alignment: state.alignment,
			lineHeight: state.lineHeight,
			renderer: &renderer
		)
	}

	public func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		let style = context.text
		let effectiveWidth = proposal.width ?? .greatestFiniteMagnitude
		let lines = wrappedLines(content, frameWidth: effectiveWidth, font: style.font, size: style.size)
		let width = lines.map { style.font.width(of: $0, size: style.size) }.max() ?? 0
		let height = Double(lines.count) * style.size * style.lineHeight
		return Size(width: width, height: height)
	}
}

// MARK: - Rect

/// a rectangle (optionally rounded), filled and/or stroked by modifiers.
///
///     Rect(x: 72, y: 160, width: 140, height: 70)
///         .fill(.sky.opacity(0.35))
///         .stroke(.blue, width: 2)
///
/// `x`,`y` are the top-left corner, `width`/`height` extend right and down.
public struct Rect: PathMark {
	public let x: Double
	public let y: Double
	public let width: Double
	public let height: Double
	public let cornerRadius: Double

	public init(x: Double, y: Double, width: Double, height: Double, cornerRadius: Double = 0) {
		self.x = x
		self.y = y
		self.width = width
		self.height = height
		self.cornerRadius = max(cornerRadius, 0)
	}

	public func write(to renderer: inout Renderer) {
		writePath(to: &renderer)
	}

	public func writePath(to renderer: inout Renderer) {
		let bottom = renderer.flippedY(y) - height
		if cornerRadius > 0 {
			let radius = min(cornerRadius, min(width, height) / 2)
			roundedRectPath(x: x, y: bottom, width: width, height: height, radius: radius, renderer: &renderer)
		} else {
			renderer.append("\(PDFNumber(x)) \(PDFNumber(bottom)) \(PDFNumber(width)) \(PDFNumber(height)) re\n")
		}
	}

	public func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		Size(width: width, height: height)
	}
}

// MARK: - Ellipse

/// an ellipse (or circle) inside a bounding box.
///
///     Ellipse(x: 72, y: 280, width: 90, height: 60)
///         .fill(.amber)
///         .stroke(.orange, width: 2)
///
/// `x`,`y` are the top-left of the bounding box; equal `width`/`height` make
/// a circle.
public struct Ellipse: PathMark {
	public let x: Double
	public let y: Double
	public let width: Double
	public let height: Double

	public init(x: Double, y: Double, width: Double, height: Double) {
		self.x = x
		self.y = y
		self.width = width
		self.height = height
	}

	public func write(to renderer: inout Renderer) {
		writePath(to: &renderer)
	}

	public func writePath(to renderer: inout Renderer) {
		let bottom = renderer.flippedY(y) - height
		let centerX = x + width / 2
		let centerY = bottom + height / 2
		let radiusX = width / 2
		let radiusY = height / 2
		let curve = radiusY * 0.5523
		let curveX = radiusX * 0.5523
		renderer.append("\(PDFNumber(centerX + radiusX)) \(PDFNumber(centerY)) m\n")
		renderer.append("\(PDFNumber(centerX + radiusX)) \(PDFNumber(centerY + curve)) \(PDFNumber(centerX + curveX)) \(PDFNumber(centerY + radiusY)) \(PDFNumber(centerX)) \(PDFNumber(centerY + radiusY)) c\n")
		renderer.append("\(PDFNumber(centerX - curveX)) \(PDFNumber(centerY + radiusY)) \(PDFNumber(centerX - radiusX)) \(PDFNumber(centerY + curve)) \(PDFNumber(centerX - radiusX)) \(PDFNumber(centerY)) c\n")
		renderer.append("\(PDFNumber(centerX - radiusX)) \(PDFNumber(centerY - curve)) \(PDFNumber(centerX - curveX)) \(PDFNumber(centerY - radiusY)) \(PDFNumber(centerX)) \(PDFNumber(centerY - radiusY)) c\n")
		renderer.append("\(PDFNumber(centerX + curveX)) \(PDFNumber(centerY - radiusY)) \(PDFNumber(centerX + radiusX)) \(PDFNumber(centerY - curve)) \(PDFNumber(centerX + radiusX)) \(PDFNumber(centerY)) c\n")
	}

	public func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		Size(width: width, height: height)
	}
}

// MARK: - Line

/// a straight line between two points.
///
///     Line(from: Point(x: 72, y: 420), to: Point(x: 500, y: 420))
///         .stroke(.coral, width: 3)
public struct Line: PathMark {
	public let from: Point
	public let to: Point

	public init(from: Point, to: Point) {
		self.from = from
		self.to = to
	}

	public func write(to renderer: inout Renderer) {
		writePath(to: &renderer)
	}

	public func writePath(to renderer: inout Renderer) {
		renderer.append("\(PDFNumber(from.x)) \(PDFNumber(renderer.flippedY(from.y))) m\n")
		renderer.append("\(PDFNumber(to.x)) \(PDFNumber(renderer.flippedY(to.y))) l\n")
	}

	public func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		Size(width: abs(to.x - from.x), height: abs(to.y - from.y))
	}
}

// MARK: - Polygon

/// a closed polygon through the given vertices.
///
///     Polygon([
///         Point(x: 72, y: 500),
///         Point(x: 172, y: 500),
///         Point(x: 172, y: 560),
///     ]).fill(.green)
public struct Polygon: PathMark {
	public let vertices: [Point]

	public init(_ vertices: [Point]) {
		self.vertices = vertices
	}

	public func write(to renderer: inout Renderer) {
		writePath(to: &renderer)
	}

	public func writePath(to renderer: inout Renderer) {
		guard let first = vertices.first else { return }
		renderer.append("\(PDFNumber(first.x)) \(PDFNumber(renderer.flippedY(first.y))) m\n")
		for vertex in vertices.dropFirst() {
			renderer.append("\(PDFNumber(vertex.x)) \(PDFNumber(renderer.flippedY(vertex.y))) l\n")
		}
		renderer.append("h\n")
	}

	public func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		guard let first = vertices.first else { return .zero }
		var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
		for vertex in vertices.dropFirst() {
			minX = min(minX, vertex.x)
			minY = min(minY, vertex.y)
			maxX = max(maxX, vertex.x)
			maxY = max(maxY, vertex.y)
		}
		return Size(width: maxX - minX, height: maxY - minY)
	}
}

// MARK: - rounded rect path

/// emit the path of a rounded rectangle in pdf (y-up) coordinates.
///
/// each corner is a single cubic bezier with the standard 0.5523 kappa.
private func roundedRectPath(
	x: Double, y: Double, width: Double, height: Double, radius: Double,
	renderer: inout Renderer
) {
	let curve = radius * 0.5523
	let right = x + width
	let top = y + height
	renderer.append("\(PDFNumber(x + radius)) \(PDFNumber(y)) m\n")
	renderer.append("\(PDFNumber(right - radius)) \(PDFNumber(y)) l\n")
	renderer.append("\(PDFNumber(right - radius + curve)) \(PDFNumber(y)) \(PDFNumber(right)) \(PDFNumber(y + radius - curve)) \(PDFNumber(right)) \(PDFNumber(y + radius)) c\n")
	renderer.append("\(PDFNumber(right)) \(PDFNumber(top - radius)) l\n")
	renderer.append("\(PDFNumber(right)) \(PDFNumber(top - radius + curve)) \(PDFNumber(right - radius + curve)) \(PDFNumber(top)) \(PDFNumber(right - radius)) \(PDFNumber(top)) c\n")
	renderer.append("\(PDFNumber(x + radius)) \(PDFNumber(top)) l\n")
	renderer.append("\(PDFNumber(x + radius - curve)) \(PDFNumber(top)) \(PDFNumber(x)) \(PDFNumber(top - radius + curve)) \(PDFNumber(x)) \(PDFNumber(top - radius)) c\n")
	renderer.append("\(PDFNumber(x)) \(PDFNumber(y + radius)) l\n")
	renderer.append("\(PDFNumber(x)) \(PDFNumber(y + radius - curve)) \(PDFNumber(x + radius - curve)) \(PDFNumber(y)) \(PDFNumber(x + radius)) \(PDFNumber(y)) c\n")
	renderer.append("h\n")
}
