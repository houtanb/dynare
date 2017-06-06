import JSON
import SymEngine

function process(modfile::String)
    # Run Dynare preprocessor get JSON output
    json = run_preprocessor(modfile)

    # Parse JSON output into Julia representation
    model = OrderedDict{String, Any}()
    (model["parameters"],
     model["endogenous"],
     model["exogenous"],
     model["exogenous_deterministic"],
     model["equations"],
     model["dynamic"],
     model["static"],
     model["dynamic_sub"],
     model["dict_lead_lag"],
     model["dict_lead_lag_subs"],
     model["param_init"],
     model["init_val"],
     model["end_val"]) = parse_json(json)

    @time (model["parameters"],
           model["endogenous"],
           model["exogenous"],
           model["exogenous_deterministic"],
           model["equations"],
           model["dynamic"],
           model["static"],
           model["dynamic_sub"],
           model["dict_lead_lag"],
           model["dict_lead_lag_subs"],
           model["param_init"],
           model["init_val"],
           model["end_val"]) = parse_json(json)

    # Calculate derivatives
    (static, dynamic) = compose_derivatives(model)

    # Return JSON and Julia representation of modfile
    (json, model, static, dynamic)
end

function run_preprocessor(modfile::String)
    dynare_m = "/Users/houtanb/Documents/DYNARE/julia/dynare/preprocessor/dynare_m"
    run(`$dynare_m $modfile.mod json=transform onlyjson`)

    json = open("$modfile.json")
    modfile = JSON.parse(readstring(json))
    close(json)
    return modfile
end

function get_vars(d::OrderedDict{Symbol,Any}, a::Array{Any,1})
    for i in a
        d[i["name"]]::String = (i["texName"], i["longName"])::Tuple{String, String}
    end
end

function get_vars(d::Array{DynareModel.Endo,1}, a::Array{Any,1})
    for i in a
        push!(d, DynareModel.Endo(i["name"]::String, i["texName"]::String, i["longName"]::String))
    end
end

function get_vars(d::Array{DynareModel.Exo,1}, a::Array{Any,1})
    for i in a
        push!(d, DynareModel.Exo(i["name"]::String, i["texName"]::String, i["longName"]::String))
    end
end

function get_vars(d::Array{DynareModel.Param,1}, a::Array{Any,1})
    for i in a
        push!(d, DynareModel.Param(i["name"]::String, i["texName"]::String, i["longName"]::String))
    end
end

function get_vars(d::Array{DynareModel.ExoDet,1}, a::Array{Any,1})
    for i in a
        push!(d, DynareModel.ExoDet(i["name"]::String, i["texName"]::String, i["longName"]::String))
    end
end

#@generated function get_vars(d, a)
#    for i in a
#        push!()
#    end
#end

function parse_eq(eq::Dict{String,Any})
    if eq["rhs"] == "0"
        return parse(eq["lhs"])
    end
    (lhs, rhs) = (parse(eq["lhs"]), parse(eq["rhs"]))
    return :($lhs - $rhs)
end

function get_param_inits(d::OrderedDict{Symbol,Number}, a::Array{Any,1})
    for st in a
        if st["statementName"] == "param_init"
            d[Symbol(st["name"])] = parse(st["value"])::Number
        end
    end
end

function get_numerical_initialization(d::OrderedDict{Symbol,Number}, a::Array{Any,1}, field::String)
    for st in a
        if st["statementName"] == field
            for v in st["vals"]
                d[Symbol(v["name"])] = parse(v["value"])::Number
            end
        end
    end
end

function get_endog_xrefs(dict::Dict{Any, Any}, a::Array{Any,1})
    for i in a
        if i["shift"] != 0
            dict[(i["endogenous"], i["shift"])] = round(Int, i["equations"])
        end
    end
end

function get_exog_xrefs(dict::Dict{Any, Any}, a::Array{Any,1})
    for i in a
        if i["shift"] != 0
            dict[(i["exogenous"], i["shift"])] = round(Int, i["equations"])
        end
    end
