# Dash2.jl — Project Context for Claude

## What is this project?
Dash2.jl is a Julia package that provides a complete Dash 2.x/3.x compatible web application framework. It replaces the aging Dash.jl v1.5.1 with a modern implementation supporting all Dash 2.x features.

## Key references
- **Implementation plan**: `IMPLEMENTATION_PLAN.md` — full architecture, types, protocols, phase breakdown
- **Python Dash source**: `../dash/dash/` — canonical reference implementation
- **Existing Dash.jl**: `../Dash.jl/src/` — patterns and approaches to build upon
- **Artifact metadata**: `~/.julia/artifacts/cf73063fdfc374bc98925f87ac967051cdee66e5/` — YAML metadata + JS bundles

## Architecture overview
- Core types in `src/app.jl` (DashConfig, DashApp, DevTools)
- Component system in `src/components/` (Component type, registry, code generation from YAML)
- Callback engine in `src/callbacks/` (Input/Output/State, registration, dispatch, context)
- HTTP server in `src/server/` (HTTP.jl based, custom router, all Dash endpoints)
- Frontend in `src/frontend/` (index page generation, resource management, fingerprinting)
- Dash 2.x values in `src/values/` (NoUpdate, PreventUpdate, Patch)

## Conventions
- Snake_case for all Julia functions and variables
- Component functions follow `prefix_name` pattern: `html_div`, `dcc_input`, `dash_datatable`
- Do-block syntax for callbacks: `callback!(app, Output(...), Input(...)) do val ... end`
- JSON3.jl for all JSON serialization with custom StructTypes
- YAML metadata loaded from artifacts at module `__init__` time
- `task_local_storage()` for thread-safe callback context

## Dependencies
HTTP.jl, JSON3.jl, CodecZlib.jl, YAML.jl, MD5.jl, UUIDs, DataStructures.jl, Sockets, Pkg

## Testing
Run: `julia --project=. -e "using Pkg; Pkg.test()"`
Test files in `test/` — `runtests.jl` is entry point
