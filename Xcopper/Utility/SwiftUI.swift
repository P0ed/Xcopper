import SwiftUI

@MainActor
extension UndoManager {
	func undoGroup(_ name: String, _ action: () -> Void) {
		beginUndoGrouping()
		defer { endUndoGrouping() }
		action()
		setActionName(name)
	}
}

@MainActor
extension UndoManager? {
	func undoGroup(_ name: String, _ action: () -> Void) {
		if let self { self.undoGroup(name, action) }
		else { action() }
	}
}

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

extension Glyph {

	func path(_ scale: CGFloat, origin: CGPoint) -> Path {
		switch self {
		case let .path(points, closed, _):
			Path { path in
				guard let first = points.first else { return }
				path.move(to: first.cg(scale, origin: origin))
				for point in points.dropFirst() {
					path.addLine(to: point.cg(scale, origin: origin))
				}
				if closed { path.closeSubpath() }
			}
		case let .rect(rect):
			Path(rect.cg(scale, origin: origin))
		case let .circle(center, diameter):
			Path(ellipseIn: CGRect(
				center: center.cg(scale, origin: origin),
				radius: Double(diameter).mm * scale / 2.0
			))
		}
	}

	var isFilled: Bool {
		if case let .path(_, _, filled) = self { filled } else { false }
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

extension Binding {

	subscript<Element: Sendable>(index: Int, or fallback: Element) -> Binding<Element>
	where Value == [Element] {
		Binding<Element>(
			get: { wrappedValue.indices.contains(index) ? wrappedValue[index] : fallback },
			set: { element in
				guard wrappedValue.indices.contains(index) else { return }
				wrappedValue[index] = element
			}
		)
	}

	func shared<Element: Sendable, Field: Equatable & Sendable>(
		_ indices: [Int],
		_ field: WritableKeyPath<Element, Field> & Sendable
	) -> Binding<Field?> where Value == [Element] {
		Binding<Field?>(
			get: {
				let elements = wrappedValue
				return indices
					.compactMap { index in
						elements.indices.contains(index) ? elements[index][keyPath: field] : nil
					}
					.shared
			},
			set: { value in
				guard let value else { return }
				wrappedValue = modifying(wrappedValue) { elements in
					for index in indices where elements.indices.contains(index) {
						elements[index][keyPath: field] = value
					}
				}
			}
		)
	}
}

extension Binding where Value == String? {
	var orEmpty: Binding<String> {
		Binding<String>(get: { wrappedValue ?? "" }, set: { wrappedValue = $0 })
	}
}
