(json, model, StaticG1!, staticg1ref, StaticG2!, staticg2ref, DynamicG1!, dynamicg1ref, DynamicG2!, dynamicg2ref) = include("runtest.jl");

endogsd = [i*1.0 for i=1:12];
endogss = [i*1.0 for i=1:6];
exogs = [i*1.0 for i=1:2];
params = [i*1.0 for i=1:7];

sg1 = spzeros(6, 6)
sg2 = spzeros(6, 36)
dg1 = spzeros(6, 14)
dg2 = spzeros(6, 196)
N = 10000
for i = 1:N
    StaticG1!(endogss, exogs, params, sg1)
    StaticG2!(endogss, exogs, params, sg2)
    DynamicG1!(endogsd, exogs, params, dg1)
    DynamicG2!(endogsd, exogs, params, dg2)
end
