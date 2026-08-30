import CoreGraphics

extension CGSize {

	static func * (_ size: CGSize, _ scale: CGFloat) -> CGSize {
		CGSize(width: size.width * scale, height: size.height * scale)
	}
}

extension Size {

	var cg: CGSize { CGSize(width: Double(width).mm, height: Double(height).mm) }

	func zoomToFit(_ size: CGSize, margin: CGFloat) -> CGFloat {
		let board = cg
		guard board.width > 0.0, board.height > 0.0 else { return 4.0 }
		return min(
			(size.width - margin * 2.0) / board.width,
			(size.height - margin * 2.0) / board.height
		)
	}
}

extension Double {
	/// Nanometers as millimeters
	var mm: Double { self / 1_000_000.0 }
}

extension Pt {

	func cg(_ scale: CGFloat, origin: CGPoint) -> CGPoint {
		CGPoint(
			x: origin.x + Double(x).mm * scale,
			y: origin.y + Double(y).mm * scale
		)
	}
}

extension Rect {

	func cg(_ scale: CGFloat, origin: CGPoint) -> CGRect {
		CGRect(
			origin: self.origin.cg(scale, origin: origin),
			size: size.cg * scale
		)
	}
}
