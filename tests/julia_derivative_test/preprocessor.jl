import JSON
import SymEngine


# NB: SymEngine converts Basic("e") => E,
#                    but Basic("e(-1)") => symbols("e(-1)")
#                    and Basic("e(1)") => symbols("e(1)")
# To fix this, we substitute e at time t.
# Define constants needed to do this here.
# The workhorse function is replaceNonDynareSymEngineKeyword
const nonDynareSymEngineKeyWordString = "e"
const nonDynareSymEngineKeyWordSymbol = Symbol(nonDynareSymEngineKeyWordString)
const nonDynareSymEngineKeyWordStringSub = string("___e___")
const nonDynareSymEngineKeyWordSymbolSub = Symbol(nonDynareSymEngineKeyWordStringSub)
const nonDynareSymEngineKeyWordSymEngineSymbolSub = SymEngine.symbols(nonDynareSymEngineKeyWordStringSub)
const nonDynareSymEngineKeyWordAtom = DynareModel.Endo(nonDynareSymEngineKeyWordString, nonDynareSymEngineKeyWordString, nonDynareSymEngineKeyWordString)
# END NB

function process(modfile::String)
    # Run Dynare preprocessor get JSON output
    json = run_preprocessor(modfile)

    # Parse JSON output into Julia representation
    model = OrderedDict{String, Any}()
    (model["parameters"],
     model["endogenous"],
     model["exogenous"],
     model["exogenous_deterministic"],
     model["equations_dynamic"],
     model["equations_static"],
     model["dynamic"],
     model["static"],
     model["dynamic_endog_xrefs"],
     model["dynamic_exog_xrefs"],
     model["static_xrefs"],
     model["param_init"],
     model["init_val"],
     model["end_val"]) = parse_json(json)

    @time (model["parameters"],
           model["endogenous"],
           model["exogenous"],
           model["exogenous_deterministic"],
           model["equations_dynamic"],
           model["equations_static"],
           model["dynamic"],
           model["static"],
           model["dynamic_endog_xrefs"],
           model["dynamic_exog_xrefs"],
           model["static_xrefs"],
           model["param_init"],
           model["init_val"],
           model["end_val"]) = parse_json(json)

    # Calculate derivatives
    (staticg1, staticg2, dynamicg1) = compose_derivatives(model)

    # Return JSON and Julia representation of modfile
    (json, model, staticg1, staticg2, dynamicg1)
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

function get_param_inits!(d::OrderedDict{Symbol,Number}, a::Array{Any,1})
    for st in a
        if st["statementName"] == "param_init"
            d[Symbol(st["name"])] = parse(st["value"])::Number
        end
    end
end

function get_numerical_initialization!(d::OrderedDict{Symbol,Number}, a::Array{Any,1}, field::String)
    for st in a
        if st["statementName"] == field
            for v in st["vals"]
                d[Symbol(v["name"])] = parse(v["value"])::Number
            end
        end
    end
end

function get_xrefs!(xrefs::Dict{Any, Any}, json::Array{Any, 1})
    for i in json
        if i["shift"] == 0
            xrefs[(i["name"], i["shift"])] = (convert(Array{Int}, i["equations"]),
                                              SymEngine.symbols(i["name"]))
        elseif i["shift"] == -1
            xrefs[(i["name"], i["shift"])] = (convert(Array{Int}, i["equations"]),
                                              SymEngine.symbols(string("___", i["name"], "m1___")))
        else
            xrefs[(i["name"], i["shift"])] = (convert(Array{Int}, i["equations"]),
                                              SymEngine.symbols(string("___", i["name"], "1___")))
        end
    end
end

