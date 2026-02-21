# ─── Pages System ────────────────────────────────────────────────────────────
# Phase 3 — Multi-page app support with path inference, auto-discovery,
# routing callback, path templates, and meta tags.

const PAGE_REGISTRY = DataStructures.OrderedDict{String,Dict{String,Any}}()

# Valid image extensions for page inference
const _PAGE_IMAGE_EXTENSIONS = Set(["apng", "avif", "gif", "jpeg", "jpg", "png", "svg", "webp"])

# Page component IDs
const _ID_CONTENT  = "_pages_content"
const _ID_LOCATION = "_pages_location"
const _ID_STORE    = "_pages_store"
const _ID_DUMMY    = "_pages_dummy"

# ─── Path Inference Helpers ─────────────────────────────────────────────────

"""
    _infer_path(module_name, path_template=nothing)

Convert a module name to a URL path.
`"pages.weekly_analytics"` → `"/weekly-analytics"`
Replaces `_` with `-`, `.` with `/`, lowercases, prepends `/`.
If `path_template` given, replaces `<var>` placeholders with `"none"`.
"""
function _infer_path(module_name::String, path_template=nothing)
    if !isnothing(path_template)
        # Replace <var> placeholders with "none" for path inference
        return replace(path_template, r"<[^>]+>" => "none")
    end
    # Take the last segment(s) after the first dot (skip "pages" prefix)
    parts = split(module_name, ".")
    # If there's a "pages" prefix, skip it
    start_idx = (length(parts) > 1 && parts[1] == "pages") ? 2 : 1
    path_parts = parts[start_idx:end]
    path = join(path_parts, "/")
    path = replace(path, "_" => "-")
    path = lowercase(path)
    return "/" * path
end

"""
    _module_name_to_page_name(module_name)

Convert module name to display name: last segment, replace `_` with space, titlecase.
"""
function _module_name_to_page_name(module_name::String)
    parts = split(module_name, ".")
    last_part = parts[end]
    name = replace(last_part, "_" => " ")
    return titlecase(name)
end

"""
    _infer_image(module_name, assets_folder)

Search assets folder for an image matching the module name, or fallback to `app.*`/`logo.*`.
Valid extensions: $(join(sort(collect(_PAGE_IMAGE_EXTENSIONS)), ", ")).
"""
function _infer_image(module_name::String, assets_folder::String)
    !isdir(assets_folder) && return nothing

    parts = split(module_name, ".")
    page_name = parts[end]

    # Search for image matching page name
    for file in readdir(assets_folder)
        name_part, ext_part = splitext(file)
        ext = lstrip(ext_part, '.')
        ext in _PAGE_IMAGE_EXTENSIONS || continue
        if lowercase(name_part) == lowercase(page_name)
            return file
        end
    end

    # Fallback: search for app.* or logo.*
    for prefix in ("app", "logo")
        for file in readdir(assets_folder)
            name_part, ext_part = splitext(file)
            ext = lstrip(ext_part, '.')
            ext in _PAGE_IMAGE_EXTENSIONS || continue
            if lowercase(name_part) == prefix
                return file
            end
        end
    end

    return nothing
end

"""
    _sort_registry!()

Re-sort `PAGE_REGISTRY` after each registration.
Sort key: `(order === nothing, numeric_order, string_order, module)`.
"""
function _sort_registry!()
    entries = collect(PAGE_REGISTRY)
    sort!(entries, by = function(pair)
        _, page = pair
        order = page["order"]
        has_order = !isnothing(order)
        numeric_order = has_order ? order : typemax(Int)
        string_order = has_order ? string(order) : ""
        return (!has_order, numeric_order, string_order, page["module"])
    end)
    empty!(PAGE_REGISTRY)
    for (k, v) in entries
        PAGE_REGISTRY[k] = v
    end
end

# ─── Path Template Matching ─────────────────────────────────────────────────

"""
    _parse_path_variables(pathname, path_template)

Convert template `<var>` to regex capture groups.
Match against pathname. Return `Dict{String,String}` of captured variables or `nothing`.
"""
function _parse_path_variables(pathname::String, path_template::String)
    # Build regex from template: replace <var> with named capture groups
    regex_str = replace(path_template, r"<([^>]+)>" => s"(?P<\1>[^/]+)")
    regex_str = "^" * regex_str * "\$"
    m = match(Regex(regex_str), pathname)
    isnothing(m) && return nothing
    result = Dict{String,String}()
    for var_match in eachmatch(r"<([^>]+)>", path_template)
        var_name = var_match.captures[1]
        result[var_name] = m[var_name]
    end
    return result
end

"""
    _path_to_page(path)

Iterate `PAGE_REGISTRY`, try template match first, then exact match.
Returns `(page_dict, path_variables)` or `(Dict(), nothing)`.
"""
function _path_to_page(path::String)
    # First pass: try path template matching
    for (mod, page) in PAGE_REGISTRY
        tmpl = get(page, "path_template", nothing)
        if !isnothing(tmpl)
            variables = _parse_path_variables(path, tmpl)
            if !isnothing(variables)
                return (page, variables)
            end
        end
    end

    # Second pass: exact path match
    for (mod, page) in PAGE_REGISTRY
        if page["path"] == path
            return (page, nothing)
        end
    end

    return (Dict{String,Any}(), nothing)
