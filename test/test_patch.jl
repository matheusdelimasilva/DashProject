@testset "Patch" begin
    @testset "Basic operations" begin
        p = Patch()
        push!(p, "item1")
        p["key"] = 42

        @test length(p._operations) == 2
        @test p._operations[1]["operation"] == "Append"
        @test p._operations[2]["operation"] == "Assign"
    end

    @testset "All operation types" begin
        p = Patch()
        push!(p, "val")         # Append
        Dash2.prepend!(p, "v")  # Prepend
        insert!(p, 0, "v")      # Insert
        append!(p, [1, 2])      # Extend
        Dash2.remove!(p, "x")   # Remove
        Dash2.clear!(p)         # Clear
        Dash2.reverse!(p)       # Reverse
        delete!(p, "k")         # Delete
        merge!(p, Dict("a" => 1)) # Merge
        Dash2.add!(p, 5)        # Add
        Dash2.sub!(p, 3)        # Sub
        Dash2.mul!(p, 2)        # Mul
        Dash2.div!(p, 4)        # Div

        @test length(p._operations) == 13
        ops = [o["operation"] for o in p._operations]
        @test ops == ["Append", "Prepend", "Insert", "Extend", "Remove",
                       "Clear", "Reverse", "Delete", "Merge", "Add", "Sub", "Mul", "Div"]
    end

    @testset "Nested access" begin
        p = Patch()
        push!(p["items"], "new_item")

        # The operation should target the parent's operations list
        @test length(p._operations) == 1
        @test p._operations[1]["location"] == ["items"]
        @test p._operations[1]["operation"] == "Append"
    end

    @testset "JSON serialization" begin
        p = Patch()
        p["count"] = 42
        json_str = String(JSON3.rawbytes(p))

        @test occursin("__dash_patch_update", json_str)
        @test occursin("Assign", json_str)
        @test occursin("42", json_str)

        parsed = JSON3.read(json_str)
        @test parsed.__dash_patch_update == "__dash_patch_update"
    end

    @testset "is_patch" begin
        @test Dash2.is_patch(Patch()) == true
        @test Dash2.is_patch(Dict("__dash_patch_update" => "__dash_patch_update")) == true
        @test Dash2.is_patch("string") == false
        @test Dash2.is_patch(42) == false
    end
end
