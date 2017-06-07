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
     model["dynamic_endog_xrefs"],
     model["dynamic_exog_xrefs"],
     model["static_xrefs"],
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
           model["dynamic_endog_xrefs"],
           model["dynamic_exog_xrefs"],
           model["static_xrefs"],
           model["dict_lead_lag"],
           model["dict_lead_lag_subs"],
           model["param_init"],
           model["init_val"],
           model["end_val"]) = parse_json(json)

    # Calculate derivatives
    (staticg1, staticg2, dynamic) = compose_derivatives(model)

    # Return JSON and Julia representation of modfile
    (json, model, staticg1, staticg2, dynamic)
    #(json, model)
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

function get_all_endog_xrefs(a::Array{Any,1})
    lag = OrderedDict{Any, Array{Int}}()
    t = OrderedDict{Any, Array{Int}}()
    lead = OrderedDict{Any, Array{Int}}()
    for i in a
        if i["shift"] == -1
            lag[(i["endogenous"], -1)] = round(Int, i["equations"])
        elseif i["shift"] == 0
            t[(i["endogenous"], 0)] = round(Int, i["equations"])
        elseif i["shift"] == 1
            lead[(i["endogenous"], 1)] = round(Int, i["equations"])
        else
            @assert false
        end
    end
    merge(lag, t, lead)
end

function get_all_exog_xrefs(a::Array{Any,1})
    lag = OrderedDict{Any, Array{Int}}()
    t = OrderedDict{Any, Array{Int}}()
    lead = OrderedDict{Any, Array{Int}}()
    for i in a
        if i["shift"] == -1
            lag[(i["exogenous"], -1)] = round(Int, i["equations"])
        elseif i["shift"] == 0
            t[(i["exogenous"], 0)] = round(Int, i["equations"])
        elseif i["shift"] == 1
            lead[(i["exogenous"], 1)] = round(Int, i["equations"])
        else
            @assert false
        end
    end
    merge(lag, t, lead)
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

    #
    # Model Equations
    #
    equations, dynamic = Array{Expr,1}(), Array{SymEngine.Basic, 1}()
    for e in json_model["model"]
        push!(equations, parse_eq(e))
    end
    for e in equations
        push!(dynamic, SymEngine.Basic(e))
    end

    # Cross References
    dynamic_exog_xrefs = get_all_exog_xrefs(json_model["xrefs"]["exogenous"])
    dynamic_endog_xrefs = get_all_endog_xrefs(json_model["xrefs"]["endogenous"])

    dict_lead_lag = Dict()
    static_xrefs = OrderedDict{Any, Array{Int}}()
    for i in dynamic_endog_xrefs
        if i[1][2] != 0
            dict_lead_lag[i[1]] = i[2]
        end
        if haskey(static_xrefs, i[1][1])
            static_xrefs[i[1][1]] = union(static_xrefs[i[1][1]], i[2])
        else
            static_xrefs[i[1][1]] = i[2]
        end
    end
    static, dynamic_sub = copy(dynamic), copy(dynamic)
    tostatic(static, dict_lead_lag)
    # Substitute symbols for lead and lagged variables
    # Can drop this part once SymEngine has implemented derivatives of functions. See https://github.com/symengine/SymEngine.jl/issues/53
    dict_lead_lag_subs = Dict{Any, String}()
    subLeadLagsInEqutaions(dynamic_sub, dict_lead_lag_subs, dict_lead_lag)

    #
    # Statements
    #
    # Param Init
    param_init = OrderedDict{Symbol,Number}()
    get_param_inits(param_init, json_model["statements"])

    # Init Val
    init_val = OrderedDict{Symbol,Number}()
    get_numerical_initialization(init_val, json_model["statements"], "init_val")

    # End Val
    end_val = OrderedDict{Symbol,Number}()
    get_numerical_initialization(end_val, json_model["statements"], "end_val")

    # Return
    (parameters, endogenous, exogenous, exogenous_deterministic, equations, dynamic, static, dynamic_sub, dynamic_endog_xrefs, dynamic_exog_xrefs, static_xrefs, dict_lead_lag, dict_lead_lag_subs, param_init, init_val, end_val)
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

function get_tsid(model::DataStructures.OrderedDict{String,Any}, vartype::String, name::String)
    idx = 1
    for var in model[vartype]
        var.name == name ? (return idx) : idx += 1
    end
    return -1
end

function is_var_type(vartype, name::String)
    for var in vartype
        if var.name == name
            return true
        end
    end
    return false
end

function compose_derivatives(model)
    nendog = length(model["endogenous"])
    ndynvars = length(model["dynamic_endog_xrefs"]) + length(model["dynamic_exog_xrefs"])

    # Static Jacobian
    I, J, V = Array{Int,1}(), Array{Int,1}(), Array{SymEngine.Basic,1}()
    for i = 1:nendog
        for eq in model["static_xrefs"][model["endogenous"][i].name]
            deriv = SymEngine.diff(model["static"][eq], SymEngine.symbols(model["endogenous"][i].name))
            if deriv != 0
                I = [I; eq]
                J = [J; i]
                V = [V; deriv]
            end
        end
    end
    staticg1 = sparse(I, J, V, nendog, nendog)

    # Static Hessian
    I, J, V = Array{Int,1}(), Array{Int,1}(), Array{SymEngine.Basic,1}()
    for i = 1:nendog
        for eq in staticg1.rowval[staticg1.colptr[i]:staticg1.colptr[i+1]-1]
            # Diagonal
            deriv = SymEngine.diff(staticg1[eq, i], SymEngine.symbols(model["endogenous"][i].name))
            if deriv != 0
                I = [I; eq]
                J = [J; (i-1)*nendog+i]
                V = [V; deriv]
            end
            for j = i+1:nendog
                # Off-diagonal
                if any(eq .== model["static_xrefs"][model["endogenous"][j].name])
                    deriv = SymEngine.diff(staticg1[eq, i], SymEngine.symbols(model["endogenous"][j].name))
                    if deriv != 0
                        I = [I; eq; eq]
                        J = [J; (i-1)*nendog+j; (j-1)*nendog+i]
                        V = [V; deriv; deriv]
                    end
                end
            end
        end
    end
    staticg2 = sparse(I, J, V, nendog, nendog^2)

    # Dynamic Jacobian
    I, J, V = Array{Int,1}(), Array{Int,1}(), Array{SymEngine.Basic,1}()

    dynamic = sparse(I, J, V)

    (staticg1, staticg2, dynamic)
end
