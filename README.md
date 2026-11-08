# PCB editor

Minimal schematic capture and PCB layout for macOS. One rectangular board and one sheet per document.

Build a release and copy it to `/Applications`:

```sh
xcodebuild -project Xcopper.xcodeproj -scheme Xcopper -configuration Release \
  -destination 'platform=macOS' -derivedDataPath /tmp/XcopperRelease \
  CODE_SIGNING_ALLOWED=NO build && \
  ditto /tmp/XcopperRelease/Build/Products/Release/Xcopper.app /Applications/Xcopper.app
```

- Schematic capture with parametric symbols, a built-in component library and net labels
- One part placed once: a symbol brings its footprint with it, and a footprint its symbol
- Netlist read straight back out of the drawing — nothing to keep in sync by hand
- Ratsnest on the layout showing what the schematic wants and copper does not yet do
- Design rule check against the clearance, every violation a place to go
- Inspector in the sidebar with the properties of whatever is selected, one object or many of a kind
- Find by reference or value, selecting every part that answers to it
- Classic, Digital or Analog stackup, of 2, 4 or 6 copper layers
- Traces with 45° routing, vias, plated and non-plated holes
- Solid plane fills on internal layers, with automatic clearance knockouts
- Built-in parametric footprints plus manufacturer-specific library footprints
- Reusable `.xcb` designs as modules with schematic IO blocks and locked layout groups
- Gerber and Excellon export of the whole manufacturing set
- 3D preview of the finished board with the parts standing on it

## Schematic

| Key | Tool |
| --- | --- |
| `S` | Select |
| `W` | Wire |
| `F` | Place symbol |

`⌘B` sets how big the sheet is, in millimetres or inches, the way the same key
sets the board on the layout. A new one is 297 × 210 mm. The sheet is the
rectangle the drawing stands on, what `Size to fit` fits and where a parked part
looks for room; resizing it moves nothing already drawn, so a sheet made smaller
than its drawing leaves it hanging over the edge.

`G` cycles the sheet snap spacing. Grid dots have a separate display spacing.
`R` rotates a selection clockwise and `⇧R` rotates it counterclockwise. Wires
use horizontal and vertical segments, including when snapping to an offset pin
or wire. Click or drag to draw and continue from the last endpoint; landing on a
pin or existing wire finishes the route and returns to Select. Hold `⌃`
to ignore connection snapping, or press `⎋` to cancel. `⇧` keeps wires orthogonal.

Dragging a symbol, module or wire segment preserves its connections.
Hold `⌘` to select a whole wire run up to a pin or branch.

Symbols are parametric: resistor, capacitor, inductor, diode, transistor and an IC
box with any pin count. Every symbol represents a part with one footprint.
Double-click a resistor or capacitor in Select mode to edit its value in the
sidebar.
Select a symbol or module and edit its **Pin net labels** fields in the sidebar.
Each pin has an optional net label; an empty field clears the label.
Labels appear at every pin that specifies one and move with the part. Matching
labels connect pins, including supplies such as `GND`, `VCC` and `VEE`.
Use `#1 OUT1` to name a net `OUT1` and expose it as module IO pin 1, named `OUT1`.

The part picker also contains manufacturer-specific symbols with named pins and
matching footprints. Package variants use SOIC where the manufacturer offers it.
Pomona 1581 includes a custom plated panel-hole footprint with an auxiliary wire
hole. NKK MN12/MN15 use the G03 straight-PC terminal pattern.

## Layout

**Design → Board settings** (`⌘B`) sets the board size, stackup and solder mask.
The **mm / in** toggle controls the size units. With nothing selected, the layout
inspector's **Globals** panel sets clearance, trace width, minimum trace length
and via drill and pad diameters.
All numeric inputs use `.` as the decimal separator. Turn off **Solder mask** to leave both faces unmasked in the 3D
preview and fabrication set. This setting is saved with the board and can be undone.
Every via uses the board's sizes, including existing vias and vias
inside imported modules. Applying a change updates them together and can be undone.
Vias always pass through the whole board, from top to bottom.
Blind and buried vias are not supported.

