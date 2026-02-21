# ─── Fingerprinting (Cache Busting) ──────────────────────────────────────────

const FP_VERSION_CLEAN = r"[^\w-]"
const FP_CACHE_REGEX = r"^v[\w-]+m[0-9a-fA-F]+$"

function build_fingerprint(path::AbstractString, version, hash_value)
    path_parts = split(path, '/')
    (filename, extension) = split(path_parts[end], '.', limit=2)
    return string(
        join(vcat(path_parts[1:end-1], filename), '/'),
        ".v", replace(string(version), FP_VERSION_CLEAN => "_"),
        'm', hash_value,
        '.', extension
    )
end

function parse_fingerprint_path(path::AbstractString)
    path_parts = split(path, '/')
    name_parts = split(path_parts[end], '.')
    if length(name_parts) > 2 && occursin(FP_CACHE_REGEX, name_parts[2])
        origin_path = string(
            join(vcat(path_parts[1:end-1], [name_parts[1]]), '/'),
            '.', join(name_parts[3:end], '.')
        )
        return (origin_path, true)
    end
    return (path, false)
end
