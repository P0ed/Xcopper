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

		var defaultDevice: Device {
			switch self {
			case .chip: .resistor
			case .soic, .dip: .ic
			case .sot23: .transistor
			case .header: .connector
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

		var metrics: (pad: Size, offset: Int, body: Size) {
			switch self {
			case .c0402: (Size(width: 600, height: 600), 500, Size(width: 1 * .mm, height: 500))
			case .c0603: (Size(width: 900, height: 950), 800, Size(width: 1_600, height: 800))
			case .c0805: (Size(width: 1_150, height: 1_400), 1 * .mm, Size(width: 2 * .mm, height: 1_250))
			case .c1206: (Size(width: 1_150, height: 1_750), 1_500, Size(width: 3_200, height: 1_600))
			}
		}
	}

	struct Spec: Hashable, Codable {
		var kind: Kind
		var chip: Chip
		var device: Device
		var pins: Int
		var rows: Int
		var component: Component?

		init(kind: Kind = .chip, chip: Chip = .c1206, device: Device? = nil, pins: Int = 8, rows: Int = 1, component: Component? = nil) {
			self.kind = kind
			self.chip = chip
			self.device = device ?? kind.defaultDevice
			self.pins = pins
			self.rows = rows
			self.component = component
		}

		static var `default`: Spec { Spec() }

		var referencePrefix: String { component?.referencePrefix ?? device.prefix }

		var package: Package {
			if let component { return component.package }
			return switch kind {
			case .chip: .chip(chip)
			case .soic: .soic(max(2, pins & ~1))
			case .sot23: .sot23
			case .dip: .dip(max(2, pins & ~1))
			case .header: .header(pins: max(1, pins), rows: max(1, min(2, rows)))
			}
		}

		var summary: String {
			if component == nil, kind == .chip { return "\(device.name) \(chip.name)" }
			return package.name
		}
	}
}

extension Footprint {

	init(spec: Footprint.Spec, reference: String, at: Point) {
		guard let built = spec.package.makeFootprint() else {
			preconditionFailure("\(spec.package.name) has no generated footprint")
		}
		self = modifying(built) { footprint in
			footprint.reference = reference
			footprint.at = at
			footprint.device = spec.component?.device ?? spec.device
			footprint.component = spec.component
			footprint.value = spec.component?.name ?? ""
		}
	}

	private static func make(_ package: Package, pads: [Pad], body: Size) -> Footprint {
		Footprint(
			reference: "",
			value: "",
			at: .zero,
			rotation: .r0,
			flipped: false,
			pads: pads,
			body: Rect(center: .zero, size: body),
			package: package
		)
	}

	private static func smd(_ name: Int, _ x: Int, _ y: Int, _ size: Size) -> Pad {
		Pad(
			at: Point(x: x, y: y),
			size: size,
			shape: .rect,
			drill: 0,
			layer: 0,
			name: "\(name)",
			net: nil
		)
	}

	private static func through(_ name: Int, _ x: Int, _ y: Int, drill: µm, pad: µm) -> Pad {
		Pad(
			at: Point(x: x, y: y),
			size: Size(width: Int(pad), height: Int(pad)),
			shape: .oval,
			drill: drill,
			layer: 0,
			name: "\(name)",
			net: nil
		)
	}

	static func chip(_ chip: Chip) -> Footprint {
		let metrics = chip.metrics
		return make(
			.chip(chip),
			pads: [
				smd(1, -metrics.offset, 0, metrics.pad),
				smd(2, metrics.offset, 0, metrics.pad),
			],
			body: metrics.body
		)
	}

	static func soic(pins: Int) -> Footprint {
		let pitch = 1_270
		let span = 5_200
		let size = Size(width: 1_550, height: 600)
		let perSide = pins / 2
		let first = -(perSide - 1) * pitch / 2

		let pads = (0 ..< perSide).flatMap { index in
			[
				smd(index + 1, -span / 2, first + index * pitch, size),
				smd(pins - index, span / 2, first + index * pitch, size),
			]
		}
		return make(
			.soic(pins),
			pads: pads.sorted { Int($0.name) ?? 0 < Int($1.name) ?? 0 },
			body: Size(width: 3_900, height: (perSide - 1) * pitch + 1_200)
		)
	}

	static func sot23() -> Footprint {
		let size = Size(width: 1 * .mm, height: 600)
		let span = 2_600
		let pitch = 950
		return make(
			.sot23,
			pads: [
				smd(1, -span / 2, -pitch, size),
				smd(2, -span / 2, pitch, size),
				smd(3, span / 2, 0, size),
			],
			body: Size(width: 1_300, height: 2_900)
		)
	}

	static func dip(pins: Int) -> Footprint {
		let pitch = 2_540
		let span = 7_620
		let perSide = pins / 2
		let first = -(perSide - 1) * pitch / 2

		let pads = (0 ..< perSide).flatMap { index in
			[
				through(index + 1, -span / 2, first + index * pitch, drill: 800, pad: 1_600),
				through(pins - index, span / 2, first + index * pitch, drill: 800, pad: 1_600),
			]
		}
		return make(
			.dip(pins),
			pads: pads.sorted { Int($0.name) ?? 0 < Int($1.name) ?? 0 },
			body: Size(width: 6_400, height: (perSide - 1) * pitch + 2_540)
		)
	}

