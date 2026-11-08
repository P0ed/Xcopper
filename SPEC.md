# Developer specification

Implementation rules and document compatibility for Xcopper. User controls and
workflows are in [README.md](README.md); MCP setup and the tool contract are in
[MCP.md](MCP.md).

## Document model and persistence

### Structure

Each `.xcb` JSON document encodes `nets`, `board`, `modules` and `parameters`.
Existing documents without `modules` remain readable. Resolved source geometry,
projection caches and folder access bookmarks are not embedded in the file.
All coordinates and lengths are stored as integer micrometers.

The board stores paired parts in `footprints`; each footprint contains its own
`symbol`, whose pins carry optional `netLabel` values. Schematic dimensions and
wires are stored as `board.sheetSize` and `board.wires`. Legacy root-level
`schematic.symbols` records migrate into these paired parts when opened.

Module instances store numbered IO definitions in `interface` and optional
pin assignments in `netLabels`, keyed by IO number.

### Parameters

Each design stores parameter names and defaults in a `parameters` array.
Names are derived from schematic values beginning with `#NAME`; repeated names
share one parameter. Definitions are synchronized with the values that use them.

Module instances retain parameter definitions and defaults in `parameters`, with
per-instance overrides in `parameterValues`, keyed by parameter name. Older
documents without these fields derive parameters from their schematic values and
have no overrides.

### Component geometry

Library footprints store their component ID, placement, reference, value and BOM
setting. Pads, body dimensions, device and package come from the current library
definition when opened, and pad nets are rebuilt from the schematic.
Generic and custom footprints retain their stored geometry.

### Compatibility defaults

Via diameters are stored once in the board's rules. Older documents use their
saved board via sizes; per-via drill and pad overrides are discarded when opened.
The rules store `minTraceLength`; older documents default to 100 µm (0.1 mm).
Saved via layer ranges are discarded: every via spans the current board stack.
The board stores `solderMask`; older documents without it open with mask enabled.
Module origins are derived from the source board center and are not stored.
Saved `origin` fields in older documents are ignored.

## Editing and geometry

### Paired parts and placement

A native part is one footprint containing its schematic symbol. Reference and
value belong to that shared part. Pin labels belong to the symbol pins. Deleting
either representation removes the pair in one Undo step while retaining wires
and copper. Copying and duplication carry both representations and pin labels,
allocate a new reference and park the counterpart.

The counterpart is parked at the first spot, in reading order, where it covers
nothing already drawn, on the 0.1 inch pitch both snap grids share, so it lands
on the grid whatever the snap is set to and is ready to be dragged where it
belongs. On the sheet that keeps a parked symbol off the wires as well as off the
other parts — a pin tip landing on a wire would join its net.

### Schematic movement and selection

Dragging a symbol, module or wire segment keeps its existing
connections. Neighbouring wires extend or contract, corners slide, and extra
right-angle legs appear where needed to reach a fixed pin or junction. Collapsed segments disappear
and straight segments fuse. `⌘` selects a whole wire run up to a pin or
branch, using the same selection rules as layout traces.

A selected symbol or wire lights up the way copper does on the layout,
with the glow carrying the selection on a symbol already drawn near white.

### Pointer gestures

A click is still a click when the hand is not quite still. The pointer has to
travel a few points across the screen before a press counts as a drag, so a
wobble under the button neither carries a part off its position nor turns a
click into a rubber band that catches nothing. It is measured on the screen
rather than on the board, since it is the hand that wanders and not the design,
so the same wobble is forgiven at any magnification, and a pointer brought back
inside it is a click again. The sheet reads a press the same way.

### Copper routing and repair

Landing on a pad, a via or copper already drawn ends the route
there, straightens the connected run into horizontal, vertical and 45° legs,
and hands the tool back to Select. Compatible segments in a straight line merge,
while pad, via and branch connections stay fixed. Finishing and straightening
share one undo step. If there is no room for the required bends, routing stays
active so the last segment can be adjusted.

Copper never turns a right angle. A route chaining on from a segment already
drawn keeps to the three headings that carry straight on or bend 45° either
way, so a square corner has to be drawn as the two bends it is really made of,
and there is no heading at all straight back the way the route came. Copper
joined on a pad or a via is joined rather than bent, and so is copper the route
branches off, so neither ties down which way the next segment leaves.

Dragging a segment straightens it and the neighbours it stretches to horizontal,
vertical or 45° legs. Copper already on those headings keeps its direction, and the joint slides to
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
has no single heading to keep, or between two headings that never meet. A segment
drag also folds copper drawn at a free angle into 45° legs, keeping the far
connections in place. Moving a footprint alone preserves free-angle copper.

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

## Connectivity and design rules

Connectivity is derived from wires and pin labels. A wire shorts its own two ends, and any
pin tip or wire end sitting on a wire joins it. Pins with matching net labels
also share a net without a wire.
Because only those terminals are tested against wires, a T-junction connects
and two wires merely crossing do not — the usual schematic convention, and junction dots follow from
it rather than being placed by hand.

A net takes its name from a label in it. New unnamed nets get a name based on
their sorted reference and pin numbers, such as `N$R1.1/R2.2`, when they reach the board.
Existing unnamed nets keep their names and IDs so routed copper stays connected.