| Key | Tool |
| --- | --- |
| `S` | Select |
| `W` | Route |
| `V` | Via |
| `H` | Hole |
| `F` | Place footprint |

`1` and `2` pick the signal layer to draw on. `⇥` / `⇧⇥` step between them and
`G` cycles the active tool's grid; in Select it follows the selected objects.
`⇧G` cycles backward. The Place grid is 1.27, 2.54 or 12.7 mm for footprints,
holes and module groups. The Route grid is 0.127, 0.254 or 0.635 mm for traces
and vias. Each setting is remembered independently, with defaults of 2.54 mm
for placement and 0.254 mm for routing. Moving, nudging, duplicating and pasting
use the grid for those objects; a mixed group containing a footprint, hole or
module moves together on the placement grid. Grid dots keep their separate
spacing setting in Display. `R` rotates a selection clockwise and `⇧R` rotates
it counterclockwise.

The sidebar's **Display → Silkscreen** checkbox shows or hides footprint outlines,
pin-one markers and reference text on the layout. It starts enabled and controls
only the drawing; the fabrication set carries no silkscreen.
The **Layers → Ratsnest** toggle follows the copper layer toggles and shows or hides
unrouted connection lines. It starts enabled.

While routing, segments snap to 45° and chain from the previous endpoint.
Click or drag to draw; hold `⇧` for a free angle or `⌃` to ignore pad snapping.
Delete removes the last placed segment and returns to its start; repeat to step
back through the route. `⎋` cancels routing. Landing on a pad, via or existing
copper finishes the route and returns to Select. If there is no room to finish,
adjust the last segment and try again.

Selection includes both top and bottom copper when visible, including Select All.
Overlapping traces prefer the active layer.
Clicking picks up the one segment under the pointer, and a rubber band takes
every segment that fits inside it whole. Where objects overlap, clicks prefer
traces, then vias, holes and footprints. Hold `⌘` to take the run instead — the
chain of segments joined end to end on one layer, up to wherever the copper
branches or lands on a pad or via. A run selects, moves and deletes as one
object, and a `⌘` band that covers only part of one takes none of it.

Select a footprint first, then click one of its pads to inspect that pad.
Box selection selects whole objects and never individual pads. The inspector
shows a pad's number, dimensions, layer, position and net as read-only values.
Assign pad nets with net labels in the schematic; the board updates automatically
as the schematic changes. Layout net assignment applies only to traces and vias. Choose **Select footprint**
in the inspector to move or edit the whole part. Module pads can be clicked directly
to inspect their resolved net, dimensions and position.
`⌘`-click an imported object to select its whole module instance.

Dragging parts, vias or traces preserves their existing connections. Copper is
adjusted to horizontal, vertical and 45° segments as needed. An invalid drag is
refused without changing the board or adding an Undo step. Moving a footprint
alone preserves any free-angle copper attached to it.

## Parts

Placing a symbol also creates its footprint, and placing a footprint creates
its symbol. Both views share the part's reference and value.

The counterpart is parked automatically where there is room. Move it into place
when you switch to the other view.

The value belongs to the part rather than to either drawing. Typing a resistance
into the sidebar on the sheet writes it on the footprint as well, typing it on
the layout writes it back on the symbol, and a part placed with a value carries
it to the half that follows: the two are one part under the reference they
share. Net labels belong to the symbol pins.

The reference belongs to the part as well. Retyping it on either side renames
both halves at once, so a rename never breaks the pair, and deleting either half
deletes the part: the symbol goes with the footprint and the footprint with the
symbol, in one undoable step. Wires and copper already drawn stay where they
are — only the part goes.

Copying carries the part whole. Either half copied puts both on the clipboard,
and pasting or duplicating lays the half in front of you where the offset falls
while the other is parked where there is room, the two sharing the one new
reference. Pin net labels travel with the copied part or module.

Select a part and press `⌘J` to switch views, select its counterpart and bring it
into view. The sidebar offers the same action.

The picker shelves the library by what a part does rather than by the package
it comes in — op-amps, multipliers, logic, switches, panel controls, connectors
and discretes — with `Generic` standing above the shelves. The layout's picker
is shelved the same way, carrying only the parts that stand on the board.

