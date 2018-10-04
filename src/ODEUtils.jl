mutable struct ODyn <: DEDataVector{Float64}
    x
    c
end

function initial(::Type{objTypes}) where objTypes<:Tuple
    sizes = mapreduce(dims, (a,b)->(values(a).+values(b)), objTypes.parameters)
    return ODyn(zeros(Float64,sizes[1]), zeros(Float64,sizes[2]))
end


function gradient!(du::AbstractVector, uc, objs, t)
    mvs = collect(map(idx->MView(du, uc.x, uc.c, objs, idx), eachindex(objs)))
    
    for (i,(mv,obj)) ∈ enumerate(zip(mvs,objs))
        # calculate inputs
        rules  = getfield(obj,:_inputs)
        inputs = Vector{Pair{Symbol, Union{Float64,Vector{<:Number}}}}(undef, length(rules))
        for (j,(n1,(idx, n2))) ∈ enumerate(rules)
            prop = getproperty(mvs[idx], n2)
            inputs[j] = (n1 => length(prop)==1 ? prop[] : copy(prop))
        end
        # inputs = map((n1,(idx,n2))->(n=>getproperty(mvs[idx], n2)), rules)
        gradient!(mv, t; inputs...)
    end
end
