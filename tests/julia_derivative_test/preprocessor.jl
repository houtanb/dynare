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
    model = Dict{String, Any}()
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
     model["dynamic_endog_reverse_lookup"],
     model["dynamic_exog_reverse_lookup"],
     model["lead_lag_incidence"],
     model["lead_lag_incidence_ref"],
     model["lead_lag_incidence_exo"],
     model["lead_lag_incidence_exo_ref"],
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
           model["dynamic_endog_reverse_lookup"],
           model["dynamic_exog_reverse_lookup"],
           model["lead_lag_incidence"],
           model["lead_lag_incidence_ref"],
           model["lead_lag_incidence_exo"],
           model["lead_lag_incidence_exo_ref"],
           model["param_init"],
           model["init_val"],
           model["end_val"]) = parse_json(json)

    # Calculate derivatives
    #    (staticg1ref, staticg2ref, dynamicg1ref) = compose_derivatives(model)
    (StaticG1, StaticG2, DynamicG1) = compose_derivatives(model)

    # Return JSON and Julia representation of modfile
    #    (json, model, StaticG1, staticg1ref, StaticG2, staticg2ref, DynamicG1, dynamicg1ref)
    (json, model, StaticG1, StaticG2, DynamicG1)
end

function run_preprocessor(modfile::String)
    dynare_m = "/Users/houtanb/Documents/DYNARE/julia/dynare/preprocessor/dynare_m"
    run(`$dynare_m $modfile.mod json=transform onlyjson`)

    json = open("$modfile.json")
    jsonout = JSON.parse(readstring(json))
    close(json)
    return jsonout
end

function get_vars!(d::Array{T,1}, json::Array{Any,1}) where {T <: DynareModel.Atom}
    idx = 1
    for i in json
        d[idx] = T(i["name"]::String, i["texName"]::String, i["longName"]::String)
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

function get_xrefs!(xrefs::Dict{Tuple{String,Int}, Tuple{Array{Int,1},SymEngine.Basic}}, json::Array{Any, 1})
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

function create_reverse_lookup_dict!(reverse_lookup::Dict{SymEngine.Basic, String}, xrefs::Dict{Tuple{String,Int}, Tuple{Array{Int,1},SymEngine.Basic}})
    for i in xrefs
        reverse_lookup[i[2][2]] = i[1][2] == 0 ? i[1][1] : string(i[1][1], "(", i[1][2], ")")
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
    idx = 1
    equations_dynamic = Array{Expr, 1}(length(json_model["model"]))
    for e in json_model["model"]
        equations_dynamic[idx] = parse_eq(e)
        idx += 1
    end
    equations_static = Array{Expr,1}(length(equations_dynamic))
    idx = 1
    for e in equations_dynamic
        equations_static[idx] = tostatic([endogenous; exogenous; exogenous_deterministic], e)
        idx += 1
    end

    #
    # Equation Cross References
    dynamic_endog_xrefs, dynamic_exog_xrefs =
        Dict{Tuple{String,Int}, Tuple{Array{Int,1},SymEngine.Basic}}(), Dict{Tuple{String,Int}, Tuple{Array{Int,1},SymEngine.Basic}}()
    get_xrefs!(dynamic_endog_xrefs, json_model["xrefs"]["endogenous"])
    get_xrefs!(dynamic_exog_xrefs, json_model["xrefs"]["exogenous"])

    static_xrefs = Dict{String, Array{Int}}()
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

    dynamic_endog_reverse_lookup, dynamic_exog_reverse_lookup = Dict{SymEngine.Basic, String}(), Dict{SymEngine.Basic, String}()
    create_reverse_lookup_dict!(dynamic_endog_reverse_lookup, dynamic_endog_xrefs)
    create_reverse_lookup_dict!(dynamic_exog_reverse_lookup, dynamic_exog_xrefs)

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

    # Lead Lag Incidence
    lead_lag_incidence_ref, lead_lag_incidence_exo_ref = Dict{String, Int}(), Dict{String, Int}()
    lead_lag_incidence, lead_lag_incidence_exo = zeros(Int64, 3, length(endogenous)), zeros(Int64, 3, length(exogenous))
    create_lead_lag_incidence!(lead_lag_incidence, lead_lag_incidence_ref, endogenous, dynamic_endog_xrefs)
    create_lead_lag_incidence!(lead_lag_incidence_exo, lead_lag_incidence_exo_ref, exogenous, dynamic_exog_xrefs)

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
     dynamic_endog_reverse_lookup, dynamic_exog_reverse_lookup,
     lead_lag_incidence, lead_lag_incidence_ref,
     lead_lag_incidence_exo, lead_lag_incidence_exo_ref,
     param_init, init_val, end_val)
end

function create_lead_lag_incidence!(lli::Array{Int64,2}, lliref::Dict{String, Int}, vars::Array{T,1}, var_xrefs::Dict{Tuple{String,Int}, Tuple{Array{Int,1},SymEngine.Basic}}) where {T <: DynareModel.Atom}
    idx = 1
    for lag in -1:1
        for i = 1:length(vars)
            if haskey(var_xrefs, (vars[i].name, lag))
                lliref[SymEngine.toString(var_xrefs[(vars[i].name, lag)][2])] = idx
                lli[2+lag, i] = idx
                idx += 1
            end
        end
    end
end

