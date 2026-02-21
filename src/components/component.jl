# ─── Component Type ──────────────────────────────────────────────────────────
# Absorbed from DashBase — no external dependency needed.

"""
    to_dash(t)

Convert a value to its Dash-compatible representation. By default, returns
the value unchanged. Override for custom types (e.g., PlotlyJS figures).
"""
to_dash(t::Any) = t

"""
    Component

Represents a Dash component (e.g., html.Div, dcc.Input, dash_table.DataTable).
Components have a type, namespace, and a set of properties.

Components are not constructed directly — use generated wrapper functions
like `html_div()`, `dcc_input()`, etc.
"""
struct Component
    name::String
    type::String
    namespace::String
    props::Dict{Symbol,Any}
    available_props::Set{Symbol}
    wildcard_regex::Union{Nothing,Regex}

    function Component(name::String, type::String, namespace::String,
                       props::Vector{Symbol}, wildcard_props::Vector{Symbol}; kwargs...)
        available_props = Set{Symbol}(props)
        wildcard_regex::Union{Nothing,Regex} = nothing
        if !isempty(wildcard_props)
            wildcard_regex = Regex(join(string.(wildcard_props), "|"))
        end
        component = new(name, type, namespace, Dict{Symbol,Any}(), available_props, wildcard_regex)
        for (prop, value) in kwargs
            Base.setproperty!(component, prop, value)
        end
        return component
    end
end

get_name(comp::Component) = getfield(comp, :name)
get_type(comp::Component) = getfield(comp, :type)
get_namespace(comp::Component) = getfield(comp, :namespace)
get_available_props(comp::Component) = getfield(comp, :available_props)
get_wildcard_regex(comp::Component) = getfield(comp, :wildcard_regex)
get_props(comp::Component) = getfield(comp, :props)

const VecChildTypes = Union{NTuple{N,Component} where {N},Vector{<:Component}}

function Base.getindex(component::Component, id::AbstractString)
    hasproperty(component, :id) && component.id == id && return component
    hasproperty(component, :children) || return nothing
    cc = component.children
    return if cc isa Union{VecChildTypes,Component}
        cc[id]
    elseif cc isa AbstractVector
        fcc = identity.(filter(x -> x isa Component && hasproperty(x, :id), cc))
        isempty(fcc) ? nothing : fcc[id]
    else
        nothing
    end
end

function Base.getindex(children::VecChildTypes, id::AbstractString)
    for element in children
        hasproperty(element, :id) && element.id == id && return element
        el = element[id]
        el !== nothing && return el
    end
    return nothing
end

function Base.getproperty(comp::Component, prop::Symbol)
    !Base.hasproperty(comp, prop) && error("Component $(get_name(comp)) has no property $(prop)")
    props = get_props(comp)
    return haskey(props, prop) ? props[prop] : nothing
end

function Base.setproperty!(comp::Component, prop::Symbol, value)
    !Base.hasproperty(comp, prop) && error("Component $(get_name(comp)) has no property $(prop)")
    props = get_props(comp)
    push!(props, prop => to_dash(value))
end

function check_wildcard(wildcard_regex::Union{Nothing,Regex}, name::Symbol)
    isnothing(wildcard_regex) && return false
    return startswith(string(name), wildcard_regex)
end

function Base.hasproperty(comp::Component, prop::Symbol)
    return in(prop, get_available_props(comp)) || check_wildcard(get_wildcard_regex(comp), prop)
end

Base.propertynames(comp::Component) = collect(get_available_props(comp))

push_prop!(component::Component, prop::Symbol, value) = push!(get_props(component), prop => to_dash(value))

# JSON serialization: Component → {"type": ..., "namespace": ..., "props": {...}}
JSON3.StructTypes.StructType(::Type{Component}) = JSON3.StructTypes.Struct()
JSON3.StructTypes.excludes(::Type{Component}) = (:name, :available_props, :wildcard_regex)
