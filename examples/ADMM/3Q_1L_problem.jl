include("methods.jl")
include("models.jl")

function quad_obstacles()
    r_cylinder = 0.5
    _cyl = []
    h = 3.75 - 0*1.8  # x-loc [-1.8,2.0]
    w = 1. + 10*0  # doorway width [0.1, inf)
    off = 0*0.6    # y-offset [0, 0.6]
    push!(_cyl,(h,  w+off, r_cylinder))
    push!(_cyl,(h, -w+off, r_cylinder))
    push!(_cyl,(h,  w+off+2r_cylinder, 2r_cylinder))
    push!(_cyl,(h, -w+off-2r_cylinder, 2r_cylinder))
    # push!(_cyl,(h,  1+off+4r_cylinder, 3r_cylinder))
    x_door = [h, off, 0]
    return _cyl, x_door
end

function get_quad_locations(x_load::Vector, d::Real, α=π/4, num_lift=3)
    h = d*cos(α)
    r = d*sin(α)
    z = x_load[3] + h
    circle(θ) = [x_load[1] + r*cos(θ), x_load[2] + r*sin(θ)]
    θ = range(0,2π,length=num_lift+1)
    x_lift = [zeros(3) for i = 1:num_lift]
    for i = 1:num_lift
        x_lift[i][1:2] = circle(θ[i])
        x_lift[i][3] = z
    end
    return x_lift
end

