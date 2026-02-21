# ─── Index Page Generation ───────────────────────────────────────────────────

function resource_url(app::DashApp, resource::AppRelativeResource)
    prefix = app.config.requests_pathname_prefix
    return string(prefix,
        "_dash-component-suites/",
        resource.namespace, "/",
        build_fingerprint(resource.relative_path, resource.version, resource.ts)
    )
end

function asset_path(app::DashApp, path::AbstractString)
    return string(
        app.config.requests_pathname_prefix,
        lstrip(app.config.assets_url_path, '/'),
        "/", path
    )
end

resource_url(::DashApp, resource::AppExternalResource) = resource.url

function resource_url(app::DashApp, resource::AppAssetResource)
    return string(asset_path(app, resource.path), "?m=", resource.ts)
end

# ─── HTML Tag Helpers ────────────────────────────────────────────────────────

make_css_tag(url::String) = """<link rel="stylesheet" href="$(url)">"""
make_css_tag(app::DashApp, resource::AppCustomResource) = format_tag("link", resource.params, opened=true)
make_css_tag(app::DashApp, resource::AppResource) = make_css_tag(resource_url(app, resource))

make_script_tag(url::String) = """<script src="$(url)"></script>"""
make_script_tag(app::DashApp, resource::AppCustomResource) = format_tag("script", resource.params)
make_script_tag(app::DashApp, resource::AppResource) = make_script_tag(resource_url(app, resource))
make_inline_script_tag(script::String) = """<script>$(script)</script>"""

# ─── Index Page Sections ─────────────────────────────────────────────────────

function metas_html(app::DashApp)
    meta_tags = app.config.meta_tags
    has_ie_compat = any(meta_tags) do tag
        get(tag, "http-equiv", "") == "X-UA-Compatible"
    end
    has_charset = any(tag -> haskey(tag, "charset"), meta_tags)

    result = String[]
    !has_ie_compat && push!(result, "<meta http-equiv=\"X-UA-Compatible\" content=\"IE=edge\">")
    !has_charset && push!(result, "<meta charset=\"UTF-8\">")
    append!(result, format_tag.("meta", meta_tags, opened=true))
    return join(result, "\n        ")
end

function css_html(app::DashApp, resources::ApplicationResources)
    join(make_css_tag.(Ref(app), resources.css), "\n        ")
end

function scripts_html(app::DashApp, resources::ApplicationResources)
    join(vcat(
        make_script_tag.(Ref(app), resources.js),
        make_inline_script_tag.(app.inline_scripts)
    ), "\n        ")
end

function app_entry_html()
    return """
<div id="react-entry-point">
    <div class="_dash-loading">
        Loading...
    </div>
</div>
"""
end

function config_html(app::DashApp)
    config = Dict{Symbol,Any}(
        :url_base_pathname => app.config.url_base_pathname,
        :requests_pathname_prefix => app.config.requests_pathname_prefix,
        :ui => get_devsetting(app, :ui),
        :props_check => get_devsetting(app, :props_check),
        :show_undo_redo => app.config.show_undo_redo,
        :suppress_callback_exceptions => app.config.suppress_callback_exceptions,
        :update_title => app.config.update_title,
        :children_props => get_children_props(),
        :serve_locally => app.config.serve_locally
    )
    if get_devsetting(app, :hot_reload)
        config[:hot_reload] = (
            interval=trunc(Int, get_devsetting(app, :hot_reload_interval) * 1000),
            max_retry=get_devsetting(app, :hot_reload_max_retry)
        )
    end
    return """<script id="_dash-config" type="application/json">$(JSON3.write(config))</script>"""
end

function renderer_html()
    return """<script id="_dash-renderer" type="application/javascript">var renderer = new DashRenderer();</script>"""
end

function favicon_html(app::DashApp, resources::ApplicationResources)
    favicon_url = if !isnothing(resources.favicon)
        asset_path(app, resources.favicon.path)
    else
        "$(app.config.requests_pathname_prefix)_favicon.ico?v=$(_metadata[].dash["version"])"
    end
    return format_tag("link",
        Dict("rel" => "icon", "type" => "image/x-icon", "href" => favicon_url),
        opened=true
    )
end

# ─── Full Index Page ─────────────────────────────────────────────────────────

function index_page(app::DashApp, resources::ApplicationResources)
    result = interpolate_string(app.index_string;
        metas=metas_html(app),
        title=app.title,
        favicon=favicon_html(app, resources),
        css=css_html(app, resources),
        app_entry=app_entry_html(),
        config=config_html(app),
        scripts=scripts_html(app, resources),
        renderer=renderer_html()
    )

    validate_index("index", result, [
        "#react-entry-point" => r"id=\"react-entry-point\"",
        "#_dash_config" => r"id=\"_dash-config\"",
        "dash-renderer" => r"src=\"[^\"]*dash[-_]renderer[^\"]*\"",
        "new DashRenderer" => r"id=\"_dash-renderer",
    ])

    return result
end
