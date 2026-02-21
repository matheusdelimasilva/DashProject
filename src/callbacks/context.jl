# ─── Callback Context ────────────────────────────────────────────────────────
# Uses task_local_storage() for thread-safe context management.

const TriggeredParam = NamedTuple{(:prop_id, :value)}

"""
    CallbackContext

Provides context information within a callback execution, including
triggered inputs, current values, and the ability to set side-effect props.

Access via `callback_context()` inside a callback function.
"""
mutable struct CallbackContext
    response::HTTP.Response
    inputs::Dict{String,Any}
    states::Dict{String,Any}
    outputs_list::Vector{Any}
    inputs_list::Vector{Any}
    states_list::Vector{Any}
    triggered::Vector{TriggeredParam}
    # Dash 2.x additions
    updated_props::Dict{String,Dict{String,Any}}  # for set_props → sideUpdate

    function CallbackContext(response, outputs_list, inputs_list, states_list, changed_props)
        input_values = inputs_list_to_dict(inputs_list)
        state_values = inputs_list_to_dict(states_list)
        triggered = TriggeredParam[
            (prop_id=id, value=get(input_values, id, nothing))
            for id in changed_props
        ]
        return new(
            response, input_values, state_values,
            outputs_list, inputs_list, states_list,
            triggered,
            Dict{String,Dict{String,Any}}()
        )
    end
end

const _CALLBACK_CONTEXT_KEY = :_dash2_callback_context

function with_callback_context(f, context::CallbackContext)
    return task_local_storage(f, _CALLBACK_CONTEXT_KEY, context)
end

"""
    callback_context()::CallbackContext

Get the context of the current callback execution. Only available inside
a callback processing function.

# Available fields
- `inputs` — Dict of input values keyed by "id.property"
- `states` — Dict of state values keyed by "id.property"
- `triggered` — Vector of triggered input `(prop_id, value)` tuples
- `response` — HTTP.Response object (for setting cookies/headers)
"""
function callback_context()
    ctx = get(task_local_storage(), _CALLBACK_CONTEXT_KEY, nothing)
    isnothing(ctx) && error("callback_context() is only available from a callback processing function")
    return ctx::CallbackContext
end

"""
    triggered_id()

Get the component ID that triggered the current callback.
Returns the prop_id string of the first triggered input, or `nothing`.
"""
function triggered_id()
    ctx = callback_context()
    isempty(ctx.triggered) && return nothing
    prop_id = ctx.triggered[1].prop_id
    # Extract just the component ID (before the dot)
    dot_pos = findlast('.', prop_id)
    isnothing(dot_pos) && return prop_id
    return prop_id[1:dot_pos-1]
end

"""
    set_props(component_id::String, props::Dict)

Update component properties outside of direct callback outputs.
These updates are sent as `sideUpdate` in the callback response.

# Example
```julia
callback!(app, Output("out", "children"), Input("btn", "n_clicks")) do n
    set_props("other-component", Dict("value" => 42))
    return "Updated!"
end
```
"""
function set_props(component_id::String, props::Dict)
    ctx = callback_context()
    existing = get(ctx.updated_props, component_id, Dict{String,Any}())
    ctx.updated_props[component_id] = merge(existing, Dict{String,Any}(string(k) => v for (k, v) in props))
end

# ─── Helper Functions ────────────────────────────────────────────────────────

function inputs_list_to_dict(list::AbstractVector)
    result = Dict{String,Any}()
    _item_to_dict!.(Ref(result), list)
    return result
end

_dep_id_string(id::AbstractDict) = sorted_json(id)
_dep_id_string(id::AbstractString) = String(id)

function _item_to_dict!(target::Dict{String,Any}, item)
    target["$(_dep_id_string(item.id)).$(item.property)"] = get(item, :value, nothing)
end

_item_to_dict!(target::Dict{String,Any}, item::AbstractVector) = _item_to_dict!.(Ref(target), item)