end

function parse_json(json_model::Dict{String,Any})
    # Model variables, parameters
#    MUCH SLOWER THIS WAY
#    parameters, endogenous, exogenous, exogenous_deterministic =
#        OrderedDict{Symbol,Any}(), OrderedDict{Symbol,Any}(), OrderedDict{Symbol,Any}(), OrderedDict{Symbol,Any}()

    parameters, endogenous, exogenous, exogenous_deterministic =
        Array{DynareModel.Param, 1}(), Array{DynareModel.Endo, 1}(), Array{DynareModel.Exo, 1}(), Array{DynareModel.ExoDet, 1}()

    get_vars(parameters, json_model["parameters"])
    get_vars(endogenous, json_model["endogenous"])
    get_vars(exogenous, json_model["exogenous"])
    get_vars(exogenous_deterministic, json_model["exogenous_deterministic"])

    # Model Equations
    equations, dynamic = Array{Expr,1}(), Array{SymEngine.Basic, 1}()
    for e in json_model["model"]
        push!(equations, parse_eq(e))
    end
    for e in equations
        push!(dynamic, SymEngine.Basic(e))
    end

    dict_lead_lag = Dict()
    get_exog_xrefs(dict_lead_lag, json_model["xrefs"]["exogenous"])
    get_endog_xrefs(dict_lead_lag, json_model["xrefs"]["endogenous"])
    static, dynamic_sub = dynamic, dynamic
    dict_lead_lag_subs = Dict{Any, String}()
    subLeadLagsInEqutaions(dynamic_sub, dict_lead_lag_subs, dict_lead_lag)
    tostatic(static, dict_lead_lag)

    # Statements
    # Param Init
    param_init = OrderedDict{Symbol,Number}()
    get_param_inits(param_init, json_model["statements"])

    # Init Val
    init_val = OrderedDict{Symbol,Number}()
    get_numerical_initialization(init_val, json_model["statements"], "init_val")

    # End Val
    end_val = OrderedDict{Symbol,Number}()
    get_numerical_initialization(end_val, json_model["statements"], "end_val")

    # Cross References

    # Return
    (parameters, endogenous, exogenous, exogenous_deterministic, equations, dynamic, static, dynamic_sub, dict_lead_lag, dict_lead_lag_subs, param_init, init_val, end_val)
end

function tostatic(subeqs::Array{SymEngine.Basic, 1}, dict_lead_lag::Dict{Any,Any})
    for de in dict_lead_lag
        for i in de[2]
            subeqs[i] = SymEngine.subs(subeqs[i], SymEngine.Basic(string(de[1][1], "(", de[1][2], ")")), SymEngine.symbols(de[1][1]))
        end
    end
end

function subLeadLagsInEqutaions(subeqs::Array{SymEngine.Basic, 1}, dict_lead_lag_subs::Dict{Any, String}, dict_lead_lag::Dict{Any,Any})
    for de in dict_lead_lag
        var = de[1][1]
        lag = de[1][2]
        subvar = string("__lead_lag_subvar__", var, lag < 0 ? string("m", abs(lag)) : lag)
        dict_lead_lag_subs[de[1]] = subvar
        for i in de[2]
            subeqs[i] = SymEngine.subs(subeqs[i], SymEngine.Basic(string(var, "(", lag, ")")), SymEngine.symbols(subvar))
        end
    end
end

function compose_derivatives(model)
    (static, dynamic) = (Array{Expr, 1}(), Array{Expr, 1}())

    # declare symengine vars
#    diff(SymEngine.Basic("x^2*y"), SymEngine.symbols("x"))

    # Substitute symbols for lead and lagged variables
    # Can drop this part once SymEngine has implemented derivatives of functions. See https://github.com/symengine/SymEngine.jl/issues/53
    #
    # SymEngine.subs(SymEngine.Basic("y*x(1)^3"), SymEngine.Basic("x(1)"), SymEngine.symbols("newvar"))

    (static, dynamic)
end
