# Dash2.jl — Implementation Progress

## Current Status: Phase 1 & 2 Complete

**Test suite: 139 tests pass, 0 failures**

---

## Phase 1: MVP — "Hello Dash" Works [COMPLETE]

### Task 1.1: Project Setup [DONE]
- `Project.toml` with dependencies: HTTP, JSON3, CodecZlib, YAML, MD5, UUIDs, DataStructures, Sockets, Pkg
- `Artifacts.toml` pointing to existing DashCoreResources v2.10.2 (same artifact as Dash.jl)
- Directory structure: `src/{components,callbacks,server,frontend,pages,values,utils}`, `test/`, `assets/`

### Task 1.2: Core Types [DONE]
- **File**: `src/app.jl`
- `DashConfig` — immutable config struct with all Dash 2.x fields (pages_folder, use_pages, health_endpoint)
- `DashApp` — mutable app struct with dual callback storage (`callback_list` + `callback_map`), hooks, on_error
- `DevTools` — dev tools config with environment variable support via `@env_default!`
- `dash()` factory function with full keyword arguments + do-block layout syntax
- `enable_dev_tools!()` for activating dev mode
- Property access control — only `layout`, `title`, `index_string` are settable

### Task 1.3: Component System [DONE]
- **Files**: `src/components/component.jl`, `registry.jl`, `generation.jl`
- `Component` struct absorbed from DashBase — no external dependency needed
- Full property access: `getproperty`, `setproperty!`, `hasproperty`, wildcard props (`data-*`, `aria-*`)
- Component tree lookup via `getindex` with recursive ID search
- `Resource`, `ResourcePkg`, `ResourcesRegistry` — full resource type system
- `ComponentRegistry` with `children_props` tracking for Dash 2.x config JSON
- Code generation from YAML metadata at module load time via `@place_embedded_components`
- All components generated: `html_div`, `html_h1`, `html_p`, `dcc_input`, `dcc_graph`, `dash_datatable`, etc.
- JSON serialization: `Component → {"type": ..., "namespace": ..., "props": {...}}`

### Task 1.4: Values (Sentinels) [DONE]
- **Files**: `src/values/no_update.jl`, `prevent_update.jl`, `patch.jl`
- `NoUpdate` singleton with JSON serialization (`{"_dash_no_update": "_dash_no_update"}`)
- `PreventUpdate` exception (triggers HTTP 204 response)
- `InvalidCallbackReturnValue` exception for validation errors

### Task 1.5: Callback Engine [DONE]
- **Files**: `src/callbacks/dependencies.jl`, `context.jl`, `registration.jl`, `dispatch.jl`, `grouping.jl`
- `Input`, `Output`, `State` dependency types with `allow_duplicate` support on Output
- `Wildcard` types: `MATCH`, `ALL`, `ALLSMALLER` with JSON serialization
- `CallbackDeps` bundle, `Callback` struct, `ClientsideFunction`
- `callback!` with three signatures: do-block, explicit vectors, flat deps
- Callback validation (output/input checks, function arity)
- `CallbackContext` using `task_local_storage()` for thread-safe context
- Dispatch handler for `_dash-update-component` POST requests
- Response building with `multi`, `response`, `sideUpdate` fields
- Return validation for multi-output callbacks

### Task 1.6: HTTP Server [DONE]
- **Files**: `src/server/router.jl`, `handlers.jl`, `endpoints.jl`, `server.jl`
- Custom router with `StaticRoute` and `DynamicRoute` (URL parameter extraction)
- Middleware chain: state injection → exception handling → gzip compression
- All 9 required endpoints implemented:
  - `GET /` and `/*` — index HTML page (catch-all)
  - `GET /_dash-layout` — layout JSON
  - `GET /_dash-dependencies` — callback specs JSON
  - `POST /_dash-update-component` — callback dispatch
  - `GET /_dash-component-suites/<pkg>/<path>` — component JS/CSS bundles
  - `GET /assets/<path>` — static files
  - `GET /_favicon.ico` — default favicon
  - `GET /_reload-hash` — hot reload polling
  - `GET /_dash-health` — health check (new in Dash 2.x)
