# PCB editor

Minimal PCB layout for macOS. No schematic capture: you place footprints, route
copper, and assign nets by hand. One rectangular board per document.

- 2, 4 or 6 copper layers
- Traces with 45° routing, vias, plated and non-plated holes
- Solid plane fills on internal layers, with automatic clearance knockouts
- Built-in parametric footprints: chip, SOIC, QFP, SOT-23, DIP, headers
- Lightweight named nets

## Tools

| Key | Tool |
| --- | --- |
| `S` | Select |
| `T` | Route |
| `V` | Via |
| `H` | Hole |
| `F` | Place footprint |

`1`…`6` pick the active copper layer; pressing the active layer's key hides it.
`⇥` / `⇧⇥` step through layers, `G` and `W` cycle grid and trace width.

While routing, segments snap to 45° and chain from the previous endpoint —
click, click, click. Hold `⇧` for a free angle, `⌃` to ignore pad snapping,
`⎋` to cancel.

## Layers

Copper layers are indexed from the top. On a 4 or 6 layer board any internal
layer can be turned into a plane by picking a net for it in the sidebar: the
plane fills the board and clears around every pad, via, hole and trace that
carries a different net.
