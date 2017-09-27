push!(LOAD_PATH, "/Users/houtanb/Documents/DYNARE/julia/dynare/julia")
#push!(LOAD_PATH, "/Users/houtanb/Documents/DYNARE/julia/dynare/tests/julia_derivative_test/v0.5")

include("DynareJsonComputingPass.jl")

modfile = "example1"
(json, json_static, json_dynamic) = DynareJsonComputingPass.process(modfile)