A library part brings its own package. A generic one takes a default package for
its device type — a chip for a resistor, capacitor, inductor or diode, SOT-23 for
a transistor, SOIC for an IC — and the symbol dialog names it before placement.
The layout picker lets you choose the device and a supported package separately,
including chip size or SOIC versus DIP for an IC, and draws the matching symbol.

Library parts use the current library footprint definition when a document
opens.

## Find

`⌘F` selects by name. The query is matched against the reference and the value
of every part in the editor in front of you, ignoring case, and a part answers
when either field begins with it: `R10` finds that resistor, `C` every
capacitor, `1K5` everything of that value. A module answers to its reference and
to the file it came from. Pin net labels also match: `GND` finds every symbol
or module with a pin carrying that net name. What matched becomes the selection and is scrolled
into view, ready for the sidebar to edit as one; a query nothing answers selects
nothing. Open the part picker with `⌘⇧F` in either view.

## Inspector

The top of either sidebar describes what is selected and lets it be edited in
place. A trace gives its width, layer, net and length; a via its drill, pad,
the layers it spans and its net; a hole its drill; a footprint its reference,
value, side, rotation, position and whether the bill of materials carries it.
On the sheet a symbol gives its reference and value — the resistance, the
capacitance, the part number — along with its rotation, whether it is mirrored
and where it stands. A single symbol or module also gives an editable net label
for each pin. A wire reports its net and length.

Several objects of one kind are edited at once. A selection of traces, of
footprints — anything of a single kind — puts the same rows
in the sidebar standing for all of it: a field they agree on shows that value, one they
differ over shows empty, and what is typed or picked there lands on every one of
them. Properties that cannot be shared stay out of it, a reference and a
position among them, and a selection of several kinds still reports nothing but
its count. The rows that only report add up instead — how many are selected, and
how much copper or wire the selection comes to.

## Nets

Wires and matching pin labels connect pins. A T-junction connects, while two
wires crossing without a junction do not. Junction dots appear automatically.

Schematic edits update the layout automatically. Unnamed nets receive generated
names; pin labels give them meaningful names. Undo restores the schematic and
board together.

Traces and vias without a net inherit the single net of physically connected
copper, including connections through pads and vias across layers. Existing
assignments are preserved. Disconnected copper and copper touching more than one
net stay unassigned.

The ratsnest shows connections the schematic requires but the copper has not
joined. Routing a connection removes its ratsnest line.

## Design rules

The sidebar lists design-rule violations as you edit. Checks cover shorts,
clearance, holes, board edges, minimum trace length and unrouted connections.

Copper is judged against copper of another net. Touching is a short, and coming
closer than the clearance without touching is the clearance itself. Copper the
design has not named is copper it says nothing about, and is left alone; copper
of one net is free to touch itself. A hole carries no net at all, so everything
has to stand clear of one, and so it does of the cut edge. What the netlist asks
for and no copper joins is listed too — the same connections the ratsnest draws.

Each routed trace segment must meet **Min trace length** in the layout inspector's **Globals** panel,
including traces inside imported modules and traces without a net. Length is measured
between the segment's endpoints. The picker offers **None**, **0.1 mm** (the default)
and **0.3 mm**. Shorter segments appear in the sidebar, on the layout and in fabrication
preflight alongside the other violations.

Every line is a place to go. Clicking one picks up the copper at fault, turns to
the layer it stands on and scrolls it into the middle of the view. Everything
but an unrouted connection is also ringed where it stands on the layout, and the
rings follow a drag the way the ratsnest does, so a fault clears as the copper
that caused it moves away.

## Layers

A board is drawn on one of three stackups rather than on a bare layer count.
Classic is two copper layers, Digital four and Analog six, indexed from the top:

| Stackup | Layers |
| --- | --- |
| Classic | `SIG` `SIG` |
| Digital | `SIG` `GND` `VCC` `SIG` |
| Analog | `SIG` `GND` `VCC` `VEE` `GND` `SIG` |

