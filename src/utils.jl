# ─── Environment Variables ───────────────────────────────────────────────────

const DASH_ENV_PREFIX = "DASH_"

dash_env_key(name::String; prefix=DASH_ENV_PREFIX) = prefix * uppercase(name)

dash_env(name::String, default=nothing; prefix=DASH_ENV_PREFIX) =
    get(ENV, dash_env_key(name; prefix), default)

function dash_env(::Type{T}, name::String, default=nothing; prefix=DASH_ENV_PREFIX) where {T<:Number}
    key = dash_env_key(name; prefix)
    !haskey(ENV, key) && return default
    return parse(T, lowercase(get(ENV, key, "")))
end

function dash_env(::Type{Bool}, name::String, default=nothing; prefix=DASH_ENV_PREFIX)
    key = dash_env_key(name; prefix)
    !haskey(ENV, key) && return default
    return lowercase(get(ENV, key, "")) in ("true", "1", "yes")
end

dash_env(::Type{String}, name::String, default=nothing; prefix=DASH_ENV_PREFIX) =
    dash_env(name, default; prefix)

macro env_default!(name, type=String, default=nothing)
    name_str = string(name)
    return esc(:(
        $name = isnothing($name) ?
            dash_env($type, $name_str, $default) :
            $name
    ))
end

# ─── Path Utilities ──────────────────────────────────────────────────────────

function program_path()
    (isinteractive() || isempty(Base.PROGRAM_FILE)) && return nothing
    return dirname(abspath(Base.PROGRAM_FILE))
end

function app_root_path()
    prog_path = program_path()
    return isnothing(prog_path) ? pwd() : prog_path
end

function pathname_configs(url_base_pathname, requests_pathname_prefix, routes_pathname_prefix)
    raise_error = (s) -> error("""
    $s This is ambiguous.
    To fix this, set `routes_pathname_prefix` instead of `url_base_pathname`.

    Note that `requests_pathname_prefix` is the prefix for the AJAX calls that
    originate from the client (the web browser) and `routes_pathname_prefix` is
    the prefix for the API routes on the backend (as defined within HTTP.jl).
    `url_base_pathname` will set `requests_pathname_prefix` and
    `routes_pathname_prefix` to the same value.
    If you need these to be different values then you should set
    `requests_pathname_prefix` and `routes_pathname_prefix`,
    not `url_base_pathname`.
    """)

    if !isnothing(url_base_pathname) && !isnothing(requests_pathname_prefix)
        raise_error("You supplied `url_base_pathname` and `requests_pathname_prefix`")
    end
    if !isnothing(url_base_pathname) && !isnothing(routes_pathname_prefix)
        raise_error("You supplied `url_base_pathname` and `routes_pathname_prefix`")
    end

    if !isnothing(url_base_pathname) && isnothing(routes_pathname_prefix)
        routes_pathname_prefix = url_base_pathname
    elseif isnothing(routes_pathname_prefix)
        routes_pathname_prefix = "/"
    end

    !startswith(routes_pathname_prefix, "/") && error("`routes_pathname_prefix` needs to start with `/`")
    !endswith(routes_pathname_prefix, "/") && error("`routes_pathname_prefix` needs to end with `/`")

    app_name = dash_env("APP_NAME")

    if isnothing(requests_pathname_prefix) && !isnothing(app_name)
        requests_pathname_prefix = "/" * app_name * routes_pathname_prefix
    elseif isnothing(requests_pathname_prefix)
        requests_pathname_prefix = routes_pathname_prefix
    end

    !startswith(requests_pathname_prefix, "/") &&
        error("`requests_pathname_prefix` needs to start with `/`")
    !endswith(requests_pathname_prefix, routes_pathname_prefix) &&
        error("`requests_pathname_prefix` needs to end with `routes_pathname_prefix`")

    return (url_base_pathname, requests_pathname_prefix, routes_pathname_prefix)
