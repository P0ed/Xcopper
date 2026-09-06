enum Package: Hashable, Codable {
	case custom
	case chip(Footprint.Chip)
	case soic(Int)
	case sot23
	case dip(Int)
	case header(pins: Int, rows: Int)
	case ssop10
	case sip(Int)
	case mta156(Int)
	case led5mm
	case sod123
	case sot457
	case pomona1581
	case bourns51
	case nkkMNPC

	var name: String {
		switch self {
		case .custom: "Custom"
		case let .chip(size): "Chip \(size.name)"
		case let .soic(pins): "SOIC-\(pins)"
		case .sot23: "SOT-23"
		case let .dip(pins): "DIP-\(pins)"
		case let .header(pins, rows): "Header \(rows)×\(pins)"
		case .ssop10: "SSOP-10, 1.00 mm pitch"
		case let .sip(pins): "SIP-\(pins)"
		case let .mta156(pins): "MTA-156, \(pins)-position"
		case .led5mm: "T-1 3/4 (5 mm)"
		case .sod123: "SOD-123"
		case .sot457: "SOT-457 (SC-74)"
		case .pomona1581: "Panel mount, 6.35 mm ring + wire hole"
		case .bourns51: "Bourns 51, horizontal PC pins"
		case .nkkMNPC: "NKK G03 straight PC pins, 4.7 mm pitch"
		}
	}

	func makeFootprint() -> Footprint? {
		switch self {
		case .custom: nil
		case let .chip(size): .chip(size)
		case let .soic(pins): .soic(pins: pins)
		case .sot23: .sot23()
		case let .dip(pins): .dip(pins: pins)
		case let .header(pins, rows): .header(pins: pins, rows: rows)
		case .ssop10: .ssop10()
		case let .sip(pins): .sip(pins: pins)
		case let .mta156(pins): .mta156(pins: pins)
		case .led5mm: .led5mm()
		case .sod123: .sod123()
		case .sot457: .sot457()
		case .pomona1581: .pomona1581()
		case .bourns51: .bourns51()
		case .nkkMNPC: .nkkMNPC()
		}
	}
}
