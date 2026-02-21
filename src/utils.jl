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
