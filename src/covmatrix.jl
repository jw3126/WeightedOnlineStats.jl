mutable struct WeightedCovMatrix{T} <: WeightedOnlineStat{VectorOb}
    C::Matrix{T}
    A::Matrix{T}
    b::Vector{T}
    W::T
    W2::T
    n::Int
    function WeightedCovMatrix{T}(
            C = zeros(T, 0, 0), A = zeros(T, 0, 0),
            b = zeros(T, 0), W = T(0), W2 = T(0),
            n = Int(0)
        ) where T
        new{T}(C, A, b, W, W2, n)
    end
end

WeightedCovMatrix(C::Matrix{T}, A::Matrix{T}, b::Vector{T},
                  W::T, W2::T,
                  n::Int) where T = WeightedCovMatrix{T}(C, A, b, W, W2, n)
WeightedCovMatrix(::Type{T}, p::Int=0) where T =
    WeightedCovMatrix(zeros(T, p, p), zeros(T, p, p), zeros(T, p),
                             T(0), T(0), Int(0))
WeightedCovMatrix() = WeightedCovMatrix(Float64)

Base.eltype(o::WeightedCovMatrix{T}) where T = T

function _fit!(o::WeightedCovMatrix{T}, x, w) where T
    xx = convert(Vector{T}, x)
    ww = convert(T, w)

    o.W += ww
    o.W2 += ww * ww
    o.n += 1
    γ = ww / o.W
    if isempty(o.A)
        p = length(xx)
        o.b = zeros(T, p)
        o.A = zeros(T, p, p)
        o.C = zeros(T, p, p)
    end
    smooth!(o.b, xx, γ)
    smooth_syr!(o.A, xx, γ)
end

function _fit!(o::WeightedCovMatrix, x::Vector{Union{T, Missing}}, w) where T
    if !mapreduce(ismissing, |, x)
        x = convert(Vector{T}, x)
        w = convert(T, w)

        o.W += w
        o.W2 += w * w
        o.n += 1
        γ = w / o.W
        if isempty(o.A)
            p = length(x)
            o.b = zeros(T, p)
            o.A = zeros(T, p, p)
            o.C = zeros(T, p, p)
        end
        smooth!(o.b, x, γ)
        smooth_syr!(o.A, x, γ)
    end
    return o
end
_fit!(o::WeightedCovMatrix, x, w::Missing) = o

function _merge!(o::WeightedCovMatrix{T}, o2::WeightedCovMatrix) where T
    o2_A = convert(Matrix{T}, o2.A)
    o2_b = convert(Vector{T}, o2.b)
    o2_W = convert(T, o2.W)
    o2_W2 = convert(T, o2.W2)

    if isempty(o.A)
        o.C = convert(Matrix{T}, o2.C)
        o.A = o2_A
        o.b = o2_b
        o.W = o2_W
        o.W2 = o2_W2
        o.n = o2.n
    else
        W = o.W + o2_W
        γ = o2_W / W
        smooth!(o.A, o2_A, γ)
        smooth!(o.b, o2_b, γ)
        o.W = W
        o.W2 += o2_W2
        o.n += o2.n
    end

    return o
end

nvars(o::WeightedCovMatrix) = size(o.A, 1)

function value(o::WeightedCovMatrix)
    o.C[:] = Matrix(Hermitian((o.A - o.b * o.b')))
    o.C
end

mean(o::WeightedCovMatrix) = o.b
function cov(o::WeightedCovMatrix;
             corrected = false, weight_type = :analytic)
    if corrected
        if weight_type == :analytic
            rmul!(value(o), 1 / (1 - o.W2 / (weightsum(o) ^ 2)))
        elseif weight_type == :frequency
            rmul!(value(o), 1 / (weightsum(o) - 1) * weightsum(o))
        elseif weight_type == :probability
            error("If you need this, please make a PR or open an issue")
        else
            throw(ArgumentError("weight type $weight_type not implemented"))
        end
    else
        value(o)
    end
end

function cor(o::WeightedCovMatrix; kw...)
    cov(o; kw...)
    v = 1 ./ sqrt.(diag(o.C))
    rmul!(o.C, Diagonal(v))
    lmul!(Diagonal(v), o.C)
    o.C
end

var(o::WeightedCovMatrix; kw...) = diag(cov(o; kw...))

Base.copy(o::WeightedCovMatrix) =
    WeightedCovMatrix(o.C, o.A, o.b, o.W, o.W2, o.n)
