
println("......ignore this......")
include("test_symbolic_derivs.jl");
include("test_preprocessor_derivs.jl");

println()
println("IGNORE WHAT IS ABOVE THIS LINE")
println()
println()
println("-------------------------")
println("- Symbolic Derivs Below -")
println("-------------------------")
@time include("test_symbolic_derivs.jl")

println("-------------------------")
println("Preprocessor Derivs Below")
println("-------------------------")
@time include("test_preprocessor_derivs.jl")
