"""
    NoUpdate

Sentinel type indicating that a callback output should not be updated.
Use `no_update` (the singleton instance) in callback return values.

# Example
```julia
callback!(app, Output("out", "children"), Input("btn", "n_clicks")) do n
    isnothing(n) && return no_update
    return "Clicked \$n times"
end
```
"""
struct NoUpdate end

"""
    no_update

Singleton instance of `NoUpdate`. Return this from a callback to indicate
that a particular output should not be updated.
"""
const no_update = NoUpdate()

JSON3.StructTypes.StructType(::Type{NoUpdate}) = JSON3.RawType()
JSON3.rawbytes(::NoUpdate) = codeunits("{\"_dash_no_update\":\"_dash_no_update\"}")

function is_no_update(obj)
    obj isa NoUpdate && return true
    if obj isa Dict
        return get(obj, "_dash_no_update", nothing) == "_dash_no_update"
    end
    return false
end
