"""
Assign each device of a group to one of `n_clusters` clusters by k-means on its features
([`feature_matrix`](@ref)), with the random seed `seed` so results are reproducible.

Scalar features are standardized within the group (a feature equal for all devices is set to
zero); renewable profiles are already per unit and are clustered as they are. Clusters are
numbered in the order of their first device. `n_clusters` equal to the number of devices keeps
every device in its own cluster (no aggregation).

Returns a `Vector{Int}` of cluster numbers in device order. Throws `ArgumentError` unless
`1 <= n_clusters <= length(devices)`.
"""
function cluster_group(
    devices::AbstractVector{<:PSY.StaticInjection},
    n_clusters::Int;
    seed::Int = 1,
)
    if !(1 <= n_clusters <= length(devices))
        throw(
            ArgumentError(
                "n_clusters must be between 1 and the $(length(devices)) devices of the " *
                "group, got $(n_clusters).",
            ),
        )
    end
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

# Scalar features (named by Symbol) become z-scores across the group; profiles (named by time
# stamp) are already per unit.
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
