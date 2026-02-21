# ─── HTTP Middleware / Handler Wrappers ───────────────────────────────────────

struct RequestHandlerFunction <: HTTP.Handler
    func::Function
end

(x::RequestHandlerFunction)(args...) = x.func(args...)

function handle(h::RequestHandlerFunction, request::HTTP.Request, args...)
    h(request, args...)
end

function handle(handler::Function, request::HTTP.Request, args...)
    handler(request, args...)
end

# ─── State Handler ───────────────────────────────────────────────────────────
# Wraps handler to inject HandlerState and set default content headers.

function state_handler(base_handler, state)
    return RequestHandlerFunction(
        function (request::HTTP.Request, args...)
            response = handle(base_handler, request, state, args...)
            if response.status == 200
                HTTP.defaultheader!(response, "Content-Type" => HTTP.sniff(response.body))
                HTTP.defaultheader!(response, "Content-Length" => string(sizeof(response.body)))
            end
            return response
        end
    )
end

state_handler(base_handler::Function, state) = state_handler(RequestHandlerFunction(base_handler), state)

# ─── Compression Handler ────────────────────────────────────────────────────

function check_mime(message::HTTP.Message, mime_list)
    !HTTP.hasheader(message, "Content-Type") && return false
    mime_type = split(HTTP.header(message, "Content-Type", ""), ';')[1]
    return mime_type in mime_list
end

const DEFAULT_COMPRESS_MIMES = [
    "text/plain", "text/html", "text/css", "text/xml",
    "application/json", "application/javascript", "application/css"
]

function compress_handler(base_handler; mime_types=DEFAULT_COMPRESS_MIMES, compress_min_size=500)
    return RequestHandlerFunction(
        function (request::HTTP.Request, args...)
            response = handle(base_handler, request, args...)
            if response.status == 200 &&
               sizeof(response.body) >= compress_min_size &&
               occursin("gzip", HTTP.header(request, "Accept-Encoding", "")) &&
               check_mime(response, mime_types)
                HTTP.setheader(response, "Content-Encoding" => "gzip")
                response.body = transcode(CodecZlib.GzipCompressor, response.body)
                HTTP.setheader(response, "Content-Length" => string(sizeof(response.body)))
            end
            return response
        end
    )
end

compress_handler(base_handler::Function; kwargs...) =
    compress_handler(RequestHandlerFunction(base_handler); kwargs...)

# ─── Exception Handling Handler ──────────────────────────────────────────────

function exception_handling_handler(ex_handling_func, base_handler)
    return RequestHandlerFunction(
        function (request::HTTP.Request, args...)
            try
                return handle(base_handler, request, args...)
            catch e
                return ex_handling_func(e)
            end
        end
    )
end

exception_handling_handler(ex_handling_func, base_handler::Function) =
    exception_handling_handler(ex_handling_func, RequestHandlerFunction(base_handler))
