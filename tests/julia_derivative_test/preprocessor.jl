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
     model["param_init"],
     model["init_val"],
     model["end_val"]) = parse_json(json)

    @time (model["parameters"],
           model["endogenous"],
           model["exogenous"],
           model["exogenous_deterministic"],
           model["equations"],
           model["param_init"],
           model["init_val"],
           model["end_val"]) = parse_json(json)

    (static, dynamic) = compose_derivatives(model)

    # Return JSON and Julia representation of modfile
    (json, model, static, dynamic)
end

function run_preprocessor(modfile::String)
    dynare_m = "/Users/houtanb/dynare_unstable/preprocessor/dynare_m"
    run(`$dynare_m $modfile.mod json=transform onlyjson`)

    jsonfile = "$modfile.json"
    json = open(jsonfile)
    modfile = JSON.parse(readstring(json))
    close(json)
    return modfile
end

function get_vars(d::OrderedDict{Symbol,Any}, a::Array{Any,1})
    for i in a
        d[Symbol(i["name"])] = (i["texName"], i["longName"])::Tuple{String, String}
    end
end

function get_vars(d::Array{DynareModel.Endo,1}, a::Array{Any,1})
    for i in a
        push!(d, DynareModel.Endo(Symbol(i["name"]::String), i["texName"]::String, i["longName"]::String))
    end
end

function get_vars(d::Array{DynareModel.Exo,1}, a::Array{Any,1})
    for i in a
        push!(d, DynareModel.Exo(Symbol(i["name"]::String), i["texName"]::String, i["longName"]::String))
    end
end

function get_vars(d::Array{DynareModel.Param,1}, a::Array{Any,1})
    for i in a
        push!(d, DynareModel.Param(Symbol(i["name"]::String), i["texName"]::String, i["longName"]::String))
    end
end

function get_vars(d::Array{DynareModel.ExoDet,1}, a::Array{Any,1})
    for i in a
        push!(d, DynareModel.ExoDet(Symbol(i["name"]::String), i["texName"]::String, i["longName"]::String))
    end
end

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
    equations = Array{Expr,1}()
    for e in json_model["model"]
        push!(equations, parse_eq(e))
    end

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
    (parameters, endogenous, exogenous, exogenous_deterministic, equations, param_init, init_val, end_val)
end

function compose_derivatives(model)
    (static, dynamic) = (Array{Expr, 1}(), Array{Expr, 1}())

    

    (static, dynamic)
end
