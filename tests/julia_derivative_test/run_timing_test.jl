
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


# example1.mod
# N = 1

# Julia Derivatives
# without tmp terms: 1.570666 seconds (492.87 k allocations: 25.659 MiB, 0.81% gc time)

# Preprocessor Derivatives
# with tmp terms   : 0.358290 seconds (146.48 k allocations: 8.055 MiB)
# without tmp terms: 0.418459 seconds (193.91 k allocations: 10.207 MiB, 3.59% gc time)

# N = 10000
# Julia Derivatives
# without tmp terms: 1.544284 seconds (492.97 k allocations: 25.668 MiB, 0.97% gc time)

# Preprocessor Derivatives
# with tmp terms   : 0.381472 seconds (175.47 k allocations: 8.674 MiB)
# without tmp terms: 0.468447 seconds (432.88 k allocations: 14.013 MiB, 3.92% gc time)
