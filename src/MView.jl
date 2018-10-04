struct MView{ObjType,T1,T2,T3}
    _du::T1
    _u::T2
    _c::T3
    _obj::ObjType
end

Base.setproperty!(mv::MView, prop::Symbol, value) = setproperty!(getfield(mv,:_obj), prop, value)

@generated function Base.getproperty(mv::MView{ObjType}, prop::Symbol) where ObjType<:Model
    dynamics_infos = dynamics(ObjType)
    observable_infos = observable(ObjType)
    
    switchcase_observable = map(observable_infos) do (fname, ftype, fslice)
        quote
            if prop == $(Expr(:quote, fname))
                return view(getfield(mv, :_c), $fslice)
            end
        end
    end
    
    switchcase_dynamics = map(dynamics_infos) do (fname, ftype, fslice)
        quote
            if prop == $(Expr(:quote, fname))
                return view(getfield(mv, :_u), $fslice)
            end
            if prop == $(Expr(:quote, Symbol("∇"*String(fname))))
                return view(getfield(mv, :_du), $fslice)
            end
        end
    end
    
    switchcase_properties = map(fieldnames(ObjType)) do fname
        quote
            if prop == $(Expr(:quote, fname))
                return getfield(mv, :_obj).$fname
            end
        end
    end
    
    quote
        $(Expr(:meta, :inline))
        $(switchcase_observable...)
        $(switchcase_dynamics...)
        $(switchcase_properties...)
    end
end


@generated function MView(du, u, c, objs::Tuple, idx::Int)
    offset = (0, 0)
    ranges = Vector{Tuple{UnitRange{Int},UnitRange{Int}}}(undef, length(objs.parameters))
    
    for (i,objType) ∈ enumerate(objs.parameters)
        d = values(dims(objType))
        rd,ro = Base.OneTo.(d)
        ranges[i] = (rd.+offset[1],ro.+offset[2])
        offset = offset .+ d
    end
    
    quote
        ds,os = $(ranges)[idx]
        obj   = objs[idx]
        MView(view(du, ds), view(u, ds), view(c, os), obj)
    end
end
