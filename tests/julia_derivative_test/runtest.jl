push!(LOAD_PATH, "/Users/houtanb/dynare_unstable/tests/julia_derivative_test/v0.5")

include("DynareJson.jl")

modfile = "example1"
model = DynareJson.process(modfile)
