using Bisect
using Test
using Aqua

@testset "Bisect.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(Bisect)
    end
    # Write your tests here.
end