The outer two are the signal layers, and they are the ones drawn on. Everything
between them is a plane, and which net it carries is the stackup's to say rather
than the drawing's: the sidebar reports the pairing but does not offer it for
editing, and a net a plane stands on cannot be deleted. Choosing a stackup that
wants one brings the net with it.

A plane fills the board and clears around every pad, via, hole and trace that
carries a different net. It joins what is drilled through it, so a through-hole
pad or a via on the plane's net needs no ratsnest line to reach the rest of that
net, while copper that only ever touches an outer layer still does.

Supply labels on a module assign its component pins to `GND`, `VCC` or `VEE`.
Those nets join the parent's supply nets by name. Place a power inlet such as
MTA-156-3 on the parent and label its pins with the matching rails. On the
layout, a via carrying the same net joins its internal plane; a short trace
from a surface-mount pad to the via completes that pad's connection. Placing
a via nearby alone does not connect the pad.

Changing the stackup keeps the drawing: copper on the top stays on the top and
copper on the bottom follows the bottom to wherever the new stackup puts it.

## 3D preview

`⌘3` previews the assembled board with its parts, copper, solder mask and drilled
holes. The preview starts with the board's solder-mask setting. Its **Mask**
picker offers **None**, **Green** and **Black** to change the preview without
changing the saved board or fabrication output. Preview choices persist when
switching views; changing solder mask in Board settings updates the preview too.

| Key | View |
| --- | --- |
| `T` | Top |
| `B` | Bottom |
| `F` | Front |
| `A` | Angled |

The 3D preview shows the outer copper layers.

## Fabrication

`⌘⇧E` writes the manufacturing set into a folder: a Gerber for every copper
layer, solder mask and paste for both faces, the board outline, Excellon drill
programs split into plated and non-plated, and the two lists assembly needs.
Files are named after the document and carry the extension their layer is known
by, the way `jlcpcb.com` expects to find them. There is no silkscreen: the board
carries no legend.

| File | Holds |
| --- | --- |
| `Amp.GTL` `Amp.GBL` | the outer copper layers |
| `Amp.G1` … `Amp.G4` | the planes between them |
| `Amp.GTS` `Amp.GBS` | solder mask |
| `Amp.GTP` `Amp.GBP` | solder paste |
| `Amp.GKO` | the board outline |
| `Amp-PTH.DRL` `Amp-NPTH.DRL` | plated and bare drills |
| `Amp-BOM.csv` | what to buy |
| `Amp-CPL.csv` | where it goes |

Nothing is written before the board has been looked over. A set asked for while
a rule is broken says how many are broken and what the first of them are, and
going ahead anyway is a button; turning back takes the layout to the first.

With solder mask enabled, pads open the mask and vias do not, so vias come back
tented. Turning it off in Board settings writes a full-board opening into each
mask Gerber, leaving both faces unmasked.

The bill of materials groups parts with the same value and package. The placement
list includes each fitted part's position, board face and rotation.

Not everything drawn is fitted. A part carries its own place in the bill, turned
off in the sidebar for a panel jack, a test pad or anything else the board is
drawn around rather than populated with, and a part left out is neither bought
nor placed.

## Documents

Save designs as `.xcb` files using the standard macOS document commands.
A document contains the paired schematic and board. Module source designs remain
separate files; keep them available alongside the parent design or in its module
search folders.

## Modularity

Any `.xcb` design can be imported into another as a module. Save and edit it with
the usual schematic and layout tools. Set pin net labels in the inspector,
such as `#1 IN`, `#2 OUT` and `#3 ENABLE`. The number immediately after `#` must
be a positive integer, followed by whitespace and a nonempty, case-sensitive
net name. `#1 OUT1` creates the net `OUT1` and exposes IO pin 1 named `OUT1`.
A repeated IO number must use the same name and resolve to the same net.
Matching net labels connect separate parts of an interface net.

