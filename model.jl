using Clp, JuMP

technologies = ["SolarPV", "OnshoreWind","OffshoreWind", "Hydro", "..."] 
period = CSV.length
fuels = ["Power", "Heat"]

VariableCost = Dict(zip(technologies, [1,2,3,4]))
InvestmentCost = Dict(zip(technologies, [4,3,2,1]))

OutputRatio = Dict()
for t in technologies, f in fuels, p in period
    OutputRatio[t,f,p] = 0
end

InputRatio = Dict()
for t in technologies, f in fuels, p in period
   InputRatio[t,f,p] = 0
end

Demand = Dict()
Demand[technologies][fuels][period]

NPP = Model(Clp.Optimizer)
#Sums up the Cost for each technology per period 
@variable(NPP, TotalCostByTechnology[technologies, period] >=0)
#Sums up total Cost per period (technology Cost + Storage Cost)
@variable(NPP, TotalCostByPeriod[period] >= 0)
#Production of each technology of fuels in each period
@variable(NPP, Production[technologies, fuels ,period ] >= 0)
#The Capacity of how much a technology can produce in period t
@variable(NPP, ProductionCapacity[technologies, period] >= 0)
#Amount of fuel f wich is consumed in period t from the storage
@variable(NPP, StorageOutput[fuels, period] >= 0)
#Amount of fuel f wich is stored in period t in the storage
@variable(NPP, StorageInput[fuels, period] >= 0)
#Amount of fuel f wich is stored in period t (Input + Fuel stored in former periods)
@variable(NPP, Storage[fuels, period] >= 0)
#Maxmimum amount wich can be stored in period t 
@variable(NPP, StorageCapacity[fuels, period]>= 0)
@variable(NPP, Capacity[technologies, period] >= 0)

#Sums up the cost of each technology for period t (variable + fix costs)
@constraint(NPP, TotalCostByTechnology[t in technologies, p in time], 
    sum(Production[t,f,p] for f in fuels)* VariableCost[t] + (Capacity[t,p]-Capacity[t,p-1])*InvestmentCost[t] == TotalCostByTechnology[t,p]
)
#Sums up the entire cost of a period (all techbology cost + storage cost)
@constraint(NPP, TotalCostByPeriod[p in period], sum(TotalCostByTechnology[t,p] t in technologies) 
    + sum((StorageCapacity[f,p]- StorageCapacity[f,p-1])*StorageCapacityCost[t] for f in fuels)
    + sum(StorageUsed[f,p]*VariableStorageCost[f] for f in fuels) == TotalCostByPeriod[p]
)
#Production fucntion for each technology, fuel and time t (+ capacity constraint)
@constraint(NPP, ProductionFunction[t in technologies, f in fuels, p in period], Production[t,f,p] <= OutputRatio[t,f,p] * Capacity[t])
#Same Demand function as in the ESM Model from the lecture but with additional stored fuel capacities 
#on the left side of the equation: All the production in this period + the fuel wich can me consumed from the storage (Output)
#on the right side of the equation: Demand plus the fuel that we store in this period (Input)
@constraint(NPP, DemandAdequacy[t in technologies, f in fuels, p in period], sum(Production[t,f,p] for t in technologies) + Output[f,p] >= Demand[f] + Input[f,p])
#We can only use as much fuel from the Storage as we stored ealier
@constraint(NPP, StorageBalance[f in fuels, p in period], Output[f,p] <= Storage[f,p])
#We can only store as much fuel as we have capacities
@constraint(NPP, StorageCapacity[f in fuels, p in period], Storage[f,p] <= StorageCapacity[f,p-1])
#Update function of the amount of stored energy for each period
#The stored fuel level for the next period (StorageUsed[f,t+1]) is 
#the current fuel level(StorageUsed[f,t]) + the fuel we store this period (Input[f,t]) - the fuel we take out of the storage (Output[f,t]))
@Constraint(NPP, StorageBalanceUpdate[f in fuels, p in period], Storage[f,p] == Storage[f,p-1] + StorageInput[f,p] - StorageOutput[f,p])
#linear objective function wich sums up the cost of all periods
@objective(NPP, Min, sum(TotalCostByPeriod[p] for p in period))