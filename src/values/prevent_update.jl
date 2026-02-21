"""
    PreventUpdate <: Exception

Exception type to prevent all outputs from updating.
Throw this from a callback to return HTTP 204 (No Content).

# Example
```julia
callback!(app, Output("out", "children"), Input("btn", "n_clicks")) do n
    isnothing(n) && throw(PreventUpdate())
    return "Clicked \$n times"
end
```
"""
struct PreventUpdate <: Exception end

"""
    InvalidCallbackReturnValue <: Exception

Exception thrown when a callback returns an invalid value
(e.g. wrong number of outputs for multi-output callbacks).
"""
struct InvalidCallbackReturnValue <: Exception
    msg::String
end

Base.showerror(io::IO, e::InvalidCallbackReturnValue) = print(io, "InvalidCallbackReturnValue: ", e.msg)
