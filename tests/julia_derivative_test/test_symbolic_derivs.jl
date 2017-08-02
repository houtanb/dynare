(json, model, StaticG1, staticg1ref, StaticG2, staticg2ref, DynamicG1, dynamicg1ref, DynamicG2, dynamicg2ref) = include("runtest.jl");

endogs = [i*1.0 for i=1:20];
exogs = [i*1.0 for i=1:20];
params = [i*1.0 for i=1:20];

N = 10000
for i = 1:N
    sg1 = StaticG1(endogs, exogs, params)
    sg2 = StaticG2(endogs, exogs, params)
    dg1 = DynamicG1(endogs, exogs, params)
    dg2 = DynamicG2(endogs, exogs, params)
end
