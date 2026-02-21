# Dash2.jl Implementation Plan

## Overview

Dash2.jl is a modern Julia port of Plotly Dash, compatible with Dash 2.x/3.x. It replaces the aging Dash.jl v1.5.1 (which only supports Dash 1.5) with a complete rewrite that adds Pages system, Patch objects, set_props, flexible callback signatures, background callbacks, allow_duplicate outputs, and full Dash 2.x frontend protocol support.

## Key Design Decisions

### 1. Absorb DashBase into Dash2.jl
- Dash.jl depends on external `DashBase` package for `Component`, `Resource`, `ResourcePkg`, `ResourcesRegistry`
- Dash2.jl brings all of this inline — no external dependency
- Component type, resource types, and registry are defined directly in Dash2.jl

### 2. Reuse Existing YAML Metadata + JS Artifacts
- The existing `dash_resources` artifact (v2.10.2) from DashCoreResources contains:
  - YAML metadata files: `dash.yaml`, `dash_html_components.yaml`, `dash_core_components.yaml`, `dash_table.yaml`, `dash_renderer.yaml`
  - JS/CSS bundles for all component packages and the dash-renderer
- Dash2.jl reuses these same artifacts via `Artifacts.toml`
- Component wrapper functions are generated from the YAML metadata at module load time (same approach as Dash.jl)

### 3. HTTP.jl for Web Server
- Proven, minimal, full control over routing
- Dash needs < 10 routes — no framework necessary

### 4. JSON3.jl for Serialization
- Good performance, struct mapping support
- Custom serialization for Component, Patch, NoUpdate, Wildcard types

### 5. Dual Callback Storage (New in Dash 2.x)
- `callback_list::Vector{Dict}` — serialized for `_dash-dependencies` endpoint (frontend needs this)
- `callback_map::Dict{String, Callback}` — for fast dispatch lookup in `_dash-update-component`

---

## Project Structure

```
Dash2.jl/
  Project.toml                         # Dependencies: HTTP, JSON3, CodecZlib, YAML, MD5, UUIDs, etc.
  Artifacts.toml                       # Points to DashCoreResources v2.10.2 artifact
  src/
    Dash2.jl                           # Module entry: includes, exports, __init__
    app.jl                             # DashApp, DashConfig, DevTools, dash(), enable_dev_tools!
    utils.jl                           # General utilities (env, paths, misc helpers)
    components/
      component.jl                     # Component struct (absorbed from DashBase)
      registry.jl                      # Resource, ResourcePkg, ResourcesRegistry, ComponentRegistry
      generation.jl                    # Generate component wrapper functions from YAML metadata
    callbacks/
      dependencies.jl                  # Input, Output, State, Wildcard types, CallbackDeps
      registration.jl                  # callback!, @callback macro, check_callback
      dispatch.jl                      # _dash-update-component handler, callback execution
      context.jl                       # CallbackContext, task_local_storage-based
      grouping.jl                      # Flexible signature support (flatten/reconstruct)
      background.jl                    # BackgroundManager (Phase 3)
    server/
      router.jl                        # Route matching (static + dynamic routes)
      handlers.jl                      # Middleware (compression, error handling, state)
      endpoints.jl                     # All endpoint implementations
      server.jl                        # run_server() entry point
    frontend/
      index.jl                         # Index HTML page generation
      resources.jl                     # Resource collection, setup_renderer, setup_dash
      fingerprint.jl                   # Cache busting (build/parse fingerprinted paths)
    pages/
      pages.jl                         # Pages system (Phase 3)
      registry.jl                      # PAGE_REGISTRY (Phase 3)
    values/
      no_update.jl                     # NoUpdate sentinel
      prevent_update.jl                # PreventUpdate exception
      patch.jl                         # Patch object for partial updates
  test/
    runtests.jl
    test_app.jl
    test_components.jl
    test_callbacks.jl
    test_dispatch.jl
    test_patch.jl
    test_server.jl
```

---

## Phase 1: MVP — "Hello Dash" Works

**Goal**: A minimal working Dash app that renders a layout and fires callbacks.

### Task 1.1: Project Setup
- `Project.toml` with deps: HTTP, JSON3, CodecZlib, YAML, MD5, UUIDs, DataStructures, Sockets, Pkg
- `Artifacts.toml` pointing to existing DashCoreResources v2.10.2