end

# ─── Misc Utilities ──────────────────────────────────────────────────────────

function format_tag(name::String, attributes::Dict{String,String}, inner::String=""; opened=false, closed=false)
    attrs_string = join(["$k=\"$v\"" for (k, v) in attributes], " ")
    tag = "<$name $attrs_string"
    if closed
        tag *= "/>"
    elseif opened
        tag *= ">"
    else
        tag *= ">$inner</$name>"
    end
    return tag
end

function interpolate_string(s::String; kwargs...)
    result = s
    for (k, v) in kwargs
        result = replace(result, "{%$(k)%}" => v)
    end
    return result
end

function validate_index(name::AbstractString, index::AbstractString, checks::Vector)
    missings = filter(checks) do check
        !occursin(check[2], index)
    end
    if !isempty(missings)
        error(string(
            "Missing item", (length(missings) > 1 ? "s" : ""), " ",
            join(getindex.(missings, 1), ", "),
            " in ", name
        ))
    end
end

function generate_hash()
    return strip(string(UUIDs.uuid4()), '-')
end

# ─── File-System Polling (Hot Reload) ────────────────────────────────────────

struct WatchState
    filename::String
    mtime::Float64
    WatchState(filename) = new(filename, mtime(filename))
end

"""
    poll_until_changed(files; interval=1.0)

Block the current task until the mtime of any file in `files` changes or
any file is deleted. Used by `hot_restart` to detect when the user saves a
`.jl` source file so the server can be restarted.
"""
function poll_until_changed(files::Set{String}; interval=1.0)
    watched = WatchState[]
    for f in files
        !isfile(f) && return
        push!(watched, WatchState(f))
    end
    active = true
    while active
        for w in watched
            if !isfile(w.filename) || mtime(w.filename) != w.mtime
                active = false
                break
            end
        end
        sleep(interval)
    end
end

"""
    init_watched(folders) → Dict{String,Float64}

Snapshot the modification times of every file under `folders`.
Returns a Dict mapping absolute path → mtime.
"""
function init_watched(folders)
    watched = Dict{String,Float64}()
    for folder in folders
        !isdir(folder) && continue
        for (base, _, files) in walkdir(folder)
            for f in files
                path = joinpath(base, f)
                watched[path] = mtime(path)
            end
        end
    end
    return watched
end

"""
    poll_folders(on_change, folders, initial_watched; interval=1.0)

Poll `folders` every `interval` seconds and call `on_change(path, new_mtime, deleted)`
whenever a file is added, modified, or removed.
- `deleted == true` means the file was removed (new_mtime == -1).
"""
function poll_folders(on_change, folders, initial_watched; interval=1.0)
    watched = initial_watched
    while true
        walked = Set{String}()
        for folder in folders
            !isdir(folder) && continue
            for (base, _, files) in walkdir(folder)
                for f in files
                    path = joinpath(base, f)
                    new_time = mtime(path)
                    if new_time > get(watched, path, -1.0)
                        on_change(path, new_time, false)
                    end
                    watched[path] = new_time
                    push!(walked, path)
                end
            end
        end
        # Detect deletions
        for path in collect(keys(watched))
            if !(path in walked)
                on_change(path, -1.0, true)
                delete!(watched, path)
            end
        end
        sleep(interval)
    end
end

# ─── Julia Source File Discovery ─────────────────────────────────────────────

function _parse_elem!(file::AbstractString, ex::Expr, dest::Set{String})
    if ex.head == :call && ex.args[1] == :include && length(ex.args) >= 2 && ex.args[2] isa String
        dir = dirname(file)
        include_file = normpath(joinpath(dir, ex.args[2]))
        _parse_includes!(include_file, dest)
        return
    end
    for arg in ex.args
        _parse_elem!(file, arg, dest)
    end
end
_parse_elem!(::AbstractString, ::Any, ::Set{String}) = nothing

