import JSON

function process(modfile::String)
    (json, json_static, json_dynamic) = run_preprocessor(modfile)

    model = Dict{String, Any}()
    (model["parameters"],
     model["endogenous"],
     model["exogenous"],
     model["exogenous_deterministic"],
     model["equations_dynamic"],
     model["equations_static"],
     model["dynamic_endog_xrefs"],
     model["dynamic_exog_xrefs"],
     model["lead_lag_incidence"],
     model["lead_lag_incidence_exo"],
     model["param_init"],
     model["init_val"],
     model["end_val"]) = parse_json(json)

    endos, exos, params = Dict{String, Int}(), Dict{String, Int}(), Dict{String, Int}()
    create_var_map!(endos, model["endogenous"])
    create_var_map!(exos, model["exogenous"])
    create_var_map!(params, model["parameters"])

    (StaticG1!, StaticG2!) = parse_json_static(json_static, model, endos, exos, params)
    (DynamicG1!, DynamicG2!) = parse_json_dynamic(json_dynamic, model, params)

    (model, StaticG1!, StaticG2!, DynamicG1!, DynamicG2!)
end

function create_var_map!(varmap::Dict{String,Int}, vars::Array{T, 1}) where {T <: DynareModel.Atom}
    idx = 1
    for i in vars
        varmap[i.name] = idx
        idx += 1
    end
end

function run_preprocessor(modfile::String)
    dynare_m = "/Users/houtanb/Documents/DYNARE/julia/dynare/preprocessor/dynare_m"
    run(`$dynare_m $modfile.mod json=compute onlyjson compute_xrefs`)

    json = open("$modfile.json")
    jsonout = JSON.parse(readstring(json))
    close(json)

    json_static = open(string(modfile, "_static.json"))
    json_static_out = JSON.parse(readstring(json_static))
    close(json_static)

    json_dynamic = open(string(modfile, "_dynamic.json"))
    json_dynamic_out = JSON.parse(readstring(json_dynamic))
    close(json_dynamic)

    (jsonout, json_static_out, json_dynamic_out)
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

function get_xrefs!(xrefs::OrderedDict{Tuple{String,Int}, Tuple{Any, Int}}, json::Array{Any, 1})
    # Ordering is important for later replacement: t = -1, 1 vars must come before t = 0 vars
    p1idxs = find([i["shift"] == 1 for i in json])
    m1idxs = find([i["shift"] == -1 for i in json])
    zidxs = setdiff(1:length(json), [m1idxs; p1idxs])
    for i in [m1idxs; p1idxs; zidxs]
        if json[i]["shift"] == 0
            xrefs[(json[i]["name"], 0)] = (parse(json[i]["name"]), -1)
        else
            xrefs[(json[i]["name"], json[i]["shift"])] = (parse(string(json[i]["name"], "(", json[i]["shift"], ")")), -1)
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

    dynamic_endog_xrefs, dynamic_exog_xrefs =
        OrderedDict{Tuple{String,Int}, Tuple{Any, Int}}(), OrderedDict{Tuple{String,Int}, Tuple{Any, Int}}()
    get_xrefs!(dynamic_endog_xrefs, json_model["xrefs"]["endogenous"])
    get_xrefs!(dynamic_exog_xrefs, json_model["xrefs"]["exogenous"])

    lead_lag_incidence, lead_lag_incidence_exo =
        zeros(Int64, 3, length(endogenous)), zeros(Int64, 3, length(exogenous))
    create_lead_lag_incidence!(lead_lag_incidence, dynamic_endog_xrefs, endogenous)
    create_lead_lag_incidence!(lead_lag_incidence_exo, dynamic_exog_xrefs, exogenous)

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
     equations_dynamic, equations_static, dynamic_endog_xrefs, dynamic_exog_xrefs,
     lead_lag_incidence, lead_lag_incidence_exo,
     param_init, init_val, end_val)
end

function create_lead_lag_incidence!(lli::Array{Int64,2}, var_xrefs::OrderedDict{Tuple{String,Int}, Tuple{Any, Int}}, vars::Array{T,1}) where {T <: DynareModel.Atom}
    idx = 1
    for lag in -1:1
        for i = 1:length(vars)
            if haskey(var_xrefs, (vars[i].name, lag))
                var_xrefs[(vars[i].name, lag)] = (var_xrefs[(vars[i].name, lag)][1], idx)
                lli[lag + 2, i] = idx
                idx += 1
            end
        end
    end
end

