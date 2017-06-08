import JSON
import SymEngine

# See below for why we need this
SymEngineKeyWords = ["e"]
SymEngineKeyWords = [Symbol(kw) for kw in SymEngineKeyWords]
SymEngineKeywordAtoms = [DynareModel.Endo(string(i), string(i), string(i)) for i in SymEngineKeyWords]

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
     model["dict_subs"],
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
           model["dict_subs"],
           model["param_init"],
           model["init_val"],
           model["end_val"]) = parse_json(json)

    # Calculate derivatives
    (staticg1, staticg2, dynamicg1) = compose_derivatives(model)

    # Return JSON and Julia representation of modfile
    (json, model, staticg1, staticg2, dynamicg1)
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

function get_vars!(d::Array{DynareModel.Endo,1}, json::Array{Any,1})
    idx = 1
    for i in json
        d[idx] = DynareModel.Endo(i["name"]::String, i["texName"]::String, i["longName"]::String)
        idx += 1
    end
end

function get_vars!(d::Array{DynareModel.Exo,1}, json::Array{Any,1})
    idx = 1
    for i in json
        d[idx] = DynareModel.Exo(i["name"]::String, i["texName"]::String, i["longName"]::String)
        idx += 1
    end
end

function get_vars!(d::Array{DynareModel.Param,1}, json::Array{Any,1})
    idx = 1
    for i in json
        d[idx] = DynareModel.Param(i["name"]::String, i["texName"]::String, i["longName"]::String)
        idx += 1
    end
end

function get_vars!(d::Array{DynareModel.ExoDet,1}, json::Array{Any,1})
    idx = 1
    for i in json
        d[idx] = DynareModel.ExoDet(i["name"]::String, i["texName"]::String, i["longName"]::String)
        idx += 1
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

function get_xrefs(json::Array{Any,1})
    lag = OrderedDict{Any, Array{Int}}()
    t = OrderedDict{Any, Array{Int}}()
    lead = OrderedDict{Any, Array{Int}}()
    for i in json
        if i["shift"] == -1
            lag[(i["name"], -1)] = round(Int, i["equations"])
        elseif i["shift"] == 0
            t[(i["name"], 0)] = round(Int, i["equations"])
        elseif i["shift"] == 1
            lead[(i["name"], 1)] = round(Int, i["equations"])
        else
            @assert false
        end
    end
    merge(lag, t, lead)
end

