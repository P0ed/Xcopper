# MCP access

Xcopper uses the local, dependency-free `MCPS` Swift package at [../MCPS](https://github.com/P0ed/MCPS),
which hosts Streamable HTTP using Apple's Network framework. Use **AI Access → Start MCP Server**
to listen at `http://127.0.0.1:8765/mcp`, and **Stop MCP Server** to disconnect clients
and close the listener. The server starts stopped on every app launch.

In **Settings → AI Access**, choose a workspace folder and, optionally, a different
port from 1024 through 65535 while the server is stopped. Configuration persists.
The workspace uses a security-scoped bookmark; paths are resolved against it and
symlinks cannot extend its access. Document creation requires a relative `.pcb`
path whose parent folder exists. Other paths may be workspace-relative or absolute
inside that folder. Already open documents keep their native access grants and can
be inspected, edited and saved without selecting a workspace. Module loading also
accepts folder grants previously retained through **Reload Modules**. Missing grants
return instructions to select a workspace or grant the module folder in the app;
automatic module loading does not open permission dialogs.

Copy the generated bearer token or connection JSON from the settings pane. The
token is stored in Keychain. Regenerating it stops the listener and disconnects
existing clients; copy the new token and start the server again. A client configuration
using the common `mcpServers` JSON format looks like this; adapt it to your client's
configuration format:

```json
{
  "mcpServers": {
    "xcopper": {
      "type": "http",
      "url": "http://127.0.0.1:8765/mcp",
      "headers": {
        "Authorization": "Bearer COPY_TOKEN_FROM_AI_ACCESS"
      }
    }
  }
}
```

Clients must support [MCP Streamable HTTP](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports),
including SSE responses. Initialize a session at `/mcp`, then send its
`MCP-Session-Id` and negotiated `MCP-Protocol-Version` headers on subsequent requests.
Each session has its own permit, pending calls and event stream. Requests require the bearer
token, a Host of `127.0.0.1:PORT` or `localhost:PORT`, and, if supplied, the matching
`http://` Origin. The listener binds only to IPv4 loopback. Sessions expire after
one hour without requests; clients can terminate a session with HTTP DELETE.

All 34 tools start with `xcopper_` and advertise input schemas and read/write
annotations through `tools/list`. Results contain structured JSON and the same JSON
as text for clients that only display text content. `render_design` also returns
an inline PNG image; its base64 data is excluded from the JSON metadata.

| Tools after the `xcopper_` prefix | Purpose |
| --- | --- |
| `list_documents`, `create_document`, `open_document`, `save_document`, `close_document` | Manage native documents independently of window focus; closing saves first |
| `get_design`, `get_netlist`, `render_design`, `search_library`, `list_module_sources`, `check_design` | Inspect settings, objects, placed geometry, resolved nets, specifications, module interfaces and diagnostics |
| `apply_edits`, `configure_design`, `place_part`, `update_part`, `set_pin_labels` | Configure dimensions, layers, rules and parameters; edit paired parts and connectivity labels |
| `add_wires`, `route_traces`, `place_via`, `place_hole`, `update_objects` | Add orthogonal wires and 45-degree copper routes, and edit copper or holes |
| `plan_connection`, `apply_connection` | Preview and commit one connection using native obstacle-aware routing |
| `transform_objects`, `delete_objects` | Move, rotate, flip, duplicate or delete in the explicit `schematic` or `layout` view |
| `place_module`, `update_module`, `replace_module_source`, `reload_modules` | Validate and manage module instances, source changes, positions, rotations, labels and parameter overrides |
| `undo`, `redo`, `reveal_objects`, `fit_view`, `export_fabrication` | Use native history, reveal objects and export Gerber, drill, BOM and placement files |

Geometry uses integer micrometres. Rotations are clockwise degrees: `0`, `90`, `180`
or `270`. Copper layers are zero based, with routing on the top and bottom signal
layers. Vias use the board's global drill and pad rules. `search_library` returns
`spec` objects accepted by `place_part`; select exactly one of `component`,
`symbolKind` or `footprintKind`. Placing either view creates both the symbol and
footprint. Optional `labels` assigns pin connectivity during placement, with the
same pin-number keys and null/empty clearing behavior as `set_pin_labels`. An omitted counterpart position is parked using the same model helpers
as manual placement. Pins and pads include their placed coordinates and resolved
net assignments in `get_design` and full edit responses.

`list_documents` gives each live document a runtime `documentId` and `revision`.
Design edits, Undo/Redo and reveal requests require `expectedRevision`. Object
handles include the document and revision and must be copied from the latest
inspection. Batches can use `$id` aliases for earlier placement results within
that request. Aliases are temporary and are returned as current handles after
commit. Human edits and native history changes advance revisions too. On
`stale_revision`, inspect again and rebuild the request with current handles. Runtime
IDs, revisions and handles are never written into `.pcb` files.

Edits operate on a candidate design on the main actor, validate it, synchronize
connectivity and commit through the document binding in one Undo group. A failed
edit leaves the design unchanged. Movement reuses connection-preserving routing;
deletion removes both sides of paired parts. `busy` means a gesture, route, module
placement, editing field, dialog or file operation needs to finish first. Imported
module internals and pad geometry return `read_only`; edit their source documents
or use native part pin labels. Module instances support translations and quarter
turns; flipping a module is unsupported.

Existing mutation tools keep full responses by default. Pass `response: "compact"`
to receive the document summary, `previousRevision`, `changes.created`,
`changes.updated`, deleted previous-revision handles, and relevant design settings,
connectivity changes and notices. Compact create/open/save responses contain the
document summary. `apply_edits` and `apply_connection` default to compact; both
accept `response: "full"`. All handles still expire when the revision changes.
`get_design` accepts `sections`, `references` and `nets` to refresh selected data;
reference filtering applies to parts/modules, and net filtering follows resolved
pin/pad/copper assignments. Board settings and summary metadata remain included.

`apply_edits` accepts 1–256 ordered `operations`, each containing `tool` (without
`xcopper_`), `arguments`, and an optional unique `id`. Document ID, revision and
response mode belong to the outer request. Design edits include module edits;
file operations, export, history, nested batches and viewport operations are
excluded. Connectivity synchronizes after each operation, and the group commits
once with an optional `name` for Undo. A failure reports a zero-based
`operationIndex` and optional `operationId`, leaving design, revision and history
unchanged. `$id` object aliases refer to earlier part/module/via/hole placements.
Deletion remaps surviving references. Geometry repair invalidates removed or
ambiguous copper targets, which must be addressed in a subsequent inspected
request. `dryRun: true` returns proposed geometry and diagnostics without committing,
changing editor state or issuing live handles.

`check_design` returns structured `islands` and `connections` with revision-scoped
IDs, resolved net identities, pad references and pin numbers, terminal geometry,
layers, actual ratsnest endpoints and plane destinations. Physical violations
include precise object/pad handles, owner handles, net identities and `measured`
and `required` distances in micrometres. Route-finishing failures include the
junction, original vertex index when available, turn angle, segment directions and
lengths, grid and attempted repair. Complete polylines are finalized in a canonical
order so reversing an equivalent request produces the same result.

`plan_connection` is read-only and requires the inspected `expectedRevision`.
Supply either a `connection` ID from `check_design`, or `from` and `to` handles for
assigned pads, traces, vias or islands. Set `to: "plane"` for the source net's plane.
Endpoints must share a resolved net. Optional `layers`, `width`, `clearance`,
`viaLimit`, `grid` and `maxNodes` constrain the search. Defaults are both outer
signal layers, board width/clearance, four vias, a 100 µm grid and 200,000 visited
states. Clearance cannot be weaker than the board rule. Search preserves existing
placement and copper, respects unassigned copper and holes, and uses through vias.
It runs off the main actor and supports cancellation. This is a bounded connection
helper; it does not reorder nets, rip up copper or route a whole board.

Planning returns exact proposed traces/vias, length, visited states, resulting
violations (without live candidate-object handles) and a
`proposalId`, after verifying native connectivity and absence of new physical
DRC faults. Unrelated existing faults and unrouted nets do not block it. Apply with
`apply_connection` and the same revision to commit exactly that proposal in one
Undo step. Each document retains up to eight proposals for ten minutes. Any design
revision invalidates them. `no_path`, `search_exhausted`, `invalid_endpoint`,
`incompatible_nets`, `invalid_rules`, `routing_violations`, `cancelled` and
`stale_revision` distinguish recovery paths. A grid search can fail even when a
route at another resolution exists.

`render_design` takes `view`, optional `proposalId` to preview planned copper before
applying it, optional `bounds` (`origin` and `size` in µm), visible
`layers`, pixel `width`/`height` (64–2048, default 1024), `ratsnest` and `silkscreen`.
It uses the native layout drawing geometry or schematic renderer and returns
revision-tagged PNG metadata without changing the live viewport or selection.
`get_netlist` returns resolved hierarchical references, effective component values,
component identities, numbered pins and net assignments for external analysis.
It does not simulate the circuit. `reveal_objects` accepts an empty `objects` array
to clear selection; `fit_view` fits the board or sheet in the requested view.

Saving an untitled document requires `path`. Existing destinations for creation,
Save As and export require `overwrite: true`; saving a document to its current path
uses its existing grant. An open document cannot be overwritten by another one.
Fabrication export always blocks unresolved modules and returns diagnostics.
DRC findings require `allowViolations: true` to proceed. Export overwrites only the
named fabrication files, preserving other files in an existing destination folder.

## Example workflow

These are `tools/call` payloads after initialization. Replace `DOC` and each
revision/handle with the actual values returned by the preceding call.

```json
{"name":"xcopper_create_document","arguments":{"path":"mcp-demo.pcb"}}
```

Place two fully labeled parts in one transaction:

```json
{"name":"xcopper_apply_edits","arguments":{"documentId":"DOC","expectedRevision":1,"name":"AI: resistor network","operations":[{"id":"r1","tool":"place_part","arguments":{"spec":{"symbolKind":"resistor"},"view":"schematic","at":{"x":25400,"y":25400},"counterpartAt":{"x":20000,"y":20000},"reference":"R1","value":"10k","labels":{"1":"IN","2":"BUS"}}},{"id":"r2","tool":"place_part","arguments":{"spec":{"symbolKind":"resistor"},"view":"schematic","at":{"x":50800,"y":25400},"counterpartAt":{"x":30000,"y":20000},"reference":"R2","value":"10k","labels":{"1":"BUS","2":"OUT"}}}]}}
```

Add `dryRun: true` to preview the same batch first. Later operations can address
these placements as `"object":"$r1"` or `"object":"$r2"` within that batch.

```json
{"name":"xcopper_check_design","arguments":{"documentId":"DOC"}}
```

Use the BUS connection ID from diagnostics to preview and apply its route:

```json
{"name":"xcopper_plan_connection","arguments":{"documentId":"DOC","expectedRevision":2,"connection":"CONNECTION","layers":[0]}}
```

```json
{"name":"xcopper_apply_connection","arguments":{"documentId":"DOC","expectedRevision":2,"proposalId":"PROPOSAL"}}
```

Inspect the native preview and verify the resulting diagnostics before saving:

```json
{"name":"xcopper_render_design","arguments":{"documentId":"DOC","view":"layout","layers":[0],"width":1024,"height":768}}
```

```json
{"name":"xcopper_check_design","arguments":{"documentId":"DOC"}}
```

```json
{"name":"xcopper_save_document","arguments":{"documentId":"DOC","response":"compact"}}
```

```json
{"name":"xcopper_export_fabrication","arguments":{"documentId":"DOC","path":"mcp-demo-fabrication"}}
```

For modules, discover sources with `list_module_sources`, pass a returned `name`
as `source` to `place_module`, and set `schematicAt`, `layoutAt`, rotations, labels
or named parameter overrides as needed. Open a source's returned `path` within the
workspace to edit its internals, then reload the containing document's modules.

Manual verification should cover connection and authentication, Start/Stop and
relaunch behavior, document creation/open/save/close, paired geometry and net
synchronization, routing and transformations, module imports/replacement/reload,
batch Undo/Redo, dry-run isolation, proposal preview/application, native PNGs,
selection clearing and fit-view, rejection of stale revisions and busy edits, and the exported
fabrication files. Build validation does not exercise these UI interactions.
