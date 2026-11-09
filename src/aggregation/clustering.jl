"""
Cluster a group's `devices` by k-means on their features. Returns cluster numbers in device
order, numbered by first appearance; identical devices can leave fewer than `n_clusters`.
"""
function cluster_group(
    devices::AbstractVector{<:PSY.StaticInjection},
    n_clusters::Int;
    seed::Int = 1,
)
    if n_clusters == length(devices)
        return collect(1:n_clusters)
    end
    matrix, row_names = feature_matrix(devices)
    result = Clustering.kmeans(
        _scale_features(matrix, row_names),
        n_clusters;
        rng = Random.Xoshiro(seed),
    )
    return _number_by_first_device(Clustering.assignments(result))
end

# Z-scores for scalar features; profiles are already per unit.
function _scale_features(matrix::Matrix{Float64}, ::Vector{Symbol})
    means = Statistics.mean(matrix; dims = 2)
    deviations = Statistics.std(matrix; dims = 2, corrected = false)
    return (matrix .- means) ./ ifelse.(iszero.(deviations), 1.0, deviations)
end

_scale_features(matrix::Matrix{Float64}, ::Vector{Dates.DateTime}) = matrix

function _number_by_first_device(assignments::Vector{Int})
    numbers = Dict{Int, Int}()
    return [get!(numbers, a, length(numbers) + 1) for a in assignments]
end
