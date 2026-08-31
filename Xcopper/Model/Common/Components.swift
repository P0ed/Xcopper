import Foundation

/// Built-in, manufacturer-specific parts. Pin names and package choices follow
/// the manufacturers' data sheets; package variants prefer SOIC when offered.
enum Component: String, Codable, CaseIterable, Identifiable {
	case ad823 = "AD823"
	case ad823a = "AD823A"
	case ad633 = "AD633"
	case adr5045 = "ADR5045"
	case adg419 = "ADG419"
	case cd4013 = "CD4013"
	case cd4029 = "CD4029"
	case cd4070 = "CD4070"
	case cd4093 = "CD4093"
	case cd40106 = "CD40106"
	case ssi2162 = "SSI2162"
	case that2180 = "THAT2180"
	case pomona1581 = "Pomona 1581"
	case bourns51 = "Bourns 51"
	case mta1563 = "MTA-156-3"
	case mta1564 = "MTA-156-4"
	case hlmpWL02 = "HLMP-WL02"
	case nkkMN12 = "NKK MN12"
	case nkkMN15 = "NKK MN15"
	case oneN4148W = "1N4148W"
	case bcm847DS = "BCM847DS"
	case bcm857DS = "BCM857DS"
	case ssm2212 = "SSM2212"

	var id: String { rawValue }
	var name: String { rawValue }

	var referencePrefix: String {
		switch self {
		case .pomona1581, .mta1563, .mta1564: "J"
		case .bourns51: "RV"
		case .hlmpWL02, .oneN4148W: "D"
		case .nkkMN12, .nkkMN15: "SW"
		case .bcm847DS, .bcm857DS, .ssm2212: "Q"
		default: "U"
		}
	}

	var symbolKind: Symbol.Kind {
		switch self {
		case .hlmpWL02, .oneN4148W: .diode
		default: .ic
		}
	}

	/// Pin names in physical pin-number order, starting at pin 1.
	var pinNames: [String] {
		switch self {
		case .ad823, .ad823a:
			["OUT1", "-IN1", "+IN1", "-VS", "+IN2", "-IN2", "OUT2", "+VS"]
		case .ad633:
			// AD633 has different SOIC and PDIP pinouts; this is the SOIC variant.
			["Y1", "Y2", "-VS", "Z", "W", "+VS", "X1", "X2"]
		case .adr5045:
			["V+", "V-", "T"]
		case .adg419:
			["D", "S1", "GND", "VDD", "VL", "IN", "VSS", "S2"]
		case .cd4013:
			["Q1", "/Q1", "CLOCK1", "RESET1", "D1", "SET1", "VSS", "SET2", "D2", "RESET2", "CLOCK2", "/Q2", "Q2", "VDD"]
		case .cd4029:
			["PRESET ENABLE", "Q4", "J4", "J1", "CARRY IN", "Q1", "CARRY OUT", "VSS", "BINARY/DECADE", "UP/DOWN", "Q2", "J2", "J3", "Q3", "CLOCK", "VDD"]
		case .cd4070:
			["A", "B", "J", "K", "C", "D", "VSS", "E", "F", "L", "M", "G", "H", "VDD"]
		case .cd4093:
			["A", "B", "J", "K", "C", "D", "VSS", "E", "F", "L", "M", "G", "H", "VDD"]
		case .cd40106:
			["A", "G (/A)", "B", "H (/B)", "C", "I (/C)", "VSS", "J (/D)", "D", "K (/E)", "E", "L (/F)", "F", "VDD"]
		case .ssi2162:
			["MODE", "IIN1", "VC1", "IOUT1", "GND", "V-", "IOUT2", "VC2", "IIN2", "V+"]
		case .that2180:
			["INPUT", "EC+", "EC-", "SYM", "V-", "GND", "V+", "OUTPUT"]
		case .pomona1581:
			["JACK"]
		case .bourns51:
			["CCW", "WIPER", "CW"]
		case .mta1563:
			["1", "2", "3"]
		case .mta1564:
			["1", "2", "3", "4"]
		case .hlmpWL02, .oneN4148W:
			["K", "A"]
		case .nkkMN12, .nkkMN15:
			["THROW 1", "COM", "THROW 2"]
		case .bcm847DS, .bcm857DS:
			["E1", "B1", "C2", "E2", "B2", "C1"]
		case .ssm2212:
			["C1", "B1", "E1", "NIC", "NIC", "E2", "B2", "C2"]
		}
	}

	var packageName: String {
		switch package {
		case let .soic(pins): "SOIC-\(pins)"
		case .sot23: "SOT-23"
		case .ssop10: "SSOP-10, 1.00 mm pitch"
		case .sip8: "SIP-8"
		case let .mta156(pins): "MTA-156, \(pins)-position"
		case .led5mm: "T-1 3/4 (5 mm)"
		case .sod123: "SOD-123"
		case .sot457: "SOT-457 (SC-74)"
		case .pomona1581: "Panel mount, 6.35 mm ring + wire hole"
		case .bourns51: "Bourns 51, horizontal PC pins"
		case .nkkMNPC: "NKK G03 straight PC pins, 4.7 mm pitch"
		}
	}

	var hasFootprint: Bool { true }

	static var layoutCases: [Component] { allCases.filter(\.hasFootprint) }

	func makeSymbol() -> Symbol {
		var symbol: Symbol
		switch symbolKind {
		case .diode:
			symbol = .diode()
			// The schematic anode remains on the left and cathode bar on the
			// right, while SOD-123 and 5 mm LEDs number K=1 and A=2.
			symbol.pins[0].name = "A"
			symbol.pins[0].number = "2"
			symbol.pins[1].name = "K"
			symbol.pins[1].number = "1"
		default:
			symbol = .ic(pinNames: pinNames)
		}
		symbol.value = name
		return symbol
	}

	func makeFootprint() -> Footprint? {
		let footprint: Footprint
		switch package {
		case let .soic(pins): footprint = .soic(pins: pins)
		case .sot23: footprint = .sot23()
		case .ssop10: footprint = .ssop10()
		case .sip8: footprint = .sip(pins: 8)
		case let .mta156(pins): footprint = .mta156(pins: pins)
		case .led5mm: footprint = .led5mm()
		case .sod123: footprint = .sod123()
		case .sot457: footprint = .sot457()
		case .pomona1581: footprint = .pomona1581()
		case .bourns51: footprint = .bourns51()
		case .nkkMNPC: footprint = .nkkMNPC()
		}
		return modifying(footprint) { $0.value = name }
	}

	private enum Package {
		case soic(Int)
		case sot23
		case ssop10
		case sip8
		case mta156(Int)
		case led5mm
		case sod123
		case sot457
		case pomona1581
		case bourns51
		case nkkMNPC
	}

	private var package: Package {
		switch self {
		case .ad823, .ad823a, .ad633, .adg419, .ssm2212: .soic(8)
		case .cd4013, .cd4070, .cd4093, .cd40106: .soic(14)
		case .cd4029: .soic(16)
		case .adr5045: .sot23
		case .ssi2162: .ssop10
		case .that2180: .sip8
		case .pomona1581: .pomona1581
		case .bourns51: .bourns51
		case .nkkMN12, .nkkMN15: .nkkMNPC
		case .mta1563: .mta156(3)
		case .mta1564: .mta156(4)
		case .hlmpWL02: .led5mm
		case .oneN4148W: .sod123
		case .bcm847DS, .bcm857DS: .sot457
		}
	}
}