### Task 1.2: Core Types (`src/app.jl`)

```julia
# DashConfig — immutable config, constructed via keyword arguments
Base.@kwdef struct DashConfig
    external_stylesheets::Vector{Union{String, Dict{String,String}}} = []
    external_scripts::Vector{Union{String, Dict{String,String}}} = []
    url_base_pathname::Union{String, Nothing} = nothing
    requests_pathname_prefix::String = "/"
    routes_pathname_prefix::String = "/"
    assets_folder::String = "assets"
    assets_url_path::String = "assets"
    assets_ignore::String = ""
    assets_external_path::Union{String, Nothing} = nothing
    include_assets_files::Bool = true
    serve_locally::Bool = true
    suppress_callback_exceptions::Bool = false
    prevent_initial_callbacks::Bool = false
    eager_loading::Bool = false
    meta_tags::Vector{Dict{String,String}} = []
    show_undo_redo::Bool = false
    compress::Bool = true
    update_title::String = "Updating..."
    # New in Dash 2.x:
    pages_folder::String = "pages"
    use_pages::Bool = false
    health_endpoint::String = "_dash-health"
    background_callback_manager::Any = nothing
end

# DashApp — mutable app struct
mutable struct DashApp
    root_path::String
    is_interactive::Bool
    config::DashConfig
    index_string::Union{String, Nothing}
    title::String
    layout::Union{Nothing, Component, Function}
    devtools::DevTools
    # Dash 2.x dual callback storage:
    callback_list::Vector{Dict{String,Any}}
    callback_map::Dict{String, Callback}
    inline_scripts::Vector{String}
    # New fields:
    page_registry::OrderedDict{String, Dict{String,Any}}
    hooks::Union{Nothing, Dict{String,Any}}
    on_error::Union{Nothing, Function}
end
```

### Task 1.3: Component System (`src/components/`)

**Component struct** (absorbed from DashBase):
```julia
struct Component
    name::String       # e.g. "html_div"
    type::String       # e.g. "Div"
    namespace::String  # e.g. "dash_html_components"
    props::Dict{Symbol, Any}
    available_props::Set{Symbol}
    wildcard_regex::Union{Nothing, Regex}
end
```

**Resource types** (absorbed from DashBase):
```julia
struct Resource
    relative_package_path::Union{Nothing, Vector{String}}
    dev_package_path::Union{Nothing, Vector{String}}
    external_url::Union{Nothing, Vector{String}}
    type::Symbol  # :js or :css
    async::Symbol  # :none, :eager, :lazy
end

struct ResourcePkg
    namespace::String
    path::String
    resources::Vector{Resource}
    version::String
end

mutable struct ResourcesRegistry
    components::Dict{String, ResourcePkg}
    dash_dependency::Union{Nothing, NamedTuple{(:dev,:prod), Tuple{ResourcePkg,ResourcePkg}}}
    dash_renderer::Union{Nothing, ResourcePkg}
end
```

**ComponentRegistry** (new for Dash 2.x):
```julia
mutable struct ComponentRegistry
    namespaces::Set{String}
    children_props::Dict{String, Dict{String, Vector{String}}}
    namespace_to_package::Dict{String, String}
end
```

**Component generation** — same approach as Dash.jl:
- `generate_component!()` reads YAML metadata and creates exported functions like `html_div()`, `dcc_input()`
- `@place_embedded_components` macro executes at module load time

### Task 1.4: Values (`src/values/`)

```julia
# NoUpdate sentinel
struct NoUpdate end
const no_update = NoUpdate()

# PreventUpdate exception
struct PreventUpdate <: Exception end

# Patch (full in Phase 2, placeholder here)
```

### Task 1.5: Callback Engine (`src/callbacks/`)

**Dependency types**:
```julia
struct Wildcard
    type::Symbol  # :MATCH, :ALL, :ALLSMALLER
end
const MATCH = Wildcard(:MATCH)
const ALL = Wildcard(:ALL)
const ALLSMALLER = Wildcard(:ALLSMALLER)

struct Dependency{Trait, IdT}
    id::IdT
    property::String
    allow_duplicate::Bool  # new (Output only)
end
const Input = Dependency{TraitInput}
const Output = Dependency{TraitOutput}
const State = Dependency{TraitState}
```

