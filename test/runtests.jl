using Dash2
using Test
using JSON3
using HTTP

@testset "Dash2.jl" begin
    include("test_components.jl")
    include("test_app.jl")
    include("test_callbacks.jl")
    include("test_patch.jl")
    include("test_dispatch.jl")
    include("test_server.jl")
    include("test_pages.jl")
    include("test_background.jl")
end
