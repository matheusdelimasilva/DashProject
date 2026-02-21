# ─── Handler State ────────────────────────────────────────────────────────────

struct ChangedAsset
    url::String
    modified::Int
    is_css::Bool
end
JSON3.StructTypes.StructType(::Type{ChangedAsset}) = JSON3.StructTypes.Struct()

mutable struct StateReload
    hash::Union{String,Nothing}
    hard::Bool
    changed_assets::Vector{ChangedAsset}
    task::Union{Nothing,Task}
    StateReload(hash) = new(hash, false, ChangedAsset[], nothing)
end

mutable struct StateCache
    resources::ApplicationResources
    index_string::String
    dependencies_json::Vector{UInt8}
    need_recache::Bool
    StateCache(app, registry) = new(_cache_tuple(app, registry)..., false)
end

function _dependencies_json(app::DashApp)
    return Vector{UInt8}(JSON3.write(app.callback_list))
end

function _cache_tuple(app::DashApp, registry::ResourcesRegistry)
    app_resources = ApplicationResources(app, registry)
    idx_string::String = index_page(app, app_resources)
    deps_json = _dependencies_json(app)
    return (app_resources, idx_string, deps_json)
end

struct HandlerState
    app::DashApp
    registry::ResourcesRegistry
    cache::StateCache
    reload::StateReload
    HandlerState(app, registry=main_registry()) =
        new(app, registry, StateCache(app, registry), make_reload_state(app))
end

make_reload_state(app::DashApp) =
    get_devsetting(app, :hot_reload) ? StateReload(generate_hash()) : StateReload(nothing)

get_cache(state::HandlerState) = state.cache

function rebuild_cache!(state::HandlerState)
    cache = get_cache(state)
    (cache.resources, cache.index_string, cache.dependencies_json) =
        _cache_tuple(state.app, state.registry)
    cache.need_recache = false
end

# ─── Error Handling ──────────────────────────────────────────────────────────

function exception_handling(ex; prune_errors=false)
    st = stacktrace(catch_backtrace())
    @error "error handling request" exception = (ex, st)
    return HTTP.Response(500)
end

function debug_exception_handling(ex; prune_errors=false)
    response = HTTP.Response(500, ["Content-Type" => "text/html"])
    io = IOBuffer()
    write(io,
        "<!DOCTYPE HTML><html><head><style>",
        "body{font-family:monospace;padding:20px}",
        "pre{background:#f5f5f5;padding:15px;border:1px solid #ddd;overflow:auto}",
        "h1{color:#c00}",
        "</style></head><body>",
        "<h1>Dash2 Error</h1><pre>"
    )
    showerror(io, ex)
    write(io, "\n")
    st = stacktrace(catch_backtrace())
    Base.show_backtrace(io, st)
    write(io, "</pre></body></html>")
    response.body = take!(io)
    @error "error handling request" exception = (ex, st)
    return response
end

# ─── Layout Validation ───────────────────────────────────────────────────────

validate_layout(layout::Component) = nothing
validate_layout(layout::Function) = validate_layout(layout())
validate_layout(layout) = error("The layout must be a component, tree of components, or a function which returns a component.")

# ─── Make Handler ────────────────────────────────────────────────────────────

function make_handler(app::DashApp, registry::ResourcesRegistry; check_layout=false)
    state = HandlerState(app, registry)
    prefix = app.config.routes_pathname_prefix
    assets_url_path = app.config.assets_url_path
    health_endpoint = app.config.health_endpoint

    check_layout && validate_layout(app.layout)

    router = Router()
    add_route!(process_layout, router, "$(prefix)_dash-layout")
    add_route!(process_dependencies, router, "$(prefix)_dash-dependencies")
    add_route!(process_reload_hash, router, "$(prefix)_reload-hash")
    add_route!(process_default_favicon, router, "$(prefix)_favicon.ico")
    add_route!(process_resource, router, "$(prefix)_dash-component-suites/<namespace>/<path>")
    add_route!(process_assets, router, "$(prefix)$(assets_url_path)/<file_path>")
    add_route!(process_callback, router, "POST", "$(prefix)_dash-update-component")
    add_route!(process_health, router, "$(prefix)$(health_endpoint)")
    add_route!(process_index, router, "$prefix*")
    add_route!(process_index, router, "$prefix")

    handler = state_handler(router, state)

    if get_devsetting(app, :ui)
        handler = exception_handling_handler(handler) do ex
            debug_exception_handling(ex, prune_errors=get_devsetting(app, :prune_errors))
        end
    else
        handler = exception_handling_handler(handler) do ex
            exception_handling(ex, prune_errors=get_devsetting(app, :prune_errors))
        end
    end

    app.config.compress && (handler = compress_handler(handler))

    # Precompilation request
    compile_request = HTTP.Request("GET", prefix)
    HTTP.setheader(compile_request, "Accept-Encoding" => "gzip")
    handle(handler, compile_request)

    return handler
end

make_handler(app::DashApp) = make_handler(app, main_registry(), check_layout=true)

# ─── Run Server ──────────────────────────────────────────────────────────────

get_inetaddr(host::String, port::Integer) = Sockets.InetAddr(parse(IPAddr, host), port)
get_inetaddr(host::IPAddr, port::Integer) = Sockets.InetAddr(host, port)

"""
    run_server(app::DashApp, host="127.0.0.1", port=8050; debug=false, kwargs...)

Start the Dash HTTP server.

# Arguments
- `app` — DashApp instance
- `host` — hostname or IP (default: "127.0.0.1")
- `port` — port number (default: 8050)
- `debug` — enable dev tools (default: false)
"""
function run_server(app::DashApp,
                    host=dash_env("HOST", "127.0.0.1", prefix=""),
                    port=dash_env(Int64, "PORT", 8050, prefix="");
                    debug=nothing,
                    dev_tools_ui=nothing,
                    dev_tools_props_check=nothing,
                    dev_tools_serve_dev_bundles=nothing,
                    dev_tools_hot_reload=nothing,
                    dev_tools_hot_reload_interval=nothing,
                    dev_tools_hot_reload_watch_interval=nothing,
                    dev_tools_hot_reload_max_retry=nothing,
                    dev_tools_silence_routes_logging=nothing,
                    dev_tools_prune_errors=nothing)

    @env_default!(debug, Bool, false)
    enable_dev_tools!(app;
        debug,
        dev_tools_ui,
        dev_tools_props_check,
        dev_tools_serve_dev_bundles,
        dev_tools_hot_reload,
        dev_tools_hot_reload_interval,
        dev_tools_hot_reload_watch_interval,
        dev_tools_hot_reload_max_retry,
        dev_tools_silence_routes_logging,
        dev_tools_prune_errors
    )

    handler = make_handler(app)

    println("Dash2 is running on http://$(host):$(port)$(app.config.routes_pathname_prefix)")
    println("  * Debug mode: $(debug)")

    server = Sockets.listen(get_inetaddr(host, port))
    task = @async HTTP.serve(handler, host, port; server=server)

    try
        wait(task)
    catch e
        close(server)
        if e isa InterruptException
            println("\nDash2 server stopped.")
            return
        else
            rethrow(e)
        end
    end
end
