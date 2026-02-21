module Dash2

using HTTP
using JSON3
using CodecZlib
using MD5
using UUIDs
using Sockets
using Pkg
using Pkg.Artifacts
using DataStructures

# ─── Utilities (must come first — used by everything) ────────────────────────
include("utils.jl")

# ─── Values (sentinel types) ────────────────────────────────────────────────
include("values/no_update.jl")
include("values/prevent_update.jl")
include("values/patch.jl")

# ─── Component System ───────────────────────────────────────────────────────
include("components/component.jl")
include("components/registry.jl")

# ─── Background Manager (abstract type needed before dependencies.jl) ────────
include("callbacks/background.jl")

# ─── Callback Dependencies (types needed before app.jl) ─────────────────────
include("callbacks/dependencies.jl")

# ─── Application Types ──────────────────────────────────────────────────────
include("app.jl")

# ─── Callback Engine ────────────────────────────────────────────────────────
include("callbacks/context.jl")
include("callbacks/grouping.jl")
include("callbacks/registration.jl")
include("callbacks/dispatch.jl")

# ─── Frontend (index page, resources, fingerprinting) ────────────────────────
include("frontend/fingerprint.jl")
include("frontend/resources.jl")
include("frontend/index.jl")

# ─── HTTP Server ─────────────────────────────────────────────────────────────
include("server/router.jl")
include("server/handlers.jl")
include("server/endpoints.jl")
include("server/server.jl")

# ─── Component Generation (loads metadata + generates wrapper functions) ─────
include("components/generation.jl")

# Module-level metadata storage — populated in __init__
const _metadata = Ref{Any}(nothing)

function __init__()
    _metadata[] = load_all_metadata()
    setup_renderer_resources()
    setup_dash_resources()
    register_embedded_children_props()
end

# Generate component wrapper functions at precompilation time
@place_embedded_components

# ─── Pages System (must come after component generation) ─────────────────────
include("pages/pages.jl")

# ─── Exports ─────────────────────────────────────────────────────────────────

# Core API
export dash, run_server, enable_dev_tools!

# Component type
export Component

# Callback API
export callback!, Input, Output, State
export PreventUpdate, no_update, NoUpdate
export Patch
export callback_context, triggered_id, set_props

# Wildcards
export ALL, MATCH, ALLSMALLER

# Clientside
export ClientsideFunction

# Pages (Phase 3)
export register_page, PAGE_REGISTRY

# Background (Phase 3)
export AbstractBackgroundManager, ThreadPoolManager

# Grouping utilities
export flatten_grouping, make_grouping_by_index, map_grouping

end # module Dash2
