import SwiftUI

enum Layout {
	static let margin: CGFloat = 24.0
	static let origin = CGPoint(x: margin, y: margin)

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

/// Cursor position and the settings that matter for the active tool
@MainActor
struct Readout<Content: View>: View {
	@ViewBuilder var content: () -> Content

	var body: some View {
		HStack(spacing: 10.0) {
			content()
		}
		.font(.caption.monospacedDigit())
		.foregroundStyle(.secondary)
		.padding(.horizontal, 10.0)
		.padding(.vertical, 5.0)
		.background(.regularMaterial, in: .rect(cornerRadius: 6.0))
		.padding(8.0)
	}
}

@MainActor
struct Coordinates: View {
	var cursor: Pt

	var body: some View {
		Text("\(Nm(clamping: cursor.x).coordinate), \(Nm(clamping: cursor.y).coordinate) mm")
	}
}

/// Dotted grid over `bounds`, skipped once the dots would crowd together
func renderGrid(
	_ bounds: Rect,
	step: Nm,
	in context: GraphicsContext,
	scale: CGFloat,
	origin: CGPoint
) {
	let step = Double(step).mm * scale
	guard step >= 5.0 else { return }

	let bounds = bounds.cg(scale, origin: origin)
	let dot = min(1.5, max(0.75, step / 12.0))
	var path = Path()

	var y = bounds.minY
	while y <= bounds.maxY + 0.5 {
		var x = bounds.minX
		while x <= bounds.maxX + 0.5 {
			path.addEllipse(in: CGRect(center: CGPoint(x: x, y: y), radius: dot / 2.0))
			x += step
		}
		y += step
	}
	context.fill(path, with: .color(Palette.grid))
}

/// Selection outline, legible over any fill
func marching(_ path: Path, in context: GraphicsContext) {
	context.stroke(path, with: .color(.black), lineWidth: 2.0)
	context.stroke(
		path,
		with: .color(Palette.highlight),
		style: StrokeStyle(lineWidth: 1.0, dash: [4.0, 4.0])
	)
}

/// Crosshair at the snapped cursor position
func renderCursor(_ cursor: Pt, in context: GraphicsContext, scale: CGFloat, origin: CGPoint) {
	let center = cursor.cg(scale, origin: origin)
	let arm = 6.0
	var path = Path()
	path.move(to: CGPoint(x: center.x - arm, y: center.y))
	path.addLine(to: CGPoint(x: center.x + arm, y: center.y))
	path.move(to: CGPoint(x: center.x, y: center.y - arm))
	path.addLine(to: CGPoint(x: center.x, y: center.y + arm))
	context.stroke(path, with: .color(Palette.preview), lineWidth: 1.0)
}
