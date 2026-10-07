import Testing
import Letterpress

// this target imports Letterpress WITHOUT `@testable` on purpose: everything it
// touches must be public. if a member a conformer needs ever goes internal, this
// file stops compiling — which is the assertion.
//
// the paint helpers are constrained to `PathMark`, so `Text("x").fill(.red)` is
// a compile error. that is a type-system guarantee, not a runtime one, and this
// file compiling without it is the proof.

// MARK: - a mark written from the public surface alone

/// draws a rule spanning half the width it is proposed — it reads the ambient
/// proposal and emits its own content-stream operators.
struct HalfRule: Mark {
	func write(to renderer: inout Renderer) {
		let width = (renderer.proposedSize.width ?? 100) / 2
		let y = renderer.flippedY(renderer.text.position.y)
		renderer.append("\(PDFNumber(0)) \(PDFNumber(y)) m\n")
		renderer.append("\(PDFNumber(width)) \(PDFNumber(y)) l S\n")
	}

	func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		Size(width: proposal.width ?? 100, height: 1)
	}
}

// MARK: - a modifier written from the public surface alone

/// renders its content monospaced by pushing the text style in and restoring it.
struct Monospaced: MarkModifier {
	let size: Double

	func apply<Content: Mark>(content: Content, to renderer: inout Renderer) {
		let saved = renderer.text
		renderer.text.font = .courier
		renderer.text.size = size
		content.write(to: &renderer)
		renderer.text = saved
	}

	func sizeThatFits<Content: Mark>(
		content: Content, proposal: ProposedSize, in context: inout MeasureContext
	) -> Size {
		let saved = context.text
		context.text.font = .courier
		context.text.size = size
		let result = content.sizeThatFits(proposal, in: &context)
		context.text = saved
		return result
	}
}

extension Mark {
	/// the consumer-side spelling of the custom modifier above.
	func monospaced(size: Double) -> ModifiedMark<Self, Monospaced> {
		ModifiedMark(content: self, modifier: Monospaced(size: size))
	}
}

// MARK: - the seam is open

@Suite struct PublicAPISurfaceTests {
	private func stream(_ document: PDFDocument) -> String {
		String(decoding: document.render(), as: UTF8.self)
	}

	@Test("a consumer mark reads the ambient proposal and emits operators")
	func markEmitsFromPublicSurface() {
		let document = PDFDocument {
			PDFPage(.custom(width: 200, height: 100)) {
				HalfRule().frame(maxWidth: 120)
			}
		}
		let text = stream(document)
		// the mark saw the 120pt proposal the frame pushed in, and drew to half of it
		#expect(text.contains("0 100 m"))
		#expect(text.contains("60 100 l S"))
	}

	@Test("a consumer modifier pushes and restores renderer text state")
	func modifierPushesTextState() {
		let document = PDFDocument {
			PDFPage(.custom(width: 200, height: 100)) {
				Text("hi").monospaced(size: 9).at(x: 10, y: 10)
			}
		}
		#expect(stream(document).contains("/BaseFont /Courier"))
	}

	@Test("a consumer modifier measures under the style it renders with")
	func modifierMeasuresUnderItsStyle() {
		var context = MeasureContext()
		let measured = Text("hi").monospaced(size: 10).sizeThatFits(.unconstrained, in: &context)
		#expect(measured.width == Font.courier.width(of: "hi", size: 10))
	}

	@Test("a consumer modifier restores the style for the marks after it")
	func modifierRestoresStyle() {
		let document = PDFDocument {
			PDFPage(.custom(width: 200, height: 100)) {
				Text("mono").monospaced(size: 9).at(x: 10, y: 10)
				Text("plain").at(x: 10, y: 30)
			}
		}
		// the second mark must render in the DEFAULT face, not the pushed one
		let text = stream(document)
		#expect(text.contains("/BaseFont /Courier"))
		#expect(text.contains("/BaseFont /Helvetica"))
	}
}