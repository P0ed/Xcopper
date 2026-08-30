/// Single stroke lettering for silkscreen, on a cell 6 wide and 10 tall with y
/// running up. A glyph is a set of polylines: points written `x,y` and
/// separated by spaces, strokes separated by a slash.
enum StrokeFont {
	static var width: Int { 6 }
	static var height: Int { 10 }

	/// Cell pitch, and the part of it that is the gap to the next glyph
	static var advance: Int { 8 }
	static var gap: Int { advance - width }

	/// Polylines for `character`, empty for a space or anything unlettered —
	/// the cell still advances, so a run of text keeps its spacing either way
	static func strokes(for character: Character) -> [[(x: Int, y: Int)]] {
		table[character] ?? []
	}

	private static let table: [Character: [[(x: Int, y: Int)]]] = glyphs.mapValues { glyph in
		glyph.split(separator: "/").map { stroke in
			stroke.split(separator: " ").compactMap { point in
				let pair = point.split(separator: ",").compactMap { Int($0) }
				return pair.count == 2 ? (x: pair[0], y: pair[1]) : nil
			}
		}
	}

	private static let glyphs: [Character: String] = [
		"0": "0,2 2,0 4,0 6,2 6,8 4,10 2,10 0,8 0,2",
		"1": "1,8 3,10 3,0 / 1,0 5,0",
		"2": "0,8 1,10 5,10 6,8 6,6 0,0 6,0",
		"3": "0,10 6,10 3,6 6,4 6,2 4,0 2,0 0,2",
		"4": "4,0 4,10 0,3 6,3",
		"5": "6,10 0,10 0,6 4,6 6,4 6,2 4,0 1,0 0,1",
		"6": "6,9 4,10 2,10 0,8 0,2 2,0 4,0 6,2 6,4 4,6 2,6 0,4",
		"7": "0,10 6,10 2,0",
		"8": "2,6 0,8 0,9 2,10 4,10 6,9 6,8 4,6 2,6 0,4 0,1 2,0 4,0 6,1 6,4 4,6",
		"9": "0,1 2,0 4,0 6,2 6,8 4,10 2,10 0,8 0,6 2,4 4,4 6,6",
		"A": "0,0 3,10 6,0 / 1,3 5,3",
		"B": "0,0 0,10 4,10 6,8 6,7 4,5 0,5 / 4,5 6,3 6,2 4,0 0,0",
		"C": "6,8 4,10 2,10 0,8 0,2 2,0 4,0 6,2",
		"D": "0,0 0,10 3,10 6,7 6,3 3,0 0,0",
		"E": "6,10 0,10 0,0 6,0 / 0,5 4,5",
		"F": "6,10 0,10 0,0 / 0,5 4,5",
		"G": "6,8 4,10 2,10 0,8 0,2 2,0 4,0 6,2 6,5 3,5",
		"H": "0,0 0,10 / 6,0 6,10 / 0,5 6,5",
		"I": "1,10 5,10 / 3,10 3,0 / 1,0 5,0",
		"J": "4,10 4,2 2,0 0,2",
		"K": "0,0 0,10 / 6,10 0,4 / 2,6 6,0",
		"L": "0,10 0,0 6,0",
		"M": "0,0 0,10 3,5 6,10 6,0",
		"N": "0,0 0,10 6,0 6,10",
		"O": "0,2 2,0 4,0 6,2 6,8 4,10 2,10 0,8 0,2",
		"P": "0,0 0,10 4,10 6,8 6,7 4,5 0,5",
		"Q": "0,2 2,0 4,0 6,2 6,8 4,10 2,10 0,8 0,2 / 3,3 6,0",
		"R": "0,0 0,10 4,10 6,8 6,7 4,5 0,5 / 3,5 6,0",
		"S": "6,9 4,10 2,10 0,9 0,6 2,5 4,5 6,4 6,1 4,0 2,0 0,1",
		"T": "0,10 6,10 / 3,10 3,0",
		"U": "0,10 0,2 2,0 4,0 6,2 6,10",
		"V": "0,10 3,0 6,10",
		"W": "0,10 1,0 3,5 5,0 6,10",
		"X": "0,0 6,10 / 0,10 6,0",
		"Y": "0,10 3,5 6,10 / 3,5 3,0",
		"Z": "0,10 6,10 0,0 6,0",
		"-": "1,5 5,5",
		"_": "0,0 6,0",
		".": "3,0 3,1",
		"+": "1,5 5,5 / 3,3 3,7",
		"/": "0,0 6,10",
		"$": "6,9 4,10 2,10 0,9 0,6 2,5 4,5 6,4 6,1 4,0 2,0 0,1 / 3,10 3,0",
	]
}