function _parse_includes!(file::AbstractString, dest::Set{String})
    !isfile(file) && return
    file in dest && return
    push!(dest, abspath(file))
    ex = Base.parse_input_line(read(file, String); filename=file)
    _parse_elem!(file, ex, dest)
end

"""
    parse_includes(file) → Set{String}

Return the set of all `.jl` files reachable from `file` via literal
`include("path")` calls (recursive). Used by `hot_restart` to build the
complete list of source files to watch.
"""
function parse_includes(file::AbstractString)
    result = Set{String}()
    _parse_includes!(file, result)
    return result
end

# ─── Hot Restart ─────────────────────────────────────────────────────────────

"""
    is_hot_restart_available() → Bool

Returns `true` when Julia is running a script from the command line (not
interactively), which means `Base.PROGRAM_FILE` is set and the server can be
restarted by re-evaluating the script.
"""
is_hot_restart_available() = !isinteractive() && !isempty(Base.PROGRAM_FILE)

"""
    hot_restart(func; check_interval=1.0, env_key="DASH2_HOT_RELOADABLE")

Restart the server automatically whenever any Julia source file changes.

**Parent path** (first call): sets the env key, then loops forever —
re-evaluating the entire user script via `Base.eval` after each restart.

**Child path** (re-evaluated script calls `run_server` again): calls `func()`
to start the HTTP server, watches all `.jl` files reachable from the script,
blocks until any file changes, then closes the server. The parent loop then
re-evaluates the script to start a fresh server with the new code.
"""
function hot_restart(func::Function; check_interval=1.0, env_key="DASH2_HOT_RELOADABLE")
    app_path = abspath(Base.PROGRAM_FILE)

    if get(ENV, env_key, "false") == "true"
        # ── Child path: start server, watch files, close on change ──
        (server, _) = func()
        files = parse_includes(app_path)
        poll_until_changed(files; interval=check_interval)
        close(server)
    else
        # ── Parent path: set flag, loop re-evaluating the script ──
        ENV[env_key] = "true"
        try
            while true
                sym = gensym()
                task = @async Base.eval(Main,
                    :(module $(sym) include($app_path) end)
                )
                wait(task)
            end
        catch e
            if e isa InterruptException
                println("\nDash2 server stopped.")
                return
            else
                rethrow(e)
            end
        end
    end
end

sort_by_keys(data) = (; sort!(collect(pairs(data)), by=(x) -> x[1])...,)

sorted_json(data) = JSON3.write(sort_by_keys(data))

function parse_props(s)
    function make_prop(part)
        m = match(r"^(?<id>[A-Za-z]+[\w\-\:\.]*)\.(?<prop>[A-Za-z]+[\w\-\:\.]*)$", strip(part))
        isnothing(m) && error("expected <id>.<property>[,<id>.<property>...] in $(part)")
        return (Symbol(m[:id]), Symbol(m[:prop]))
    end
    props_parts = split(s, ",", keepempty=false)
    return map(make_prop, props_parts)
end

# ─── MIME Types ──────────────────────────────────────────────────────────────

function mime_by_path(path)
    endswith(path, ".js") && return "application/javascript"
    endswith(path, ".css") && return "text/css"
    endswith(path, ".map") && return "application/json"
    endswith(path, ".json") && return "application/json"
    endswith(path, ".html") && return "text/html"
    endswith(path, ".ico") && return "image/x-icon"
    endswith(path, ".png") && return "image/png"
    endswith(path, ".jpg") && return "image/jpeg"
    endswith(path, ".jpeg") && return "image/jpeg"
    endswith(path, ".svg") && return "image/svg+xml"
    endswith(path, ".gif") && return "image/gif"
    endswith(path, ".woff") && return "font/woff"
    endswith(path, ".woff2") && return "font/woff2"
    endswith(path, ".ttf") && return "font/ttf"
    return nothing
end