end

"""
    _parse_query_string(search)

Parse `"?foo=bar&baz=1"` into `Dict{String,String}`.
"""
function _parse_query_string(search::String)
    result = Dict{String,String}()
    isempty(search) && return result
    qs = lstrip(search, '?')
    isempty(qs) && return result
    for pair in split(qs, "&", keepempty=false)
        parts = split(pair, "=", limit=2)
        key = HTTP.URIs.unescapeuri(parts[1])
        value = length(parts) > 1 ? HTTP.URIs.unescapeuri(parts[2]) : ""
        result[key] = value
    end
    return result
end

# ─── Strip Relative Path ───────────────────────────────────────────────────

"""
    _strip_relative_path(app, path)

Strip the requests_pathname_prefix from the path to get the relative page path.
"""
function _strip_relative_path(app, path::String)
    prefix = app.config.requests_pathname_prefix
    if startswith(path, prefix)
        stripped = path[length(prefix)+1:end]
        return startswith(stripped, "/") ? stripped : "/" * stripped
    end
    return path
end

# ─── Register Page ──────────────────────────────────────────────────────────

"""
    register_page(module_name; path=nothing, name=nothing, layout=nothing, ...)

Register a page in the multi-page application system.
Pages are stored in the global `PAGE_REGISTRY`.

# Arguments
- `module_name` — unique identifier for the page (typically derived from file path)
- `path` — URL path for the page (e.g., "/analytics"). Inferred from module_name if not given.
- `path_template` — path with `<var>` placeholders (e.g., "/report/<id>")
- `name` — display name for navigation
- `title` — page title (String or Function)
- `description` — page description (String or Function)
- `layout` — component or function returning the page layout
- `order` — display order in page listings
- `image` — OG/Twitter image filename
- `image_url` — full URL for OG/Twitter image
- `redirect_from` — list of paths that redirect to this page
"""
function register_page(module_name::String;
                       path=nothing,
                       path_template=nothing,
                       name=nothing,
                       title=nothing,
                       description=nothing,
                       layout=nothing,
                       order=nothing,
                       image=nothing,
                       image_url=nothing,
                       redirect_from=nothing,
                       kwargs...)
    supplied_path = path
    supplied_name = name
    supplied_title = title
    supplied_order = order
    supplied_layout = layout
    supplied_image = image

    # Infer path from module name if not supplied
    if isnothing(path)
        path = _infer_path(module_name, path_template)
    end

    # Infer name from module name if not supplied
    if isnothing(name)
        name = _module_name_to_page_name(module_name)
    end

    # Default title to name if not supplied
    if isnothing(title)
        title = name
    end

    # Default description to empty string
    if isnothing(description)
        description = ""
    end

    # Compute relative_path (assumes default prefix "/" for now)
    relative_path = path

    page_entry = Dict{String,Any}(
        "module" => module_name,
        "path" => path,
        "path_template" => path_template,
        "name" => name,
        "title" => title,
        "description" => description,
        "order" => order,
        "image" => image,
        "image_url" => image_url,
        "redirect_from" => redirect_from,
        "layout" => layout,
        "supplied_path" => supplied_path,
        "supplied_name" => supplied_name,
        "supplied_title" => supplied_title,
        "supplied_order" => supplied_order,
        "supplied_layout" => supplied_layout,
        "supplied_image" => supplied_image,
        "relative_path" => relative_path,
    )
    for (k, v) in kwargs
        page_entry[string(k)] = v
    end

    PAGE_REGISTRY[module_name] = page_entry
    _sort_registry!()
    return nothing
end

# ─── Page Auto-Discovery ───────────────────────────────────────────────────

"""
    _include_page(page_path, module_name)

Include a page file in a generated module to isolate its scope.
If the file calls `register_page()`, it updates PAGE_REGISTRY directly.
If a `layout` variable is defined in the file and the page's layout is not set,
it is captured from the module.
"""
function _include_page(page_path::String, module_name::String)
    mod = Module(Symbol(module_name))
    Base.include(mod, page_path)
    if haskey(PAGE_REGISTRY, module_name) && isnothing(get(PAGE_REGISTRY[module_name], "supplied_layout", nothing))
        if isdefined(mod, :layout)
            PAGE_REGISTRY[module_name]["layout"] = getfield(mod, :layout)
        end
    end
end

