# ─── Component Code Generation ───────────────────────────────────────────────
# Generates Julia wrapper functions from YAML metadata at module load time.

using YAML

load_meta(name) = YAML.load_file(joinpath(artifact"dash_resources", "$(name).yaml"))

deps_path(name) = joinpath(artifact"dash_resources", "$(name)_deps")

dash_dependency_resource(meta) = Resource(
    relative_package_path=meta["relative_package_path"],
    external_url=meta["external_url"]
)

nothing_if_empty(v) = isempty(v) ? nothing : v

dash_module_resource(meta) = Resource(
    relative_package_path=nothing_if_empty(get(meta, "relative_package_path", "")),
    external_url=nothing_if_empty(get(meta, "external_url", "")),
    dev_package_path=nothing_if_empty(get(meta, "dev_package_path", "")),
    dynamic=get(meta, "dynamic", nothing),
    type=Symbol(meta["type"]),
    async=haskey(meta, "async") ? string(meta["async"]) : nothing
)

function setup_renderer_resources()
    renderer_meta = _metadata[].dash_renderer
    renderer_resource_path = joinpath(artifact"dash_resources", "dash_renderer_deps")
    renderer_version = renderer_meta["version"]
    _resources_registry.dash_dependency = (
        dev=ResourcePkg(
            "dash_renderer",
            renderer_resource_path, version=renderer_version,
            dash_dependency_resource.(renderer_meta["js_dist_dependencies"]["dev"])
        ),
        prod=ResourcePkg(
            "dash_renderer",
            renderer_resource_path, version=renderer_version,
            dash_dependency_resource.(renderer_meta["js_dist_dependencies"]["prod"])
        )
    )
    renderer_renderer_meta = renderer_meta["deps"][1]
    _resources_registry.dash_renderer = ResourcePkg(
        "dash_renderer",
        renderer_resource_path, version=renderer_version,
        dash_module_resource.(renderer_renderer_meta["resources"])
    )
end

function setup_dash_resources()
    meta = _metadata[].dash
    path = deps_path("dash")
    version = meta["version"]
    for dep in meta["deps"]
        register_package(
            ResourcePkg(
                dep["namespace"],
                path,
                version=version,
                dash_module_resource.(dep["resources"])
            )
        )
    end
end

function load_all_metadata()
    dash_meta = load_meta("dash")
    renderer_meta = load_meta("dash_renderer")
    components = Dict{Symbol,Any}()
    for comp in dash_meta["embedded_components"]
        components[Symbol(comp)] = filter(v -> v.first != "components", load_meta(comp))
    end
    return (
        dash=dash_meta,
        dash_renderer=renderer_meta,
        embedded_components=(; components...)
    )
end

# ─── Component Function Generation ──────────────────────────────────────────

function generate_component!(block, module_name, prefix, meta)
    args = isempty(meta["args"]) ? Symbol[] : Symbol.(meta["args"])
    wild_args = isempty(meta["wild_args"]) ? Symbol[] : Symbol.(meta["wild_args"])
    fname = string(prefix, "_", lowercase(meta["name"]))
    fsymbol = Symbol(fname)

    # Register children_props for Dash 2.x config
    children_props = String[]
    if in(:children, args)
        push!(children_props, "children")
    end

    append!(block.args,
        (quote
            export $fsymbol
            function $(fsymbol)(; kwargs...)
                available_props = $args
                wild_props = $wild_args
                return Component($fname, $(meta["name"]), $module_name, available_props, wild_props; kwargs...)
            end
        end).args
    )

    signatures = String[string(repeat(" ", 4), fname, "(;kwargs...)")]
    if in(:children, args)
        append!(block.args,
            (quote
                $(fsymbol)(children::Any; kwargs...) = $(fsymbol)(; kwargs..., children=children)
                $(fsymbol)(children_maker::Function; kwargs...) = $(fsymbol)(children_maker(); kwargs...)
            end).args
        )
        push!(signatures, string(repeat(" ", 4), fname, "(children::Any, kwargs...)"))
        push!(signatures, string(repeat(" ", 4), fname, "(children_maker::Function, kwargs...)"))
    end

    docstr = string(join(signatures, "\n"), "\n\n", meta["docstr"])
    push!(block.args, :(@doc $docstr $fsymbol))
end

function generate_components_package(meta)
    result = Expr(:block)
    name = meta["name"]
    prefix = meta["prefix"]
    for cmeta in meta["components"]
        generate_component!(result, name, prefix, cmeta)
    end
    return result
end

function generate_embedded_components()
    dash_meta = load_meta("dash")
    packages = dash_meta["embedded_components"]
    result = Expr(:block)
    for p in packages
        append!(result.args,
            generate_components_package(load_meta(p)).args
        )
    end
    return result
end

macro place_embedded_components()
    return esc(generate_embedded_components())
end

function register_embedded_children_props()
    dash_meta = load_meta("dash")
    for pkg_name in dash_meta["embedded_components"]
        pkg_meta = load_meta(pkg_name)
        namespace = pkg_meta["name"]
        register_component_namespace!(namespace)
        for cmeta in pkg_meta["components"]
            comp_name = cmeta["name"]
            props = String[]
            if "children" in cmeta["args"]
                push!(props, "children")
            end
            register_children_props!(namespace, comp_name, props)
        end
    end
end
