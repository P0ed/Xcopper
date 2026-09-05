import SwiftUI

struct Viewport: Equatable {
	var cursor: Pt = .zero
	var size: CGSize = .zero
	var frame: CGRect = .zero
	var scrollPosition: ScrollPosition = .init(point: .zero)
	var magnification: CGFloat = 2.0
	var pending: Pt?
}

extension Viewport {

	func visibleRect(in contentSize: CGSize) -> CGRect {
		guard size.width > 0.0, size.height > 0.0, !frame.isEmpty else {
			return CGRect(origin: .zero, size: contentSize)
		}
		return CGRect(
			x: max(0.0, -frame.minX),
			y: max(0.0, -frame.minY),
			width: size.width,
			height: size.height
		).intersection(CGRect(origin: .zero, size: contentSize))
	}

	mutating func setScale(_ scale: CGFloat) {
		let scale = min(max(scale, 2.0), 256.0)
		let frame = frame
		let size = size
		let dm = scale / magnification
		let ds = CGVector(
			dx: frame.width - size.width,
			dy: frame.height - size.height
		)
		let progress = CGVector(
			dx: ds.dx > 0.0 ? (size.width * 0.5 - frame.minX) / frame.width : 0.5,
			dy: ds.dy > 0.0 ? (size.height * 0.5 - frame.minY) / frame.height : 0.5,
		)
		let offset = CGPoint(
			x: (frame.width * dm * progress.dx - size.width * 0.5),
			y: (frame.height * dm * progress.dy - size.height * 0.5)
		)

		magnification = scale
		scrollPosition = .init(point: offset)
	}

	mutating func fit(_ size: Size) {
		setScale(size.zoomToFit(self.size, margin: Layout.margin))
	}

	mutating func reveal(_ point: Pt) {
		pending = point
	}

	mutating func revealPending(in content: Size) {
		guard let point = pending, size.width > 0.0, size.height > 0.0 else { return }
		pending = nil

		let full = Layout.contentSize(content, scale: magnification)
		let at = point.cg(magnification, origin: Layout.origin)
		scrollPosition = .init(point: CGPoint(
			x: min(max(at.x - size.width / 2.0, 0.0), max(full.width - size.width, 0.0)),
			y: min(max(at.y - size.height / 2.0, 0.0), max(full.height - size.height, 0.0))
		))
	}
}