**Callback registration** — `callback!` with do-block syntax:
```julia
callback!(func, app, outputs, inputs, states; prevent_initial_call, allow_duplicate)
```

**CallbackContext** — uses `task_local_storage()`:
```julia
mutable struct CallbackContext
    response::HTTP.Response
    inputs::Dict{String, Any}
    states::Dict{String, Any}
    triggered::Vector{Dict{String, Any}}
    triggered_id::Union{String, Dict, Nothing}
    triggered_prop_ids::Dict{String, Any}
    outputs_list::Vector
    inputs_list::Vector
    states_list::Vector
    # Dash 2.x additions:
    updated_props::Dict{String, Dict{String, Any}}  # for set_props → sideUpdate
end
```

### Task 1.6: HTTP Server (`src/server/`)

**Routes** (from MAKE_A_NEW_BACK_END.md):
| Route | Method | Handler |
|---|---|---|
| `/` and `/*` | GET | `process_index` — returns HTML page |
| `/_dash-layout` | GET | `process_layout` — returns layout JSON |
| `/_dash-dependencies` | GET | `process_dependencies` — returns callback specs |
| `/_dash-update-component` | POST | `process_callback` — dispatch callbacks |
| `/_dash-component-suites/<pkg>/<path>` | GET | `process_resource` — serve JS/CSS |
| `/_reload-hash` | GET | `process_reload_hash` — hot reload |
| `/_favicon.ico` | GET | `process_favicon` — default favicon |
| `/assets/<path>` | GET | `process_assets` — static files |
| `/_dash-health` | GET | `process_health` — health check (new) |

**Router** — same pattern as Dash.jl with static + dynamic route matching.

### Task 1.7: Frontend Integration (`src/frontend/`)

**Index page** template with `{%placeholder%}` interpolation:
```html
<!DOCTYPE html>
<html>
    <head>
        {%metas%}
        <title>{%title%}</title>
        {%favicon%}
        {%css%}
    </head>
    <body>
        {%app_entry%}
        <footer>
            {%config%}
            {%scripts%}
            {%renderer%}
        </footer>
    </body>
</html>
```

**Config JSON** (embedded in `<script id="_dash-config">`):
```json
{
    "url_base_pathname": "/",
    "requests_pathname_prefix": "/",
    "ui": true,
    "props_check": true,
    "show_undo_redo": false,
    "suppress_callback_exceptions": false,
    "update_title": "Updating...",
    "children_props": { ... },
    "serve_locally": true
}
```

### Task 1.8: Module Entry Point (`src/Dash2.jl`)

Exports:
- `dash`, `run_server`, `enable_dev_tools!`
- `Component`, `callback!`, `@callback`
- `Input`, `Output`, `State`
- `PreventUpdate`, `no_update`, `NoUpdate`
- `ALL`, `MATCH`, `ALLSMALLER`
- `Patch`
- `callback_context`, `set_props`
- `html_*`, `dcc_*`, `dash_datatable` (component functions)

---

## Phase 2: Full Dash 2.x Protocol

### Task 2.1: Patch Objects (`src/values/patch.jl`)
```julia
mutable struct Patch
    _location::Vector{Union{String, Int}}
    _operations::Vector{Dict{String, Any}}
end
```
Operations: Assign, Delete, Append, Prepend, Insert, Extend, Remove, Clear, Reverse, Merge, Add, Sub, Mul, Div

JSON format:
```json
{"__dash_patch_update": "__dash_patch_update", "operations": [...]}
```

Julia-idiomatic interface:
- `setindex!(p, val, key)` → Assign
- `push!(p, val)` → Append
- `append!(p, vals)` → Extend
- `delete!(p, key)` → Delete
- `merge!(p, dict)` → Merge

### Task 2.2: set_props via CallbackContext
```julia
function set_props(component_id::String, props::Dict)
    ctx = callback_context()
    ctx.updated_props[component_id] = merge(get(ctx.updated_props, component_id, Dict()), props)
end
```
Produces `sideUpdate` in response JSON.

### Task 2.3: Flexible Callback Signatures
Dict-based inputs/outputs:
```julia
callback!(app, output=Output("o","children"), inputs=Dict("val" => Input("i","value"))) do val
    return "Hello $val"
end
```
Requires porting `_grouping.py`: `flatten_grouping`, `make_grouping_by_index`, `map_grouping`.

