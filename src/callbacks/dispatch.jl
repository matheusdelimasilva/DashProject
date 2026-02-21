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
        # Strip @hash suffix added by allow_duplicate (e.g. "children@abc123" → "children")
        prop = first(split(String(out.property), "@"))
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

        # Phase 3: Background callback dispatch
        if cb.background
            query = HTTP.queryparams(HTTP.URI(request.target))
            if !haskey(query, "cacheKey")
                return _setup_background_callback(app, cb, cb_key, inputs, cb_state, output, params)
            else
                return _poll_background_callback(app, cb, query, output, params)
            end
        end

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

# ─── Background Callback: First Request ────────────────────────────────────

function _setup_background_callback(app, cb, cb_key, inputs, cb_state, output, params)
    args = make_args(inputs, cb_state)
    changedProps = get(params, :changedPropIds, [])

    # Build cache key from args + callback_id
    cache_key = make_cache_key(cb_key, args, changedProps)

    # Get manager
    mgr = something(cb.manager, app.config.background_callback_manager)
    if isnothing(mgr)
        error("Background callback requires a manager. Set `background_callback_manager` in `dash()` or pass `manager` to `callback!`.")
    end

    # Spawn the background job
    # The wrapped func expects (cache_key, args...) for progress injection
    call_job_fn(mgr, cache_key, cb.func, (cache_key, args...), Dict{String,Any}())

    # Build initial response
    result = Dict{String,Any}(
        "cacheKey" => cache_key,
        "job" => cache_key,
    )

    if !isnothing(cb.cancel)
        result["cancel"] = cb.cancel
    end
    if !isnothing(cb.progress_default)
        result["progressDefault"] = cb.progress_default
    end

    response = HTTP.Response(200, ["Content-Type" => "application/json"])
    response.body = Vector{UInt8}(JSON3.write(result))
    return response
end

# ─── Background Callback: Poll Request ─────────────────────────────────────

function _poll_background_callback(app, cb, query, output, params)
    cache_key = query["cacheKey"]
    mgr = something(cb.manager, app.config.background_callback_manager)

    response_data = Dict{String,Any}()

    # Check for progress
    progress_data = get_progress(mgr, cache_key)
    if !isnothing(progress_data) && !isnothing(cb.progress)
        progress_response = Dict{String,Any}()
        for (i, prog_out) in enumerate(cb.progress)
            id_str = dep_id_string(prog_out.id)
            if !haskey(progress_response, id_str)
                progress_response[id_str] = Dict{String,Any}()
            end
            val = i <= length(progress_data) ? progress_data[i] : nothing
            progress_response[id_str][prog_out.property] = val
        end
        response_data["progress"] = progress_response
    end

    # Check for result
    result = get_result(mgr, cache_key)
    if !(result isa _Undefined)
        # Handle error results
        if result isa Dict && get(result, "error", false) == true
            response_data["error"] = result["message"]
        elseif is_no_update(result) || result isa NoUpdate
            # Return 204 equivalent
            return HTTP.Response(204)
        else
            is_multi = is_multi_out(cb)
            outputs_list = outputs_to_vector(
                get(params, :outputs, split_callback_id(string(output))),
                is_multi
            )
            res_vector = is_multi ? result : _single_element_vect(result)

            response_dict = Dict{String,Any}()
            _push_to_res!(response_dict, res_vector, outputs_list)

            if !isempty(response_dict)
                response_data["response"] = response_dict
                response_data["multi"] = true
            end

            # Check for updated props from the background job
            updated_props = get_updated_props(mgr, cache_key)
            if !isempty(updated_props)
                response_data["sideUpdate"] = updated_props
            end
        end
    end

    response = HTTP.Response(200, ["Content-Type" => "application/json"])
    response.body = Vector{UInt8}(JSON3.write(response_data))
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
