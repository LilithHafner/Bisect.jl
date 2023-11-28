using Bisect
using Test
using Aqua

@testset "Bisect.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(Bisect, deps_compat=false)
        Aqua.test_deps_compat(Bisect, check_extras=false)
    end
    # Write your tests here.
end