### Task 2.4: allow_duplicate Outputs
Flag on `Output` type. Skip duplicate-output validation when set.

### Task 2.5: Clientside Callbacks
```julia
clientside_callback!(app, "function(val) { return val; }", Output("o","children"), Input("i","value"))
```
Generates inline JS, stores `ClientsideFunction` in callback_map.

### Task 2.6: @callback Macro (Module-level)
```julia
@callback(app, Output("o","children"), Input("i","value")) do value
    return "Hello $value"
end
```

### Task 2.7: Expanded Config JSON
Add `children_props` field to config (maps namespace → component → children prop names).

---

## Phase 3: Pages + Background Callbacks

### Task 3.1: Page Registry
```julia
const PAGE_REGISTRY = OrderedDict{String, Dict{String,Any}}()

function register_page(module_name; path=nothing, name=nothing, layout=nothing, order=nothing, ...)
    # Register page in PAGE_REGISTRY
end
```

### Task 3.2: Page Auto-discovery
Scan `pages/` folder for `.jl` files, `include()` each, register pages.

### Task 3.3: Background Callbacks
```julia
abstract type AbstractBackgroundManager end
struct ThreadPoolManager <: AbstractBackgroundManager end
```
Uses `Threads.@spawn` for long-running callbacks with progress/cancel support.

---

## Phase 4: Polish

- Hot reload with Revise.jl integration
- Comprehensive error handling (JSON errors for callbacks, HTML debug pages)
- Testing utilities module
- Documentation + examples
- Performance (precompilation, caching)

---

## Critical Reference: Callback Dispatch Protocol

### Request (POST `_dash-update-component`):
```json
{
    "inputs": [{"id": "comp-id", "property": "value", "value": "current-val"}],
    "state": [{"id": "state-id", "property": "value", "value": "state-val"}],
    "output": "output-id.children",
    "outputs": {"id": "output-id", "property": "children"},
    "changedPropIds": ["comp-id.value"]
}
```

### Response:
```json
{
    "multi": true,
    "response": {
        "output-id": {"children": "new value"}
    }
}
```

### With Patch:
```json
{
    "multi": true,
    "response": {
        "output-id": {
            "children": {
                "__dash_patch_update": "__dash_patch_update",
                "operations": [
                    {"operation": "Assign", "location": ["key"], "params": {"value": 123}}
                ]
            }
        }
    }
}
```

### With sideUpdate (from set_props):
```json
{
    "multi": true,
    "response": { ... },
    "sideUpdate": {
        "other-component": {"value": 42}
    }
}
```

### NoUpdate sentinel:
```json
{"_dash_no_update": "_dash_no_update"}
```

---

## Critical Reference: Component JSON Format

```json
{
    "type": "Div",
    "namespace": "dash_html_components",
    "props": {
        "id": "my-div",
        "children": "Hello World",
        "style": {"color": "red"}
    }
}
```

---

## Critical Reference: _dash-dependencies Format

```json
[
    {
        "output": "output-id.children",
        "inputs": [{"id": "input-id", "property": "value"}],
        "state": [],
        "prevent_initial_call": false
    }
]
```

For multi-output:
```json
{
    "output": "..output1.children...output2.value..",
    "inputs": [...],
    "state": [...],
    "prevent_initial_call": false
}
```

---

## Critical Reference: Artifact Structure

Path: `~/.julia/artifacts/cf73063fdfc374bc98925f87ac967051cdee66e5/`

```
dash.yaml                              # Main manifest: version, embedded_components, deps
dash_renderer.yaml                     # Renderer metadata: version, deps, js_dist_dependencies
dash_html_components.yaml              # HTML components: name, prefix, components list
dash_core_components.yaml              # DCC components metadata
dash_table.yaml                        # DataTable components metadata
dash_deps/                             # JS/CSS bundle files
  dcc/                                 # Core component JS files
    dash_core_components.js
    async-dropdown.js
    plotly.min.js
    ...
  html/                                # HTML component JS files
    dash_html_components.min.js
  dash_table/                          # Table component JS files
    bundle.js
    async-table.js
    ...
dash_renderer_deps/                    # Renderer JS files
  dash_renderer.min.js
  react@16.14.0.min.js
  react-dom@16.14.0.min.js
  prop-types@15.8.1.min.js
```

## YAML Metadata Format

