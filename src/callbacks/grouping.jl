# ─── Grouping Utilities ──────────────────────────────────────────────────────
# Port of Python Dash's _grouping.py for flexible callback signatures.
# Supports dict-based and nested input/output structures.

"""
    flatten_grouping(grouping)

Recursively flatten a nested grouping structure into a flat vector.
Leaves (non-dict, non-vector scalars) are collected in order.

# Examples
```julia
flatten_grouping([[1, 2], Dict("a" => 3)]) # → [1, 2, 3]
flatten_grouping(42) # → [42]
```
"""
function flatten_grouping(grouping)
    result = Any[]
    _flatten_into!(result, grouping)
    return result
end

function _flatten_into!(result, grouping::AbstractVector)
    for item in grouping
        _flatten_into!(result, item)
    end
end

function _flatten_into!(result, grouping::Tuple)
    for item in grouping
        _flatten_into!(result, item)
    end
end

function _flatten_into!(result, grouping::AbstractDict)
    for key in sort(collect(keys(grouping)))
        _flatten_into!(result, grouping[key])
    end
end

function _flatten_into!(result, grouping)
    push!(result, grouping)
end

"""
    grouping_len(grouping)

Count the number of scalar values in a nested grouping structure.
"""
function grouping_len(grouping)
    return length(flatten_grouping(grouping))
end

"""
    make_grouping_by_index(schema, flat_values)

Reconstruct a nested structure from a flat list of values,
using `schema` as the template for the structure.
"""
function make_grouping_by_index(schema, flat_values)
    idx = Ref(1)
    return _reconstruct(schema, flat_values, idx)
end

function _reconstruct(schema::AbstractVector, flat_values, idx::Ref{Int})
    return [_reconstruct(item, flat_values, idx) for item in schema]
end

function _reconstruct(schema::Tuple, flat_values, idx::Ref{Int})
    return Tuple(_reconstruct(item, flat_values, idx) for item in schema)
end

function _reconstruct(schema::AbstractDict, flat_values, idx::Ref{Int})
    result = Dict{Any,Any}()
    for key in sort(collect(keys(schema)))
        result[key] = _reconstruct(schema[key], flat_values, idx)
    end
    return result
end

function _reconstruct(schema, flat_values, idx::Ref{Int})
    val = flat_values[idx[]]
    idx[] += 1
    return val
end

"""
    map_grouping(fn, grouping)

Apply a function to every scalar value in a nested grouping,
preserving the structure.
"""
function map_grouping(fn, grouping::AbstractVector)
    return [map_grouping(fn, item) for item in grouping]
end

function map_grouping(fn, grouping::Tuple)
    return Tuple(map_grouping(fn, item) for item in grouping)
end

function map_grouping(fn, grouping::AbstractDict)
    result = Dict{Any,Any}()
    for (k, v) in grouping
        result[k] = map_grouping(fn, v)
    end
    return result
end

function map_grouping(fn, grouping)
    return fn(grouping)
end