function parse_json(json_model::Dict{String,Any})
    # Model variables, parameters
    parameters, endogenous, exogenous, exogenous_deterministic =
        (Array{DynareModel.Param, 1}(length(json_model["parameters"])),
         Array{DynareModel.Endo, 1}(length(json_model["endogenous"])),
         Array{DynareModel.Exo, 1}(length(json_model["exogenous"])),
         Array{DynareModel.ExoDet, 1}(length(json_model["exogenous_deterministic"])))

    get_vars!(parameters, json_model["parameters"])
    get_vars!(endogenous, json_model["endogenous"])
    get_vars!(exogenous, json_model["exogenous"])
    get_vars!(exogenous_deterministic, json_model["exogenous_deterministic"])

    #
    # Model Equations
    #

    #
    # Equations in Expr form: equations_dynamic, equations_static
    equations_dynamic = Array{Expr,1}()
    for e in json_model["model"]
        push!(equations_dynamic, parse_eq(e))
    end
    equations_static = Array{Expr,1}(length(equations_dynamic))
    idx = 1
    for e in equations_dynamic
        equations_static[idx] = tostatic([endogenous; exogenous; exogenous_deterministic], e)
        idx += 1
    end

    #
    # Equation Cross References
    dynamic_endog_xrefs, dynamic_exog_xrefs = Dict(), Dict()
    get_xrefs!(dynamic_endog_xrefs, json_model["xrefs"]["endogenous"])
    get_xrefs!(dynamic_exog_xrefs, json_model["xrefs"]["exogenous"])

    static_xrefs = Dict{Any, Array{Int}}()
    for i in dynamic_endog_xrefs
        if haskey(static_xrefs, i[1][1])
            static_xrefs[i[1][1]] = union(static_xrefs[i[1][1]], i[2][1])
        else
            static_xrefs[i[1][1]] = i[2][1]
        end
    end

    #
    # Equations in SymEngine form: dynamic, static
    nonDynareSymEngineKeywordPresent = false
    if nonDynareSymEngineKeyWordAtom in endogenous
        nonDynareSymEngineKeywordPresent = true
        dynamic_endog_xrefs[(nonDynareSymEngineKeyWordString, 0)] = (dynamic_endog_xrefs[(nonDynareSymEngineKeyWordString, 0)][1],
                                                                     nonDynareSymEngineKeyWordSymEngineSymbolSub)
    elseif nonDynareSymEngineKeyWordAtom in exogenous || nonDynareSymEngineKeyWordAtom in exogenous_deterministic
        nonDynareSymEngineKeywordPresent = true
        dynamic_exog_xrefs[(nonDynareSymEngineKeyWordString, 0)] = (dynamic_exog_xrefs[(nonDynareSymEngineKeyWordString, 0)][1],
                                                                    nonDynareSymEngineKeyWordSymEngineSymbolSub)
    elseif nonDynareSymEngineKeyWordAtom in parameters
        nonDynareSymEngineKeywordPresent = true
    end

    idx = 1
    static = Array{SymEngine.Basic, 1}(length(equations_static))
    for e in equations_static
        if nonDynareSymEngineKeywordPresent
            e = replaceNonDynareSymEngineKeyword(e)
        end
        static[idx] = SymEngine.Basic(e)
        idx += 1
    end

    idx = 1
    dynamic = Array{SymEngine.Basic, 1}(length(equations_dynamic))
    for e in equations_dynamic
        if nonDynareSymEngineKeywordPresent
            e = replaceNonDynareSymEngineKeyword(e)
        end
        dynamic[idx] = SymEngine.Basic(e)
        idx += 1
    end

    # Substitute symbols for lead and lagged variables
    # Can drop this part once SymEngine has implemented derivatives of functions.
    # See https://github.com/symengine/SymEngine.jl/issues/53
    subLeadLagsInEqutaions!(dynamic, merge(dynamic_endog_xrefs, dynamic_exog_xrefs))

    #
    # Statements
    #
    # Param Init
    param_init = OrderedDict{Symbol,Number}()
    get_param_inits!(param_init, json_model["statements"])

    # Init Val
    init_val = OrderedDict{Symbol,Number}()
    get_numerical_initialization!(init_val, json_model["statements"], "init_val")

    # End Val
    end_val = OrderedDict{Symbol,Number}()
    get_numerical_initialization!(end_val, json_model["statements"], "end_val")

    # Return
    (parameters, endogenous, exogenous, exogenous_deterministic,
     equations_dynamic, equations_static,
     dynamic, static,
     dynamic_endog_xrefs, dynamic_exog_xrefs, static_xrefs,
     param_init, init_val, end_val)
end

