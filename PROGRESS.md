# Dash2.jl — Implementation Progress

## Current Status: Phase 1, 2, & 3 Complete + Hot Reload

**Test suite: 269 tests pass, 0 failures**

---

## Latest Updates (Phase 3.5: Hot Reload)

**Server Restart on Julia File Changes** ✓
- Implemented `hot_restart(func; check_interval)` mechanism identical to Dash.jl
- Parent/child execution pattern using `Base.eval(Main, :(module X; include(file) end))`
- When any `.jl` file is saved → server closes → script re-evaluated → new server starts
- Browser detects new hash from fresh server instance → triggers reload
- Works from command line (`julia main.jl debug=true`) — unavailable in REPL

**Asset Hot Reload** ✓
- `start_reload_poll(state)` watches CSS/JS changes and component packages
- Updates reload hash for browser reload (with CSS hot-swap optimization)
- Separate async task — doesn't block server

**Source File Discovery** ✓
- `parse_includes(file)` walks AST to find all `.jl` files reachable via `include()` calls
- Ensures all application source files are monitored, not just the main script

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

## Phase 3: Pages + Background Callbacks [COMPLETE]

### Task 3.1: Page Registry System [DONE]
- **File**: `src/pages/pages.jl`
- `PAGE_REGISTRY` OrderedDict with full field tracking
- `register_page()` with path inference (`pages.foo` → `/foo`), image inference, name inference
- Path template matching (`<var>` placeholders) with variable extraction
- Query string parsing and page title/description callbacks
- Auto-discovery from `pages/` folder via `_import_layouts_from_pages()`
- Routing callback with multi-output support
- Page meta tags (description, og:title, og:image, twitter:card, etc.)

### Task 3.2: Background Callbacks [DONE]
- **File**: `src/callbacks/background.jl`
- `AbstractBackgroundManager` abstract type and interface
- `ThreadPoolManager` full implementation with result/progress/job tracking
- Task spawning via `Threads.@spawn` with cache keys
- Progress reporting to dedicated Output targets
- Job cancellation via interrupt scheduling
- Error handling and `PreventUpdate` support

### Task 3.3: Callback allow_duplicate [DONE]
- **File**: `src/callbacks/dependencies.jl`, `registration.jl`, `dispatch.jl`
- `allow_duplicate` flag on `Output` enables multiple callbacks to target same output
- Unique hashing via MD5 of input strings (`output_id@hash` format)
- Response JSON uses clean property names (hash stripped when applying to DOM)
- Full test coverage with 4 test cases

### Task 3.4: Server Integration [DONE]
- Pages system setup in `make_handler()` via `_setup_pages!(app)`
- Background cancel callbacks registered via `_setup_background_cancels!(app)`
- Page meta tags injected into `process_index` when enabled
- Correct include order in `src/Dash2.jl` (background before dependencies before pages)

---

## Phase 3.5: Hot Reload [COMPLETE]

### Task 3.5.1: File Watching [DONE]
- **File**: `src/utils.jl`
- `WatchState` struct for tracking file `mtime`
- `poll_until_changed(files; interval)` — blocks until any watched file changes
- `init_watched(folders)` — snapshot all file mtimes
- `poll_folders(on_change, folders, initial_watched; interval)` — async polling with callback
- Used by both server restart and asset reload mechanisms

### Task 3.5.2: Source File Discovery [DONE]
- `parse_includes(file)` — recursively discover all `.jl` files via AST analysis
- `_parse_includes!`, `_parse_elem!` — walk AST following `include()` calls
- Used to build complete list of Julia source files for hot reload monitoring

### Task 3.5.3: Server Restart on `.jl` Changes [DONE]
- **File**: `src/utils.jl`, `src/server/server.jl`
- `is_hot_restart_available()` — checks `!isinteractive() && !isempty(Base.PROGRAM_FILE)`
- `hot_restart(func; check_interval)` — parent/child execution pattern
  - **Parent path**: loops forever, re-evaluating script via `Base.eval(Main, :(module X; include(file) end))`
  - **Child path**: starts server, watches files, blocks until change, closes server
- When `.jl` file is saved → server closes → script re-evaluated → new server starts with updated code
- Browser detects new hash from fresh server → reloads and shows updated layout/callbacks

### Task 3.5.4: Asset Hot Reload [DONE]
- `start_reload_poll(state)` watches assets folder (CSS/JS) and component packages
- On asset change: updates reload hash (hard reload) or performs CSS hot-swap (soft reload)
- Separate from server restart mechanism — browser reload without server downtime

---

## Phase 4: Polish + Production Readiness [NOT STARTED]

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
Dash2.jl      |  269    269  10.4s
  Components                    21
  DashApp                       26
  Callbacks                     42
  Patch                         16
  Dispatch                      22
  Server                        10
  Pages                         14
  Background                    11
  Allow-Duplicate              18
```

### Test Files
- `test/runtests.jl` — entry point
- `test/test_components.jl` — component creation, properties, wildcards, JSON, tree lookup
- `test/test_app.jl` — dash() factory, config, layout, devtools, pathname_configs
- `test/test_callbacks.jl` — dependency types, registration, multi-output, allow_duplicate (robust renderer tests), clientside, context, validation
- `test/test_patch.jl` — all operations, nested access, JSON serialization, is_patch
- `test/test_dispatch.jl` — NoUpdate, PreventUpdate, split_callback_id, grouping utilities, callback execution, set_props
- `test/test_server.jl` — router, fingerprint, compression, exception handling, make_handler + endpoints
- `test/test_pages.jl` — register_page, path inference, image inference, sorting, template matching, query parsing, page container, meta tags
- `test/test_background.jl` — ThreadPoolManager, job lifecycle, progress updates, cancellation, PreventUpdate, errors, cache keys, Callback struct, background registration

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
      pages.jl                    # PAGE_REGISTRY, register_page, routing callback, meta tags
  test/
    runtests.jl
    test_app.jl
    test_callbacks.jl
    test_components.jl
    test_dispatch.jl
    test_patch.jl
    test_server.jl
    test_pages.jl                 # Pages system tests
    test_background.jl            # Background callbacks tests
```
