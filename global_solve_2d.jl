include("diagonal_sbp_D2.jl")
using SparseArrays

⊗ = (A,B) -> kron(A, B)

function locoperator(p, Nx, Ny, τ1, τ2, τ3, τ4,
                     corners::NTuple{4, Tuple{T, T}}) where T <: Number
  @assert (corners[1][1], corners[2][1]) == (corners[3][1], corners[4][1])
  @assert (corners[1][2], corners[3][2]) == (corners[2][2], corners[4][2])

  (D2x, BSx, HIx, Hx, rx) = diagonal_sbp_D2(p, Nx; xc = (corners[1][1],
                                                         corners[4][1]))
  (D2y, BSy, HIy, Hy, ry) = diagonal_sbp_D2(p, Ny; xc = (corners[1][2],
                                                         corners[4][2]))

  Ax = BSx - Hx* D2x
  Ay = BSy - Hy* D2y

  E0x = sparse([     1], [     1], [1], Nx + 1, Nx + 1)
  ENx = sparse([Nx + 1], [Nx + 1], [1], Nx + 1, Nx + 1)
  E0y = sparse([     1], [     1], [1], Ny + 1, Ny + 1)
  ENy = sparse([Ny + 1], [Ny + 1], [1], Ny + 1, Ny + 1)

  e0x = sparse([     1], [1], [1], Nx + 1, 1)
  eNx = sparse([Nx + 1], [1], [1], Nx + 1, 1)
  e0y = sparse([     1], [1], [1], Ny + 1, 1)
  eNy = sparse([Ny + 1], [1], [1], Ny + 1, 1)


  hx = rx[2] - rx[1]
  hy = ry[2] - ry[1]

  M = (Hy ⊗ (Ax - BSx - BSx' + τ1 * E0x + τ2 * ENx)) +
      ((Ay - BSy - BSy' + τ3 * E0y + τ4 * ENy) ⊗ Hx)
  B1 = (Hy ⊗ (-BSx' * e0x + τ1 * e0x))
  B2 = (Hy ⊗ (-BSx' * eNx + τ2 * eNx))
  B3 = ((-BSy' * e0y + τ3 * e0y) ⊗ Hx)
  B4 = ((-BSy' * eNy + τ4 * eNy) ⊗ Hx)

  r = ones(Ny + 1) ⊗ rx
  s = ry ⊗ ones(Nx + 1)
  N1 = [-ones(Ny+1) zeros(Ny+1)]
  N2 = [ ones(Ny+1) zeros(Ny+1)]
  N3 = [zeros(Nx+1) -ones(Nx+1)]
  N4 = [zeros(Nx+1)  ones(Nx+1)]
  # M           << interior Dirichlet Matrix
  # B[1-4]      << Boundary Dirichlet Matrices
  # τ[1-4]H[xy] << Scaling matrices for λ in penalty equation
  ((M, B1, B2, B3, B4, τ1 * Hy, τ2 * Hy, τ3 * Hx, τ4 * Hx),
   r, s, rx, ry, Hy ⊗ Hx, (N1, N2, N3, N4))
end

function glooperator(lop,
                     FToλOffset, FToDirichletOffset,
                     FToNeumannOffset, FToδOffset,
                     EToF, EToS, FToB, FToτ,
                     Dirichlet, Neumann, δ)
  M = sparse(Array{typeof(lop[1][1][1][1]),2}(undef, 0, 0))
  # Set up the block diagonal volume terms
  nelem = length(lop)
  Npλ = FToλOffset[end]-1
  Npe = zeros(Int64, nelem)
  IM = Array{Int64,1}(undef,0)
  JM = Array{Int64,1}(undef,0)
  VM = Array{typeof(lop[1][1][1][1]),1}(undef,0)
  Npu = 0
  for e = 1:nelem
    Me = lop[e][1][1]
    (Ie, Je, Ve) = findnz(Me)
    IM = [IM;Ie .+ Npu]
    JM = [JM;Je .+ Npu]
    VM = [VM;Ve]

    Npe[e] = length(lop[e][2])
    Npu += Npe[e]
  end
  @assert Npu == sum(Npe)

  # Set up the boundary and interface terms
  nlfaces = 4
  bM = zeros(Npu)
  glo_elm_rng = 0:0
  IL = Array{Int64,1}(undef,0)
  JL = Array{Int64,1}(undef,0)
  VL = Array{typeof(lop[1][1][1][1]),1}(undef,0)
  ID = Array{Int64,1}(undef,0)
  JD = Array{Int64,1}(undef,0)
  VD = Array{typeof(lop[1][1][1][1]),1}(undef,0)
  for e = 1:nelem
    glo_elm_rng = glo_elm_rng[end] .+ (1:Npe[e])

    for lf = 1:nlfaces
      gf = EToF[lf, e]
      Bf = lop[e][1][lf+1]
      if FToB[gf] == 0 || FToB[gf] == -1
        # update Lambda matrix
        (Ie, Je, Ve) = findnz(Bf)
        Ie .+= (glo_elm_rng[1]-1)
        Je .+= (FToλOffset[gf]-1)
        IL = [IL;Ie]
        JL = [JL;Je]
        VL = [VL;-Ve]

        λrng = FToλOffset[gf]:FToλOffset[gf+1]-1
        ID = [ID;λrng]
        JD = [JD;λrng]
        H = Vector(diag(lop[e][1][lf+5]))
        VD = [VD;H]

        if FToB[gf] == -1
          δrng = FToδOffset[gf]:FToδOffset[gf+1]-1
          if EToS[e, lf] == 1
            bM[glo_elm_rng] += Bf * δ[δrng]
          else
            bM[glo_elm_rng] -= Bf * δ[δrng]
          end
        end
      elseif FToB[gf] == 1
        # update RHS matrix
        drng = FToDirichletOffset[gf]:(FToDirichletOffset[gf+1]-1)
        bM[glo_elm_rng] += Bf * Dirichlet[drng]
      elseif FToB[gf] == 2
        # update volume matrix
        H = Vector(diag(lop[e][1][lf+5]))
        HI = sparse(1:length(H), 1:length(H), 1 ./ H[:])
        (Ie, Je, Ve) = findnz(Bf*HI*Bf')
        Ie .+= (glo_elm_rng[1]-1)
        Je .+= (glo_elm_rng[1]-1)
        IM = [IM; Ie];
        JM = [JM; Je];
        VM = [VM; -Ve];

        nrng = FToNeumannOffset[gf]:(FToNeumannOffset[gf+1]-1)
        bM[glo_elm_rng] += Bf * Neumann[nrng] ./ FToτ[gf]
      else
        error("BC = ", FToB[gf]," not implemented")
      end
    end
  end

  M = sparse(IM, JM, VM, Npu, Npu)
  L = sparse(IL, JL, VL, Npu, Npλ)
  D = sparse(ID, JD, VD, Npλ, Npλ)
  bλ = zeros(Npλ)
  (M, bM, L, D, bλ)
end

function localsolve(M, g1, g2, g3, g4)
  localsolve(M[1], M[2], M[3], M[4], M[5], g1, g2, g3, g4)
end

function localsolve(M, B1, B2, B3, B4, g1, g2, g3, g4)
  b = B1 * g1 + B2 * g2 + B3 * g3 + B4 * g4
  M \ b
end

let
  # min size required for order p/2
  N0 = (2, 8, 12, 16, 21)

  # What order to run
  p = 4

  # 7---9---8--12---9
  # |       |       |
  # 4   3   5   4   6
  # |       |       |
  # 4---8---5--11---6
  # |       |       |
  # 1   1   2   2   3
  # |       |       |
  # 1---7---2--10---3

  # verts: Vertices
  verts = ((-1,-1), ( 0,-1), ( 1,-1),
           (-1, 0), ( 0, 0), ( 1, 0),
           (-1, 1), ( 0, 1), ( 1, 1))

  # EToV: Element to Vertices
  EToV = ((1, 2, 4, 5), (2, 3,  5,  6), (4, 5, 7, 8), (5, 6,  8,  9))

  # EToF: Element to Unique Global Faces
  EToF = ((1, 2, 7, 8), (2, 3, 10, 11), (4, 5, 8, 9), (5, 6, 11, 12))

  # EToF: Element to Unique Global Faces Orientation
  EToO = ((0, 0, 0, 0), (0, 0,  0,  0), (0, 0, 0, 0), (0, 0,  0,  0))

  # EToS: Element to Unique Global Face Side
  EToS = ((1, 1, 1, 1), (2, 1, 1, 1), (1, 1, 2, 1), (2, 1, 1, 1))

  # FToB: Unique Global Face to Boundary Conditions
  #      -1 = Jumps
  #       0 = internal face
  #       1 = Dirichlet
  #       2 = Neumann
  # FToB = (1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1)
  FToB = (1, -1, 1, 1, -1, 1, 2, 0, 2, 2, 0, 2)
  # FToB = (1, 0, 1, 1, 0, 1, 0, 0, 1, 0, 0, 1)
  # FToB = (1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1)

  # number of elements
  nelem = length(EToV)
  nlfaces = 4

  # Some sanity check on the mesh
  @assert typeof(EToV) == NTuple{nelem, NTuple{4, Int}}
  @assert typeof(EToF) == NTuple{nelem, NTuple{4, Int}}
  @assert typeof(EToO) == NTuple{nelem, NTuple{4, Int}}
  @assert maximum(maximum(EToF)) == length(FToB)

  flatten_tuples = (x) -> reshape(collect(Iterators.flatten(x)),
                                  length(x[1]), length(x))
  verts = flatten_tuples(verts)
  EToV = flatten_tuples(EToV)
  EToF = flatten_tuples(EToF)
  EToO = flatten_tuples(EToO)
  EToS = flatten_tuples(EToS)
  FToB = flatten_tuples(FToB)

  # number of levels run is based on size of this array
  ϵ = zeros(5)
  for lvl = 1:length(ϵ)
    Nx1 = 2^(lvl-1) * (N0[div(p,2)] + 0)
    Nx2 = 2^(lvl-1) * (N0[div(p,2)] + 1)
    Ny1 = 2^(lvl-1) * (N0[div(p,2)] + 2)
    Ny2 = 2^(lvl-1) * (N0[div(p,2)] + 3)

    # EToN: Element to (Nx, Ny) size
    #       (N[xy[ = number of points in that dimension minus 1)
    EToN = flatten_tuples(((Nx1, Ny1), (Nx2, Ny1), (Nx1, Ny2), (Nx2, Ny2)))

    # FToNp: Face to Face Number of points on that face
    FToNp = zeros(Int64, length(FToB))

    #FToτ: parameter τ for each face of the mesh
    FToτ = zeros(Float64, length(FToB))
    for e = 1:nelem
      τ = 4 * EToN[:, e] ./ (verts[:, EToV[4, e]] - verts[:,EToV[1, e]])
      for lf = 1:nlfaces
        gf = EToF[lf, e]
        if FToNp[gf] == 0
          FToNp[gf] = EToN[2 - div(lf - 1, 2), e] + 1
          FToNp[gf] = EToN[2 - div(lf - 1, 2), e] + 1
        else
          @assert FToNp[gf] == EToN[2 - div(lf - 1, 2), e] + 1
        end
        FToτ[gf] = max(FToτ[gf], τ[div(lf - 1, 2) + 1])
      end
    end

    # FToTraceOffset: Face to Face Offset in unique global numbering of trace
    FToTraceOffset = accumulate(+, [1; FToNp[:]]);

    # Build the local operators
    tmp = locoperator(2, 3, 3, 1.0, 1.0, 1.0, 1.0,
                      ((0, 0), (1, 0), (0, 1), (1, 1)))
    lop = Dict{Int64, typeof(tmp)}()

    for e = 1:nelem
      v1 = Tuple(verts[:, EToV[1, e]])
      v2 = Tuple(verts[:, EToV[2, e]])
      v3 = Tuple(verts[:, EToV[3, e]])
      v4 = Tuple(verts[:, EToV[4, e]])
      (Nr, Ns) = EToN[:,e]
      (gf1, gf2, gf3, gf4) = EToF[:, e]
      # TODO: Fix for when metric terms are needed
      lop[e] = locoperator(p, Nr, Ns, FToτ[gf1], FToτ[gf2], FToτ[gf3],
                           FToτ[gf4], (v1, v2, v3, v4))
    end

    #{{{ global trace to local face maps and trace grid
    # unique point [xy]trace along the elements
    xtrace = fill(NaN, FToTraceOffset[end]-1)
    ytrace = fill(NaN, FToTraceOffset[end]-1)

    for e = 1:nelem
      (Nr, Ns) = EToN[:,e]
      xe = lop[e][2]
      ye = lop[e][3]
      for lf = 1:nlfaces
        gf = EToF[lf, e]
        glorng = FToTraceOffset[gf]:(FToTraceOffset[gf+1]-1)
        locrng = 0:1
        if lf == 1
          locrng = 1:(Nr+1):(Ns * (Nr+1) + 1)
        elseif lf == 2
          locrng = (Nr+1):(Nr+1):((Ns+1) * (Nr+1))
        elseif lf == 3
          locrng = 1:(Nr+1)
        elseif lf == 4
          locrng = (Ns * (Nr+1)+1):((Ns+1) * (Nr+1))
        else
          error("Invalid face")
        end
        if isnan(xtrace[glorng[1]])
          xtrace[glorng] = xe[locrng]
          ytrace[glorng] = ye[locrng]
        else
          @assert xtrace[glorng] ≈ xe[locrng]
          @assert ytrace[glorng] ≈ ye[locrng]
        end
      end
    end
    @assert !maximum(isnan.(xtrace)) && !maximum(isnan.(ytrace))
    #}}}

    #{{{ Set up various trace maps
    TraceToλ = Array{Int64, 1}()
    TraceToδ = Array{Int64, 1}()
    TraceToDirichlet = Array{Int64, 1}()
    TraceToNeumann = Array{Int64, 1}()
    FToλOffset = ones(Int64, length(FToB)+1)
    FToδOffset = ones(Int64, length(FToB)+1)
    FToDirichletOffset = ones(Int64, length(FToB)+1)
    FToNeumannOffset = ones(Int64, length(FToB)+1)
    for gf = 1:length(FToB)
      FToλOffset[gf+1] = FToλOffset[gf]
      FToDirichletOffset[gf+1] = FToDirichletOffset[gf]
      FToNeumannOffset[gf+1] = FToNeumannOffset[gf]
      FToδOffset[gf+1] = FToδOffset[gf]
      if FToB[gf] == 1
        TraceToDirichlet = [TraceToDirichlet;FToTraceOffset[gf]:(FToTraceOffset[gf+1]-1)]
        FToDirichletOffset[gf+1] = FToDirichletOffset[gf] + FToNp[gf]
      elseif FToB[gf] == 2
        TraceToNeumann = [TraceToNeumann;FToTraceOffset[gf]:(FToTraceOffset[gf+1]-1)]
        FToNeumannOffset[gf+1] = FToNeumannOffset[gf] + FToNp[gf]
      else
        TraceToλ = [TraceToλ;FToTraceOffset[gf]:(FToTraceOffset[gf+1]-1)]
        FToλOffset[gf+1] = FToλOffset[gf] + FToNp[gf]
        if FToB[gf] == -1
          TraceToδ = [TraceToδ;FToTraceOffset[gf]:(FToTraceOffset[gf+1]-1)]
          FToδOffset[gf+1] = FToδOffset[gf] + FToNp[gf]
        end
      end
    end
    #}}}

    #{{{ Set up the BCs
    v   = (x,y,e) ->      cos.(π * x) .* cosh.(π * y) .+ mod(e, 2)
    v_x = (x,y,e) -> -π * sin.(π * x) .* cosh.(π * y)
    v_y = (x,y,e) ->  π * cos.(π * x) .* sinh.(π * y)
    # Neumann
    neumann_bc = fill(NaN, FToNeumannOffset[end]-1)
    dirichlet_bc = fill(NaN, FToDirichletOffset[end]-1)
    δ = fill(0.0, FToDirichletOffset[end]-1)
    for e = 1:nelem
      for lf = 1:nlfaces
        gf = EToF[lf, e]
        if FToB[gf] == 1
          @assert isnan(dirichlet_bc[FToDirichletOffset[gf]])
          drng = FToDirichletOffset[gf]:(FToDirichletOffset[gf+1]-1)
          trng = TraceToDirichlet[drng]
          xd = xtrace[trng]
          yd = ytrace[trng]
          dirichlet_bc[drng] = v(xd, yd, e)
        elseif FToB[gf] == 2
          @assert isnan(neumann_bc[FToNeumannOffset[gf]])
          nrng = FToNeumannOffset[gf]:(FToNeumannOffset[gf+1]-1)
          trng = TraceToNeumann[nrng]
          xn = xtrace[trng]
          yn = ytrace[trng]
          N = lop[e][7][lf]
          neumann_bc[nrng] = (N[:,1] .* v_x(xn, yn, e) +
                              N[:, 2] .* v_y(xn, yn, e))
        elseif FToB[gf] == -1
          jrng = FToδOffset[gf]:(FToδOffset[gf+1]-1)
          trng = TraceToδ[jrng]
          xj = xtrace[trng]
          yj = ytrace[trng]
          if EToS[lf, e] == 1
            δ[jrng] -= v(xj, yj, e)
          else
            δ[jrng] += v(xj, yj, e)
          end
        end
      end
    end
    @assert !maximum(isnan.(dirichlet_bc))
    @assert !maximum(isnan.(neumann_bc))

    #}}}

    # Setup global system and solve
    (M, bM, L, D, bλ) = glooperator(lop,
                                    FToλOffset, FToDirichletOffset,
                                    FToNeumannOffset, FToδOffset,
                                    EToF, EToS, FToB, FToτ,
                                    dirichlet_bc, neumann_bc, δ)
    utrace_λ = [M L;L' D] \ [bM;bλ]

    #{{{ Check the error
    ϵ[lvl] = 0
    EToOffset = accumulate(+, [1; (EToN[1,:].+1).*(EToN[2,:].+1)])
    for e = 1:nelem
      locrng = EToOffset[e]:EToOffset[e+1]-1
      ul = utrace_λ[locrng]

      (xe, ye, He) = (lop[e][2], lop[e][3], lop[e][6])
      Δu = ul - v(xe, ye, e)
      ϵ[lvl] += Δu' * He * Δu
    end
    #}}}

    #=
    #{{{ Solve the local problems from known trace
    ϵ[lvl] = 0
    for e = 1:nelem
      # Dirichlet boundary conditions
      (gf1, gf2, gf3, gf4) = EToF[:, e]
      u1 = utrace[FToTraceOffset[gf1]:(FToTraceOffset[gf1+1]-1)]
      u2 = utrace[FToTraceOffset[gf2]:(FToTraceOffset[gf2+1]-1)]
      u3 = utrace[FToTraceOffset[gf3]:(FToTraceOffset[gf3+1]-1)]
      u4 = utrace[FToTraceOffset[gf4]:(FToTraceOffset[gf4+1]-1)]

      # Solve local problem
      u = localsolve(lop[e][1], u1, u2, u3, u4)

      # Check the error
      xe = lop[e][2]
      ye = lop[e][3]
      He  = lop[e][6]
      Δu = u - v(xe, ye)
      ϵ[lvl] += Δu' * He * Δu
    end
    #}}}
    =#

    ϵ[lvl] = sqrt(ϵ[lvl])
    println("level = ", lvl, " :: error = ", ϵ[lvl])
  end

  # Check the rate
  println(ϵ)
  println((log.(ϵ[1:end-1]) - log.(ϵ[2:end])) / log(2))

  nothing
end