import Foundation

enum Device: String, Codable, CaseIterable, Identifiable {
	case unknown, resistor, capacitor, inductor, diode, transistor, ic, connector, potentiometer, switchContact

	var id: String { rawValue }
	var name: String {
		switch self {
		case .unknown: "Unknown"
		case .ic: "IC"
		case .switchContact: "Switch"
		default: rawValue.capitalized
		}
	}

	var prefix: String {
		switch self {
		case .unknown: "X"
		case .resistor: "R"
		case .capacitor: "C"
		case .inductor: "L"
		case .diode: "D"
		case .transistor: "Q"
		case .ic: "U"
		case .connector: "J"
		case .potentiometer: "P"
		case .switchContact: "SW"
		}
	}

	static var genericCases: [Device] { [.resistor, .capacitor, .inductor, .diode, .transistor, .ic, .connector] }

	var packageKinds: [Footprint.Kind] {
		switch self {
		case .resistor, .capacitor, .inductor, .diode: [.chip]
		case .transistor: [.sot23]
		case .ic: [.soic, .dip]
		case .connector: [.header]
		default: []
		}
	}

	var symbolKind: Symbol.Kind {
		switch self {
		case .resistor: .resistor
		case .capacitor: .capacitor
		case .inductor: .inductor
		case .diode: .diode
		case .transistor: .transistor
		default: .ic
		}
	}
}

extension Symbol.Kind {
	var device: Device {
		switch self {
		case .resistor: .resistor
		case .capacitor: .capacitor
		case .inductor: .inductor
		case .diode: .diode
		case .transistor: .transistor
		case .ic: .ic
		case .power, .ground: .unknown
		}
	}
}