Schematic edits automatically update the layout. Each footprint's symbol pins
are matched to its pads by pin number, and `Pad.net` is assigned from the resolved
schematic net.
The pass is additive — a pad the schematic says nothing about keeps the net it
had. Unnamed nets keep their names across updates, and undo restores the schematic
and board together.

Traces and vias without a net inherit the single net of physically connected
copper as the design changes, including chains through pads and vias across their
copper layers. Existing assignments are preserved. Disconnected copper and copper
touching more than one net stay unassigned.

The layout then draws a ratsnest for every net whose copper does not yet join all
of it, as a minimum spanning tree over the disconnected islands. Route one of
those connections and its line goes away.

The board is looked over as it is drawn, and what is wrong with it is listed in
the sidebar under the clearance it is measured against. Nothing is stored: the
violations are read back out of the copper the way the netlist is read back out
of the wires, so one can never outlive the thing that caused it.

Physical checks cover foreign-net shorts and clearance, holes, board edges and
minimum trace length. Unassigned copper is excluded from copper-to-copper
checks but remains subject to hole, edge and trace-length rules. Traces inside
resolved modules use the parent's rules. Checks are derived from current geometry
and connectivity rather than persisted findings.

## Components and preview geometry

Preview geometry includes the substrate, copper, solder mask, open pads, drill
holes and plated barrels. Copper geometry matches the layout. No legend is drawn,
matching the fabrication output.

Each footprint has a device type, physical package and optional library identity
separate from its reference and value. Renaming a part or importing it into
a module preserves its identity. Library components load their current footprint
definition whenever a document opens. Custom land patterns can be represented
without assigning a device or library identity.

Only the outer copper layers are on show, since those are the only ones a
finished board lets you see. Part appearance comes from the stored device and
package: chip capacitors have a ceramic body and stand taller than resistors of
the same size. Custom packages use a geometric approximation based on their land
pattern. Reference and value text do not select a 3D model.

## Modules

### Discovery

Save the parent design. Xcopper finds modules by name in the document's folder
and its subfolders, following Finder aliases and symbolic links to other folders.
For example, a design in `Modules/Function` can use modules from `Modules/Base`
through an alias to `Base` inside `Function`. Hidden folders and packages are skipped.
Names must be unique throughout the search, including differences only in letter
case. Multiple aliases to the same source count as one module. Circular folder
links are visited only once. Nested dependencies use the same search results.
Existing saved filenames and relative paths are resolved by their module names.

### Placement transforms

The instance's layout position places the center of its source board in the parent.
Rotating a single module turns around that center. Nested modules also use their
own source board centers. Resizing a source board and reloading keeps the instance's
position fixed and centers the resized board there. Opening a source directly keeps
the root board's origin at `[0, 0]`.

### Projection, connectivity and parent rules

Wire the block's pins; the board updates automatically. Connections
pass through module IO to imported pads, traces, vias and nested modules. All
non-power nets, including IO nets, and component references belong to their
instance hierarchy. Use qualified labels such as `M1.NET` to connect to a module's
local nets. IO connections do not add module nets to the parent's net list.
The `GND`, `VCC` and `VEE` supply nets are shared between instances.
The parent supplies its stack, internal planes, clearance rules, via sizes, solder mask and 3D thickness.
Source top and bottom copper map to the parent's outer layers, and through holes
span the parent stack. Module rectangles are placement bounds; fabrication
exports only the parent's outline.

### Reload, access and history

Unused nets are removed when a file opens; copper assignments, schematic labels
and power nets are retained. Sources reload when the parent opens or moves. After editing a source, choose
**File → Reload Modules** in its parent. Placements stay fixed; if the IO list
changes, pins regenerate and a notice asks you to check the parent wires, which
retain their coordinates. Missing, malformed, cyclic or incompatible dependencies
appear as unresolved blocks and layout rectangles. The Modules panel explains
how to recover. Unresolved geometry is excluded, and fabrication stays blocked
until every dependency resolves. Stack reductions that would invalidate imports
are refused. Pasting into another document searches for module names in the
destination's folder and subfolders before adding any instances.

macOS may ask you to select a source's containing folder to grant access.
You can select a shared parent folder, such as `Modules`, to cover all of its
subfolders. Xcopper retains that grant in its preferences, outside the design.
Moving the parent searches its new folder for dependencies and may require a new grant.
Import, source replacement, movement, rotation, duplication, deletion, paste and explicit reload are
undoable. Undo restores the previous resolved snapshot even if sources have since
changed or disappeared; source files are never modified by parent edits.

## Fabrication encoding

The Gerbers are RS-274X in millimeters at a 4.6 format. Board coordinates are stored
as integer micrometers and multiplied by 1,000 for export without rounding. Copper
carries X2 net attributes, and each file states its own place in the stack. A plane goes
out the way the layout draws it: poured over the board, cleared back around
everything on another net, then the copper on that layer drawn over the top.

The bill of materials carries one line per value and package, with everything
that shares them gathered into a single designator field and counted. The
placement list gives each part its middle, the face it stands on, and how far it
is turned counter-clockwise seen from that face — measured from the same corner
the Gerbers count from, so the two agree. A part's value is what the bill calls
it, or failing that the library part it came from, or what sort of device it is.
