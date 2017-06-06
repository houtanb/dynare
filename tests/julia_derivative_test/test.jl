push!(LOAD_PATH, "/Users/houtanb/Documents/DYNARE/julia/dynare/julia")

using DataStructures

abstract Atom

immutable Endo <: Atom
    name::Symbol
    tex_name::String
    long_name::String
end

function create_type_array(d::Array{Endo,1}, a::Array{Tuple{String,String,String},1})
    for i in a
        push!(d, Endo(Symbol(i[1]::String), i[2]::String, i[3]::String))
    end
end

function create_dict_array(d::OrderedDict{Symbol,Any}, a::Array{Tuple{String,String,String},1})
    for i in a
        d[Symbol(i[1])] = (i[2]::String, i[3]::String)
    end
end

a = [
     ("a", "aa", "aaa")
     ("b", "bb", "bbb")
     ("c", "cc", "ccc")
     ("d", "dd", "ddd")
     ("e", "ee", "eee")
     ("f", "ff", "fff")
     ("g", "gg", "ggg")
     ("h", "hh", "hhh")
     ("i", "ii", "iii")
     ]

b = Array{Endo,1}()
create_type_array(b, a)
b = Array{Endo,1}()
@time create_type_array(b, a)

d = OrderedDict{Symbol,Any}()
create_dict_array(d, a)
d = OrderedDict{Symbol,Any}()
@time create_dict_array(d, a)
b, d