function build_quad_problem(agent, x0_load=zeros(3), xf_load=[7.5,0,0], d=1.2, quat::Bool=false)
    num_lift = 3

    # Discretization
    N = 101
    dt = 0.1

    if quat
        quad_model = let quad = quadrotor_lift
            d = copy(quad.info)
            d[:quat] = 4:7
            Model(quad.f, quad.∇f, quad.n, quad.m, quad.params, d)
        end
    else
        quad_model = quadrotor_lift
    end
    n_lift = quad_model.n
    m_lift = quad_model.m

    n_load = doubleintegrator3D_load.n
    m_load = doubleintegrator3D_load.m


    #~~~~~~~~~~~~~~~~~~ INITIAL CONDITIONS ~~~~~~~~~~~~~~~~~~~~~~~~~~#
    # shift_ = zeros(n_lift)
    # shift_[1:3] = [0.0;0.0;0.25]
    # scaling = 1.

    # Specify task by load locations
    # x0_load = [0, -1, 0.5]
    # move = [7.5, 0., 1.8]
    # shift = [-1.5, 1.5, -1]
    # xf_load = x0_load + move + shift
    # d = 1.2           # length of string / rod
    α = deg2rad(45)   # angle between string and vertical for each quad


    # Calculate initial position
    x0_lift = get_quad_locations(x0_load, d)
    xlift0 = [zeros(n_lift) for i = 1:num_lift]

    # Send quads to default configuration at first
    xf_lift = get_quad_locations(xf_load, d)
    xliftf = [zeros(n_lift) for i = 1:num_lift]

    # Copy positions into state vectors
    for i = 1:num_lift
        xlift0[i][1:3] = x0_lift[i]
        xliftf[i][1:3] = xf_lift[i]

        # Set quaternion
        xlift0[i][4] = 1
        xliftf[i][4] = 1
    end

    xload0 = zeros(n_load)
    xloadf = zeros(n_load)
    xload0[1:3] = x0_load
    xloadf[1:3] = xf_load


    #~~~~~~~~~~~~~~~~~~ CONSTRAINTS ~~~~~~~~~~~~~~~~~~~~~~~~~~#
    # Robot sizes
    r_lift = 0.275
    r_load = 0.2

    # Workspace
    ceiling = 3.0
    flr = 0.0
    hall = 3.0

    # Control limits for lift robots
    u_lim_l = -Inf*ones(m_lift)
    u_lim_u =  Inf*ones(m_lift)
    u_lim_l[1:4] .= 0.
    u_lim_u[1:4] .= 12.0/4.0

    x_min_lift= -Inf*ones(n_lift)
    x_min_lift[2] = -hall
    x_min_lift[3] = flr + r_lift
    x_max_lift = Inf*ones(n_lift)
    x_max_lift[2] = hall
    x_max_lift[3] = ceiling - r_lift

    # Load
    x_lim_l_load = -Inf*ones(n_load)
    x_lim_l_load[3] = 0.

    # Load table
    table_len = 0.1  # last fraction of trajectory to enforce the table height on the load (e.g. 0.25 enforces it for the last fourth of knot points)
    table_k::Int = N - floor(N*table_len)  # Start enforcing table at this knot point
    table_height = xf_load[3] - r_load

    x_min_load_table = -Inf*ones(n_load)
    x_min_load_table[3] = table_height + r_load

    bnd1 = BoundConstraint(n_lift,m_lift,u_min=u_lim_l,u_max=u_lim_u)
    bnd2 = BoundConstraint(n_lift,m_lift,u_min=u_lim_l,u_max=u_lim_u, x_min=x_min_lift, x_max=x_max_lift)
    bnd_load = BoundConstraint(n_load,m_load, x_min=x_lim_l_load)
    bnd_table = BoundConstraint(n_load,m_load, x_min=x_min_load_table)

    # Obstacles
    _cyl, x_door = quad_obstacles()

    function cI_cylinder_lift(c,x,u)
        for i = 1:length(_cyl)
            c[i] = circle_constraint(x[1:3],_cyl[i][1],_cyl[i][2],_cyl[i][3] + 1.25*r_lift)
        end
    end
    obs_lift = Constraint{Inequality}(cI_cylinder_lift,n_lift,m_lift,length(_cyl),:obs_lift)

    function cI_cylinder_load(c,x,u)
        for i = 1:length(_cyl)
            c[i] = circle_constraint(x[1:3],_cyl[i][1],_cyl[i][2],_cyl[i][3] + 1.25*r_load)
        end
    end
    obs_load = Constraint{Inequality}(cI_cylinder_load,n_load,m_load,length(_cyl),:obs_load)



    #~~~~~~~~~~~~~~~~~~ INITIAL CONDITIONS ~~~~~~~~~~~~~~~~~~~~~~~~~~#
    shift_ = zeros(n_lift)
    shift_[1:3] = [0.0;0.0;0.25]
    scaling = 1.
    x10 = zeros(n_lift)
    x10[4] = 1.
    x10[1:3] = scaling*[sqrt(8/9);0.;4/3]
    x10 += shift_
    x20 = zeros(n_lift)
    x20[4] = 1.
    x20[1:3] = scaling*[-sqrt(2/9);sqrt(2/3);4/3]
    x20 += shift_
    x30 = zeros(n_lift)
    x30[4] = 1.
    x30[1:3] = scaling*[-sqrt(2/9);-sqrt(2/3);4/3]
    x30 += shift_
    xload0 = zeros(n_load)
    xload0[3] = 3/6
    xload0[1:3] += shift_[1:3]

    xlift0 = [x10,x20,x30]

    _shift = zeros(n_lift)
    _shift[1:3] = [7.5;0.0;0.0]

    # goal state
    xloadf = zeros(n_load)
    xloadf[1:3] = xload0[1:3] + _shift[1:3]
    x1f = copy(x10) + _shift
    x2f = copy(x20) + _shift
    x3f = copy(x30) + _shift

    xliftf = [x1f,x2f,x3f]

    _shift_ = zeros(n_lift)
    _shift_[1] = 3.75

    ℓ1 = norm(x30[1:3]-x10[1:3])
    # norm(x10[1:3]-x20[1:3])
    # norm(x20[1:3]-x30[1:3])

    ℓ2 = norm(xload0[1:3]-x10[1:3])
    norm(xload0[1:3]-x20[1:3])
    # norm(xload0[1:3]-x30[1:3])


    x1m = copy(x10)
    x1m += _shift_
    x3m = copy(x1m)
    x3m[1] -= ℓ1
    x2m = copy(x1m)
    x2m[1] = 3.75
    x2m[3] = xload0[3] + ℓ2

    xliftmid = [x1m,x2m,x3m]

    #~~~~~~~~~~~~~~~~~~~~~~~~~~~ BUILD PROBLEMS ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
    # Discretization
    N = 101
    Nmid = Int(floor(N/2))
    dt = 0.1

    # Objectives
    q_diag = ones(n_lift)
    # q_diag[3] = 1e-3   # don't weight height very much
    # q_diag[2] = 1

    q_diag1 = copy(q_diag)
    q_diag2 = copy(q_diag)
    q_diag3 = copy(q_diag)
    # q_diag1[1] = 1.0
    # q_diag2[1] = 1.5e-2
    # q_diag3[1] = 1.0e-3
    q_diag1[1] = 1.0e-3
    q_diag2[1] = 1.0e-3
    q_diag3[1] = 1.0e-3
    # q_diag1[3] = 1.0e-3
    # q_diag2[3] = 1.0e-3
    # q_diag3[3] = 1.0e-3


    # q_diag[2] = 1
    # q_diag[2:end] .*= 1e-3  # encourage only x in the final state

    r_diag = ones(m_lift)
    r_diag[1:4] .= 1.0e-6
    r_diag[5:7] .= 1.0e-6
    Q_lift = [1.0e-2*Diagonal(q_diag1), 1.0e-2*Diagonal(q_diag2), 1.0e-2*Diagonal(q_diag3)]
    Qf_lift = [1.0*Diagonal(q_diag), 1.0*Diagonal(q_diag), 1.0*Diagonal(q_diag)]
    R_lift = Diagonal(r_diag)
    Q_load = 0.0*Diagonal(I,n_load)
    Qf_load = 0.0*Diagonal(I,n_load)
    R_load = 1.0e-6*Diagonal(I,m_load)
    # Q_load[3,3] = 1e-4

    q_mid = zeros(n_lift)
    q_mid[1:3] .= 100.0

    Q_mid = Diagonal(q_mid)
    cost_mid = [LQRCost(Q_mid,R_lift,xliftmid[i]) for i = 1:num_lift]

    obj_lift = [LQRObjective(Q_lift[i],R_lift,Qf_lift[i],xliftf[i],N) for i = 1:num_lift]
    # update mid cost function
    for i = 1:num_lift
        obj_lift[i].cost[Nmid] = cost_mid[i]
    end
    obj_load = LQRObjective(Q_load,R_load,Qf_load,xloadf,N)


    # Modify cost at middle of the trajectory
    x_mid = [copy(xlift0[1]) for i = 1:num_lift]
    x_mid[1][1:3] = x_door + [ d, 0, 0]
    x_mid[2][1:3] = x_door + [ 0, 0, d]
    x_mid[3][1:3] = x_door + [-d, 0, 0]
    cost_mid = [LQRCost(Q_lift[i]*10, R_lift, x_mid[i]) for i = 1:num_lift]

    Nmid = N÷2
    for i = 1:num_lift
        obj_lift[i].cost[Nmid] = cost_mid[i]
    end


    # obj_lift[1][Nmid].q[1] = -1
    # obj_kikklift[2][Nmid].q[3] = -1
    # obj_lift[3][Nmid].q[1] =  1

    # Constraints
    constraints_lift = []
    for i = 1:num_lift
        con = Constraints(N)
        con[1] += bnd1
        for k = 2:N-1
            con[k] += bnd2 + obs_lift
        end
        # con[N] += goal_constraint(xliftf[i])
        push!(constraints_lift,copy(con))
    end

    constraints_load = Constraints(N)
    for k = 2:N-1
        constraints_load[k] += obs_load
    end
    for k = 2:N-1
        if k < table_k
            constraints_load[k] += bnd_load
        else
            constraints_load[k] += bnd_table
        end
    end
    constraints_load[N] += goal_constraint(xloadf)

    # Initial controls
    u_load = [0.;0.;-9.81*0.35/num_lift]

    u_lift = zeros(m_lift)
    u_lift[1:4] .= 9.81*(quad_params.m)/4.
    u_lift[5:7] = u_load
    U0_lift = [u_lift for k = 1:N-1]
    U0_load = [-1.0*[u_load;u_load;u_load] for k = 1:N-1]

    # Create problems
    if agent ∈ 1:num_lift
        i = agent
        prob= Problem(quad_model,
                        obj_lift[i],
                        U0_lift,
                        integration=:midpoint,
                        constraints=constraints_lift[i],
                        x0=xlift0[i],
                        xf=xliftf[i],
                        N=N,
                        dt=dt)

    elseif agent ∈ [0, :load]
        prob= Problem(doubleintegrator3D_load,
                        obj_load,
                        U0_load,
                        integration=:midpoint,
                        constraints=constraints_load,
                        x0=xload0,
                        xf=xloadf,
                        N=N,
                        dt=dt)
    end
    return prob