function subLeadLagsInEqutaions!(subeqs::Array{SymEngine.Basic, 1},
                                 dict_lead_lag::Dict{Tuple{String,Int}, Tuple{Array{Int,1},SymEngine.Basic}})
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

function replace_all_symengine_symbols(expr, endos::Dict{String, Int}, exos::Dict{String, Int}, params::Dict{String, Int})
    for (k, v) in endos
        expr = replace_symengine_symbols(expr, k, :(endo[$v]))
    end

    for (k, v) in exos
        expr = replace_symengine_symbols(expr, k, :(exo[$v]))
    end

    for (k, v) in params
        expr = replace_symengine_symbols(expr, k, :(param[$v]))
    end
    expr
end

function create_var_map!(varmap::Dict{String,Int}, vars::Array{T, 1}) where {T <: DynareModel.Atom}
    idx = 1
    for i in vars
        varmap[i.name] = idx
        idx += 1
    end
end

function compose_derivatives(model)
    nendog = length(model["endogenous"])
    ndynvars = length(model["dynamic_endog_xrefs"]) + length(model["dynamic_exog_xrefs"])

    endos, exos, params = Dict{String, Int}(), Dict{String, Int}(), Dict{String, Int}()
    create_var_map!(endos, model["endogenous"])
    create_var_map!(exos, model["exogenous"])
    create_var_map!(params, model["parameters"])

    # Static Jacobian
    staticg1ref = Dict{Tuple{Int64, String}, SymEngine.Basic}()
    I, J, V = Array{Int,1}(), Array{Int,1}(), String("[")
    for i = 1:nendog
        for eq in model["static_xrefs"][model["endogenous"][i].name]
            sederiv = SymEngine.diff(model["static"][eq],
                                   get_static_symbol(model["dynamic_endog_xrefs"], model["endogenous"][i].name))
            if sederiv != 0
                staticg1ref[(eq, model["endogenous"][i].name)] = sederiv
                I = [I; eq]
                J = [J; i]
                V *= (V == "[" ? "" : ";") * string(replace_all_symengine_symbols(sederiv, endos, exos, params))
            end
        end
    end
    V = parse(V * "]")
    StaticG1 = @eval (endo, exo, param) -> sparse($I, $J, $V, $nendog, $nendog)

    # Static Hessian
    staticg2ref = Dict{Tuple{Int64, String, String}, SymEngine.Basic}()
    I, J, V = Array{Int,1}(), Array{Int,1}(), String("[")
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
                    V *= (V == "[" ? "" : ";") * string(replace_all_symengine_symbols(sederiv, endos, exos, params))
                end
                for j = i+1:nendog
                    if any(eq .== model["static_xrefs"][model["endogenous"][j].name])
                        sederiv = SymEngine.diff(staticg1ref[eq, model["endogenous"][i].name],
                                                 get_static_symbol(model["dynamic_endog_xrefs"], model["endogenous"][j].name))
                        if sederiv != 0
                            staticg2ref[(eq, model["endogenous"][i].name, model["endogenous"][j].name)] = sederiv
                            staticg2ref[(eq, model["endogenous"][j].name, model["endogenous"][i].name)] = sederiv
                            deriv = string(replace_all_symengine_symbols(sederiv, endos, exos, params))
                            I = [I; eq; eq]
                            J = [J; (i-1)*nendog+j; (j-1)*nendog+i]
                            V *= (V == "[" ? "" : ";") * deriv * ";" * deriv
                        end
                    end
                end
            end
        end
    end
    V = parse(V * "]")
    StaticG2 = @eval (endo, exo, param) -> sparse($I, $J, $V, $nendog, $nendog^2)

    # Dynamic Jacobian
    col = 1
    dynamicg1ref = Dict{Tuple{Int64, String}, SymEngine.Basic}()
    I, J, V = Array{Int,1}(), Array{Int,1}(), String("[")
    endos = model["lead_lag_incidence_ref"]
    exos = model["lead_lag_incidence_exo_ref"]
    for ae in [ filter((k,v)->k[2] == i, model["dynamic_endog_xrefs"]) for i = -1:1 ]
        for i in 1:nendog
            for tup in filter((k,v)-> k[1] == model["endogenous"][i], ae)
                for eq in tup[2][1]
                    sederiv = SymEngine.diff(model["dynamic"][eq], tup[2][2])
                    if sederiv != 0
                        dynamicg1ref[(eq, model["dynamic_endog_reverse_lookup"][tup[2][2]])] = sederiv
                        I = [I; eq]
                        J = [J; col]
                        V *= (V == "[" ? "" : ";") * string(replace_all_symengine_symbols(sederiv, endos, exos, params))
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
                    sederiv = SymEngine.diff(model["dynamic"][eq], tup[2][2])
                    if sederiv != 0
                        dynamicg1ref[(eq, model["dynamic_exog_reverse_lookup"][tup[2][2]])] = sederiv
                        I = [I; eq]
                        J = [J; col]
                        V *= (V == "[" ? "" : ";") * string(replace_all_symengine_symbols(sederiv, endos, exos, params))
                    end
                end
                col += 1
            end
        end
    end
    V = parse(V * "]")
    DynamicG1 = @eval (endo, exo, param) -> sparse($I, $J, $V, $nendog, $ndynvars)

    (StaticG1, StaticG2, DynamicG1)
end
