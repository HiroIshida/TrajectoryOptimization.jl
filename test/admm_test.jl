using PartedArrays
n1,m1 = 4,3
n2,m2 = 4,1

Q1 = Diagonal(1.0I,n1)
R1 = Diagonal(1.0I,m1)
Qf1 = Diagonal(0.0I,n1)
Q2 = Diagonal(1.0I,n2)
R2 = Diagonal(1.0I,m2)
Qf2 = Diagonal(10.0I,n2)

cost1 = QuadraticCost(Q1,R1,zeros(m1,n1),zeros(n1),zeros(m1),0,Qf1,zeros(n1),0)
cost2 = QuadraticCost(Q2,R2,zeros(m2,n2),zeros(n2),zeros(m2),0,Qf2,zeros(n2),0)
bodies = (:a1,:m)
costs = NamedTuple{bodies}((cost1,cost2))
costs.a1

part_x = create_partition((n1,n2),bodies)
part_u = create_partition((m1,m2),bodies)
y0 = [0.;0.;1.;0.]
v0 = zeros(m1)
z0 = [0.;0.;0.;0.]
w0 = zeros(m2)
x0 = [y0;z0]
d = 1
x = BlockArray(x0,part_x)
u = BlockArray(zeros(m1+m2),part_u)
ϕ(x::BlockArray) = norm(x.a1[1:2] - x.m[1:2]) - d^2
ϕ(x::Vector) = norm(x[part_x.a1][1:2] - x[part_x.m][1:2])^2 - d^2
function ∇ϕ(grad,x)
    y = x.a1[1:2]
    z = x.m[1:2]
    grad[1:2] = 2(y-z)
    grad[5:6] = -2(y-z)
    grad
end
∇ϕ(x) = begin grad = zeros(8); ∇ϕ(grad,x); grad end
function ∇ϕ(grad,x,b::Symbol)
    y = x.a1[1:2]
    z = x.m[1:2]
    if b == :a1
        grad[1:2] = 2(y-z)
    elseif b == :m
        grad[1:2] = -2(y-z)
    end
end
∇ϕ(x,b::Symbol) = begin grad = zeros(4); ∇ϕ(grad,x,b); grad end
ϕ(x)
ϕ(x0)
∇ϕ(x,:m)
ForwardDiff.gradient(ϕ,x0)
typeof(acost) <: CostFunction

acost = ADMMCost(costs,ϕ,∇ϕ,2,[:a1],n1+n2,m1+m2,part_x,part_u)
stage_cost(acost,x,u)
stage_cost(cost1,y0,v0)
stage_cost(cost2,z0,w0)

taylor_expansion(acost,x,u,:m)
z0 == x.m
w0 == u.m

taylor_expansion(acost.costs.m,x.m,u.m)

ns = (n1,n2)
ms = (m1,m2)
p = 1
N = 11
res = ADMMResults(bodies,ns,ms,p,N,0);

# X  = [BlockArray(zeros(sum(ns)),part_x)   for i = 1:N];
# U  = [BlockArray(zeros(sum(ms)),part_u)   for i = 1:N-1];
#
# K  = NamedTuple{bodies}([[zeros(m,n) for i = 1:N-1] for (n,m) in zip(ns,ms)])
# d  =  NamedTuple{bodies}([[zeros(m)   for i = 1:N-1] for m in ms])
#
# testres(X,U,K,d);

## Test joint solve
model = Dynamics.model_admm
tf = 1.0
y0 = [0.;1.]
ẏ0 = [0.;0.]
z0 = [0.;0.]
ż0 = [0.;0.]
x0 = [y0;ẏ0;z0;ż0]

yf = [10.;1.]
ẏf = ẏ0
zf = [10.;0.]
żf = ż0
xf = [yf;ẏf;zf;żf]

Q1 = Diagonal(1.0I,n1)
R1 = Diagonal(1.0I,m1)
Qf1 = Diagonal(0.0I,n1)
Q2 = Diagonal(1.0I,n2)
R2 = Diagonal(1.0I,m2)
Qf2 = Diagonal(10.0I,n2)

