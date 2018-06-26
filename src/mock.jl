struct BlockMatrix{T} <: AbstractMatrix{T}
    blocks::Vector{Matrix{T}}
end
Base.getindex(BM::BlockMatrix, i::Integer) = BM.blocks[i]
mutable struct MockSDOptimizer{T} <: AbstractSDOptimizer
    nconstrs::Int
    blkdims::Vector{Int}
    constraint_constants::Vector{T}
    objective_coefficients::Vector{Tuple{T, Int, Int, Int}}
    constraint_coefficients::Vector{Vector{Tuple{T, Int, Int, Int}}}
    optimize!::Function # Function used to set dummy primal/dual values and statuses
    hasprimal::Bool
    hasdual::Bool
    terminationstatus::MOI.TerminationStatusCode
    primalstatus::MOI.ResultStatusCode
    dualstatus::MOI.ResultStatusCode
    X::BlockMatrix{T}
    Z::BlockMatrix{T}
    y::Vector{T}
end
MockSDOptimizer{T}() where T = MockSDOptimizer{T}(0,
                                                  Int[],
                                                  T[],
                                                  Tuple{T, Int, Int, Int}[],
                                                  Vector{Tuple{T, Int, Int, Int}}[],
                                                  (::MockSDOptimizer) -> begin end,
                                                  false,
                                                  false,
                                                  MOI.Success,
                                                  MOI.UnknownResultStatus,
                                                  MOI.UnknownResultStatus,
                                                  BlockMatrix{T}(Matrix{T}[]),
                                                  BlockMatrix{T}(Matrix{T}[]),
                                                  T[])
mockSDoptimizer(T::Type) = SDOIOptimizer(MockSDOptimizer{T}(), T)
coefficienttype(::MockSDOptimizer{T}) where T = T

getnumberofconstraints(optimizer::MockSDOptimizer) = optimizer.nconstrs
getnumberofblocks(optimizer::MockSDOptimizer) = length(optimizer.blkdims)
getblockdimension(optimizer::MockSDOptimizer, blk) = optimizer.blkdims[blk]
function init!(optimizer::MockSDOptimizer{T}, blkdims::Vector{Int}, nconstrs::Integer) where T
    optimizer.nconstrs = nconstrs
    optimizer.blkdims = blkdims
    optimizer.constraint_constants = zeros(T, nconstrs)
    optimizer.objective_coefficients = Tuple{T, Int, Int, Int}[]
    optimizer.constraint_coefficients = map(i -> Tuple{T, Int, Int, Int}[], 1:nconstrs)
end

getconstraintconstant(optimizer::MockSDOptimizer, c) = optimizer.constraint_constants[c]
function setconstraintconstant!(optimizer::MockSDOptimizer, val, c::Integer)
    optimizer.constraint_constants[c] = val
end

getobjectivecoefficients(optimizer::MockSDOptimizer) = optimizer.objective_coefficients
function setobjectivecoefficient!(optimizer::MockSDOptimizer, val, blk::Integer, i::Integer, j::Integer)
    push!(optimizer.objective_coefficients, (val, blk, i, j))
end

getconstraintcoefficients(optimizer::MockSDOptimizer, c) = optimizer.constraint_coefficients[c]
function setconstraintcoefficient!(optimizer::MockSDOptimizer, val, c::Integer, blk::Integer, i::Integer, j::Integer)
    push!(optimizer.constraint_coefficients[c], (val, blk, i, j))
end

MOI.canget(mock::MockSDOptimizer, ::MOI.PrimalStatus) = mock.hasprimal
MOI.canget(mock::MockSDOptimizer, ::MOI.DualStatus) = mock.hasdual
MOI.canset(mock::MockSDOptimizer, ::Union{MOI.PrimalStatus,MOI.DualStatus}) = true
MOI.get(mock::MockSDOptimizer, ::MOI.TerminationStatus) = mock.terminationstatus
MOI.set!(mock::MockSDOptimizer, ::MOI.TerminationStatus, value::MOI.TerminationStatusCode) = (mock.terminationstatus = value)
MOI.get(mock::MockSDOptimizer, ::MOI.PrimalStatus) = mock.primalstatus
MOI.set!(mock::MockSDOptimizer, ::MOI.PrimalStatus, value::MOI.ResultStatusCode) = (mock.primalstatus = value)
MOI.get(mock::MockSDOptimizer, ::MOI.DualStatus) = mock.dualstatus
MOI.set!(mock::MockSDOptimizer, ::MOI.DualStatus, value::MOI.ResultStatusCode) = (mock.dualstatus = value)

getX(mock::MockSDOptimizer) = mock.X
getZ(mock::MockSDOptimizer) = mock.Z
gety(mock::MockSDOptimizer) = mock.y
function getprimalobjectivevalue(mock::MockSDOptimizer{T}) where T
    v = zero(T)
    for (α, blk, i, j) in mock.objective_coefficients
        v += α * mock.X[blk][i, j]
        if i != j
            v += α * mock.X[blk][j, i]
        end
    end
    v
end
function getdualobjectivevalue(mock::MockSDOptimizer{T}) where T
    v = zero(T)
    for c in 1:mock.nconstrs
        v += mock.constraint_constants[c] * mock.y[c]
    end
    v
