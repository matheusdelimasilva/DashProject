# ─── Endpoint Implementations ────────────────────────────────────────────────

# ─── Layout ──────────────────────────────────────────────────────────────────

layout_data(layout::Component) = layout
layout_data(layout::Function) = layout()

function process_layout(request::HTTP.Request, state)
    return HTTP.Response(
        200,
        ["Content-Type" => "application/json"],
        body=Vector{UInt8}(JSON3.write(layout_data(state.app.layout)))
    )
end

# ─── Dependencies ────────────────────────────────────────────────────────────

function process_dependencies(request::HTTP.Request, state)
    return HTTP.Response(
        200,
        ["Content-Type" => "application/json"],
        body=state.cache.dependencies_json
    )
end

# ─── Index Page ──────────────────────────────────────────────────────────────

function process_index(request::HTTP.Request, state; kwargs...)
    app = state.app

    # Phase 3: If use_pages with meta tags, regenerate index with page-specific meta
    if app.config.use_pages && app.config.include_pages_meta
        request_path = HTTP.URIs.splitpath(request.target) |> p -> "/" * join(p, "/")
        page_metas = _page_meta_tags(app, request_path)
        resources = state.cache.resources

        # Combine base meta tags with page-specific ones
        original_metas = app.config.meta_tags
        all_meta_tags = vcat(page_metas, original_metas)
        meta_html_str = _metas_html_with_extra(app, all_meta_tags)

        idx_string = interpolate_string(app.index_string;
            metas=meta_html_str,
            title=app.title,
            favicon=favicon_html(app, resources),
            css=css_html(app, resources),
            app_entry=app_entry_html(),
            config=config_html(app),
            scripts=scripts_html(app, resources),
            renderer=renderer_html()
        )
        return HTTP.Response(200, ["Content-Type" => "text/html"], body=idx_string)
    end

    get_cache(state).need_recache && rebuild_cache!(state)
    return HTTP.Response(
        200,
        ["Content-Type" => "text/html"],
        body=state.cache.index_string
    )
end

# Helper to build metas HTML with extra page-specific tags
function _metas_html_with_extra(app::DashApp, all_meta_tags::Vector{Dict{String,String}})
    has_ie_compat = any(all_meta_tags) do tag
        get(tag, "http-equiv", "") == "X-UA-Compatible"
    end
    has_charset = any(tag -> haskey(tag, "charset"), all_meta_tags)

    result = String[]
    !has_ie_compat && push!(result, "<meta http-equiv=\"X-UA-Compatible\" content=\"IE=edge\">")
    !has_charset && push!(result, "<meta charset=\"UTF-8\">")
    append!(result, format_tag.("meta", all_meta_tags, opened=true))
    return join(result, "\n        ")
end

# ─── Assets ──────────────────────────────────────────────────────────────────

function process_assets(request::HTTP.Request, state; file_path::AbstractString)
    app = state.app
    filename = joinpath(get_assets_path(app), file_path)
    try
        headers = Pair{String,String}[]
        mimetype = mime_by_path(filename)
        !isnothing(mimetype) && push!(headers, "Content-Type" => mimetype)
        file_contents = read(filename)
        return HTTP.Response(200, headers; body=file_contents)
    catch
        return HTTP.Response(404)
    end
end

# ─── Component Resources (JS/CSS bundles) ────────────────────────────────────

function process_resource(request::HTTP.Request, state; namespace::AbstractString, path::AbstractString)
    (relative_path, is_fp) = parse_fingerprint_path(path)
    registered_files = state.cache.resources.files
    if !haskey(registered_files, namespace)
        return HTTP.Response(404)
    end
    namespace_files = registered_files[namespace]
    if !in(relative_path, namespace_files.files)
        return HTTP.Response(404)
    end

    try
        headers = Pair{String,String}[]
        file_contents = read(joinpath(namespace_files.base_path, relative_path))
        mimetype = mime_by_path(relative_path)
        !isnothing(mimetype) && push!(headers, "Content-Type" => mimetype)
        if is_fp
            push!(headers, "Cache-Control" => "public, max-age=31536000")
        else
            etag = bytes2hex(MD5.md5(file_contents))
            push!(headers, "ETag" => etag)
            request_etag = HTTP.header(request, "If-None-Match", "")
            request_etag == etag && return HTTP.Response(304)
        end
        return HTTP.Response(200, headers; body=file_contents)
    catch e
        !(e isa SystemError) && rethrow(e)
        return HTTP.Response(404)
    end
end

# ─── Default Favicon ─────────────────────────────────────────────────────────

function process_default_favicon(request::HTTP.Request, state)
    favicon_path = joinpath(@__DIR__, "..", "..", "assets", "favicon.ico")
    if isfile(favicon_path)
        ico_contents = read(favicon_path)
        return HTTP.Response(200, ["Content-Type" => "image/x-icon"], body=ico_contents)
    end
    return HTTP.Response(404)
end

# ─── Reload Hash (Hot Reload) ────────────────────────────────────────────────

function process_reload_hash(request::HTTP.Request, state)
    reload_tuple = (
        reloadHash=state.reload.hash,
        hard=state.reload.hard,
        packages=collect(keys(state.cache.resources.files)),
        files=state.reload.changed_assets
    )
    state.reload.hard = false
    state.reload.changed_assets = ChangedAsset[]
    return HTTP.Response(200, ["Content-Type" => "application/json"],
                         body=Vector{UInt8}(JSON3.write(reload_tuple)))
end

# ─── Health Check ────────────────────────────────────────────────────────────

function process_health(request::HTTP.Request, state)
    return HTTP.Response(200, ["Content-Type" => "application/json"],
                         body=Vector{UInt8}("{\"status\":\"ok\"}"))
end