- `HandlerState`, `StateCache`, `StateReload` for server state management
- `make_handler()` builds complete handler with precompilation pass
- `run_server()` starts HTTP.jl server with dev tools configuration

### Task 1.7: Frontend Integration [DONE]
- **Files**: `src/frontend/index.jl`, `resources.jl`, `fingerprint.jl`
- Index page generation with `{%placeholder%}` template interpolation
- HTML section builders: `metas_html`, `css_html`, `scripts_html`, `config_html`, `renderer_html`, `favicon_html`
- `ApplicationResources` collection from registry (CSS, JS, assets, favicon)
- Fingerprinting for cache busting (`build_fingerprint` / `parse_fingerprint_path`)
- Dash 2.x config JSON includes `children_props`, `serve_locally`, `update_title`
- Asset walking with ignore regex support

### Task 1.8: Module Entry Point [DONE]
- **File**: `src/Dash2.jl`
- Correct include order (utils → values → components → dependencies → app → callbacks → frontend → server → pages → generation)
- `__init__` function loads metadata, sets up renderer/dash resources, registers children_props
- `@place_embedded_components` generates all component functions at precompilation time
- Full export list: `dash`, `run_server`, `callback!`, `Input`, `Output`, `State`, `Patch`, `no_update`, `PreventUpdate`, `MATCH`, `ALL`, `ALLSMALLER`, etc.

### Task 1.9: Utilities [DONE]
- **File**: `src/utils.jl`
- Environment variable helpers: `dash_env`, `@env_default!`
- Path utilities: `app_root_path`, `pathname_configs`
- HTML helpers: `format_tag`, `interpolate_string`, `validate_index`
- Misc: `generate_hash`, `sorted_json`, `parse_props`, `mime_by_path`

---

## Phase 2: Full Dash 2.x Protocol [COMPLETE]

### Task 2.1: Patch Objects [DONE]
- **File**: `src/values/patch.jl`
- `Patch` type with location tracking and parent operation list
- All 13 operations: Assign, Delete, Append, Prepend, Insert, Extend, Remove, Clear, Reverse, Merge, Add, Sub, Mul, Div
- Julia-idiomatic interface: `setindex!`, `push!`, `append!`, `delete!`, `merge!`, `insert!`
- Nested access: `p["items"]` returns a child Patch targeting parent's operations
- JSON serialization: `{"__dash_patch_update": "__dash_patch_update", "operations": [...]}`

### Task 2.2: set_props via Context [DONE]
- **File**: `src/callbacks/context.jl`
- `set_props(component_id, props)` stores updates in `CallbackContext.updated_props`
- Dispatch handler includes `sideUpdate` in response when `updated_props` is non-empty
- `triggered_id()` helper for getting the triggering component ID

### Task 2.3: Flexible Callback Signatures [DONE]
- **File**: `src/callbacks/grouping.jl`
- `flatten_grouping` — recursively flatten nested structures (vectors, tuples, dicts)
- `grouping_len` — count scalar values in nested structures
- `make_grouping_by_index` — reconstruct nested structure from flat values
- `map_grouping` — apply function to all scalar values preserving structure

### Task 2.4: allow_duplicate Outputs [DONE]
- `allow_duplicate` field on `Output` dependency type
- Registration logic skips duplicate-output validation when flag is set
- Tested: multiple callbacks can target the same output property

### Task 2.5: Clientside Callbacks [DONE]
- `ClientsideFunction(namespace, function_name)` type
- `make_callback_func!` converts JS string to `ClientsideFunction` + inline script
- Inline scripts injected into index page
- `clientside_function` field added to callback_list entries

### Task 2.6: Expanded Config JSON [DONE]
- `config_html` includes `children_props` from `ComponentRegistry`
- `serve_locally` field in config
- Hot reload config with interval and max_retry

---

## Phase 3: Pages + Background Callbacks [STUBS ONLY]

