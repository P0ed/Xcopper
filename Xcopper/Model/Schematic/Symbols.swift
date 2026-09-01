import Foundation

extension Symbol {

	enum Kind: String, Codable, CaseIterable, Identifiable {
		case resistor, capacitor, inductor, diode, transistor, ic, power, ground

		var id: String { rawValue }

		var name: String {
			switch self {
			case .resistor: "Resistor"
			case .capacitor: "Capacitor"
			case .inductor: "Inductor"
			case .diode: "Diode"
			case .transistor: "Transistor"
			case .ic: "IC"
			case .power: "Power"
			case .ground: "Ground"
			}
		}

		var prefix: String {
			switch self {
			case .resistor: "R"
			case .capacitor: "C"
			case .inductor: "L"
			case .diode: "D"
			case .transistor: "Q"
			case .ic: "U"
			case .power, .ground: "#PWR"
			}
		}

		var hasPins: Bool { self == .ic }

		/// Power and ground flags name the net they touch instead of carrying a value
		var isPower: Bool { self == .power || self == .ground }

		var defaultValue: String {
			switch self {
			case .power: "VCC"
			case .ground: "GND"
			default: ""
			}
		}
	}

	struct Spec: Hashable, Codable {
		var kind: Kind = .resistor
		var pins: Int = 8
		var value: String = ""
		var component: Component?

		static var `default`: Spec { Spec() }

		var referencePrefix: String { component?.referencePrefix ?? kind.prefix }

		/// What the sidebar and the footprint dialog call a part drawn like this
		var summary: String {
			if let component { return component.name }

			return switch kind {
			case .ic: "IC-\(pins)"
			case .power, .ground: "\(kind.name) \(value.isEmpty ? kind.defaultValue : value)"
			default: kind.name
			}
		}
	}
}

extension Symbol {

	init(spec: Spec, reference: String, at: Pt) {
		if let component = spec.component {
			self = modifying(component.makeSymbol()) { symbol in
				symbol.reference = reference
				symbol.at = at
				symbol.value = spec.value.isEmpty ? component.name : spec.value
			}
			return
		}

		let built = switch spec.kind {
		case .resistor: Symbol.resistor()
		case .capacitor: Symbol.capacitor()
		case .inductor: Symbol.inductor()
		case .diode: Symbol.diode()
		case .transistor: Symbol.transistor()
		case .ic: Symbol.ic(pins: max(2, spec.pins))
		case .power: Symbol.power()
		case .ground: Symbol.ground()
		}

		self = modifying(built) { symbol in
			symbol.reference = reference
			symbol.at = at
			symbol.value = spec.value.isEmpty ? spec.kind.defaultValue : spec.value
		}
	}

	private static func make(_ kind: Kind, pins: [Pin], body: Rect, glyph: [Glyph]) -> Symbol {
		Symbol(
			reference: "",
			value: "",
			at: .zero,
			rotation: .r0,
			mirrored: false,
			kind: kind,
			pins: pins,
			body: body,
			glyph: glyph
		)
	}

	private static func centred(_ size: Size) -> Rect { Rect(center: .zero, size: size) }

	private static func pin(
		_ number: Int,
		_ name: String,
		_ x: Int,
		_ y: Int,
		_ direction: Rotation,
		_ length: Nm = .mm(2.54)
	) -> Pin {
		Pin(at: Pt(x: x, y: y), direction: direction, length: length, name: name, number: "\(number)")
	}

	static func resistor() -> Symbol {
		let half = Int.mm(2.54)
		return make(
			.resistor,
			pins: [pin(1, "1", -half * 2, 0, .r180), pin(2, "2", half * 2, 0, .r0)],
			body: centred(Size(width: half * 2, height: .mm(1.778))),
			glyph: [.rect(Rect(center: .zero, size: Size(width: half * 2, height: .mm(1.778))))]
		)
	}

	static func capacitor() -> Symbol {
		let gap = Int.mm(0.635)
		let plate = Int.mm(1.27)
		return make(
			.capacitor,
			pins: [
				pin(1, "1", -.mm(2.54), 0, .r180, .mm(1.905)),
				pin(2, "2", .mm(2.54), 0, .r0, .mm(1.905)),
			],
			body: centred(Size(width: gap * 2, height: plate * 2)),
			glyph: [
				.path([Pt(x: -gap, y: -plate), Pt(x: -gap, y: plate)], closed: false, filled: false),
				.path([Pt(x: gap, y: -plate), Pt(x: gap, y: plate)], closed: false, filled: false),
			]
		)
	}

