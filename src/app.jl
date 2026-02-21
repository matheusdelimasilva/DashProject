# ─── DevTools ────────────────────────────────────────────────────────────────

struct DevTools
    ui::Bool
    props_check::Bool
    serve_dev_bundles::Bool
    hot_reload::Bool
    hot_reload_interval::Float64
    hot_reload_watch_interval::Float64
    hot_reload_max_retry::Int
    silence_routes_logging::Bool
    prune_errors::Bool

    function DevTools(debug=false;
                      ui=nothing, props_check=nothing,
                      serve_dev_bundles=nothing, hot_reload=nothing,
                      hot_reload_interval=nothing, hot_reload_watch_interval=nothing,
                      hot_reload_max_retry=nothing, silence_routes_logging=nothing,
                      prune_errors=nothing)
        @env_default!(ui, Bool, debug)
        @env_default!(props_check, Bool, debug)
        @env_default!(serve_dev_bundles, Bool, debug)
        @env_default!(hot_reload, Bool, debug)
        @env_default!(silence_routes_logging, Bool, debug)
        @env_default!(prune_errors, Bool, debug)
        @env_default!(hot_reload_interval, Float64, 3.0)
        @env_default!(hot_reload_watch_interval, Float64, 0.5)
        @env_default!(hot_reload_max_retry, Int, 8)

        return new(ui, props_check, serve_dev_bundles, hot_reload,
                   hot_reload_interval, hot_reload_watch_interval,
                   hot_reload_max_retry, silence_routes_logging, prune_errors)
    end
end

# ─── DashConfig ──────────────────────────────────────────────────────────────

struct DashConfig
    external_stylesheets::Vector{ExternalSrcType}
    external_scripts::Vector{ExternalSrcType}
    url_base_pathname::Union{String,Nothing}
    requests_pathname_prefix::String
    routes_pathname_prefix::String
    assets_folder::String
    assets_url_path::String
    assets_ignore::String
    assets_external_path::Union{String,Nothing}
    include_assets_files::Bool
    serve_locally::Bool
    suppress_callback_exceptions::Bool
    prevent_initial_callbacks::Bool
    eager_loading::Bool
    meta_tags::Vector{Dict{String,String}}
    show_undo_redo::Bool
    compress::Bool
    update_title::String
    # Dash 2.x additions
    pages_folder::String
    use_pages::Bool
    health_endpoint::String
    # Phase 3 additions
    include_pages_meta::Bool
    routing_callback_inputs::Dict{String,Any}
    background_callback_manager::Union{AbstractBackgroundManager,Nothing}
end

# ─── DashApp ─────────────────────────────────────────────────────────────────

const DEFAULT_INDEX = """<!DOCTYPE html>
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
</html>"""

"""
    DashApp

Internal representation of a Dash application. Create instances via `dash()`.
"""
mutable struct DashApp
    root_path::String
    is_interactive::Bool
    config::DashConfig
    index_string::Union{String,Nothing}
    title::String
    layout::Union{Nothing,Component,Function}
    devtools::DevTools
    # Dash 2.x dual callback storage
    callback_list::Vector{Dict{String,Any}}
    callback_map::Dict{String,Callback}
    inline_scripts::Vector{String}
    # Dash 2.x additions
    hooks::Union{Nothing,Dict{String,Any}}
    on_error::Union{Nothing,Function}
    # Phase 3 additions
    _pages_setup_done::Bool

    function DashApp(root_path, is_interactive, config, index_string, title="Dash")
        new(root_path, is_interactive, config, index_string, title,
            nothing, DevTools(dash_env(Bool, "debug", false)),
            Dict{String,Any}[], Dict{String,Callback}(), String[],
            nothing, nothing,
            false)
    end
end

# Property access control — only layout, title, index_string are settable
function Base.setproperty!(app::DashApp, property::Symbol, value)
    property == :index_string && return set_index_string!(app, value)
    property == :layout && return set_layout!(app, value)
    property == :title && return set_title!(app, value)
    property in fieldnames(DashApp) && error("The property `$(property)` of `DashApp` is read-only")
    error("The property `$(property)` of `DashApp` does not exist.")
end

function set_title!(app::DashApp, title)
    setfield!(app, :title, title)
end

function set_layout!(app::DashApp, component::Union{Component,Function})
    setfield!(app, :layout, component)
end

get_layout(app::DashApp) = app.layout

function check_index_string(index_string::AbstractString)
    validate_index("index_string", index_string, [
        "{%app_entry%}" => r"{%app_entry%}",
        "{%config%}" => r"{%config%}",
        "{%scripts%}" => r"{%scripts%}",
    ])
end

function set_index_string!(app::DashApp, index_string::AbstractString)
    check_index_string(index_string)
    setfield!(app, :index_string, index_string)
end

get_devsetting(app::DashApp, name::Symbol) = getproperty(app.devtools, name)

