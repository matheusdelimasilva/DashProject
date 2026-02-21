# ─── Wildcard Types ──────────────────────────────────────────────────────────

"""
    Wildcard

Pattern-matching wildcard for callback IDs. Use `MATCH`, `ALL`, or `ALLSMALLER`.
"""
struct Wildcard
    type::Symbol
end

JSON3.StructTypes.StructType(::Type{Wildcard}) = JSON3.RawType()
JSON3.rawbytes(wild::Wildcard) = codeunits(string("[\"", wild.type, "\"]"))

const MATCH = Wildcard(:MATCH)
const ALL = Wildcard(:ALL)
const ALLSMALLER = Wildcard(:ALLSMALLER)

is_wild(::Wildcard) = true
is_wild(a) = false

# ─── Dependency Types ────────────────────────────────────────────────────────

struct TraitInput end
struct TraitOutput end
struct TraitState end

const IdTypes = Union{String,NamedTuple}

"""
    Dependency{Trait, IdT}

Base type for callback dependencies. Parameterized by trait (Input/Output/State)
and ID type (String or NamedTuple for pattern-matching).

The `allow_duplicate` field (relevant only for Output) enables multiple callbacks
to target the same output property.
"""
struct Dependency{Trait,IdT<:IdTypes}
    id::IdT
    property::String
    allow_duplicate::Bool

    Dependency{Trait}(id::T, property::String; allow_duplicate::Bool=false) where {Trait,T} =
        new{Trait,T}(id, property, allow_duplicate)
end

"""
    Input(id, property)

Declares a callback input dependency. When this property changes, the callback fires.
"""
const Input = Dependency{TraitInput}

"""
    Output(id, property; allow_duplicate=false)

Declares a callback output dependency. The callback return value updates this property.
Set `allow_duplicate=true` to allow multiple callbacks targeting the same output.
"""
const Output = Dependency{TraitOutput}

"""
    State(id, property)

Declares a callback state dependency. Provides the current value but does not trigger the callback.
"""
const State = Dependency{TraitState}


dep_id_string(dep::Dependency{Trait,String}) where {Trait} = dep.id
dep_id_string(dep::Dependency{Trait,<:NamedTuple}) where {Trait} = sorted_json(dep.id)

dependency_tuple(dep::Dependency) = (id=dep_id_string(dep), property=dep.property)

JSON3.StructTypes.StructType(::Type{<:Dependency}) = JSON3.StructTypes.Struct()

# ─── Dependency Equality ─────────────────────────────────────────────────────

function Base.:(==)(a::Dependency, b::Dependency)
    (a.property == b.property) && is_id_matches(a, b)
end

function Base.isequal(a::Dependency, b::Dependency)
    return a == b
end

function check_unique(deps::Vector{<:Dependency})
    tmp = Dependency[]
    for dep in deps
        dep in tmp && return false
        push!(tmp, dep)
    end
    return true
end

is_id_matches(a::Dependency{T1,String}, b::Dependency{T2,String}) where {T1,T2} = a.id == b.id
is_id_matches(a::Dependency{T1,String}, b::Dependency{T2,<:NamedTuple}) where {T1,T2} = false
is_id_matches(a::Dependency{T1,<:NamedTuple}, b::Dependency{T2,String}) where {T1,T2} = false

function is_id_matches(a::Dependency{T1,<:NamedTuple}, b::Dependency{T2,<:NamedTuple}) where {T1,T2}
    (Set(keys(a.id)) != Set(keys(b.id))) && return false
    for key in keys(a.id)
        a_value = a.id[key]
        b_value = b.id[key]
        (a_value == b_value) && continue
        a_wild = is_wild(a_value)
        b_wild = is_wild(b_value)
        (!a_wild && !b_wild) && return false
        !(a_wild && b_wild) && continue
        ((a_value == ALL) || (b_value == ALL)) && continue
        ((a_value == MATCH) || (b_value == MATCH)) && return false
    end
    return true
end

# ─── Dependency String Representations ───────────────────────────────────────

function dependency_string(dep::Dependency{Trait,String}) where {Trait}
    return "$(dep.id).$(dep.property)"
end

function dependency_string(dep::Dependency{Trait,<:NamedTuple}) where {Trait}
    id_str = replace(sorted_json(dep.id), "." => "\\.")
    return "$(id_str).$(dep.property)"
end

dependency_id_string(id::NamedTuple) = sorted_json(id)
dependency_id_string(id::String) = sorted_json(id)

# ─── Callback Dependencies Bundle ───────────────────────────────────────────

struct CallbackDeps
    output::Vector{<:Output}
    input::Vector{<:Input}
    state::Vector{<:State}
    multi_out::Bool

    CallbackDeps(output, input, state, multi_out) = new(output, input, state, multi_out)
    CallbackDeps(output::Output, input, state=State[]) = new([output], input, state, false)
    CallbackDeps(output::Vector{<:Output}, input, state=State[]) = new(output, input, state, true)
end

function output_string(deps::CallbackDeps)
    if deps.multi_out
        return ".." * join(dependency_string.(deps.output), "...") * ".."
    end
    return dependency_string(deps.output[1])
end

Base.convert(::Type{Vector{<:Output}}, v::Output{<:IdTypes}) = [v]
Base.convert(::Type{Vector{<:Input}}, v::Input{<:IdTypes}) = [v]
Base.convert(::Type{Vector{<:State}}, v::State{<:IdTypes}) = [v]

# ─── Clientside Function ─────────────────────────────────────────────────────

"""
    ClientsideFunction(namespace, function_name)

Reference to a JavaScript function for clientside callbacks.
"""
struct ClientsideFunction
    namespace::String
    function_name::String
end

JSON3.StructTypes.StructType(::Type{ClientsideFunction}) = JSON3.StructTypes.Struct()

# ─── Callback Type ───────────────────────────────────────────────────────────

"""
    Callback

Stores a registered callback function and its dependencies.
Includes Phase 3 background callback fields.
"""
struct Callback
    func::Union{Function,ClientsideFunction}
    dependencies::CallbackDeps
    prevent_initial_call::Bool
    # Phase 3: Background callback fields
    background::Bool
    background_key::Union{String,Nothing}
    interval::Int
    progress::Union{Vector{<:Output},Nothing}
    progress_default::Union{Vector,Nothing}
    running::Union{Dict{String,Any},Nothing}
    running_off::Union{Dict{String,Any},Nothing}
    cancel::Union{Vector{Dict{String,Any}},Nothing}
    manager::Union{AbstractBackgroundManager,Nothing}

    # Full constructor
    function Callback(func, deps, prevent_initial_call;
                      background=false,
                      background_key=nothing,
                      interval=1000,
                      progress=nothing,
                      progress_default=nothing,
                      running=nothing,
                      running_off=nothing,
                      cancel=nothing,
                      manager=nothing)
        new(func, deps, prevent_initial_call,
            background, background_key, interval,
            progress, progress_default,
            running, running_off, cancel, manager)
    end
end

is_multi_out(cb::Callback) = cb.dependencies.multi_out
get_output(cb::Callback) = cb.dependencies.output
get_output(cb::Callback, i) = cb.dependencies.output[i]
first_output(cb::Callback) = first(cb.dependencies.output)

const ExternalSrcType = Union{String,Dict{String,String}}