function parse_json(json_model::Dict{String,Any})
    # Model variables, parameters
    parameters, endogenous, exogenous, exogenous_deterministic =
        Array{DynareModel.Param, 1}(length(json_model["parameters"])), Array{DynareModel.Endo, 1}(length(json_model["endogenous"])), Array{DynareModel.Exo, 1}(length(json_model["exogenous"])), Array{DynareModel.ExoDet, 1}(length(json_model["exogenous_deterministic"]))

    get_vars!(parameters, json_model["parameters"])
    get_vars!(endogenous, json_model["endogenous"])
    get_vars!(exogenous, json_model["exogenous"])
    get_vars!(exogenous_deterministic, json_model["exogenous_deterministic"])

    #
    # Model Equations
    #
    equations, dynamic = Array{Expr,1}(), Array{SymEngine.Basic, 1}()
    for e in json_model["model"]
        push!(equations, parse_eq(e))
    end

    dict_subs = Dict()
    symengineKeywordPresent = false
    if !isempty(filter(x->x in endogenous, SymEngineKeywordAtoms)) ||
        !isempty(filter(x->x in exogenous, SymEngineKeywordAtoms)) ||
        !isempty(filter(x->x in exogenous_deterministic, SymEngineKeywordAtoms)) ||
        !isempty(filter(x->x in parameters, SymEngineKeywordAtoms))
        symengineKeywordPresent = true
        for i in SymEngineKeyWords
            dict_subs[(string(i), 0)] = string("___", string(i), "___")
        end
    end
    for e in equations
        if symengineKeywordPresent
            # NB: SymEngine converts Basic("e") => E,
            #                    but Basic("e(-1)") => symbols("e(-1)")
            #                    and Basic("e(1)") => symbols("e(1)")
            # To fix this, we substitute e at time t
            e = replaceSymEngineKeyword(e)
        end
        push!(dynamic, SymEngine.Basic(e))
    end

    # Cross References
    dynamic_endog_xrefs = get_xrefs(json_model["xrefs"]["endogenous"])
    dynamic_exog_xrefs = get_xrefs(json_model["xrefs"]["exogenous"])

    dict_lead_lag = Dict()
    static_xrefs = OrderedDict{Any, Array{Int}}()
    for i in dynamic_endog_xrefs
        if i[1][2] != 0
            dict_lead_lag[i[1]] = i[2]
            dict_subs[i[1]] = string("___", i[1][1], i[1][2] == -1 ? "m1" : "1", "___")
        else
            if !haskey(dict_subs, i[1])
                dict_subs[i[1]] = i[1][1]
            end
        end
        if haskey(static_xrefs, i[1][1])
            static_xrefs[i[1][1]] = union(static_xrefs[i[1][1]], i[2])
        else
            static_xrefs[i[1][1]] = i[2]
        end
    end
    for i in dynamic_exog_xrefs
        if i[1][2] != 0
            dict_lead_lag[i[1]] = i[2]
            dict_subs[i[1]] = string("___", i[1][1], i[1][2] == -1 ? "m1" : "1", "___")
        else
            if !haskey(dict_subs, i[1])
                dict_subs[i[1]] = i[1][1]
            end
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
    (parameters, endogenous, exogenous, exogenous_deterministic, equations, dynamic, static, dynamic_sub, dynamic_endog_xrefs, dynamic_exog_xrefs, static_xrefs, dict_lead_lag, dict_lead_lag_subs, dict_subs, param_init, init_val, end_val)
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
        subvar = string("___", de[1][1], de[1][2] < 0 ? string("m", abs(de[1][2])) : de[1][2], "___")
        dict_lead_lag_subs[de[1]] = subvar
        for i in de[2]
            subeqs[i] = SymEngine.subs(subeqs[i], SymEngine.Basic(string(de[1][1], "(", de[1][2], ")")), SymEngine.symbols(subvar))
        end
    end
end

# Replace "e" in equations
# Cannot be done on equations that have already passed through SymEngine.Basic
# Because we can't differentiate between E that comes from e and E that comes from exp
# as e and exp are equivalent in SymEngine
replaceSymEngineKeyword(a::Number) = a
replaceSymEngineKeyword(a::Symbol) = a in SymEngineKeyWords ? Symbol("___", string(a), "___") : a

function replaceSymEngineKeyword(expr::Expr)
    ex = copy(expr)
    for (i, arg) in enumerate(expr.args)
        ex.args[i] = replaceSymEngineKeyword(arg)
    end
    return ex
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
    col = 1
    for tup in model["dynamic_endog_xrefs"]
        for eq in tup[2]
            deriv = SymEngine.diff(model["dynamic_sub"][eq], SymEngine.symbols(model["dict_subs"][tup[1]]))
            if deriv != 0
                I = [I; eq]
                J = [J; col]
                V = [V; deriv]
            end
        end
        col += 1
    end

    for tup in model["dynamic_exog_xrefs"]
        for eq in tup[2]
            deriv = SymEngine.diff(model["dynamic_sub"][eq], SymEngine.symbols(model["dict_subs"][tup[1]]))
            if deriv != 0
                I = [I; eq]
                J = [J; col]
                V = [V; deriv]
            end
        end
        col += 1
    end
    dynamicg1 = sparse(I, J, V, nendog, ndynvars)

    (staticg1, staticg2, dynamicg1)
end
