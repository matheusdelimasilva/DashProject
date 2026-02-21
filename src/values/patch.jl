"""
    Patch

Type for partial property updates in callbacks. Instead of replacing an entire
property value, a Patch records a series of operations to apply to the existing value.

# Example
```julia
callback!(app, Output("store", "data"), Input("btn", "n_clicks")) do n
    p = Patch()
    p["items"] = push!(p["items"], "new item")
    p["count"] += 1
    return p
end
```
"""
mutable struct Patch
    _location::Vector{Union{String,Int}}
    _operations::Vector{Dict{String,Any}}
    _parent_operations::Union{Nothing, Vector{Dict{String,Any}}}

    Patch() = new(Union{String,Int}[], Dict{String,Any}[], nothing)
    function Patch(location::Vector, parent_ops::Vector{Dict{String,Any}})
        new(Union{String,Int}[location...], Dict{String,Any}[], parent_ops)
    end
end

# Access nested locations
function Base.getindex(p::Patch, key::Union{String,Int})
    ops = isnothing(p._parent_operations) ? p._operations : p._parent_operations
    child = Patch(vcat(p._location, [key]), ops)
    return child
end

# Assign operation
function Base.setindex!(p::Patch, value, key::Union{String,Int})
    _add_operation!(p, "Assign", [key]; value=value)
end

# Delete operation
function Base.delete!(p::Patch, key::Union{String,Int})
    _add_operation!(p, "Delete", [key])
    return p
end

# Append operation
function Base.push!(p::Patch, value)
    _add_operation!(p, "Append"; value=value)
    return p
end

# Prepend operation
function prepend!(p::Patch, value)
    _add_operation!(p, "Prepend"; value=value)
    return p
end

# Insert operation
function Base.insert!(p::Patch, index::Int, value)
    _add_operation!(p, "Insert"; index=index, value=value)
    return p
end

# Extend operation
function Base.append!(p::Patch, values)
    _add_operation!(p, "Extend"; value=collect(values))
    return p
end

# Remove operation (filter out a value)
function remove!(p::Patch, value)
    _add_operation!(p, "Remove"; value=value)
    return p
end

# Clear operation
function clear!(p::Patch)
    _add_operation!(p, "Clear")
    return p
end

# Reverse operation
function reverse!(p::Patch)
    _add_operation!(p, "Reverse")
    return p
end

# Merge operation
function Base.merge!(p::Patch, dict::AbstractDict)
    _add_operation!(p, "Merge"; value=Dict(dict))
    return p
end

# Arithmetic operations
function add!(p::Patch, value)
    _add_operation!(p, "Add"; value=value)
    return p
end

function sub!(p::Patch, value)
    _add_operation!(p, "Sub"; value=value)
    return p
end

function mul!(p::Patch, value)
    _add_operation!(p, "Mul"; value=value)
    return p
end

function div!(p::Patch, value)
    _add_operation!(p, "Div"; value=value)
    return p
end

# Internal: add an operation to the list
function _add_operation!(p::Patch, operation::String, extra_location::Vector=Union{String,Int}[]; kwargs...)
    location = vcat(p._location, extra_location)
    op = Dict{String,Any}(
        "operation" => operation,
        "location" => location,
        "params" => Dict{String,Any}(string(k) => v for (k, v) in kwargs)
    )
    target = isnothing(p._parent_operations) ? p._operations : p._parent_operations
    push!(target, op)
    return nothing
end

# JSON serialization
JSON3.StructTypes.StructType(::Type{Patch}) = JSON3.RawType()

function JSON3.rawbytes(p::Patch)
    ops = isnothing(p._parent_operations) ? p._operations : p._parent_operations
    result = Dict{String,Any}(
        "__dash_patch_update" => "__dash_patch_update",
        "operations" => ops
    )
    return codeunits(JSON3.write(result))
end

function is_patch(obj)
    obj isa Patch && return true
    if obj isa Dict
        return get(obj, "__dash_patch_update", nothing) == "__dash_patch_update"
    end
    return false
end
