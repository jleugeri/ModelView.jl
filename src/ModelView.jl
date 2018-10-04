module ModelView
using StaticArrays, DiffEqBase
export @model, MView, getproperty, setproperty!, dims, dynamics, observable, initial, gradient!

include("./Model.jl")
include("./MView.jl")
include("./ODEUtils.jl")

end
