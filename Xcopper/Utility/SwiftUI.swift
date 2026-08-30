import SwiftUI

extension Figure {

	func path(_ scale: CGFloat, origin: CGPoint) -> Path {
		switch self {
		case let .rect(rect):
			Path(rect.cg(scale, origin: origin))
		case let .round(center, diameter):
			Path(ellipseIn: CGRect(
				center: center.cg(scale, origin: origin),
				radius: Double(diameter).mm * scale / 2.0
			))
		case let .segment(start, end, width):
			Path { path in
				path.move(to: start.cg(scale, origin: origin))
				path.addLine(to: end.cg(scale, origin: origin))
			}
			.strokedPath(StrokeStyle(
				lineWidth: Double(width).mm * scale,
				lineCap: .round,
				lineJoin: .round
			))
		}
	}
}

extension CGRect {

	init(center: CGPoint, radius: CGFloat) {
		self.init(
			x: center.x - radius,
			y: center.y - radius,
			width: radius * 2.0,
			height: radius * 2.0
		)
	}
}
