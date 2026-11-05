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

# Unit strings such as u"MW" for the psy6 unit-aware getters.
using PowerSystems: @u_str
using DocStringExtensions

@template (FUNCTIONS, METHODS) = """
                                 $(TYPEDSIGNATURES)
                                 $(DOCSTRING)
                                 """

#### Portfolio construction ####

include("portfolio/initialize.jl")
include("portfolio/regions.jl")
include("portfolio/cost_curves.jl")
include("portfolio/technologies.jl")
include("portfolio/thermal.jl")
include("portfolio/renewable.jl")

end