cost1 = LQRCost(Q1,R1,Qf1,[yf;ẏf])#QuadraticCost(Q1,R1,zeros(m1,n1),zeros(n1),zeros(m1),0,Qf1,zeros(n1),0)
cost2 = LQRCost(Q2,R2,Qf2,[zf;żf])#QuadraticCost(Q2,R2,zeros(m2,n2),zeros(n2),zeros(m2),0,Qf2,zeros(n2),0)#LQRCost(Q2,R2,Qf2,[zf;żf])
costs = NamedTuple{bodies}((cost1,cost2))
acost = ADMMCost(costs,ϕ,∇ϕ,2,[:a1],n1+n2,m1+m2,part_x,part_u)

# Q = Diagonal(0.0001I,model.n)
# R = Diagonal(0.0001I,model.m)
# Qf = Diagonal(100.0I,model.n)

function cE(c,x::AbstractArray,u::AbstractArray)
    c[1] = norm(x[1:2] - x[5:6])^2 - d^2
    c[2] = u[3] - u[4]
end
function cE(c,x::AbstractArray)
    c[1] = norm(x[1:2] - x[5:6])^2 - d^2
end

obj = UnconstrainedObjective(acost,tf,x0,xf)
obj = ConstrainedObjective(obj,cE=ϕ,use_xf_equality_constraint=false)
solver = Solver(model,obj,integration=:none,dt=0.1)
solver.opts.verbose = true
results, stats = solve(solver,rand(model.m,solver.N-1))

res = ADMMResults(bodies,ns,ms,1,N,1);

U0 = ones(model.m,solver.N-1)
for i = 1:solver.N-1
    res.U[i] .= U0[:,i]
end
update_constraints!(res,solver,res.X_,res.U_)
rollout_admm!(res,solver,1.0)
# _backwardpass_admm!(res,solver,:a1)
_solve_admm(solver,U0,res)
# solver.c_jacobian(rand(2,model.n),rand(2,model.m),rand(model.n),rand(model.m),:a1)

acost.∇c
a = 1

function rollout_admm!(res::ADMMResults,solver::Solver,alpha::Float64)
    n,m,N = get_sizes(solver)
    m̄,mm = get_num_controls(solver)
    n̄,nn = get_num_states(solver)

    dt = solver.dt

    X = res.X; U = res.U;
    X_ = res.X_; U_ = res.U_

    K = [Array([res.K[:a1][k] zeros(3,4); zeros(1,4) res.K[:m][k]]) for k = 1:solver.N-1]
    d = [[res.d[:a1][k];res.d[:m][k]] for k = 1:solver.N-1]

    X_[1] .= solver.obj.x0;

    for k = 2:N
        # Calculate state trajectory difference
        δx = X_[k-1] - X[k-1]

        # Calculate updated control
        U_[k-1] .= U[k-1] + K[k-1]*δx + alpha*d[k-1]

        # Propagate dynamics
        solver.fd(X_[k], X_[k-1], U_[k-1], dt)

        # Check that rollout has not diverged
        if ~(norm(X_[k],Inf) < solver.opts.max_state_value && norm(U_[k-1],Inf) < solver.opts.max_control_value)
            return false
        end
    end

    # Update constraints
    update_constraints!(res,solver,X_,U_)

    return true
end

