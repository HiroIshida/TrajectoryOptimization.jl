using LinearAlgebra, Random
using Test
using BenchmarkTools
using Plots

model, obj = Dynamics.quadrotor
N = 21
solver = Solver(model,obj,N=N)
n,m = get_sizes(solver)
U0 = 6*ones(m,N-1)
X0 = rollout(solver,U0)
J0 = cost(solver,X0,U0)
res,stats = solve(solver,U0)

obj_c = ConstrainedObjective(obj,u_min=0,u_max=4.5)
solver = Solver(model,obj_c,N=N)
res_con,stats_con = solve(solver,U0)

import TrajectoryOptimization: empty_state,num_stage_constraints,num_terminal_constraints, AugmentedLagrangianProblem, ALCost
import TrajectoryOptimization: bound_constraint, is_constrained, step!, update_constraints!, dual_update!, penalty_update!
import TrajectoryOptimization: OuterLoop, update_active_set!
costfun = obj.cost
model_d = Model{Discrete}(model,rk4)
U = to_dvecs(U0)
X = empty_state(n,N)
dt = solver.dt
x0 = obj.x0
prob = Problem(model_d,costfun,U,dt=dt,x0=x0)

opts = iLQRSolverOptions(iterations=50, gradient_norm_tolerance=1e-4, verbose=false)
ilqr = iLQRSolver(prob,opts)
res1 = solve(prob,ilqr)
# plot(res1.X)
rollout!(prob)
@test J0 == cost(prob)
# Constrained
bnd = bound_constraint(n,m,u_min=0,u_max=4.5,trim=true)
add_constraints!(prob,bnd)
@test is_constrained(prob)
res2 = solve(prob,ilqr)
# plot(res2.U)
@test cost(res1) == cost(res2)
Ures = to_array(res2.U)
p = num_stage_constraints(prob)

auglag = AugmentedLagrangianSolver(prob)
prob_al = AugmentedLagrangianProblem(prob,auglag)
cost_al = ALCost(prob,auglag)
cost_al.C[1]
auglag.μ[1][5] = 4.25
@test cost_al.μ[1][5] == 4.25

@test prob_al.cost.μ[1][5] == 4.25
@test !is_constrained(prob_al)
auglag.μ[1][5] = 1
rollout!(prob_al)
cost_al.C[1]
cost(cost_al,prob.X,prob.U,prob.dt) - J0
update_constraints!(prob_al.cost.C,prob_al.cost.constraints,prob_al.X,prob_al.U)
@test max_violation(auglag) == 1.5
@test max_violation(auglag) == max_violation(prob)

prob = Problem(model_d,costfun,U,dt=dt,x0=x0)
add_constraints!(prob,bnd)
opts_al = AugmentedLagrangianSolverOptions{Float64}(verbose=true,opts_uncon=opts)
auglag = AugmentedLagrangianSolver(prob,opts_al)
res3 = solve(prob,auglag)
solve!(prob,auglag)

@test max_violation(res3) == max_violation(auglag)

X0 = zeros(prob.model.n,prob.N)
X0[4,:] .= 1.0
X0[3,:] .= range(prob.x0[2],stop=obj.xf[2],length=N)
copyto!(prob.X,X0)
prob
pa,sa = solve!(prob,ALTROSolverOptions{Float64}())


# plot(res3.U)
# @btime solve($prob,$auglag)
# @btime solve($solver,$U0)
# plot(stats_con["c_max"],yscale=:log10)
# plot!(cumsum(auglag.stats[:iterations_inner]),auglag.stats[:c_max],seriestype=:step)

# # No infeasible or minimum time
# altro_cost = ALTROCost(prob,cost_al,NaN,NaN)
# opts = iLQRSolverOptions(iterations=50, gradient_norm_tolerance=1e-4, verbose=false)
# cost_expansion!(ilqr.Q,altro_cost,rand(prob.model.n),rand(prob.model.m), 1)
# auglag = AugmentedLagrangianSolver(prob)
# prob_al = AugmentedLagrangianProblem(prob,auglag)
# cost_al = ALCost(prob,auglag)
# cost_altro1 = ALTROCost(prob,cost_al,NaN,NaN)
# cost(cost_altro1,prob.X,prob.U,prob.dt)
#
# # Infeasible
# copyto!(prob.X,[rand(prob.model.n) for k = 1:prob.N])
# prob_inf = infeasible_problem(prob)
#
# ilqr_inf = iLQRSolver(prob_inf,opts)
#
# cost_expansion!(ilqr_inf.Q,prob_inf.cost,rand(prob_inf.model.n),rand(prob_inf.model.m), 1)
# cost(prob_inf.cost,prob_inf.X,prob_inf.U,prob_inf.dt)
#
# # Minimum time
# prob_min_time = minimum_time_problem(prob)
# ilqr_min_time = iLQRSolver(prob_min_time,opts)
# cost_expansion!(ilqr_min_time.Q,prob_min_time.cost,rand(prob_min_time.model.n),rand(prob_min_time.model.m), 1)
# cost(prob_min_time.cost,prob_min_time.X,prob_min_time.U,prob_min_time.dt)
#
# # Infeasible and Minimum Time
# prob_altro = minimum_time_problem(prob_inf)
# ilqr_altro = iLQRSolver(prob_altro,opts)
# cost_expansion!(ilqr_altro.Q,prob_altro.cost,rand(prob_altro.model.n),rand(prob_altro.model.m), 1)
# cost(prob_altro.cost,prob_altro.X,prob_altro.U,prob_altro.dt)
