import JSON
import SymEngine
using NumericFuns

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

type StaticG1 <: Functor{3} end
type StaticG2 <: Functor{3} end

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
    #    (staticg1, staticg1ref, staticg2, dynamicg1) = compose_derivatives(model)
    (staticg1ref, staticg2ref, staticg11, staticg22) = compose_derivatives(model)
    #(I,J,V,nendog) = compose_derivatives(model)

    # Return JSON and Julia representation of modfile
    (json, model, StaticG1, staticg1ref, StaticG2, staticg2ref, staticg11, staticg22)
    #(json, model, StaticG1, StaticG2, I,J,V,nendog)
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

replace_symengine_symbols!(expr::Any, symb, value) = expr
replace_symengine_symbols!(expr::Symbol, symb, value) = symb == string(expr) ? value : expr
function replace_symengine_symbols!(expr::Expr, symb, value)
    for i = 1:length(expr.args)
        expr.args[i] = replace_symengine_symbols!(expr.args[i], symb, value)
    end
    expr
end
replace_symengine_symbols(expr::Number, symb, value) = expr
replace_symengine_symbols(expr::Symbol, symb, value) = replace_symengine_symbols!(expr, symb, value)
replace_symengine_symbols(expr::Expr, symb, value) = replace_symengine_symbols!(copy(expr), symb, value)
replace_symengine_symbols(expr::SymEngine.Basic, symb, value) = replace_symengine_symbols!(parse(SymEngine.toString(expr)), symb, value)

function replace_all_symengine_symbols(expr, endos, exos, params)
    i = 1
    for endo in endos
        expr = replace_symengine_symbols(expr, endo, :(endo[$i]))
        i = i + 1
    end
    i = 1
    for exo in exos
        expr = replace_symengine_symbols(expr, exo, :(exo[$i]))
        i = i + 1
    end
    i = 1
    for param in params
        expr = replace_symengine_symbols(expr, param, :(param[$i]))
        i = i + 1
    end
    expr
end

function compose_derivatives(model)
    nendog = length(model["endogenous"])
    ndynvars = length(model["dynamic_endog_xrefs"]) + length(model["dynamic_exog_xrefs"])

    endos = [v.name for v in model["endogenous"]]
    exos = [v.name for v in model["exogenous"]]
    params = [v.name for v in model["parameters"]]

    # Static Jacobian
    staticg1ref = Dict{Tuple{Int64, String}, SymEngine.Basic}()
    I, J, V = Array{Int,1}(), Array{Int,1}(), Array{SymEngine.Basic,1}()
    for i = 1:nendog
        for eq in model["static_xrefs"][model["endogenous"][i].name]
            sederiv = SymEngine.diff(model["static"][eq],
                                   get_static_symbol(model["dynamic_endog_xrefs"], model["endogenous"][i].name))
            if sederiv != 0
                staticg1ref[(eq, model["endogenous"][i].name)] = sederiv
                I = [I; eq]
                J = [J; i]
                V = [V; replace_all_symengine_symbols(sederiv, endos, exos, params)]
            end
        end
    end
    staticg11 = sparse(I, J, V, nendog, nendog)
    NumericFuns.evaluate(::StaticG1, endo::Array{Float64,1}, exo::Array{Float64,1}, param::Array{Float64,1}) = sparse(:($I), :($J), [eval(d) for d in :($V)], :($nendog), :($nendog))
    #    return (I, J, V, nendog)

    # Static Hessian
    staticg2ref = Dict{Tuple{Int64, String, String}, SymEngine.Basic}()
    I, J, V = Array{Int,1}(), Array{Int,1}(), Array{SymEngine.Basic,1}()
    eqs = unique([ k[1] for k in keys(staticg1ref) ])
    for i = 1:nendog
        for eq in eqs
            if haskey(staticg1ref, (eq, model["endogenous"][i].name))
                # Diagonal
                sederiv = SymEngine.diff(staticg1ref[eq, model["endogenous"][i].name],
                                         get_static_symbol(model["dynamic_endog_xrefs"], model["endogenous"][i].name))
                if sederiv != 0
                    staticg2ref[(eq, model["endogenous"][i].name, model["endogenous"][i].name)] = sederiv
                    I = [I; eq]
                    J = [J; (i-1)*nendog+i]
                    V = [V; replace_all_symengine_symbols(sederiv, endos, exos, params)]
                end
                for j = i+1:nendog
                    if any(eq .== model["static_xrefs"][model["endogenous"][j].name])
                        sederiv = SymEngine.diff(staticg1ref[eq, model["endogenous"][i].name],
                                                 get_static_symbol(model["dynamic_endog_xrefs"], model["endogenous"][j].name))
                        if sederiv != 0
                            staticg2ref[(eq, model["endogenous"][i].name, model["endogenous"][j].name)] = sederiv
                            staticg2ref[(eq, model["endogenous"][j].name, model["endogenous"][i].name)] = sederiv
                            deriv = replace_all_symengine_symbols(sederiv, endos, exos, params)
                            I = [I; eq; eq]
                            J = [J; (i-1)*nendog+j; (j-1)*nendog+i]
                            V = [V; deriv; deriv]
                        end
                    end
                end
            end
        end
    end
    staticg22 = sparse(I, J, V, nendog, nendog^2)

    NumericFuns.evaluate(::StaticG2, endo::Array{Float64,1}, exo::Array{Float64,1}, param::Array{Float64,1}) = sparse(:($I), :($J), [eval(d) for d in :($V)], :($nendog), :($nendog)^2)

    return staticg1ref, staticg2ref, staticg11, staticg22

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

    (staticg1, staticg1ref, staticg2, dynamicg1)
end
