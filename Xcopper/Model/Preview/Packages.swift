/// What a footprint carries once the board is populated: the shape to raise
/// over its outline, how tall it stands and what it is made of. The document
/// stores no part heights, so this is the one place that decides them.
struct Package: Equatable {

	/// The solid raised over the footprint
	enum Shell: Equatable {
		/// Nothing at all: the part is held somewhere other than the board,
		/// which carries its land pattern and no more
		case none
		/// A moulded body over the footprint outline
		case block
		/// A round body of the given diameter, centred on the outline
		case can(Nm)
		/// A round body with a rounded tip: an indicator lens
		case dome(Nm)
	}

	var shell: Shell = .block
	/// Height of the body above the board, not counting what holds it up
	var height: Nm = .mm(1.0)
	/// Gap the leads hold the body at
	var standoff: Nm = 0
	/// How far the moulding sits inside the footprint outline
	var inset: Nm = 0
	var color: RGBA = Palette.moulding
	/// Whether pins come up through the moulding, as a pin header carries.
	/// They are as thick as the hole they pass through.
	var posts = false
	/// Whether solder covered metal shows over each surface mount pad
	var leads: Bool = false

	/// Whether anything of the part stands on the board to be drawn
	var stands: Bool { shell != .none }
}

extension Footprint {

	/// How this footprint stands off the board. A part placed from the library
	/// knows its own shape; anything else is read off the land pattern, which
	/// is all the document keeps.
	var package: Package {
		Component(rawValue: value).flatMap(Package.init) ?? Package(landing: self)
	}
}

extension Package {

	/// Read off the land pattern. The pads say how the part is mounted and the
	/// outline says how much room it takes, which between them tell apart the
	/// four shapes a board is mostly made of.
	init(landing footprint: Footprint) {
		let body = footprint.body.size
		let across = Double(min(body.width, body.height)).mm
		let through = footprint.pads.contains(where: \.isThrough)
		// Holes inside the outline are pins coming up through a moulding, not
		// a package sitting beside the holes its own leads are bent into
		let shrouded = footprint.pads.allSatisfy { footprint.body.contains($0.at) }

		switch (through, footprint.pads.count) {
		case (false, 2):
			// Both chips land on the same pair of pads, so the designator is
			// what tells them apart. A capacitor is a fired ceramic block and
			// stands a good deal taller than the film printed on a resistor.
			let capacitor = footprint.part == .capacitor
			let element = min(max(across * 0.42, 0.3), 1.1)
			self.init(
				shell: .block,
				height: .mm(capacitor ? element * 3.0 : element),
				inset: .mm(0.05),
				color: capacitor ? Palette.ceramic : Palette.chip,
				leads: true
			)
		case (false, _):
			self.init(
				shell: .block,
				height: .mm(min(max(across * 0.45, 0.6), 2.2)),
				standoff: .mm(0.08),
				color: Palette.moulding,
				leads: true
			)
		case (true, _) where shrouded:
			self.init(shell: .block, height: .mm(2.5), posts: true)
		case (true, _):
			self.init(shell: .block, height: .mm(3.3))
		}
	}

	/// The library parts whose land pattern reads wrong on its own: a lens is
	/// not a header, a jack is not the flat thing its pads suggest, and a panel
	/// jack is not on the board at all.
	init?(_ component: Component) {
		switch component {
		case .hlmpWL02:
			self.init(shell: .dome(.mm(5.0)), height: .mm(8.6), color: Palette.lens)
		case .bourns51:
			self.init(shell: .block, height: .mm(6.5), inset: .mm(0.2), color: Palette.trimmer)
		case .nkkMN12, .nkkMN15:
			self.init(shell: .block, height: .mm(10.0), inset: .mm(0.1), color: Palette.metal)
		case .mta1563, .mta1564:
			self.init(shell: .block, height: .mm(9.4), color: Palette.nylon)
		case .that2180:
			self.init(shell: .block, height: .mm(9.0))
		case .pomona1581:
			// A panel jack is bolted through the panel and reaches back to the
			// board, which carries the ring its solder tab lands on and nothing
			// standing on it
			self.init(shell: .none, height: 0)
		default:
			return nil
		}
	}
}

extension Pad {

	/// The leg standing on a surface mount pad. A land pattern is drawn wider
	/// and longer than the lead it takes so that the solder has somewhere to
	/// fillet, and a leg raised over the whole pad would cover exactly the
	/// margin that shows it.
	var leg: Figure {
		figure.outset(-min(.mm(0.1), min(size.width, size.height) / 4))
	}
}
