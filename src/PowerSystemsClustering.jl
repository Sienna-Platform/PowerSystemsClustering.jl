module PowerSystemsClustering

#### Imports ####

import Clustering
import DataFrames
import Dates
import Distances
import InfrastructureOptimizationModels
import InfrastructureSystems
import LinearAlgebra
import PowerSystems
import PowerSystemsInvestments
import PowerSystemsInvestmentsPortfolios
import Random
import Statistics
import TimeSeries

const IS = InfrastructureSystems
const IOM = InfrastructureOptimizationModels
const PSY = PowerSystems
const PSIP = PowerSystemsInvestmentsPortfolios
const PSIN = PowerSystemsInvestments

using DocStringExtensions

@template (FUNCTIONS, METHODS) = """
                                 $(TYPEDSIGNATURES)
                                 $(DOCSTRING)
                                 """

#### Portfolio construction ####

include("portfolio/initialize.jl")
include("portfolio/regions.jl")

end
