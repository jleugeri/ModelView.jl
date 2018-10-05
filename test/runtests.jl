# include("../src/ModelView.jl")
using ModelView, Plots, Test, StaticArrays, OrdinaryDiffEq


@model struct Test1
    @dynamics begin
        a
        b::Float64
        c::SVector{4,Float64}
    end
    
    @observable begin
        d
        e::Float64
        f::SVector{1,Float64}
    end
    
    α
    β
    γ
end

@model struct Test2
    @dynamics begin
        x
        y
    end
    @observable output
end


function ModelView.gradient!(m::MView{Test1}, t; x=0)
    @. m.∇a = m.α*(x-m.a)
    @. m.d  = m.a-1
end

function ModelView.gradient!(m::MView{Test2}, t)
    @. m.∇y =  m.x
    @. m.∇x = -m.y
    @. m.output = m.x
end

# Properties for Test1 are, in order: a_initial,b_initial,c_initial,α,β,γ
# Properties for Test2 are, in order: x_initial,y_initial
objs = (Test1(1,0,[1,2,3,4],1,2,3; inputs=[:x=>(2, :output)]),Test2(0,1))
u₀ = initial(objs)

tspan = (0.0, 10.0)

@testset "Construction" begin
    @test Test1 <: ModelView.Model{(:a,:b,:c),Tuple{Float64,Float64,SVector{4,Float64}},(:d,:e,:f),Tuple{Float64,Float64,SVector{1,Float64}}}
    @test (length(dynamics(Test1)),length(observable(Test1))) == (3,3)
    @test (length(dynamics(Test2)),length(observable(Test2))) == (2,1)
    @test dims(Test1) == (dynamics=6,observable=3)
    @test dims(Test2) == (dynamics=2,observable=1)
    @test (length(u₀),length(u₀.c)) == (8,4)
    @test objs[1]._inputs == [:x=>(2, :output)]
    @test u₀[1] == 1.0
    @test u₀[7] == 0.0
    @test u₀[8] == 1.0
end

prob = ODEProblem(gradient!, u₀, tspan, objs)
sol = solve(prob, Tsit5())

@testset "Simulation" begin
    @test sol.retcode == :Success
    @test sol[end].c[1] ≈ exp(-tspan[2])-1 - 0.5*(sin(tspan[2]) - cos(tspan[2]) - sinh(tspan[2]) + cosh(tspan[2])) atol=0.1
end

p=plot(sol)
plot!(t->sol(t).c[1], tspan...)
plot!(t->exp(-t)-1 - 0.5*(sin(t) - cos(t) - sinh(t) + cosh(t)), tspan..., color=:black)
savefig(p, "test.png")
