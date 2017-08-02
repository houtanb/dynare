include("test_symbolic_derivs.jl");
include("test_preprocessor_derivs.jl");

println("-------------------------")
println("- Symbolic Derivs Below -")
println("-------------------------")
@time include("test_symbolic_derivs.jl")

println("-------------------------")
println("Preprocessor Derivs Below")
println("-------------------------")
@time include("test_preprocessor_derivs.jl")