end

# function build_lift_problem(x0, xf, Q, r_lift, _cyl, num_lift)
#     # Discretization
#     N = 101
#     dt = 0.1
#
#     ### Model
#     n_lift = quadrotor_lift.n
#     m_lift = quadrotor_lift.m
#
#     ### Constraints
#     u_lim_l = -Inf*ones(m_lift)
#     u_lim_u = Inf*ones(m_lift)
#     u_lim_l[1:4] .= 0.
#     u_lim_u[1:4] .= 9.81*(quad_params.m + 1.)/4.0
#     bnd = BoundConstraint(n_lift,m_lift,u_min=u_lim_l,u_max=u_lim_u)
#
#     function cI_cylinder_lift(c,x,u)
#         for i = 1:length(_cyl)
#             c[i] = circle_constraint(x[1:3],_cyl[i][1],_cyl[i][2],_cyl[i][3] + 2*r_lift)
#         end
#     end
#     obs_lift = Constraint{Inequality}(cI_cylinder_lift,n_lift,m_lift,length(_cyl),:obs_lift)
#
#     con = Constraints(N)
#     for k = 1:N-1
#         con[k] += obs_lift + bnd
#     end
#     con[N] += goal_constraint(xf)
#
#     ### Objective
#     Qf = Diagonal(1000.0I,n_lift)
#     r_diag = ones(m_lift)
#     r_diag[1:4] .= 10.0e-3
#     r_diag[5:7] .= 1.0e-6
#     R_lift = Diagonal(r_diag)
#
#     obj_lift = LQRObjective(Q, R_lift, Qf, xf, N)
#
#     u_lift = zeros(m_lift)
#     u_lift[1:4] .= 9.81*(quad_params.m + 1.)/12.
#     u_lift[5:7] = u_load
#     U0_lift = [u_lift for k = 1:N-1]
#
#     prob_lift = Problem(quadrotor_lift,
#                 obj_lift,
#                 U0_lift,
#                 integration=:midpoint,
#                 constraints=con,
#                 x0=x0,
#                 xf=xf,
#                 N=N,
#                 dt=dt)
# end

