push!(LOAD_PATH, "/Users/houtanb/Documents/DYNARE/julia/dynare/julia")
#push!(LOAD_PATH, "/Users/houtanb/Documents/DYNARE/julia/dynare/tests/julia_derivative_test/v0.5")

include("DynareJson.jl")

modfile = "example1"
model = DynareJson.process(modfile)
