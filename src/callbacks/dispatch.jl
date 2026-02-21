# ─── Callback Dispatch ────────────────────────────────────────────────────────
# Handles the _dash-update-component POST endpoint.

function split_single_callback_id(callback_id::AbstractString)
    parts = rsplit(callback_id, ".")
    return (id=parts[1], property=parts[2])
end

function split_callback_id(callback_id::AbstractString)
    if startswith(callback_id, "..")
        result = []
        push!.(Ref(result), split_single_callback_id.(split(callback_id[3:end-2], "...", keepempty=false)))
        return result
    end
    return split_single_callback_id(callback_id)
end

input_to_arg(input) = get(input, :value, nothing)
input_to_arg(input::AbstractVector) = input_to_arg.(input)

make_args(inputs, state) = vcat(input_to_arg(inputs), input_to_arg(state))

function _push_to_res!(res, value, out::AbstractVector)
    _push_to_res!.(Ref(res), value, out)
end

function _push_to_res!(res, value, out)
    if !(value isa NoUpdate)
        id = _dep_id_str(out)
        prop = String(out.property)
        dashval = to_dash(value)
        if haskey(res, id)
            res[id][prop] = dashval
        else
            res[id] = Dict{String,Any}(prop => dashval)
        end
    end
end

# Get the id string from an output spec (from request JSON)
_dep_id_str(out) = _dep_id_str_from_id(out.id)
_dep_id_str_from_id(id::AbstractString) = String(id)
_dep_id_str_from_id(id::AbstractDict) = sorted_json(id)
_dep_id_str_from_id(id) = string(id)

_single_element_vect(e::T) where {T} = T[e]

function process_callback_call(app, callback_id, outputs, inputs, state)
    cb = app.callback_map[string(callback_id)]
    args = make_args(inputs, state)
    res = cb.func(args...)

    (res isa NoUpdate) && throw(PreventUpdate())
    res_vector = is_multi_out(cb) ? res : _single_element_vect(res)
    validate_callback_return(outputs, res_vector, callback_id)

    response = Dict{String,Any}()
    _push_to_res!(response, res_vector, outputs)

    isempty(response) && throw(PreventUpdate())
    return Dict{String,Any}("response" => response, "multi" => true)
end

outputs_to_vector(out, is_multi) = is_multi ? out : [out]

function process_callback(request::HTTP.Request, state)
    app = state.app
    response = HTTP.Response(200, ["Content-Type" => "application/json"])

    params = JSON3.read(String(request.body))
    inputs = get(params, :inputs, [])
    cb_state = get(params, :state, [])
    output = Symbol(params[:output])

    try
        cb_key = string(output)
        !haskey(app.callback_map, cb_key) && return HTTP.Response(404, "Callback not found: $cb_key")

        cb = app.callback_map[cb_key]
        is_multi = is_multi_out(cb)
        outputs_list = outputs_to_vector(
            get(params, :outputs, split_callback_id(params[:output])),
            is_multi
        )
        changedProps = get(params, :changedPropIds, [])
        context = CallbackContext(response, outputs_list, inputs, cb_state, changedProps)
        cb_result = with_callback_context(context) do
            process_callback_call(app, output, outputs_list, inputs, cb_state)
        end

        # Add sideUpdate from set_props if any
        if !isempty(context.updated_props)
            cb_result["sideUpdate"] = context.updated_props
        end

        response.body = Vector{UInt8}(JSON3.write(cb_result))
    catch e
        if isa(e, PreventUpdate)
            return HTTP.Response(204)
        else
            rethrow(e)
        end
    end

    return response
end

# ─── Callback Return Validation ──────────────────────────────────────────────

function validate_callback_return(outputs, value, callback_id)
    !(isa(value, Vector) || isa(value, Tuple)) &&
        throw(InvalidCallbackReturnValue("""
            The callback $callback_id is a multi-output.
            Expected the output type to be a list or tuple but got:
            $value
        """))

    (length(value) != length(outputs)) &&
        throw(InvalidCallbackReturnValue("""
            Invalid number of output values for $callback_id.
            Expected $(length(outputs)), got $(length(value))
        """))

    validate_return_item.(callback_id, eachindex(outputs), value, outputs)
end

function validate_return_item(callback_id, i, value::Union{<:Vector,<:Tuple}, spec::Vector)
    length(value) != length(spec) &&
        throw(InvalidCallbackReturnValue("""
            Invalid number of output values for $callback_id item $i.
            Expected $(length(value)), got $(length(spec))
            output spec: $spec
            output value: $value
        """))
end

function validate_return_item(callback_id, i, value, spec::Vector)
    throw(InvalidCallbackReturnValue("""
        The callback $callback_id output $i is a wildcard multi-output.
        Expected the output type to be a list or tuple but got:
        $value.
        output spec: $spec
    """))
end

validate_return_item(callback_id, i, value, spec) = nothing
