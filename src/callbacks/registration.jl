# ─── Callback Registration ───────────────────────────────────────────────────

"""
    callback!(func, app, output, input, [state]; prevent_initial_call=nothing, allow_duplicate=false)

Register a callback that updates `output` properties when `input` properties change.
Supports do-block syntax for idiomatic Julia callbacks.

# Examples

```julia
# Single output, single input
callback!(app, Output("out", "children"), Input("in", "value")) do value
    return "Hello \$value"
end

# Multiple outputs
callback!(app,
    [Output("out1", "children"), Output("out2", "value")],
    Input("in", "value"),
    State("state", "value")
) do input_val, state_val
    return ("Result: \$input_val", state_val)
end

# Flat deps syntax
callback!(app,
    Output("out1", "children"),
    Output("out2", "value"),
    Input("in", "value"),
    State("state", "value")
) do input_val, state_val
    return ("Result: \$input_val", state_val)
end
```
"""
function callback!(func::Union{Function,ClientsideFunction,String},
                   app::DashApp,
                   output::Union{Vector{<:Output},Output},
                   input::Union{Vector{<:Input},Input},
                   state::Union{Vector{<:State},State}=State[];
                   prevent_initial_call=nothing)
    return _callback!(func, app, CallbackDeps(output, input, state);
                       prevent_initial_call=prevent_initial_call)
end

# Flat deps version: callback!(func, app, Output(...), Output(...), Input(...), State(...))
function callback!(func::Union{Function,ClientsideFunction,String},
                   app::DashApp,
                   deps::Dependency...;
                   prevent_initial_call=nothing)
    output = Output[]
    input = Input[]
    state = State[]
    _process_callback_args(deps, (output, input, state))
    return _callback!(func, app, CallbackDeps(output, input, state, length(output) > 1);
                       prevent_initial_call=prevent_initial_call)
end

# Process flat deps into separate output/input/state vectors
function _process_callback_args(args::Tuple{T,Vararg}, dest::Tuple{Vector{T},Vararg}) where {T}
    push!(dest[1], args[1])
    _process_callback_args(Base.tail(args), dest)
end
function _process_callback_args(args::Tuple{}, dest::Tuple{Vector{T},Vararg}) where {T}
end
function _process_callback_args(args::Tuple, dest::Tuple{Vector{T},Vararg}) where {T}
    _process_callback_args(args, Base.tail(dest))
end
function _process_callback_args(args::Tuple, dest::Tuple{})
    error("The callback method must receive first all Outputs, then all Inputs, then all States")
end
function _process_callback_args(args::Tuple{}, dest::Tuple{})
end

# Core registration logic
function _callback!(func::Union{Function,ClientsideFunction,String}, app::DashApp, deps::CallbackDeps;
                    prevent_initial_call)
    check_callback(func, app, deps)

    out_id = Symbol(output_string(deps))

    # Check for duplicate outputs (unless allow_duplicate is set)
    if haskey(app.callback_map, string(out_id))
        any_allow_dup = any(o -> o.allow_duplicate, deps.output)
        if !any_allow_dup
            error("Multiple callbacks cannot target the same output. Offending output: $(out_id)")
        end
    end

    callback_func = make_callback_func!(app, func, deps)
    cb = Callback(callback_func, deps, isnothing(prevent_initial_call) ?
                  app.config.prevent_initial_callbacks : prevent_initial_call)

    # Store in callback_map for dispatch
    app.callback_map[string(out_id)] = cb

    # Store in callback_list for _dash-dependencies serialization
    cb_entry = _make_callback_list_entry(deps, callback_func, cb.prevent_initial_call)
    push!(app.callback_list, cb_entry)

    return nothing
end

function _make_callback_list_entry(deps::CallbackDeps, func, prevent_initial_call::Bool)
    entry = Dict{String,Any}(
        "output" => output_string(deps),
        "inputs" => [Dict("id" => dep_id_string(d), "property" => d.property) for d in deps.input],
        "state" => [Dict("id" => dep_id_string(d), "property" => d.property) for d in deps.state],
        "prevent_initial_call" => prevent_initial_call
    )
    if func isa ClientsideFunction
        entry["clientside_function"] = Dict(
            "namespace" => func.namespace,
            "function_name" => func.function_name
        )
    end
    return entry
end

make_callback_func!(::DashApp, func::Union{Function,ClientsideFunction}, ::CallbackDeps) = func

function make_callback_func!(app::DashApp, func::String, deps::CallbackDeps)
    first_out = first(deps.output)
    namespace = replace("_dashprivate_$(first_out.id)", "\"" => "\\\"")
    function_name = replace("$(first_out.property)", "\"" => "\\\"")

    function_string = """
        var clientside = window.dash_clientside = window.dash_clientside || {};
        var ns = clientside["$namespace"] = clientside["$namespace"] || {};
        ns["$function_name"] = $func;
    """
    push!(app.inline_scripts, function_string)
    return ClientsideFunction(namespace, function_name)
end

function check_callback(func, app::DashApp, deps::CallbackDeps)
    isempty(deps.output) && error("The callback method requires that one or more properly formatted outputs are passed.")
    isempty(deps.input) && error("The callback method requires that one or more properly formatted inputs are passed.")
    args_count = length(deps.state) + length(deps.input)
    check_callback_func(func, args_count)
end

function check_callback_func(func::Function, args_count)
    !hasmethod(func, NTuple{args_count,Any}) &&
        error("The arguments of the specified callback function do not align with the currently defined callback; please ensure that the arguments to `func` are properly defined.")
end

check_callback_func(func, args_count) = nothing

# ─── @callback Macro ─────────────────────────────────────────────────────────

"""
    @callback(app, output, input, [state]) do args...
        ...
    end

Module-level callback registration macro. Equivalent to `callback!` but
can be used at the top level of a module.

# Example
```julia
@callback(app, Output("out", "children"), Input("in", "value")) do value
    return "Hello \$value"
end
```
"""
macro callback(ex)
    # This is a simplified version — the do-block is already natural in Julia
    # so this macro mainly exists for Dash 2.0 API compatibility
    return esc(:(callback!($(ex))))
end
