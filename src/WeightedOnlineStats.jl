module WeightedOnlineStats

export WeightedMean, WeightedVariance

import OnlineStatsBase: OnlineStat, name, fit!, merge!, _fit!, _merge!
import Statistics: mean, var, std

smooth(a, b, γ) = a + γ * (b - a)

abstract type WeightedOnlineStat{T} <: OnlineStat{T} end
weightsum(o::WeightedOnlineStat) = o.W


##############################################################
# Define our own interface so that it accepts two inputs.
##############################################################

# fit single value and weight
function fit!(o::WeightedOnlineStat{T}, x::T, w::T) where T
    _fit!(o, x, w)
    o
end
# fit a tuple, allows fit(o, zip(x, w))
function fit!(o::WeightedOnlineStat{T}, x::S) where {T, S}
    T == eltype(x) && error("The input for $(name(o,false,false)) is a $T.  Found $S.")
    for xi in x
        fit!(o, xi...)
    end
    o
end
# fit two arrays, allows fit(o, x::Array, y::Array)
function fit!(o::WeightedOnlineStat{T}, x, w) where {T}
    (T == eltype(x) && T == eltype(w)) ||
        error("The input for $(name(o,false,false)) is a $T.  Found $(eltype(x)) and $(eltype(w)).")
    for (xi, wi) in zip(x, w)
        fit!(o, xi, wi)
    end
    o
end
function merge!(o::WeightedOnlineStat, o2::WeightedOnlineStat)
    (weightsum(o) > 0 || weightsum(o) > 0) && _merge!(o, o2)
    o
end
function Base.show(io::IO, o::WeightedOnlineStat)
    print(io, name(o, false, false), ": ")
    print(io, "∑wᵢ=")
    show(IOContext(io, :compact => true), weightsum(o))
    print(io, " | value=")
    show(IOContext(io, :compact => true), value(o))
end

##############################################################
# Weighted Mean
##############################################################
mutable struct WeightedMean{T} <: WeightedOnlineStat{T}
    μ::T
    W::T
end

WeightedMean(T::Type = Float64) = WeightedMean(T(0), T(0))
function _fit!(o::WeightedMean{T}, x, w) where T
    w = convert(T, w)
    o.W += w
    o.μ = smooth(o.μ, x, w / o.W)
    o
end

function _merge!(o::WeightedMean{T}, o2::WeightedMean) where T
    o.W += convert(T, o2.W)
    o.μ = smooth(o.μ, convert(T, o2.μ), o2.W / o.W)
    o
end
value(o::WeightedMean) = o.μ
mean(o::WeightedMean) = value(o)
Base.copy(o::WeightedMean) = WeightedMean(o.μ, o.W)

##############################################################
# Weighted Variance
##############################################################
mutable struct WeightedVariance{T} <: WeightedOnlineStat{T}
    μ::T
    S::T
    W::T
    W2::T
end
WeightedVariance(T::Type = Float64) = WeightedVariance(T(0), T(0), T(0), T(0))
function _fit!(o::WeightedVariance{T}, x, w) where T
    x = convert(T, x)
    w = convert(T, w)

    o.W += w
    o.W2 += w * w
    μ = o.μ

    o.μ = smooth(μ, x, w / o.W)
    o.S += w * (x - μ) * (x - o.μ)
    # o.S = smooth(o.S, (x - o.μ) * (x - μ), w)

    return o
end
# function _fit!(o::Variance, x)
#     μ = o.μ
#     γ = o.weight(o.n += 1)
#     o.μ = smooth(o.μ, x, γ)
#     o.σ2 = smooth(o.σ2, (x - o.μ) * (x - μ), γ)
# end
function _merge!(o::WeightedVariance{T}, o2::WeightedVariance) where T
    # o.W += o2.W
    # o.W2 += o2.W2

    # γ = o2.W / o.W
    # δ = o2.μ - o.μ

    # o.S = smooth(o.S, o2.S, γ) + δ ^ 2 * γ * (1.0 - γ)
    # o.μ = smooth(o.μ, o2.μ, γ)

    ########

    o.W += o2.W
    o.W2 += o2.W2

    μ = o.μ
    o.μ = smooth(o.μ, o2.μ, o2.W / o.W)
    o.S += o2.S + o2.W * (o2.μ - μ) * (o2.μ - o.μ)

    ########

    # o.S += o2_W / o.W * (o2_S - o.S)
    # o.S = smooth(o.S, o2_S, o2_W / o.W)
    # o.S =
    #     o.S * o2_W / o.W +
    #     o2_S * o_W / o.W +
    #     ((o2_μ - o.μ) ^ 2) * o2_W * o_W / o.W

    # o.S =
    #     o.S +
    #     o2.S +
    #     o.W / o2.W / (o.W + o2.W) *
    #     ((o2.W * o.μ - (o.W + o2.W) * (o2.μ + o.μ)) ^ 2)
    # o.S = o.S + o2.S - o.W * o.μ^2 - o2.W * o2.μ^2

    # o.μ = smooth(o.μ, o2.μ, o2.W / (o.W + o2.W))


    return o
end
# function _merge!(o::Variance, o2::Variance)
#     γ = o2.n / (o.n += o2.n)
#     δ = o2.μ - o.μ
#     o.σ2 = smooth(o.σ2, o2.σ2, γ) + δ ^ 2 * γ * (1.0 - γ)
#     o.μ = smooth(o.μ, o2.μ, γ)
#     o
# end
value(o::WeightedVariance) = var(o)
mean(o::WeightedVariance) = o.μ
function var(o::WeightedVariance; corrected = false, weight_type = :analytic)
    if corrected
        if weight_type == :analytic
            o.S / (weightsum(o) - o.W2 / weightsum(o))
        elseif weight_type == :frequency
            o.S / (weightsum(o) - 1)
        elseif weight_type == :probability
            error("If you need this, please make a PR")
        else
            throw(ArgumentError("weight type $weight_type not implemented"))
        end
    else
        o.S / weightsum(o)
    end
end

end # module WeightedOnlineStats