function subLeadLagsInEqutaions!(subeqs::Array{SymEngine.Basic, 1},
                                 dict_lead_lag::Dict{Any, Any})
    for de in dict_lead_lag
        if (de[1][2] != 0)
            for i in de[2][1]
                subeqs[i] = SymEngine.subs(subeqs[i],
                                           SymEngine.Basic(string(de[1][1], "(", de[1][2], ")")),
                                           de[2][2])
            end
        end
    end
end

replaceNonDynareSymEngineKeyword(expr::Number) = expr
replaceNonDynareSymEngineKeyword(expr::Symbol) = expr == nonDynareSymEngineKeyWordSymbol ? nonDynareSymEngineKeyWordSymbolSub : expr
function replaceNonDynareSymEngineKeyword(expr::Expr)
    ex = copy(expr)
    for (i, arg) in enumerate(expr.args)
        ex.args[i] = replaceNonDynareSymEngineKeyword(arg)
    end
    return ex
end

tostatic(vars, expr::Number) = expr
tostatic(vars, expr::Symbol) = expr
function tostatic(vars, expr::Expr)
    ex = copy(expr)
    for (i, arg) in enumerate(expr.args)
        if typeof(ex.args[i]) == Expr &&
            length(ex.args[i].args) == 2
            if typeof(ex.args[i].args[1]) == Symbol &&
                typeof(ex.args[i].args[2]) == Int &&
                any(ex.args[i].args[1] .== vars)
                ex.args[i] = ex.args[i].args[1]
            else
                ex.args[i] = tostatic(vars, arg)
            end
        else
            ex.args[i] = tostatic(vars, arg)
        end
    end
    return ex
end

function get_static_symbol(dynamic_endog_xrefs, name::String)
    haskey(dynamic_endog_xrefs, (name, 0)) ? dynamic_endog_xrefs[(name, 0)][2] : SymEngine.symbols(name)
end

function compose_derivatives(model)
    nendog = length(model["endogenous"])
    ndynvars = length(model["dynamic_endog_xrefs"]) + length(model["dynamic_exog_xrefs"])

    # Static Jacobian
    I, J, V = Array{Int,1}(), Array{Int,1}(), Array{SymEngine.Basic,1}()
    for i = 1:nendog
        for eq in model["static_xrefs"][model["endogenous"][i].name]
            deriv = SymEngine.diff(model["static"][eq],
                                   get_static_symbol(model["dynamic_endog_xrefs"], model["endogenous"][i].name))
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
            deriv = SymEngine.diff(staticg1[eq, i],
                                   get_static_symbol(model["dynamic_endog_xrefs"], model["endogenous"][i].name))
            if deriv != 0
                I = [I; eq]
                J = [J; (i-1)*nendog+i]
                V = [V; deriv]
            end
            for j = i+1:nendog
                # Off-diagonal
                if any(eq .== model["static_xrefs"][model["endogenous"][j].name])
                    deriv = SymEngine.diff(staticg1[eq, i],
                                           get_static_symbol(model["dynamic_endog_xrefs"], model["endogenous"][j].name))
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
    for ae in [ filter((k,v)->k[2] == i, model["dynamic_endog_xrefs"]) for i = -1:1 ]
        for i in 1:nendog
            for tup in filter((k,v)-> k[1] == model["endogenous"][i], ae)
                for eq in tup[2][1]
                    deriv = SymEngine.diff(model["dynamic"][eq], tup[2][2])
                    if deriv != 0
                        I = [I; eq]
                        J = [J; col]
                        V = [V; deriv]
                    end
                end
                col += 1
            end
        end
    end

    for ae in [ filter((k,v)->k[2] == i, model["dynamic_exog_xrefs"]) for i = -1:1 ]
        for i in 1:length(model["dynamic_exog_xrefs"])
            for tup in filter((k,v)-> k[1] == model["exogenous"][i], ae)
                for eq in tup[2][1]
                    deriv = SymEngine.diff(model["dynamic"][eq], tup[2][2])
                    if deriv != 0
                        I = [I; eq]
                        J = [J; col]
                        V = [V; deriv]
                    end
                end
                col += 1
            end
        end
    end
    dynamicg1 = sparse(I, J, V, nendog, ndynvars)

    (staticg1, staticg2, dynamicg1)
end