	static func inductor() -> Symbol {
		let radius = Int.mm(0.635)
		let humps = 4
		var points: [Pt] = []

		for hump in 0 ..< humps {
			let center = -(humps - 1) * radius + hump * radius * 2
			for step in 0 ... 8 {
				let angle = Double.pi * Double(step) / 8.0
				points.append(Pt(
					x: center - Int(Double(radius) * cos(angle)),
					y: -Int(Double(radius) * sin(angle))
				))
			}
		}
		let half = humps * radius
		return make(
			.inductor,
			pins: [pin(1, "1", -half * 2, 0, .r180), pin(2, "2", half * 2, 0, .r0)],
			body: centred(Size(width: half * 2, height: radius * 2)),
			glyph: [.path(points, closed: false, filled: false)]
		)
	}

	static func diode() -> Symbol {
		let half = Int.mm(1.27)
		return make(
			.diode,
			pins: [pin(1, "A", -half * 3, 0, .r180), pin(2, "K", half * 3, 0, .r0)],
			body: centred(Size(width: half * 2, height: half * 2)),
			glyph: [
				.path(
					[Pt(x: -half, y: -half), Pt(x: -half, y: half), Pt(x: half, y: 0)],
					closed: true,
					filled: true
				),
				.path([Pt(x: half, y: -half), Pt(x: half, y: half)], closed: false, filled: false),
			]
		)
	}

	static func transistor() -> Symbol {
		let base = Int.mm(1.27)
		let reach = Int.mm(2.54)
		return make(
			.transistor,
			pins: [
				pin(1, "B", -.mm(5.08), 0, .r180, .mm(3.81)),
				pin(2, "E", reach, .mm(5.08), .r90, .mm(2.54)),
				pin(3, "C", reach, -.mm(5.08), .r270, .mm(2.54)),
			],
			body: centred(Size(width: .mm(5.08), height: .mm(5.08))),
			glyph: [
				.circle(.zero, .mm(5.08)),
				.path(
					[Pt(x: -base, y: -.mm(1.524)), Pt(x: -base, y: .mm(1.524))],
					closed: false,
					filled: false
				),
				.path(
					[Pt(x: -base, y: -.mm(0.762)), Pt(x: reach, y: -reach)],
					closed: false,
					filled: false
				),
				.path(
					[Pt(x: -base, y: .mm(0.762)), Pt(x: reach, y: reach)],
					closed: false,
					filled: false
				),
			]
		)
	}

	static func ic(pins count: Int) -> Symbol {
		ic(pinNames: (1 ... count).map { "\($0)" })
	}

	static func ic(pinNames: [String]) -> Symbol {
		let pitch = Int.mm(2.54)
		let count = pinNames.count
		let perSide = (count + 1) / 2
		let width = icWidth(pinNames, perSide: perSide)
		let height = (perSide + 1) * pitch
		let first = -(perSide - 1) * pitch / 2
		var pins: [Pin] = []

		for index in 0 ..< perSide {
			pins.append(pin(index + 1, pinNames[index], -width / 2 - pitch, first + index * pitch, .r180))
		}
		for index in perSide ..< count {
			let row = count - 1 - index
			pins.append(pin(index + 1, pinNames[index], width / 2 + pitch, first + row * pitch, .r0))
		}
		return make(
			.ic,
			pins: pins,
			body: centred(Size(width: width, height: height)),
			glyph: [.rect(Rect(center: .zero, size: Size(width: width, height: height)))]
		)
	}

	private static func icWidth(_ pinNames: [String], perSide: Int) -> Int {
		let pitch = Int.mm(2.54)

		func column(_ pins: Range<Int>) -> Int {
			pins.reduce(0) { widest, index in
				guard pinNames[index] != "\(index + 1)" else { return widest }
				return max(widest, PinText.width(pinNames[index]))
			}
		}
		let needed = column(0 ..< perSide)
			+ column(perSide ..< pinNames.count)
			+ PinText.inset * 2
			+ pitch
		return max(Int.mm(12.7), (needed + pitch - 1) / pitch * pitch)
	}

	static func power() -> Symbol {
		let bar = Int.mm(1.27)
		let stem = Int.mm(2.54)
		return make(
			.power,
			pins: [pin(1, "1", 0, 0, .r90, .mm(2.54))],
			body: Rect(center: Pt(x: 0, y: -stem / 2), size: Size(width: bar * 2, height: stem)),
			glyph: [.path([Pt(x: -bar, y: -stem), Pt(x: bar, y: -stem)], closed: false, filled: false)]
		)
	}

	static func ground() -> Symbol {
		let stem = Int.mm(2.54)
		let step = Int.mm(0.635)
		return make(
			.ground,
			pins: [pin(1, "1", 0, 0, .r270, .mm(2.54))],
			body: Rect(
				center: Pt(x: 0, y: (stem + step * 2) / 2),
				size: Size(width: .mm(3.81), height: stem + step * 2)
			),
			glyph: (0 ..< 3).map { row in
				let half = Int.mm(1.905) - row * step
				let y = stem + row * step
				return .path([Pt(x: -half, y: y), Pt(x: half, y: y)], closed: false, filled: false)
			}
		)
	}
}