function subLeadLagsInEqutaions!(subeqs::Array{Expr, 1},
                                 dict_lead_lag::Dict{Tuple{String,Int}, Tuple{Array{Int,1},Symbol}})
    for de in dict_lead_lag
        if de[1][2] != 0
            for i in de[2][1]
                subeqs[i] = SymEngine.subs(subeqs[i],
                                           SymEngine.Basic(string(de[1][1], "(", de[1][2], ")")),
                                           de[2][2])
            end
        end
    end
end

replace_symbols_leads_lags!(expr::Any, symb, value) = expr
replace_symbols_leads_lags!(expr::Symbol, symb, value) = symb == expr ? value : expr
function replace_symbols_leads_lags!(expr::Expr, symb, value)
    argidxs = 1:length(expr.args)
    idx = find(symb .== expr.args)
    if !isempty(idx)
        expr.args[idx] = value
        argidxs = setdiff(argidxs, idx)
    end
    for i in argidxs
        expr.args[i] = replace_symbols_leads_lags!(expr.args[i], symb, value)
    end
    expr
end

replace_all_symbols_leads_lags(expr::Number, endos::OrderedDict{Tuple{String, Int}, Tuple{Any,Int}}, exos::OrderedDict{Tuple{String, Int}, Tuple{Any,Int}}, params::Dict{String, Int}) = expr

function replace_all_symbols_leads_lags(expr, endos::OrderedDict{Tuple{String, Int}, Tuple{Any,Int}}, exos::OrderedDict{Tuple{String, Int}, Tuple{Any,Int}}, params::Dict{String, Int})
    for (k, v) in endos
        expr = replace_symbols_leads_lags!(expr, v[1], :(endos[$(v[2])]))
    end

    for (k, v) in exos
        expr = replace_symbols_leads_lags!(expr, v[1], :(exos[$(v[2])]))
    end

    for (k, v) in params
        expr = replace_symbols(expr, k, :(params[$v]))
    end
    expr
end


replace_symbols!(expr::Any, symb, value) = expr
replace_symbols!(expr::Symbol, symb, value) = symb == string(expr) ? value : expr
function replace_symbols!(expr::Expr, symb, value)
    for i = 1:length(expr.args)
        expr.args[i] = replace_symbols!(expr.args[i], symb, value)
    end
    expr
end
replace_symbols(expr::Number, symb, value) = expr
replace_symbols(expr::Symbol, symb, value) = replace_symbols!(expr, symb, value)
replace_symbols(expr::Expr, symb, value) = replace_symbols!(copy(expr), symb, value)

function replace_all_symbols(expr, endos::Dict{String, Int}, exos::Dict{String, Int}, params::Dict{String, Int})
    for (k, v) in endos
        expr = replace_symbols(expr, k, :(endos[$v]))
    end

    for (k, v) in exos
        expr = replace_symbols(expr, k, :(exos[$v]))
    end

    for (k, v) in params
        expr = replace_symbols(expr, k, :(params[$v]))
    end
    expr
end

function get_tempterms!(funcexpr, json::Array{Any,1}, endos::Dict{String, Int}, exos::Dict{String, Int}, params::Dict{String, Int})
    for i in json
        append!(funcexpr.args, [parse(string("@inbounds const ", i["temporary_term"],
                                             "=",
                                             replace_all_symbols(parse(i["value"]), endos, exos, params)))])
    end
end

function get_matrix_entries!(funcexpr, json::Array{Any,1}, matrix_name::String, endos::Dict{String, Int}, exos::Dict{String, Int}, params::Dict{String, Int})
    for i in json
        append!(funcexpr.args, [parse(string("@inbounds ", matrix_name, "[", i["eq"], ",", i["col"][1], "]=",
                                             replace_all_symbols(parse(i["val"]), endos, exos, params)))])
        if length(i["col"]) == 2
            append!(funcexpr.args, [parse(string("@inbounds ", matrix_name, "[", i["eq"], ",", i["col"][2], "]=",
                                                 matrix_name, "[", i["eq"], ",", i["col"][1], "]"))])
        elseif length(i["col"]) > 2
            error("Shouldn't arrive here")
        end
    end
end