get_assets_path(app::DashApp) = joinpath(app.root_path, app.config.assets_folder)

# ─── enable_dev_tools! ───────────────────────────────────────────────────────

"""
    enable_dev_tools!(app; debug=true, kwargs...)

Activate development tools. Called automatically by `run_server` when `debug=true`.
"""
function enable_dev_tools!(app::DashApp; debug=nothing,
                           dev_tools_ui=nothing,
                           dev_tools_props_check=nothing,
                           dev_tools_serve_dev_bundles=nothing,
                           dev_tools_hot_reload=nothing,
                           dev_tools_hot_reload_interval=nothing,
                           dev_tools_hot_reload_watch_interval=nothing,
                           dev_tools_hot_reload_max_retry=nothing,
                           dev_tools_silence_routes_logging=nothing,
                           dev_tools_prune_errors=nothing)
    @env_default!(debug, Bool, true)
    setfield!(app, :devtools, DevTools(debug;
        ui=dev_tools_ui,
        props_check=dev_tools_props_check,
        serve_dev_bundles=dev_tools_serve_dev_bundles,
        hot_reload=dev_tools_hot_reload,
        hot_reload_interval=dev_tools_hot_reload_interval,
        hot_reload_watch_interval=dev_tools_hot_reload_watch_interval,
        hot_reload_max_retry=dev_tools_hot_reload_max_retry,
        silence_routes_logging=dev_tools_silence_routes_logging,
        prune_errors=dev_tools_prune_errors
    ))
end

# ─── dash() Factory Function ─────────────────────────────────────────────────

"""
    dash(; kwargs...)

Create a new Dash application.

# Keyword Arguments
- `external_stylesheets` — additional CSS files
- `external_scripts` — additional JS files
- `url_base_pathname` — base URL for the app
- `requests_pathname_prefix` — prefix for AJAX requests
- `routes_pathname_prefix` — prefix for API routes
- `assets_folder` — path to static assets (default: "assets")
- `serve_locally` — serve JS/CSS locally (default: true)
- `suppress_callback_exceptions` — skip callback validation (default: false)
- `prevent_initial_callbacks` — prevent callbacks on initial load (default: false)
- `meta_tags` — HTML meta tags
- `index_string` — custom HTML template
- `compress` — enable gzip compression (default: true)
- `update_title` — title during callback execution (default: "Updating...")
- `pages_folder` — multi-page folder (default: "pages")
- `use_pages` — enable multi-page routing (default: false)
- `health_endpoint` — health check URL path (default: "_dash-health")
- `include_pages_meta` — include OG/Twitter meta tags for pages (default: true)
- `background_callback_manager` — default background callback manager

# Example
```julia
app = dash()
app.layout = html_div() do
    html_h1("Hello Dash2!")
end
run_server(app)
```
"""
function dash(;
    external_stylesheets=ExternalSrcType[],
    external_scripts=ExternalSrcType[],
    url_base_pathname=dash_env("url_base_pathname"),
    requests_pathname_prefix=dash_env("requests_pathname_prefix"),
    routes_pathname_prefix=dash_env("routes_pathname_prefix"),
    assets_folder="assets",
    assets_url_path="assets",
    assets_ignore="",
    serve_locally=true,
    suppress_callback_exceptions=dash_env(Bool, "suppress_callback_exceptions", false),
    prevent_initial_callbacks=false,
    eager_loading=false,
    meta_tags=Dict{String,String}[],
    index_string=DEFAULT_INDEX,
    assets_external_path=dash_env("assets_external_path"),
    include_assets_files=dash_env(Bool, "include_assets_files", true),
    show_undo_redo=false,
    compress=true,
    update_title="Updating...",
    # Dash 2.x additions
    pages_folder="pages",
    use_pages=false,
    health_endpoint="_dash-health",
    # Phase 3 additions
    include_pages_meta=true,
    routing_callback_inputs=Dict{String,Any}(),
    background_callback_manager=nothing
)
    check_index_string(index_string)
    config = DashConfig(
        external_stylesheets,
        external_scripts,
        pathname_configs(url_base_pathname, requests_pathname_prefix, routes_pathname_prefix)...,
        assets_folder,
        lstrip(assets_url_path, '/'),
        assets_ignore,
        assets_external_path,
        include_assets_files,
        serve_locally,
        suppress_callback_exceptions,
        prevent_initial_callbacks,
        eager_loading,
        meta_tags,
        show_undo_redo,
        compress,
        update_title,
        pages_folder,
        use_pages,
        health_endpoint,
        include_pages_meta,
        routing_callback_inputs,
        background_callback_manager
    )
    return DashApp(app_root_path(), isinteractive(), config, index_string)
end

# Do-block syntax for layout: dash() do ... end
function dash(layout_func::Function; kwargs...)
    app = dash(; kwargs...)
    app.layout = layout_func()
    return app
end
