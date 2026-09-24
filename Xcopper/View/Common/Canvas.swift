import SwiftUI

enum Layout {
	static let margin: CGFloat = 24.0
	static let origin = CGPoint(x: margin, y: margin)

	static let epsilon: CGFloat = 4.0

	static func contentSize(_ size: Size, scale: CGFloat) -> CGSize {
		let size = size.cg * scale
		return CGSize(width: size.width + margin * 2.0, height: size.height + margin * 2.0)
	}

	static func point(_ location: CGPoint, scale: CGFloat) -> Point {
		Point(
			x: µm(((location.x - margin) / scale * CGFloat(µm.mm)).rounded()),
			y: µm(((location.y - margin) / scale * CGFloat(µm.mm)).rounded())
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

@MainActor
struct ViewportCanvas: View {
	var viewport: Viewport
	var render: (GraphicsContext, CGFloat, CGRect) -> Void

	var body: some View {
		GeometryReader { geo in
			let visible = viewport.visibleRect(in: geo.size)
				.insetBy(dx: -128, dy: -128)
				.intersection(CGRect(origin: .zero, size: geo.size))
			if !visible.isNull, !visible.isEmpty {
				Canvas { context, _ in
					var context = context
					context.translateBy(x: -visible.minX, y: -visible.minY)
					context.clip(to: Path(visible))
					render(context, viewport.magnification, visible)
				}
				.frame(width: visible.width, height: visible.height)
				.offset(x: visible.minX, y: visible.minY)
				.allowsHitTesting(false)
			}
		}
	}
}

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
		.onChange(of: viewport.pending) { _, _ in viewport.revealPending(in: size) }
	}

	private var background: some View {
		GeometryReader { geo in
			Palette.background
				.onChange(of: geo.size, initial: true) { _, new in
					viewport.resize(to: new, content: size)
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

func renderCursor(_ cursor: Point, in context: GraphicsContext, scale: CGFloat, origin: CGPoint) {
	let center = cursor.cg(scale, origin: origin)
	let arm = 8.0
	var path = Path()
	path.move(to: CGPoint(x: center.x - arm, y: center.y))
	path.addLine(to: CGPoint(x: center.x + arm, y: center.y))
	path.move(to: CGPoint(x: center.x, y: center.y - arm))
	path.addLine(to: CGPoint(x: center.x, y: center.y + arm))
	context.stroke(path, with: .color(Palette.preview), lineWidth: 1.0)
}