"""
    _import_layouts_from_pages(app)

Walk the pages folder recursively, include `.jl` files that call `register_page`.
Skips directories and files starting with `_` or `.`.
"""
function _import_layouts_from_pages(app)
    pages_folder = joinpath(app.root_path, app.config.pages_folder)
    !isdir(pages_folder) && return

    for (root, dirs, files) in walkdir(pages_folder)
        # Skip hidden/private directories
        filter!(d -> !startswith(d, "_") && !startswith(d, "."), dirs)

        for file in files
            # Skip hidden/private files and non-Julia files
            (startswith(file, "_") || startswith(file, ".")) && continue
            !endswith(file, ".jl") && continue

            page_path = joinpath(root, file)
            content = read(page_path, String)

            # Only include files that call register_page
            !occursin("register_page", content) && continue

            # Derive module name from relative path
            rel = relpath(page_path, pages_folder)
            module_name = replace(rel, "/" => ".", "\\" => ".")
            module_name = replace(module_name, ".jl" => "")
            module_name = "pages." * module_name

            _include_page(page_path, module_name)
        end
    end
end

# ─── Page Container ─────────────────────────────────────────────────────────

"""
    default_page_container()

Create the default page container component tree used by the pages system.
Contains Location, content div, Store, and dummy div for title updates.
"""
function default_page_container()
    html_div([
        dcc_location(; id=_ID_LOCATION, refresh="callback-nav"),
        html_div(; id=_ID_CONTENT),
        dcc_store(; id=_ID_STORE),
        html_div(; id=_ID_DUMMY),
    ])
end

# ─── Routing Callback Setup ────────────────────────────────────────────────

"""
    _setup_pages!(app)

Called from `make_handler()` when `app.config.use_pages == true`.
Auto-discovers pages, sets default layout, and registers routing callbacks.
"""
function _setup_pages!(app)
    # Auto-discover page files
    _import_layouts_from_pages(app)

    # Set default layout if none specified
    if isnothing(app.layout)
        setfield!(app, :layout, default_page_container())
    end

    # Register the routing callback
    callback!(app,
        [Output(_ID_CONTENT, "children"), Output(_ID_STORE, "data")],
        [Input(_ID_LOCATION, "pathname"), Input(_ID_LOCATION, "search")];
        prevent_initial_call=false
    ) do pathname, search
        query_params = _parse_query_string(something(search, ""))
        stripped = _strip_relative_path(app, something(pathname, "/"))
        page, path_variables = _path_to_page(stripped)

        if isempty(page)
            # Look for not_found_404 page
            layout = html_h1("404 - Page not found")
            title = app.title
            for (mod, p) in PAGE_REGISTRY
                if endswith(mod, "not_found_404")
                    layout = p["layout"]
                    title = p["title"]
                    break
                end
            end
        else
            layout = get(page, "layout", "")
            title = page["title"]
        end

        # Call layout/title if they are functions
        if layout isa Function
            kwargs = merge(something(path_variables, Dict{String,String}()), query_params)
            if isempty(kwargs)
                layout = layout()
            else
                layout = layout(; (Symbol(k) => v for (k, v) in kwargs)...)
            end
        end
        if title isa Function
            kwargs = something(path_variables, Dict{String,String}())
            if isempty(kwargs)
                title = title()
            else
                title = title(; (Symbol(k) => v for (k, v) in kwargs)...)
            end
        end

        return (layout, Dict("title" => title))
    end

    # Register clientside title-update callback
    callback!("function(data) { if(data) { document.title = data.title; } return ''; }",
        app, Output(_ID_DUMMY, "children"), Input(_ID_STORE, "data");
        prevent_initial_call=true)

    setfield!(app, :_pages_setup_done, true)
end

# ─── Page Meta Tags ─────────────────────────────────────────────────────────

"""
    _page_meta_tags(app, request_path)

Returns `Vector{Dict{String,String}}` of OG/Twitter meta tags based on the matched page.
"""
function _page_meta_tags(app, request_path::String)
    stripped = _strip_relative_path(app, request_path)
    page, _ = _path_to_page(stripped)

    title = app.title
    description = ""
    image = ""

    if !isempty(page)
        page_title = page["title"]
        title = page_title isa Function ? app.title : string(page_title)
        page_desc = get(page, "description", "")
        description = page_desc isa Function ? "" : string(page_desc)

        # Resolve image
        image_url = get(page, "image_url", nothing)
        if !isnothing(image_url)
            image = image_url
        else
            img = get(page, "image", nothing)
            if !isnothing(img)
                image = string(app.config.requests_pathname_prefix,
                              lstrip(app.config.assets_url_path, '/'), "/", img)
            end
        end
    end

    return Dict{String,String}[
        Dict("name" => "description", "content" => description),
        Dict("name" => "twitter:card", "content" => "summary_large_image"),
        Dict("name" => "twitter:url", "content" => request_path),
        Dict("name" => "twitter:title", "content" => title),
        Dict("name" => "twitter:description", "content" => description),
        Dict("name" => "twitter:image", "content" => image),
        Dict("property" => "og:title", "content" => title),
        Dict("property" => "og:type", "content" => "website"),
        Dict("property" => "og:description", "content" => description),
        Dict("property" => "og:image", "content" => image),
    ]
end
