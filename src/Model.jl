abstract type Model{DynamicsNames, DynamicsTypes, ObservableNames, ObservableTypes} end

num_fields(::Type{T}) where {T<:Number} = 1
num_fields(::Type{SVector{N,T}}) where {N,T<:Number} = N

macro model(def)
    @assert def.head == :struct "Must wrap struct definition."
    
    # determine the name by unwrapping the first (logic) line
    # parse block `@model struct <name> ... end`
    structname,parameters,parent = if isa(def.args[2], Symbol)
        def.args[2], nothing, nothing
    elseif def.args[2].head == :<:
        # parse block `@model struct <name> <: <type> ... end`
        if isa(def.args[2].args[1], Symbol)
            def.args[2].args[1], nothing, def.args[2].args[2] 
        # parse block `@model struct <name>{<types...>} <: <type> ... end`
        elseif def.args[2].args[1].head == :curly
            def.args[2].args[1].args[1], def.args[2].args[1].args[2], def.args[2].args[2]
        else
            error("Cannot parse struct name $(def.args[2]).")
        end
    # parse block `@model struct <name>{<types>} ... end`
    elseif def.args[2].head == :curly
        def.args[2].args[1], def.args[2].args[2], nothing
    else
        error("Cannot parse struct name $(def.args[2]).")
    end

    ignore = []
    if parameters != nothing
        push!(ignore,"parameters `$(parameters)`")
    end
    if parent != nothing
        push!(ignore,"subtyping from `$(parent)`.")
    end
    if !isempty(ignore)
        println("Warning: ignoring "*join(ignore,"and"))
    end

    # parse struct definition for dynamics
    # for each field, store name, and type
    dynamics_infos = Tuple{Symbol, Type}[]
    observable_infos = Tuple{Symbol, Type}[]

    keep_rows = []
    # parse all lines in the struct definition body
    for (i,row) ∈ enumerate(def.args[3].args)
        # parse block/line starting with @dynamics or @observable
        if isa(row, Expr) && row.head == :macrocall
            is_dynamics_macro = row.args[1] == Symbol("@dynamics")
            is_observable_macro = row.args[1] == Symbol("@observable")
            infos = if is_dynamics_macro
                dynamics_infos
            elseif is_observable_macro
                observable_infos
            else
                # keep all other macros untouched
                push!(keep_rows, row)
            end
            
            
            # parse block `@<observable/dynamics> begin ... end`
            if isa(row.args[3], Expr) && row.args[3].head == :block
                for obs_row ∈ row.args[3].args
                    # parse line @<observable/dynamics> <name>
                    if isa(obs_row, Symbol)
                        ftype = Float64
                        push!(infos, (obs_row, ftype))
                        # for each dynamic variable, keep an initial value
                        if is_dynamics_macro
                            push!(keep_rows, :($(Symbol(String(obs_row)*"_initial"))::$(ftype)))
                        end
                    # parse line @<observable/dynamics> <name>::<type>
                    elseif isa(obs_row, Expr)
                        ftype = eval(obs_row.args[2])
                        @assert ftype <: Union{Number, SVector{N, <:Number} where N} "Type error for field $(obs_row.args[1]): $(ftype) ∉ Union{Number, SVector{N, <:Number} where N}"
                        push!(infos, (obs_row.args[1], ftype))
                        # for each dynamic variable, keep an initial value
                        if is_dynamics_macro
                            push!(keep_rows, :($(Symbol(String(obs_row.args[1])*"_initial"))::$(ftype)))
                        end
                    end
                end
            # parse line @<observable/dynamics> <name>
            elseif isa(row.args[3], Symbol)
                ftype = Float64
                push!(infos, (row.args[3], Float64))
                # for each dynamic variable, keep an initial value
                if is_dynamics_macro
                    push!(keep_rows, :($(Symbol(String(row.args[3])*"_initial"))::$(ftype)))
                end
            # parse line @<observable/dynamics> <name>::<type>
            elseif isa(row.args[3], Expr)
                ftype = eval(row.args[3].args[2])
                @assert ftype <: Union{Number, SVector{N, <:Number} where N} "Type error for field $(row.args[3].args[1]): $(ftype) ∉ Union{Number, SVector{N, <:Number} where N}"
                push!(infos, (row.args[3].args[1], ftype))
                # for each dynamic variable, keep an initial value
                if is_dynamics_macro
                    push!(keep_rows, :($(Symbol(String(row.args[3].args[1])*"_initial"))::$(ftype)))
                end
            end
        else
            # keep all other rows untouched
            push!(keep_rows, row)
        end
    end
    
    # replace the type declaration
    dynNames,dynTypes = isempty(dynamics_infos) ? ((),()) : zip(dynamics_infos...)
    obsNames,obsTypes = isempty(observable_infos) ? ((),()) : zip(observable_infos...)    
    def.args[2] = :($(structname) <: $(Model){$(dynNames), $(Tuple{dynTypes...}), $(obsNames), $(Tuple{obsTypes...})})
    
    # add row for `_inputs` property
    push!(keep_rows, :(_inputs::Vector{Pair{Symbol, Tuple{Int, Symbol}}}))
    
    # replace rows in struct definition with the ones we need to keep
    def.args[3].args = keep_rows
    
    
    return esc(quote
        $(def)
        
        $(structname)(args...; inputs=Pair{Symbol,Tuple{Int,Symbol}}[]) = $(structname)(args..., inputs)
    end)
end

dims(::Type{<:Model{DynName,DynTypes,ObsNames,ObsTypes}}) where {DynName,DynTypes,ObsNames,ObsTypes} =
    (dynamics=isempty(DynTypes.parameters) ? 0 : mapreduce(num_fields, +, DynTypes.parameters), 
     observable=isempty(ObsTypes.parameters) ? 0 : mapreduce(num_fields, +, ObsTypes.parameters))

function dynamics(::Type{<:Model{DynNames,DynTypes,ObsNames,ObsTypes}}) where {DynNames,DynTypes,ObsNames,ObsTypes}
    dynamics = Vector{Tuple{Symbol, Type, UnitRange{Int}}}(undef, length(DynNames))
    offset = 0
    for (i,(name, ftype)) ∈ enumerate(zip(DynNames,DynTypes.parameters))
        nf = num_fields(ftype)
        dynamics[i] = (name, ftype, Base.OneTo(nf).+offset)
        offset += nf
    end
    return dynamics
end

function observable(::Type{<:Model{DynNames,DynTypes,ObsNames,ObsTypes}}) where {DynNames,DynTypes,ObsNames,ObsTypes}
    observable = Vector{Tuple{Symbol, Type, UnitRange{Int}}}(undef, length(ObsNames))
    offset = 0
    for (i,(name, ftype)) ∈ enumerate(zip(ObsNames,ObsTypes.parameters))
        nf = num_fields(ftype)
        observable[i] = (name, ftype, Base.OneTo(nf).+offset)
        offset += nf
    end
    return observable
end
