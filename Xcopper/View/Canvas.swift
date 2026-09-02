import SwiftUI

enum Layout {
	static let margin: CGFloat = 24.0
	static let origin = CGPoint(x: margin, y: margin)

	static let epsilon: CGFloat = 4.0

	static func contentSize(_ size: Size, scale: CGFloat) -> CGSize {
		let size = size.cg * scale
		return CGSize(width: size.width + margin * 2.0, height: size.height + margin * 2.0)
	}

	static func point(_ location: CGPoint, scale: CGFloat) -> Pt {
		Pt(
			x: Int(((location.x - margin) / scale * 1_000_000.0).rounded()),
			y: Int(((location.y - margin) / scale * 1_000_000.0).rounded())
		)
	}

	static func reached(from start: CGPoint, to location: CGPoint) -> CGPoint {
		let dx = location.x - start.x
		let dy = location.y - start.y
		return abs(dx) > epsilon || abs(dy) > epsilon ? location : start
	}

	static func reached(by gesture: DragGesture.Value) -> CGPoint {
		reached(from: gesture.startLocation, to: gesture.location)
	}
}

/// Scrolling, zooming host shared by the layout and schematic canvases
@MainActor
struct CanvasScroll<Content: View>: View {
	@Binding var viewport: Viewport
	var size: Size
	@ViewBuilder var content: () -> Content

	@GestureState private var magnifyGestureState: CGFloat?

	var body: some View {
		ScrollView([.horizontal, .vertical]) {
			GeometryReader { geo in
				content()
					.onChange(of: geo.frame(in: .scrollView)) { _, new in
						viewport.frame = new
					}
			}
			.frame(
				width: Layout.contentSize(size, scale: viewport.magnification).width,
				height: Layout.contentSize(size, scale: viewport.magnification).height
			)
		}
		.scrollPosition($viewport.scrollPosition)
		.gesture(magnificationController)
		.background { background }
		// A canvas already on screen when it is asked to look somewhere has
		// only to go there; one appearing with the request already made goes
		// as soon as it has measured itself, below
		.onChange(of: viewport.pending) { _, _ in viewport.revealPending(in: size) }
	}

	private var background: some View {
		GeometryReader { geo in
			Color(nsColor: .underPageBackgroundColor)
				// `initial` matters: the second mode's canvas appears at a size that
				// never changes afterwards, so it would otherwise never fit itself
				.onChange(of: geo.size, initial: true) { _, new in
					guard new.width != 0.0, new.height != 0.0 else { return }

					let old = viewport.size
					viewport.size = new
					if old == .zero { viewport.fit(size) }
					viewport.revealPending(in: size)
				}
		}
	}

	private var magnificationController: some Gesture {
		MagnifyGesture(minimumScaleDelta: 0.0)
			.updating($magnifyGestureState) { gesture, initial, _ in
				if initial == .none { initial = viewport.magnification }
				let initial = initial ?? viewport.magnification
				viewport.setScale(initial * gesture.magnification)
			}
	}
}

@MainActor
struct Coordinates: View {
	var cursor: Pt

	var body: some View {
		Text("\(Nm(clamping: cursor.x).coordinate), \(Nm(clamping: cursor.y).coordinate) mm")
	}
}

func renderGrid(
	_ bounds: Rect,
	step: Nm,
	in context: GraphicsContext,
	scale: CGFloat,
	origin: CGPoint,
	visible: CGRect
) {
	let step = CGFloat(Double(step).mm) * scale
	let tileSpan = step * 10.0
	guard step > 0.0, tileSpan >= 3.0 else { return }

	let bounds = bounds.cg(scale, origin: origin)
	let visible = bounds.intersection(visible)
	guard !visible.isNull, !visible.isEmpty else { return }

	let firstColumn = Int(floor((visible.minX - bounds.minX) / tileSpan))
	let lastColumn = Int(floor((visible.maxX - bounds.minX) / tileSpan))
	let firstRow = Int(floor((visible.minY - bounds.minY) / tileSpan))
	let lastRow = Int(floor((visible.maxY - bounds.minY) / tileSpan))
	let columns = lastColumn - firstColumn + 1
	let rows = lastRow - firstRow + 1
	guard columns > 0, rows > 0, columns * rows <= 50_000 else { return }

	let tileCount = columns * rows
	let drawMinor = step >= 3.0 && tileCount <= 200
	let minorSize = min(1.5, max(0.75, step / 12.0))
	let majorSize = min(2.0, max(1.0, minorSize * 1.5))
	let minorDot = CGRect(center: .zero, radius: minorSize / 2.0)
	let majorDot = CGRect(center: .zero, radius: majorSize / 2.0)

	var tile = Path()
	if drawMinor {
		for row in 0 ..< 10 {
			for column in 0 ..< 10 where row != 0 || column != 0 {
				tile.addRect(minorDot.offsetBy(dx: CGFloat(column) * step, dy: CGFloat(row) * step))
			}
		}
	}

	var minor = Path()
	var major = Path()
	for row in firstRow ... lastRow {
		for column in firstColumn ... lastColumn {
			let x = bounds.minX + CGFloat(column) * tileSpan
			let y = bounds.minY + CGFloat(row) * tileSpan
			if drawMinor {
				minor.addPath(tile, transform: CGAffineTransform(translationX: x, y: y))
			}
			major.addRect(majorDot.offsetBy(dx: x, dy: y))
		}
	}

	var context = context
	context.clip(to: Path(visible))
	if drawMinor { context.fill(minor, with: .color(Palette.grid)) }
	context.fill(major, with: .color(Palette.gridMajor))
}

func marching(_ path: Path, in context: GraphicsContext) {
	context.stroke(path, with: .color(.black), lineWidth: 2.0)
	context.stroke(
		path,
		with: .color(Palette.highlight),
		style: StrokeStyle(lineWidth: 1.0, dash: [4.0, 4.0])
	)
}

enum Lit {

	static let spread: CGFloat = 4.0

	static func fill(_ path: Path, _ color: Color, in context: GraphicsContext) {
		guard !path.isEmpty else { return }
		context.stroke(
			path,
			with: .color(Palette.halo),
			style: StrokeStyle(lineWidth: spread, lineJoin: .round)
		)
		context.fill(path, with: .color(color))
	}

	static func stroke(
		_ path: Path,
		_ color: Color,
		lineWidth: CGFloat,
		in context: GraphicsContext
	) {
		guard !path.isEmpty else { return }
		context.stroke(
			path,
			with: .color(Palette.halo),
			style: StrokeStyle(lineWidth: lineWidth + spread, lineCap: .round, lineJoin: .round)
		)
		context.stroke(path, with: .color(color), lineWidth: lineWidth)
	}

	static func plate(_ frame: CGRect, in context: GraphicsContext) {
		context.fill(
			Path(roundedRect: frame.insetBy(dx: -spread, dy: -spread / 2.0), cornerRadius: spread),
			with: .color(Palette.halo)
		)
	}
}

func renderCursor(_ cursor: Pt, in context: GraphicsContext, scale: CGFloat, origin: CGPoint) {
	let center = cursor.cg(scale, origin: origin)
	let arm = 8.0
	var path = Path()
	path.move(to: CGPoint(x: center.x - arm, y: center.y))
	path.addLine(to: CGPoint(x: center.x + arm, y: center.y))
	path.move(to: CGPoint(x: center.x, y: center.y - arm))
	path.addLine(to: CGPoint(x: center.x, y: center.y + arm))
	context.stroke(path, with: .color(Palette.preview), lineWidth: 1.0)
}