To use a module parameter, set a schematic part's value to `#NAME`, such as
`#RESISTANCE`. The name runs from `#` to the next whitespace or the end of the
value. Repeated, case-sensitive names share one parameter. With nothing selected,
the inspector's **Parameters** panel lists these names and their editable defaults.
New parameters start with an empty default; names disappear when no schematic
value uses them. Save the source and reload modules in the parent.
Select an instance to edit its **Parameters**;
each instance keeps its own overrides. The reset arrow restores the source value,
including future source changes. Parameters appear inside the schematic block as
one `RESISTANCE: 10k` line per parameter. The schematic canvas displays resolved
values in place of `#NAME`. Opening a module instance passes its effective
parameter values to the source schematic for that editing session, including
forwarded parameters, while preserving the source's saved defaults and references.
Defaults apply to the source layout and
bill of materials; instance overrides apply to imported parts, including nested
modules. A child instance's parameter override can use `#NAME` to forward a
parameter from its containing module.

Save the parent design before importing modules. Xcopper searches its folder
and subfolders, including folders reached through Finder aliases or symbolic
links. Module names must be unique regardless of letter case. For a shared
library, place an alias to its folder within the parent's search folders.

Choose **Objects → Place Module** (`M`) to open a searchable list of module names.
Select a module and choose **Place**, or double-click it. The current document is
excluded from the list. Module pickers, inspectors and schematic blocks show names
without file extensions. After validating its
dependencies, Xcopper shows a preview that follows the pointer in the current
schematic or layout. Click to place it on the active placement grid; `Esc` or
**Cancel** discards the preview. Nothing is added until the click, and placement
is one undoable action. The counterpart in the other view is parked automatically.
Starting from 3D switches to layout for placement. The schematic block
lists IO pins in ascending numeric order. A module can import other modules, provided each
source has no more copper layers than its containing design. Circular dependencies
and duplicate module names are rejected.

Wire the block's pins; the board updates automatically. Use qualified labels such
as `M1.NET` to connect to a module's local nets. `GND`, `VCC` and `VEE` are shared
between instances. The parent board's stackup and design rules apply to imported
modules.

Click an imported layout part to inspect it individually, or click a pad directly
to inspect its net and dimensions. `⌘`-click any imported object or
empty space inside its layout rectangle to select the whole instance. Schematic
blocks and layout box selection select whole instances. A layout selection box
must contain a part's center; overlapping its body or pads is insufficient. Move, quarter-turn,
duplicate, copy, paste or delete a selected instance using the usual
commands. A duplicate has a new identity and both representations; deleting
either representation removes both. `⌘J` shows the counterpart. The inspector
edits the instance reference and each representation's position and rotation.
In schematic mode it also edits the net label on each IO pin. Click the **Source**
name to choose another module from the same searchable list, including
a renamed source or an alternate implementation. The selected instance keeps its
identity, reference, positions, rotations, pin labels and parameter overrides.
The replacement and its dependencies are validated before the change is applied;
if its IO changes, check the parent wires, which keep their coordinates.
Imported internals remain locked, including nested modules; use **Open Module
Source** to edit them, or select a single module in schematic mode and press `Enter`.
Flipping modules and assigning layout nets to imported internals are disabled.
Moving a layout group keeps its geometry rigid and stretches parent traces
attached to its pads or vias. If trace repair fails, the whole move is refused.
Rotating a group leaves external copper in place.

After editing a source, choose **File → Reload Modules** in its parent. Sources
also reload when the parent opens or moves. Placements stay fixed. If the IO list
changes, check the parent wires as the notice requests.

Missing, malformed, cyclic or incompatible dependencies appear as unresolved
blocks and layout rectangles. The Modules panel explains how to recover.
Fabrication stays blocked until every dependency resolves. Stack reductions that
would invalidate an imported module are refused.

macOS may ask you to select a source's containing folder to grant access. Select a
shared parent folder, such as `Modules`, to cover its subfolders. Xcopper remembers
the grant. Moving the parent to another folder may require a new grant.

Module imports, edits and explicit reloads are undoable. Changes in the parent do
not modify source files.

## MCP access

See [MCP.md](MCP.md) for setup, the tool reference, routing, and example workflows.

## Developer reference

See [SPEC.md](SPEC.md) for document formats, editing rules and implementation details.
