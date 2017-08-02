modfile="example1"
dynare_m = "/Users/houtanb/Documents/DYNARE/julia/dynare/preprocessor/dynare_m"
run(`$dynare_m $modfile.mod language=julia output=dynamic`)

include("example1Static.jl")
#import example1Static

include("example1Dynamic.jl")

endogsd = [i*1.0 for i=1:12];
endogss = [i*1.0 for i=1:6];
exogss = [i*1.0 for i=1:2];
params = [i*1.0 for i=1:7];

sresidual, dresidual = Vector{Float64}(6), Vector{Float64}(6)
sg1, sg2 = Matrix{Float64}(6,6), Matrix{Float64}(6,36)
dg1, dg2 = Matrix{Float64}(6,14), Matrix{Float64}(6,196)

exogsd = Matrix{Float64}(1,2)
exogsd[1] = 1
exogsd[2] = 2

N = 10000
for i = 1:N
    example1Static.static!(endogss, exogss, params, sresidual, sg1, sg2)
    example1Dynamic.dynamic!(endogsd, exogsd, params, params, 1, dresidual, dg1, dg2)
end
