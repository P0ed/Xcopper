# PCB editor

Minimal schematic capture and PCB layout for macOS. One rectangular board and one sheet per document.

- Schematic capture with parametric symbols, a built-in component library and net labels
- One part placed once: a symbol brings its footprint with it, and a footprint its symbol
- Netlist read straight back out of the drawing — nothing to keep in sync by hand
- Ratsnest on the layout showing what the schematic wants and copper does not yet do
- Design rule check against the clearance, every violation a place to go
- Inspector in the sidebar with the properties of whatever is selected
- 2, 4 or 6 copper layers
- Traces with 45° routing, vias, plated and non-plated holes
- Solid plane fills on internal layers, with automatic clearance knockouts
- Built-in parametric footprints plus manufacturer-specific library footprints
- Gerber and Excellon export of the whole manufacturing set
- 3D preview of the finished board with the parts standing on it

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

A selected symbol, wire or label lights up the way copper does on the layout,
with the glow carrying the selection on a symbol already drawn near white.

Symbols are parametric: resistor, capacitor, inductor, diode, transistor, an IC
box with any pin count, and power and ground flags. A flag's value **is** a net
name — dropping a `GND` flag on a wire names that net, no label needed.

The part picker also contains manufacturer-specific symbols with named pins and
matching footprints. Package variants use SOIC where the manufacturer offers it.
Pomona 1581 includes a custom plated panel-hole footprint with an auxiliary wire
hole. NKK MN12/MN15 use the G03 straight-PC terminal pattern.

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
`⎋` to cancel. Landing on a pad, a via or copper already drawn ends the route
there and hands the tool back to Select.

Copper never turns a right angle. A route chaining on from a segment already
drawn keeps to the three headings that carry straight on or bend 45° either
way, so a square corner has to be drawn as the two bends it is really made of,
and there is no heading at all straight back the way the route came. Copper
joined on a pad or a via is joined rather than bent, and so is copper the route
branches off, so neither ties down which way the next segment leaves.

Clicking picks up the one segment under the pointer, and a rubber band takes
every segment that fits inside it whole. Hold `⌘` to take the run instead — the
chain of segments joined end to end on one layer, up to wherever the copper
branches or lands on a pad or via. A run selects, moves and deletes as one
object, and a `⌘` band that covers only part of one takes none of it.

A click is still a click when the hand is not quite still. The pointer has to
travel a few points across the screen before a press counts as a drag, so a
wobble under the button neither carries a part off its position nor turns a
click into a rubber band that catches nothing. It is measured on the screen
rather than on the board, since it is the hand that wanders and not the design,
so the same wobble is forgiven at any magnification, and a pointer brought back
inside it is a click again. The sheet reads a press the same way.

Dragging a segment stretches the copper it is soldered to rather than carrying
it along. Both sides keep the heading they were drawn at and the joint slides to
where those headings now cross, so the segment dragged changes length and so does
the one it hangs off, while the far end of it stays put: drag the bottom of a U
towards the top and it comes out longer, the legs either side of it shorter. A
leg taken up to nothing goes away with the drag.

Copper a pad carries off has no such say. Every trace end sitting on a pad of a
moving footprint follows the pad exactly, and the segment it stretches is put
back on the 45° grid — the corner it runs into slides along to absorb the move,
and where there is no corner to slide, a pad, a via or a branch, the segment
folds into two legs instead. The fold picks the leg order that leaves the joint
it hangs off gently, rather than the one that would meet it square. A joint no
stretch can work out is carried and folded the same way: one at a branch, which
has no single heading to keep, or between two headings that never meet. Copper
drawn at a free angle keeps it.

No drag leaves copper turning a right angle either. Where a corner comes out
square anyway, it comes apart into the two 45° bends it is really made of: each
leg gives up one snap grid step and a short segment joins where they left off.
Where even that will not do — copper doubled right back on itself, or a leg with
no step to spare — the drag is refused whole. The board is left exactly as it
stood, so the copper visibly stops following the pointer rather than bending
square, and a refused drag leaves nothing on the undo stack.

A drag never leaves a straight line in pieces: segments that come to rest end to
end in line fuse back into the one segment they look like, and a segment
squashed down to nothing goes away. Copper meeting on a pad or a via is joined
there rather than bent, so that stays two segments.

## Parts

A part is placed once and stands on both sides. Placing a symbol on the sheet
also puts its footprint on the board, and placing a footprint puts its symbol on
the sheet. Nothing links the two but the reference designator they share, which
is all `⌘U` needs to pair them up again.

The counterpart is parked at the first spot, in reading order, where it covers
nothing already drawn, on the 0.1 inch pitch both snap grids share, so it lands
on the grid whatever the snap is set to and is ready to be dragged where it
belongs. On the sheet that keeps a parked symbol off the wires as well as off the
other parts — a pin tip landing on a wire would join its net.

