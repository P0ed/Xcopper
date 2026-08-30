extension Footprint {

	enum Kind: String, Codable, CaseIterable, Identifiable {
		case chip, soic, sot23, dip, header

		var id: String { rawValue }

		var name: String {
			switch self {
			case .chip: "Chip"
			case .soic: "SOIC"
			case .sot23: "SOT-23"
			case .dip: "DIP"
			case .header: "Header"
			}
		}

		var prefix: String {
			switch self {
			case .chip: "R"
			case .soic, .sot23, .dip: "U"
			case .header: "J"
			}
		}

		var hasPins: Bool { self != .chip && self != .sot23 }
		var hasRows: Bool { self == .header }
		var hasChip: Bool { self == .chip }
	}

	enum Chip: String, Codable, CaseIterable, Identifiable {
		case c0402, c0603, c0805, c1206

		var id: String { rawValue }
		var name: String { String(rawValue.dropFirst()) }

		/// Pad size and center offset from the origin
		var metrics: (pad: Size, offset: Int, body: Size) {
			switch self {
			case .c0402: (Size(width: .mm(0.6), height: .mm(0.6)), .mm(0.5), Size(width: .mm(1.0), height: .mm(0.5)))
			case .c0603: (Size(width: .mm(0.9), height: .mm(0.95)), .mm(0.8), Size(width: .mm(1.6), height: .mm(0.8)))
			case .c0805: (Size(width: .mm(1.15), height: .mm(1.4)), .mm(1.0), Size(width: .mm(2.0), height: .mm(1.25)))
			case .c1206: (Size(width: .mm(1.15), height: .mm(1.75)), .mm(1.5), Size(width: .mm(3.2), height: .mm(1.6)))
			}
		}
	}

	struct Spec: Hashable, Codable {
		var kind: Kind = .chip
		var chip: Chip = .c1206
		var pins: Int = 8
		var rows: Int = 1

		static var `default`: Spec { Spec() }
	}
}

extension Footprint {

	init(spec: Footprint.Spec, reference: String, at: Pt) {
		let built = switch spec.kind {
		case .chip: Footprint.chip(spec.chip)
		case .soic: Footprint.soic(pins: max(2, spec.pins & ~1))
		case .sot23: Footprint.sot23()
		case .dip: Footprint.dip(pins: max(2, spec.pins & ~1))
		case .header: Footprint.header(pins: max(1, spec.pins), rows: max(1, min(2, spec.rows)))
		}

		self = modifying(built) { footprint in
			footprint.reference = reference
			footprint.at = at
		}
	}

	private static func make(pads: [Pad], body: Size) -> Footprint {
		Footprint(
			reference: "",
			value: "",
			at: .zero,
			rotation: .r0,
			flipped: false,
			pads: pads,
			body: Rect(center: .zero, size: body)
		)
	}

	private static func smd(_ name: Int, _ x: Int, _ y: Int, _ size: Size) -> Pad {
		Pad(
			at: Pt(x: x, y: y),
			size: size,
			shape: .rect,
			drill: 0,
			layer: 0,
			name: "\(name)",
			net: nil
		)
	}

	private static func through(_ name: Int, _ x: Int, _ y: Int, drill: Nm, pad: Nm) -> Pad {
		Pad(
			at: Pt(x: x, y: y),
			size: Size(width: Int(pad), height: Int(pad)),
			shape: name == 1 ? .rect : .oval,
			drill: drill,
			layer: 0,
			name: "\(name)",
			net: nil
		)
	}

	static func chip(_ chip: Chip) -> Footprint {
		let metrics = chip.metrics
		return make(
			pads: [
				smd(1, -metrics.offset, 0, metrics.pad),
				smd(2, metrics.offset, 0, metrics.pad),
			],
			body: metrics.body
		)
	}

	static func soic(pins: Int) -> Footprint {
		let pitch = Int.mm(1.27)
		let span = Int.mm(5.2)
		let size = Size(width: .mm(1.55), height: .mm(0.6))
		let perSide = pins / 2
		let first = -(perSide - 1) * pitch / 2

		let pads = (0 ..< perSide).flatMap { index in
			[
				smd(index + 1, -span / 2, first + index * pitch, size),
				smd(pins - index, span / 2, first + index * pitch, size),
			]
		}
		return make(
			pads: pads.sorted { Int($0.name) ?? 0 < Int($1.name) ?? 0 },
			body: Size(width: .mm(3.9), height: (perSide - 1) * pitch + .mm(1.2))
		)
	}

	static func sot23() -> Footprint {
		let size = Size(width: .mm(1.0), height: .mm(0.6))
		let span = Int.mm(2.6)
		let pitch = Int.mm(0.95)
		return make(
			pads: [
				smd(1, -span / 2, -pitch, size),
				smd(2, -span / 2, pitch, size),
				smd(3, span / 2, 0, size),
			],
			body: Size(width: .mm(1.3), height: .mm(2.9))
		)
	}

	static func dip(pins: Int) -> Footprint {
		let pitch = Int.mm(2.54)
		let span = Int.mm(7.62)
		let perSide = pins / 2
		let first = -(perSide - 1) * pitch / 2

		let pads = (0 ..< perSide).flatMap { index in
			[
				through(index + 1, -span / 2, first + index * pitch, drill: .mm(0.8), pad: .mm(1.6)),
				through(pins - index, span / 2, first + index * pitch, drill: .mm(0.8), pad: .mm(1.6)),
			]
		}
		return make(
			pads: pads.sorted { Int($0.name) ?? 0 < Int($1.name) ?? 0 },
			body: Size(width: .mm(6.4), height: (perSide - 1) * pitch + .mm(2.54))
		)
	}

	static func header(pins: Int, rows: Int) -> Footprint {
		let pitch = Int.mm(2.54)
		let first = -(pins - 1) * pitch / 2
		let column = (rows - 1) * pitch / 2

		let pads = (0 ..< pins).flatMap { index in
			(0 ..< rows).map { row in
				through(
					index * rows + row + 1,
					-column + row * pitch,
					first + index * pitch,
					drill: .mm(1.0),
					pad: .mm(1.7)
				)
			}
		}
		return make(
			pads: pads,
			body: Size(width: rows * pitch, height: pins * pitch)
		)
	}
}
