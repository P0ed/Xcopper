import CoreGraphics

struct LayoutViewport: Equatable {
	var cursor: Point = .zero
	var size: CGSize = .zero
	private(set) var center: CGPoint = .zero
	private(set) var magnification: CGFloat = 4.0
	private(set) var fitting = true
}

extension LayoutViewport {

	func point(at location: CGPoint) -> Point {
		Point(
			x: Int(((center.x + (location.x - size.width / 2.0) / magnification) * CGFloat(µm.mm)).rounded()),
			y: Int(((center.y + (location.y - size.height / 2.0) / magnification) * CGFloat(µm.mm)).rounded())
		)
	}

	var visible: Rect {
		Rect(from: point(at: .zero), to: point(at: CGPoint(x: size.width, y: size.height)))
	}

	mutating func setScale(_ scale: CGFloat) {
		fitting = false
		magnification = min(max(scale, 0.05), 64.0)
	}

	mutating func fit(_ content: Size) {
		guard size.width > 0.0, size.height > 0.0 else { return }
		setScale(content.zoomToFit(size, margin: Layout.margin))
		center = CGPoint(x: Double.mm(content.width) / 2.0, y: Double.mm(content.height) / 2.0)
		fitting = true
	}

	mutating func resize(to size: CGSize, content: Size) {
		guard size.width > 0.0, size.height > 0.0 else { return }
		self.size = size
		if fitting { fit(content) }
	}

	mutating func pan(by delta: CGSize) {
		fitting = false
		center.x -= delta.width / magnification
		center.y -= delta.height / magnification
	}

	mutating func reveal(_ point: Point) {
		fitting = false
		center = point.cg(1.0, origin: .zero)
	}
}