Either half shows the other. With a part picked, `⌘J` turns the document over,
lights up what stands there for it — the footprint a symbol stands for, or the
symbol a footprint does — and scrolls it into the middle of the view. The sidebar
offers the same under the selection. It is the shared designator that pairs the
two, so a part whose other half has been deleted has nothing to show, and neither
has a wire, a length of copper or a power flag.

The picker shelves the library by what a part does rather than by the package
it comes in — op-amps, multipliers, logic, switches, panel controls, connectors
and discretes — with `Generic` standing above the shelves. The layout's picker
is shelved the same way, carrying only the parts that stand on the board.

A library part brings its own package. A generic one takes the package its
symbol implies — a chip for a resistor, capacitor, inductor or diode, SOT-23 for
a transistor, SOIC for an IC — and the symbol dialog names it before the part is
placed. To choose a package precisely, place from the layout instead: that draws
the symbol. Power and ground flags name a net rather than standing for a part,
so they go on the sheet alone.

## Inspector

The top of either sidebar describes what is selected and lets it be edited in
place. A trace gives its width, layer, net and length; a via its drill, pad,
the layers it spans and its net; a hole its drill; a footprint its reference,
value, side, rotation and position. On the sheet a symbol gives its reference
and value — the resistance, the capacitance, the part number — along with its
rotation, whether it is mirrored and where it stands, and a label the net name
it carries. A wire reports the net it lands in and how long it is, both read
back out of the drawing rather than stored.

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

## Design rules

The board is looked over as it is drawn, and what is wrong with it is listed in
the sidebar under the clearance it is measured against. Nothing is stored: the
violations are read back out of the copper the way the netlist is read back out
of the wires, so one can never outlive the thing that caused it.

Copper is judged against copper of another net. Touching is a short, and coming
closer than the clearance without touching is the clearance itself. Copper the
design has not named is copper it says nothing about, and is left alone; copper
of one net is free to touch itself. A hole carries no net at all, so everything
has to stand clear of one, and so it does of the cut edge. What the netlist asks
for and no copper joins is listed too — the same connections the ratsnest draws.

Every line is a place to go. Clicking one picks up the copper at fault, turns to
the layer it stands on and scrolls it into the middle of the view. Everything
but an unrouted connection is also ringed where it stands on the layout, and the
rings follow a drag the way the ratsnest does, so a fault clears as the copper
that caused it moves away.

## Layers

Copper layers are indexed from the top. On a 4 or 6 layer board any internal
layer can be turned into a plane by picking a net for it in the sidebar: the
plane fills the board and clears around every pad, via, hole and trace that
carries a different net.

## 3D preview

`⌘3` shows the board the way it comes back from the fab: laminate of the chosen
thickness with its cut edge showing, solder mask over it, copper reading through
the mask, pads left open and plated, holes drilled through and lined, and every
part standing where the layout puts it. Nothing is approximated away: the copper
drawn is the copper on the board, and no legend is drawn because the fabrication
set carries none.

| Key | View |
| --- | --- |
| `T` | Top |
| `B` | Bottom |
| `F` | Front |
| `A` | Angled |

Only the outer copper layers are on show, since those are the only ones a
finished board lets you see. Part heights come from the library for the parts it
knows and are read off the land pattern for everything else — two lands and no
holes is a chip, holes inside the outline are pins coming up through a moulding,
holes outside it are a package sitting beside them.

## Fabrication

`⌘⇧E` writes the manufacturing set into a folder: a Gerber for every copper
layer, solder mask and paste for both faces, the board outline, and Excellon
drill programs split into plated and non-plated. Files are named after the
document — `Amp-F_Cu.gbr`, `Amp-In1_Cu.gbr`, `Amp-PTH.drl` — the way fab portals
expect to find them. There is no silkscreen: the board carries no legend.

Nothing is written before the board has been looked over. A set asked for while
a rule is broken says how many are broken and what the first of them are, and
going ahead anyway is a button; turning back takes the layout to the first.

Pads open the solder mask and vias do not, so vias come back tented.

The Gerbers are RS-274X in millimeters at a 4.6 format, so a board nanometer is
written as its own integer and nothing is rounded on the way out. Copper carries
X2 net attributes, and each file states its own place in the stack. A plane goes
out the way the layout draws it: poured over the board, cleared back around
everything on another net, then the copper on that layer drawn over the top.

## File format

One JSON document holding `nets`, `board` and `schematic`.

## Roadmap

- BOM:
- - Include in BOM toggle for component.
- - BOM export.
- - Pick and place export.
- Tool to check component value against part number and availability on `jlcpcb.com/parts`.
- Modularity. Merge several PCBs onto one, sharing power nets.
- API.