	static func header(pins: Int, rows: Int) -> Footprint {
		let pitch = 2_540
		let first = -(pins - 1) * pitch / 2
		let column = (rows - 1) * pitch / 2

		let pads = (0 ..< pins).flatMap { index in
			(0 ..< rows).map { row in
				through(
					index * rows + row + 1,
					-column + row * pitch,
					first + index * pitch,
					drill: 1 * .mm,
					pad: 1_700
				)
			}
		}
		return make(
			.header(pins: pins, rows: rows),
			pads: pads,
			body: Size(width: rows * pitch, height: pins * pitch)
		)
	}

	static func ssop10() -> Footprint {
		let pitch = 1 * .mm
		let span = 5_200
		let size = Size(width: 1_550, height: 550)
		let first = -2 * pitch
		let pads = (0 ..< 5).flatMap { index in
			[
				smd(index + 1, -span / 2, first + index * pitch, size),
				smd(10 - index, span / 2, first + index * pitch, size),
			]
		}
		return make(
			.ssop10,
			pads: pads.sorted { Int($0.name) ?? 0 < Int($1.name) ?? 0 },
			body: Size(width: 3_900, height: 4_900)
		)
	}

	static func sip(pins: Int) -> Footprint {
		let pitch = 2_540
		let first = -(pins - 1) * pitch / 2
		return make(
			.sip(pins),
			pads: (0 ..< pins).map { index in
				through(index + 1, 0, first + index * pitch, drill: 900, pad: 1_700)
			},
			body: Size(width: 2_800, height: max(5_800, (pins - 1) * pitch + 1_700))
		)
	}

	static func mta156(pins: Int) -> Footprint {
		let pitch = 3_960
		let first = -(pins - 1) * pitch / 2
		return make(
			.mta156(pins),
			pads: (0 ..< pins).map { index in
				through(index + 1, 0, first + index * pitch, drill: 1_800, pad: 2_800)
			},
			body: Size(width: 9 * .mm, height: pins * pitch)
		)
	}

	static func led5mm() -> Footprint {
		make(
			.led5mm,
			pads: [
				through(1, 0, -1_270, drill: 800, pad: 1_700),
				through(2, 0, 1_270, drill: 800, pad: 1_700),
			],
			body: Size(width: 5_800, height: 5_800)
		)
	}

	static func sod123() -> Footprint {
		make(
			.sod123,
			pads: [
				smd(1, -1_650, 0, Size(width: 1_200, height: 1_200)),
				smd(2, 1_650, 0, Size(width: 1_200, height: 1_200)),
			],
			body: Size(width: 2_700, height: 1_600)
		)
	}

	static func sot457() -> Footprint {
		let size = Size(width: 900, height: 550)
		let span = 2_600
		let pitch = 950
		return make(
			.sot457,
			pads: [
				smd(1, -span / 2, -pitch, size),
				smd(2, -span / 2, 0, size),
				smd(3, -span / 2, pitch, size),
				smd(4, span / 2, pitch, size),
				smd(5, span / 2, 0, size),
				smd(6, span / 2, -pitch, size),
			],
			body: Size(width: 1_700, height: 3 * .mm)
		)
	}

	static func bourns51() -> Footprint {
		let pitch = 2_540
		return make(
			.bourns51,
			pads: (0 ..< 3).map { index in
				through(
					index + 1,
					(index - 1) * pitch,
					-7_500,
					drill: 900,
					pad: 1_800
				)
			},
			body: Size(width: 12_500, height: 14 * .mm)
		)
	}

	func copper(in stack: Stack) -> [Trace] {
		guard package == .pomona1581, pads.count >= 2 else { return [] }
		return [stack.top, stack.bottom].map { layer in
			Trace(start: place(pads[0].at), end: place(pads[1].at), width: 2 * .mm, layer: layer, net: pads[0].net)
		}
	}

	static func pomona1581() -> Footprint {
		make(
			.pomona1581,
			pads: [
				Pad(
					at: .zero,
					size: Size(width: 10 * .mm, height: 10 * .mm),
					shape: .oval,
					drill: 6_350,
					layer: 0,
					name: "1",
					net: nil
				),
				Pad(
					at: Point(x: 0, y: 6_000),
					size: Size(width: 2 * .mm, height: 2 * .mm),
					shape: .oval,
					drill: 1 * .mm,
					layer: 0,
					name: "1",
					net: nil
				),
			],
			body: Size(width: 10 * .mm, height: 12 * .mm)
		)
	}

	static func nkkMNPC() -> Footprint {
		let pitch = 4_700
		return make(
			.nkkMNPC,
			pads: (0 ..< 3).map { index in
				through(index + 1, 0, (index - 1) * pitch, drill: 1_600, pad: 2_800)
			},
			body: Size(width: 7_900, height: 13 * .mm)
		)
	}
}