### Task 3.1: Page Registry [STUB]
- **File**: `src/pages/pages.jl`
- `PAGE_REGISTRY` OrderedDict created
- `register_page()` function with basic field storage
- Not yet integrated into routing or auto-discovery

### Task 3.2: Background Callbacks [STUB]
- **File**: `src/callbacks/background.jl`
- `AbstractBackgroundManager` abstract type defined
- `ThreadPoolManager` struct defined
- Not yet integrated into callback dispatch

### Remaining Phase 3 Work
- [ ] Page auto-discovery from `pages/` folder
- [ ] Routing callback for page navigation
- [ ] Path template matching (`/asset/<asset_id>`)
- [ ] Page meta tags (title, description, og:image)
- [ ] Background callback execution with `Threads.@spawn`
- [ ] Progress reporting via dedicated output
- [ ] Cancellation support

---

## Phase 4: Polish + Production Readiness [NOT STARTED]

- [ ] Hot reload with file watching + `Revise.jl` integration
- [ ] Comprehensive error handling (JSON errors for callbacks, HTML debug pages with stack traces)
- [ ] Testing utilities module (`make_test_app()`, `fire_callback()`)
- [ ] Documentation + examples
- [ ] Performance optimization (precompilation hints, response caching)
- [ ] Component validation (`validate()` for duplicate IDs)
- [ ] Renderer hooks support

---

## Test Suite Summary

```
Test Summary: | Pass  Total  Time
Dash2.jl      |  139    139  5.7s
  Components                    21
  DashApp                       26
  Callbacks                     27
  Patch                         16
  Dispatch                      22
  Server                        10
```

### Test Files
- `test/runtests.jl` — entry point
- `test/test_components.jl` — component creation, properties, wildcards, JSON, tree lookup
- `test/test_app.jl` — dash() factory, config, layout, devtools, pathname_configs
- `test/test_callbacks.jl` — dependency types, registration, multi-output, allow_duplicate, clientside, context, validation
- `test/test_patch.jl` — all operations, nested access, JSON serialization, is_patch
- `test/test_dispatch.jl` — NoUpdate, PreventUpdate, split_callback_id, grouping utilities, callback execution, set_props
- `test/test_server.jl` — router, fingerprint, compression, exception handling, make_handler + endpoints

---

## File Structure

```
Dash2.jl/
  Project.toml                    # Dependencies
  Artifacts.toml                  # DashCoreResources v2.10.2
  CLAUDE.md                       # Project context for Claude
  IMPLEMENTATION_PLAN.md          # Full architecture plan
  PROGRESS.md                     # This file
  assets/
    favicon.ico                   # Default favicon
  src/
    Dash2.jl                      # Module entry point + exports
    app.jl                        # DashConfig, DashApp, DevTools, dash()
    utils.jl                      # Env vars, paths, HTML helpers, misc
    components/
      component.jl                # Component type (absorbed from DashBase)
      registry.jl                 # Resource, ResourcePkg, ResourcesRegistry, ComponentRegistry
      generation.jl               # YAML metadata loading + component function generation
    callbacks/
      dependencies.jl             # Input, Output, State, Wildcard, Callback, ClientsideFunction
      context.jl                  # CallbackContext, set_props, triggered_id
      registration.jl             # callback!, check_callback, make_callback_func!
      dispatch.jl                 # _dash-update-component handler, response building
      grouping.jl                 # flatten_grouping, make_grouping_by_index, map_grouping
      background.jl               # AbstractBackgroundManager, ThreadPoolManager (stub)
    server/
      router.jl                   # StaticRoute, DynamicRoute, Router
      handlers.jl                 # Middleware: state, compression, exception handling
      endpoints.jl                # All endpoint implementations
      server.jl                   # HandlerState, make_handler, run_server
    frontend/
      fingerprint.jl              # Cache busting
      resources.jl                # ApplicationResources, asset walking
      index.jl                    # Index page generation
    pages/
      pages.jl                    # PAGE_REGISTRY, register_page (stub)
  test/
    runtests.jl
    test_app.jl
    test_callbacks.jl
    test_components.jl
    test_dispatch.jl
    test_patch.jl
    test_server.jl
```