### dash.yaml
```yaml
version: 2.10.2
build: 0
embedded_components:
  - dash_core_components
  - dash_html_components
  - dash_table
deps:
  - namespace: "dash"
    resources:
      - async: true
        type: js
        external_url: "..."
        relative_package_path: "dcc/async-datepicker.js"
      - type: js
        dynamic: true
        ...
```

### dash_html_components.yaml
```yaml
version: "2.0.12"
name: "dash_html_components"
prefix: "html"
components:
  - name: A
    args: [shape, dir, key, loading_state, ..., children, id, href, ...]
    wild_args: [data, aria]
    docstr: "An A component..."
  - name: Div
    args: [...]
    wild_args: [data, aria]
    docstr: "..."
```

### dash_renderer.yaml
```yaml
version: "1.14.0"
deps:
  - resources:
    - type: js
      relative_package_path: "dash_renderer.min.js"
      ...
js_dist_dependencies:
  dev:
    - relative_package_path: "react@16.14.0.min.js"
      external_url: "..."
    - relative_package_path: "react-dom@16.14.0.min.js"
      ...
  prod:
    - relative_package_path: "react@16.14.0.min.js"
      ...
```

---

## Key Differences from Dash.jl v1.5

| Feature | Dash.jl v1.5 | Dash2.jl |
|---|---|---|
| Callback storage | Single `Dict{Symbol, Callback}` | Dual: `callback_list` + `callback_map` |
| DashBase | External package dependency | Absorbed into Dash2.jl |
| Metadata format | YAML (via DashBase artifacts) | YAML (same artifacts, loaded directly) |
| Component packages | External (DashCoreComponents, etc.) | Bundled as submodules |
| Callback context | Custom `TaskContextStorage` | `task_local_storage()` (simpler) |
| Patch objects | Not supported | Full support |
| set_props | Not supported | Via `CallbackContext.updated_props` → sideUpdate |
| allow_duplicate | Not supported | Flag on Output |
| Pages system | Not supported | `PageRegistry`, auto-discovery |
| Background callbacks | Not supported | `ThreadPoolManager` |
| Flexible signatures | Not supported | Dict-based inputs/outputs |
| Health endpoint | Not supported | Configurable `/_dash-health` |
| @callback macro | Not supported | Module-level registration |
| Config JSON | Basic fields | Expanded with `children_props`, `dash_version`, etc. |

---

## Reference: Python Dash Source Files

Located at: `/Users/matheussilva/Desktop/Dash Project Opus/dash/dash/`

| File | What to reference for |
|---|---|
| `dash.py` | DashApp init params, _setup_routes, dispatch, config generation, index page |
| `_callback.py` | Callback registration, GLOBAL_CALLBACK_LIST/MAP, dispatch flow |
| `dependencies.py` | Input/Output/State classes, handle_callback_args |
| `_patch.py` | Patch object implementation |
| `_callback_context.py` | CallbackContext properties and methods |
| `_grouping.py` | Flexible signature support functions |
| `_pages.py` | Pages system, register_page, PAGE_REGISTRY |
| `_no_update.py` | NoUpdate sentinel |
| `resources.py` | Resource types, Scripts, Css classes |
| `development/base_component.py` | Component base class, ComponentRegistry |

## Reference: Existing Dash.jl Source Files

Located at: `/Users/matheussilva/Desktop/Dash Project Opus/Dash.jl/src/`

| File | What to reuse |
|---|---|
| `app/dashapp.jl` | DashApp structure, dash() factory, default_index template |
| `app/config.jl` | DashConfig fields |
| `app/supporttypes.jl` | Dependency types, Wildcard, CallbackDeps patterns |
| `app/callbacks.jl` | callback! registration, _process_callback_args |
| `app/devtools.jl` | DevTools struct with env defaults |
| `Contexts/Contexts.jl` | Thread-safe context storage pattern |
| `handler/processors/callback.jl` | Callback dispatch logic |
| `handler/index_page.jl` | Index page generation helpers |
| `handler/make_handler.jl` | Router setup and middleware chain |
| `init/resources.jl` | YAML metadata loading, resource setup |
| `init/components.jl` | Component generation from metadata |
| `utils/fingerprint.jl` | Cache busting fingerprint logic |
| `utils/misc.jl` | format_tag, interpolate_string, sorted_json |
| `HttpHelpers/router.jl` | Route matching system |