# function build_load_problem(x0, xf, r_load, _cyl, num_lift)
#     # Discretization
#     N = 101
#     dt = 0.1
#
#     n_load = doubleintegrator3D_load.n
#     m_load = doubleintegrator3D_load.m
#
#     # Constraints
#     x_lim_l_load = -Inf*ones(n_load)
#     x_lim_l_load[3] = 0.
#
#     bnd = BoundConstraint(n_load,m_load,x_min=x_lim_l_load)
#
#     function cI_cylinder_load(c,x,u)
#         for i = 1:length(_cyl)
#             c[i] = circle_constraint(x[1:3],_cyl[i][1],_cyl[i][2],_cyl[i][3] + 1.25*r_load)
#         end
#     end
#     obs_load = Constraint{Inequality}(cI_cylinder_load,n_load,m_load,length(_cyl),:obs_load)
#
#     constraints_load = Constraints(N)
#     for k = 2:N-1
#         constraints_load[k] += obs_load + bnd
#     end
#     constraints_load[N] += goal_constraint(xf)
#
#     # Objective
#     Q_load = 0.0*Diagonal(I,n_load)
#     Qf_load = 0.0*Diagonal(I,n_load)
#     R_load = 1.0e-6*Diagonal(I,m_load)
#     obj_load = LQRObjective(Q_load,R_load,Qf_load,xf,N)
#
#     # Initial controls
#     u_load = [0.;0.;-9.81*0.35/num_lift]
#     U0_load = [-1.0*[u_load;u_load;u_load] for k = 1:N-1]
#
#     prob_load = Problem(doubleintegrator3D_load,
#                 obj_load,
#                 U0_load,
#                 integration=:midpoint,
#                 constraints=constraints_load,
#                 x0=x0,
#                 xf=xf,
#                 N=N,
#                 dt=dt)
# end