import Foundation

extension Symbol {

	enum Kind: String, Codable, CaseIterable, Identifiable {
		case resistor, capacitor, inductor, diode, transistor, ic

		var id: String { rawValue }

		var name: String {
			switch self {
			case .resistor: "Resistor"
			case .capacitor: "Capacitor"
			case .inductor: "Inductor"
			case .diode: "Diode"
			case .transistor: "Transistor"
			case .ic: "IC"
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
			}
		}

		var hasPins: Bool { self == .ic }

		var showsPinNumbers: Bool {
			switch self {
			case .capacitor, .resistor: false
			default: true
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

		var summary: String {
			if let component { return component.name }

			return switch kind {
			case .ic: "IC-\(pins)"
			default: kind.name
			}
		}
	}
}

extension Symbol {

	init(spec: Spec, reference: String, at: Point) {
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
		}

		self = modifying(built) { symbol in
			symbol.reference = reference
			symbol.at = at
			symbol.value = spec.value
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
		_ length: µm = 2_540
	) -> Pin {
		Pin(at: Point(x: x, y: y), direction: direction, length: length, name: name, number: "\(number)")
	}

	static func resistor() -> Symbol {
		let half = 2_540
		return make(
			.resistor,
			pins: [pin(1, "1", -half * 2, 0, .r180), pin(2, "2", half * 2, 0, .r0)],
			body: centred(Size(width: half * 2, height: 1_778)),
			glyph: [.rect(Rect(center: .zero, size: Size(width: half * 2, height: 1_778)))]
		)
	}

	static func capacitor() -> Symbol {
		let gap = 635
		let plate = 1_270
		return make(
			.capacitor,
			pins: [
				pin(1, "1", -2_540, 0, .r180, 1_905),
				pin(2, "2", 2_540, 0, .r0, 1_905),
			],
			body: centred(Size(width: gap * 2, height: plate * 2)),
			glyph: [
				.path([Point(x: -gap, y: -plate), Point(x: -gap, y: plate)], closed: false, filled: false),
				.path([Point(x: gap, y: -plate), Point(x: gap, y: plate)], closed: false, filled: false),
			]
		)
	}

	static func inductor() -> Symbol {
		let radius = 635
		let humps = 4
		var points: [Point] = []

		for hump in 0 ..< humps {
			let center = -(humps - 1) * radius + hump * radius * 2
			for step in 0 ... 8 {
				let angle = Double.pi * Double(step) / 8.0
				points.append(Point(
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
		let half = 1_270
		return make(
			.diode,
			pins: [pin(1, "A", -half * 3, 0, .r180), pin(2, "K", half * 3, 0, .r0)],
			body: centred(Size(width: half * 2, height: half * 2)),
			glyph: [
				.path(
					[Point(x: -half, y: -half), Point(x: -half, y: half), Point(x: half, y: 0)],
					closed: true,
					filled: true
				),
				.path([Point(x: half, y: -half), Point(x: half, y: half)], closed: false, filled: false),
			]
		)
	}

	static func transistor() -> Symbol {
		let base = 1_270
		let reach = 2_540
		return make(
			.transistor,
			pins: [
				pin(1, "B", -5_080, 0, .r180, 3_810),
				pin(2, "E", reach, 5_080, .r90, 2_540),
				pin(3, "C", reach, -5_080, .r270, 2_540),
			],
			body: centred(Size(width: 5_080, height: 5_080)),
			glyph: [
				.circle(.zero, 5_080),
				.path(
					[Point(x: -base, y: -1_524), Point(x: -base, y: 1_524)],
					closed: false,
					filled: false
				),
				.path(
					[Point(x: -base, y: -762), Point(x: reach, y: -reach)],
					closed: false,
					filled: false
				),
				.path(
					[Point(x: -base, y: 762), Point(x: reach, y: reach)],
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
		let pitch = 2_540
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
		let pitch = 2_540

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
		return max(12_700, (needed + pitch - 1) / pitch * pitch)
	}
}