end

function MOI.optimize!(mock::MockSDOptimizer)
    mock.hasprimal = true
    mock.hasdual = true
    mock.optimize!(mock)
end

function MOIU.set_mock_optimize!(mock::MockSDOptimizer, opts::Function...)
    mock.optimize! = MOIU.rec_mock_optimize(mock, opts...)
end
# TODO remove the following methods once it is defined for AbstractMockOptimizer in MOIU
function MOIU.rec_mock_optimize(mock::MockSDOptimizer, opt::Function, opts::Function...)
    # TODO replace mock.optimize! = ... by MOI.set!(..., MOIU.MockOptimizeFunction, ...)
    # where MOIU.MockOptimizeFunction is a MockModelAttribute
    (mock::MockSDOptimizer) -> (opt(mock); mock.optimize! = MOIU.rec_mock_optimize(mock, opts...))
end
MOIU.rec_mock_optimize(mock::MockSDOptimizer, opt::Function) = opt

# TOD remove the following methods once it is defined for AbstractMockSDOptimizer in MOIU
function MOIU.mock_optimize!(mock::MockSDOptimizer, termstatus::MOI.TerminationStatusCode, primal, dual...)
    MOI.set!(mock, MOI.TerminationStatus(), termstatus)
    MOIU.mock_primal!(mock, primal)
    MOIU.mock_dual!(mock, dual...)
end
# Default termination status
MOIU.mock_optimize!(mock::MockSDOptimizer, primdual...) = MOIU.mock_optimize!(mock, MOI.Success, primdual...)
function MOIU.mock_optimize!(mock::MockSDOptimizer, termstatus::MOI.TerminationStatusCode)
    MOI.set!(mock, MOI.TerminationStatus(), termstatus)
end

# Primal
function MOIU.mock_primal!(mock::MockSDOptimizer, primstatus::MOI.ResultStatusCode, varprim...)
    MOI.set!(mock, MOI.PrimalStatus(), primstatus)
    MOIU.mock_varprimal!(mock, varprim...)
end
# Default primal status
MOIU.mock_primal!(mock::MockSDOptimizer, varprim::Vector) = MOIU.mock_primal!(mock, MOI.FeasiblePoint, varprim)
function MOIU.mock_primal!(mock::MockSDOptimizer)
    # No primal solution
    mock.hasprimal = false
end

# Sets variable primal to varprim
function MOIU.mock_varprimal!(mock::MockSDOptimizer) end
function MOIU.mock_varprimal!(mock::MockSDOptimizer{T}, X::Vector{Matrix{T}}) where T
    mock.X = BlockMatrix{T}(X)
end
to_matrix(X::Matrix) = X
function to_matrix(X::Vector)
    @assert length(X) == 1
    reshape(X, 1, 1)
end
function MOIU.mock_varprimal!(mock::MockSDOptimizer{T}, X::Vector) where T
    MOIU.mock_varprimal!(mock, to_matrix.(X))
end

# Dual
function MOIU.mock_dual!(mock::MockSDOptimizer, dualstatus::MOI.ResultStatusCode, conduals...)
    MOI.set!(mock, MOI.DualStatus(), dualstatus)
    MOIU.mock_condual!(mock, conduals...)
end
# Default dual status
function MOIU.mock_dual!(mock::MockSDOptimizer, conduals...)
    status = !mock.hasprimal || MOI.get(mock, MOI.PrimalStatus()) == MOI.InfeasiblePoint ? MOI.InfeasibilityCertificate : MOI.FeasiblePoint
    MOIU.mock_dual!(mock, status, conduals...)
end
function MOIU.mock_dual!(mock::MockSDOptimizer)
    # No dual solution
    mock.hasdual = false
end

# Sets constraint dual to conduals
function MOIU.mock_condual!(mock::MockSDOptimizer) end
function MOIU.mock_condual!(mock::MockSDOptimizer{T}, y::Vector{T}) where T
    mock.y = y
    # blockdims can be negative for diagonal blocks. We allocate full blocks
    # here. As mock optimizers are used only for testing, we favor simplicity.
    mock.Z = BlockMatrix{T}(map(n -> zeros(T, abs(n), abs(n)), mock.blkdims))
    # FIXME shouldn't Z be defined as the opposite i.e. Z = C - sum y_i A_i >= 0
    # instead of sum y_i A_i - C <= 0 ?
    if mock.dualstatus != MOI.InfeasibilityCertificate
        # Infeasibility certificate is a ray so we only take the homogeneous part
        # FIXME:check that this is also done IN MOIU.MockOptimizer
        for (α, blk, i, j) in mock.objective_coefficients
            mock.Z[blk][i, j] -= α
            if i != j
                mock.Z[blk][j, i] -= α
            end
        end
    end
    for (c, constraint_coefficients) in enumerate(mock.constraint_coefficients)
        for (α, blk, i, j) in constraint_coefficients
            mock.Z[blk][i, j] += α * y[c]
            if i != j
                mock.Z[blk][j, i] += α * y[c]
            end
        end
    end
end