function _solve_admm(solver, U0::Array{Float64,2}, results::ADMMResults)::Tuple{SolverResults,Dict}
    # Reset the solver (evals and state)
    reset(solver)

    # Start timer
    t_start = time_ns()


    if solver.obj isa ConstrainedObjective
        solver.state.constrained = true
    else
        solver.state.constrained = false
        iterations_outerloop_original = solver.opts.iterations_outerloop
        solver.opts.iterations_outerloop = 1
    end

    #****************************#
    #       INITIALIZATION       #
    #****************************#
    n,m,N = get_sizes(solver)

    p,pI,pE = get_num_constraints(solver)
    p_N, = get_num_terminal_constraints(solver)

    # Unpack results for convenience
    X = results.X # state trajectory
    U = results.U # control trajectory
    X_ = results.X_ # updated state trajectory
    U_ = results.U_ # updated control trajectory

    # Set up logger
    logger = default_logger(solver)

    #****************************#
    #           SOLVER           #
    #****************************#
    ## Initial rollout
    for k = 1:solver.N-1
        U[k] .= U0[:,k]
    end

    X[1] .= solver.obj.x0
    flag = rollout!(results,solver) # rollout new state trajectoy
    !flag ? error("Bad initial control sequence") : nothing

    if solver.state.constrained
        update_constraints!(results, solver)
        # Update constraints Jacobians; if fixed (ie, no custom constraints) set solver state to not update
        update_jacobians!(results,solver)
    end

    # Solver Statistics
    iter = 0 # counter for total number of iLQR iterations
    iter_outer = 1
    iter_inner = 1
    iter_max_mu = Inf
    time_setup = time_ns() - t_start
    J_hist = Vector{Float64}()
    grad_norm_hist = Vector{Float64}()
    c_max_hist = Vector{Float64}()
    c_max_increase = 0
    Δc_max = Inf
    c_l2_norm_hist = Vector{Float64}()
    cn_Quu_hist = Vector{Float64}()
    cn_S_hist = Vector{Float64}()
    outer_updates = Int[]
    t_solve_start = time_ns()

    #****************************#
    #         OUTER LOOP         #
    #****************************#

    dJ = Inf
    gradient = Inf
    Δv = [Inf, Inf]
    #
    # with_logger(logger) do
    # for j = 1:solver.opts.iterations_outerloop
    #     iter_outer = j
    #     @info "Outer loop $j (begin)"
    #
    #     if solver.state.constrained && j == 1
    #         copyto!(results.C_prev,results.C)
    #     end
    #     c_max = 0.  # Init max constraint violation to increase scope
    #     dJ_zero_counter = 0  # Count how many time the forward pass is unsuccessful
    #
    #     J_prev = cost(solver, results, X, U)
    #     j == 1 ? push!(J_hist, J_prev) : nothing  # store the first cost
    #
    #     #****************************#
    #     #         INNER LOOP         #
    #     #****************************#
    #
    #     for ii = 1:solver.opts.iterations_innerloop
    #         iter_inner = ii
    #
    #         ### BACKWARD PASS ###
    #         update_jacobians!(results, solver)
    #         Δv = backwardpass!(results, solver)
    #
    #         ### FORWARDS PASS ###
    #         J = forwardpass!(results, solver, Δv, J_prev)
    #         push!(J_hist,J)
    #
    #         # gradient
    #         gradient = update_gradient(results,solver)
    #         push!(grad_norm_hist,gradient)
    #
    #         # condition numbers
    #         cn_Quu = backwardpass_max_condition_number(results.bp)
    #         cn_S = backwardpass_max_condition_number(results)
    #         push!(cn_Quu_hist,cn_Quu)
    #         push!(cn_S_hist,cn_S)
    #
    #         # increment iLQR inner loop counter
    #         iter += 1
    #
    #         if solver.opts.live_plotting
    #             display(plot(to_array(results.U)'))
    #             # p = plot()
    #             # plot_trajectory!(results.U)
    #             # display(p)
    #         end
    #
    #         ### UPDATE RESULTS ###
    #         copyto!(X,X_)
    #         copyto!(U,U_)
    #
    #         dJ = copy(abs(J-J_prev)) # change in cost
    #         J_prev = copy(J)
    #         dJ == 0 ? dJ_zero_counter += 1 : dJ_zero_counter = 0
    #
    #         if solver.state.constrained
    #             c_max = max_violation(results)
    #             c_ℓ2_norm = constraint_ℓ2_norm(results)
    #             iter > 1 ? Δc_max = c_max_hist[end] - c_max : nothing
    #             push!(c_max_hist, c_max)
    #             push!(c_l2_norm_hist, c_ℓ2_norm)
    #
    #             p > 0 ? m1 = maximum(maximum.(results.μ[1:N-1])) : m1 = 0
    #             p_N > 0 ? m2 = maximum(results.μ[N]) : m2 = 0
    #             μ_max = max(m1,m2)
    #             # μ_max = 1
    #
    #             @logmsg InnerLoop :c_max value=c_max
    #
    #             if μ_max == solver.opts.penalty_max && iter_max_mu > iter
    #                 iter_max_mu = iter
    #             end
    #
    #             @logmsg InnerLoop :maxmu value=μ_max
    #             musat = sum(count.(map(x->x.>=solver.opts.penalty_max,results.μ))) / sum(length.(results.μ))
    #             @logmsg InnerLoop :musat value=musat
    #
    #         end
    #
    #
    #         @logmsg InnerLoop :iter value=iter
    #         @logmsg InnerLoop :cost value=J
    #         @logmsg InnerLoop :dJ value=dJ loc=3
    #         @logmsg InnerLoop :grad value=gradient
    #         @logmsg InnerLoop :j value=j
    #         @logmsg InnerLoop :zero_count value=dJ_zero_counter
    #         @logmsg InnerLoop :Δc value=Δc_max
    #         @logmsg InnerLoop :cn value=cn_S
    #
    #
    #         ii % 10 == 1 ? print_header(logger,InnerLoop) : nothing
    #         print_row(logger,InnerLoop)
    #
    #         evaluate_convergence(solver,:inner,dJ,c_max,gradient,iter,j,dJ_zero_counter) ? break : nothing
    #         if J > solver.opts.max_cost_value
    #             @warn "Cost exceded maximum allowable cost - solve terminated"
    #
    #             stats = Dict("iterations"=>iter,
    #                 "outer loop iterations"=>iter_outer,
    #                 "runtime"=>float(time_ns() - t_solve_start)/1e9,
    #                 "setup_time"=>float(time_setup)/1e9,
    #                 "cost"=>J_hist,
    #                 "c_max"=>c_max_hist,
    #                 "c_l2_norm"=>c_l2_norm_hist,
    #                 "gradient norm"=>grad_norm_hist,
    #                 "outer loop iteration index"=>outer_updates,
    #                 "S condition number"=>cn_S_hist,
    #                 "Quu condition number"=>cn_Quu_hist,)
    #
    #             return results, stats
    #         end
    #     end
    #     ### END INNER LOOP ###
    #
    #
    #     #****************************#
    #     #      OUTER LOOP UPDATE     #
    #     #****************************#
    #
    #     # update multiplier and penalty terms
    #     outer_loop_update(results,solver,j)
    #     update_constraints!(results, solver)
    #     J_prev = cost(solver, results, results.X, results.U)
    #
    #     #****************************#
    #     #    TERMINATION CRITERIA    #
    #     #****************************#
    #     # Check if maximum constraint violation satisfies termination criteria AND cost or gradient tolerance convergence
    #     converged = evaluate_convergence(solver,:outer,dJ,c_max,gradient,iter,0,dJ_zero_counter)
    #
    #
    #     # Logger output
    #     @logmsg OuterLoop :outeriter value=j
    #     @logmsg OuterLoop :iter value=iter
    #     @logmsg OuterLoop :iterations value=iter_inner
    #     print_header(logger,OuterLoop)
    #     print_row(logger,OuterLoop)
    #
    #     push!(outer_updates,iter)
    #
    #     if converged; break end
    # end
    # end
    # ### END OUTER LOOP ###
    #
    # solver.state.constrained ? nothing : solver.opts.iterations_outerloop = iterations_outerloop_original
    #
    # # Run Stats
    # stats = Dict("iterations"=>iter,
    #     "outer loop iterations"=>iter_outer,
    #     "runtime"=>float(time_ns() - t_solve_start)/1e9,
    #     "setup_time"=>float(time_setup)/1e9,
    #     "cost"=>J_hist,
    #     "c_max"=>c_max_hist,
    #     "c_l2_norm"=>c_l2_norm_hist,
    #     "gradient norm"=>grad_norm_hist,
    #     "outer loop iteration index"=>outer_updates,
    #     "S condition number"=>cn_S_hist,
    #     "Quu condition number"=>cn_Quu_hist,
    #     "max_mu_iteration"=>iter_max_mu)
    #
    # if ((iter_outer == solver.opts.iterations_outerloop) && (iter_inner == solver.opts.iterations)) && solver.opts.verbose
    #     @warn "*Solve reached max iterations*"
    # end

    @info "*Solve Complete*"
    return results, stats
end