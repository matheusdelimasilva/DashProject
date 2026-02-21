# ─── Pages System ────────────────────────────────────────────────────────────
# Phase 3 implementation — placeholder for multi-page app support.

const PAGE_REGISTRY = DataStructures.OrderedDict{String,Dict{String,Any}}()

"""
    register_page(module_name; path=nothing, name=nothing, layout=nothing, order=nothing, kwargs...)

Register a page in the multi-page application system.
Pages are stored in the global `PAGE_REGISTRY`.

# Arguments
- `module_name` — unique identifier for the page (typically the module name)
- `path` — URL path for the page (e.g., "/analytics")
- `name` — display name for navigation
- `layout` — component or function returning the page layout
- `order` — display order in page listings
"""
function register_page(module_name::String;
                       path=nothing,
                       name=nothing,
                       layout=nothing,
                       order=nothing,
                       title=nothing,
                       description=nothing,
                       image=nothing,
                       redirect_from=nothing,
                       kwargs...)
    if isnothing(path)
        path = "/" * replace(module_name, "." => "/")
    end
    if isnothing(name)
        name = replace(basename(path), "-" => " ") |> titlecase
    end

    page_entry = Dict{String,Any}(
        "module" => module_name,
        "path" => path,
        "name" => name,
        "layout" => layout,
        "order" => isnothing(order) ? length(PAGE_REGISTRY) : order,
        "title" => isnothing(title) ? name : title,
        "description" => isnothing(description) ? "" : description,
        "image" => image,
        "redirect_from" => redirect_from,
    )
    for (k, v) in kwargs
        page_entry[string(k)] = v
    end

    PAGE_REGISTRY[module_name] = page_entry
    return nothing
end