function parse_json_static(json::Dict{String,Any}, model::Dict{String, Any}, endos::Dict{String, Int}, exos::Dict{String, Int}, params::Dict{String, Int})

    nendog = length(model["endogenous"])
    nexog = length(model["exogenous"])
    nparam = length(model["parameters"])

    funcexprtt = :(@assert length(endo) == $nendog; @assert length(exo) == $nexog; @assert length(param) == $nparam)
    get_tempterms!(funcexprtt, json["static_model"]["temporary_terms_"], endos, exos, params)
    get_tempterms!(funcexprtt, json["static_model"]["temporary_terms_jacobian"], endos, exos, params)

    funcexpr = :(@assert size(g1) == ($nendog, $nendog); fill!(g1, 0.0);)
    append!(funcexpr.args, funcexprtt.args)
    get_matrix_entries!(funcexpr, json["static_model"]["jacobian"]["entries"], "g1", endos, exos, params)
    StaticG1! = @eval (endo, exo, param, g1) -> ($funcexpr)

    funcexpr = :(@assert size(g2) == ($nendog, $(nendog^2)); fill!(g2, 0.0);)
    if (!isempty(json["static_model"]["hessian"]["entries"]))
        get_tempterms!(funcexprtt, json["static_model"]["temporary_terms_hessian"], endos, exos, params)
        append!(funcexpr.args, funcexprtt.args)
        get_matrix_entries!(funcexpr, json["static_model"]["hessian"]["entries"], "g2", endos, exos, params)
    end
    StaticG2! = @eval (endo, exo, param, g2) -> ($funcexpr)

    (StaticG1!, StaticG2!)
end

function get_tempterms!(funcexpr, json::Array{Any,1}, endos::OrderedDict{Tuple{String, Int}, Tuple{Any,Int}}, exos::OrderedDict{Tuple{String, Int}, Tuple{Any,Int}}, params::Dict{String, Int})
    for i in json
        append!(funcexpr.args, [parse(string("@inbounds const ", i["temporary_term"],
                                             "=",
                                             replace_all_symbols_leads_lags(parse(i["value"]), endos, exos, params)))])
    end
end

function get_matrix_entries!(funcexpr, json::Array{Any,1}, matrix_name::String, endos::OrderedDict{Tuple{String, Int}, Tuple{Any,Int}}, exos::OrderedDict{Tuple{String, Int}, Tuple{Any,Int}}, params::Dict{String, Int})
    for i in json
        append!(funcexpr.args, [parse(string("@inbounds ", matrix_name, "[", i["eq"], ",", i["col"][1], "]=",
                                             replace_all_symbols_leads_lags(parse(i["val"]), endos, exos, params)))])
        if length(i["col"]) == 2
            append!(funcexpr.args, [parse(string("@inbounds ", matrix_name, "[", i["eq"], ",", i["col"][2], "]=",
                                                 matrix_name, "[", i["eq"], ",", i["col"][1], "]"))])
        elseif length(i["col"]) > 2
            error("Shouldn't arrive here")
        end
    end
end

function parse_json_dynamic(json::Dict{String,Any}, model::Dict{String, Any}, params::Dict{String, Int})

    nendog = length(model["endogenous"])
    nexog = length(model["exogenous"])
    nparam = length(model["parameters"])
    ndynendog = length(model["dynamic_endog_xrefs"])
    ndynexog = length(model["dynamic_exog_xrefs"])
    ndynvars = ndynendog + ndynexog

    endos = model["dynamic_endog_xrefs"]
    exos = model["dynamic_exog_xrefs"]

    funcexprtt = :(@assert length(endo)+length(exo) == $ndynvars; @assert length(param) == $nparam)
    get_tempterms!(funcexprtt, json["dynamic_model"]["temporary_terms_"], endos, exos, params)
    get_tempterms!(funcexprtt, json["dynamic_model"]["temporary_terms_jacobian"], endos, exos, params)

    funcexpr = :(@assert size(g1) == ($nendog, $ndynvars); fill!(g1, 0.0);)
    append!(funcexpr.args, funcexprtt.args)
    get_matrix_entries!(funcexpr, json["dynamic_model"]["jacobian"]["entries"], "g1", endos, exos, params)
    DynamicG1! = @eval (endo, exo, param, g1) -> ($funcexpr)

    funcexpr = :(@assert size(g2) == ($nendog, $(ndynvars^2)); fill!(g2, 0.0);)
    if (!isempty(json["dynamic_model"]["hessian"]["entries"]))
        get_tempterms!(funcexprtt, json["dynamic_model"]["temporary_terms_hessian"], endos, exos, params)
        append!(funcexpr.args, funcexprtt.args)
        get_matrix_entries!(funcexpr, json["dynamic_model"]["hessian"]["entries"], "g2", endos, exos, params)
    end
    DynamicG2! = @eval (endo, exo, param, g2) -> ($funcexpr)
    println(funcexpr)

    (DynamicG1!, DynamicG2!)
end
