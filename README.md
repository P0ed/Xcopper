# PCB editor

Minimal schematic capture and PCB layout for macOS, both halves in one document.
Draw the schematic, let it derive the netlist, push that onto the board, then
route the copper it asks for. One rectangular board and one sheet per document.

- Schematic capture with parametric symbols, a built-in component library and net labels
- Netlist read straight back out of the drawing — nothing to keep in sync by hand
- Ratsnest on the layout showing what the schematic wants and copper does not yet do
- 2, 4 or 6 copper layers
- Traces with 45° routing, vias, plated and non-plated holes
- Solid plane fills on internal layers, with automatic clearance knockouts
- Built-in parametric footprints plus manufacturer-specific library footprints

`⌘1` opens the schematic and `⌘2` opens the layout. Each side keeps its own
zoom, scroll and selection.

## Layout

| Key | Tool |
| --- | --- |
| `S` | Select |
| `W` | Route |
| `V` | Via |
| `H` | Hole |
| `F` | Place footprint |

`1`…`6` pick the active copper layer. `⇥` / `⇧⇥` step through layers and `G`
cycles snap spacing. Grid dots have their own 1.27 mm and 2.54 mm display
spacing setting. `R` rotates a selection clockwise and `⇧R` rotates it
counterclockwise.

While routing, segments snap to 45° and chain from the previous endpoint —
click, click, click. Hold `⇧` for a free angle, `⌃` to ignore pad snapping,
`⎋` to cancel.

Clicking one segment of a route picks up the whole run — the chain of segments
joined end to end on one layer, up to wherever the copper branches or lands on a
pad or via. A run selects, moves and deletes as one object, and a rubber band
that covers only part of one takes none of it.

Moving a footprint takes its copper with it: every trace end sitting on one of
its pads follows the part, the far end stays put and the segment stretches.

## Schematic

| Key | Tool |
| --- | --- |
| `S` | Select |
| `W` | Wire |
| `L` | Label |
| `F` | Place symbol |

`G` cycles the sheet snap spacing. Grid dots have a separate display spacing.
`R` rotates a selection clockwise and `⇧R` rotates it counterclockwise. Wires
snap to 90° and chain the same way routing does, with the same `⇧`, `⌃` and `⎋`
modifiers.

Symbols are parametric: resistor, capacitor, inductor, diode, transistor, an IC
box with any pin count, and power and ground flags. A flag's value **is** a net
name — dropping a `GND` flag on a wire names that net, no label needed.

The part picker also contains manufacturer-specific symbols with named pins and
matching footprints. Package variants use SOIC where the manufacturer offers it.
Pomona 1581 includes a custom plated panel-hole footprint with an auxiliary wire
hole. NKK MN12/MN15 use the G03 straight-PC terminal pattern.

## Nets

Connectivity is never stored, only drawn. A wire shorts its own two ends, and any
pin tip, wire end or label anchor sitting on a wire joins it. Because only those
terminals are tested against wires, a T-junction connects and two wires merely
crossing do not — the usual schematic convention, and junction dots follow from
it rather than being placed by hand.

A net takes its name from a label in it, or failing that from a power or ground
flag. Unnamed nets get an `N$n` when they reach the board.

`⌘U` pushes the netlist onto the layout: footprints are matched to symbols by
reference designator and pads to pins by number, and `Pad.net` is set from that.
The pass is additive — a pad the schematic says nothing about keeps the net it
had — and the sidebar reports what it could not match: symbols with no footprint,
footprints in no schematic, and pins with no pad.

The layout then draws a ratsnest for every net whose copper does not yet join all
of it, as a minimum spanning tree over the disconnected islands. Route one of
those connections and its line goes away.

## Layers

Copper layers are indexed from the top. On a 4 or 6 layer board any internal
layer can be turned into a plane by picking a net for it in the sidebar: the
plane fills the board and clears around every pad, via, hole and trace that
carries a different net.

## File format

One JSON document holding `nets`, `board` and `schematic`.
