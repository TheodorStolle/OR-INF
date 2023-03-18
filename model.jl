using Clp, JuMP, XLSX

capacityFactors = XLSX.readxlsx("CapacityFactors.xlsx")
demands = XLSX.readxlsx("Demands.xlsx")

technologies = ["SolarPV", "OnshoreWind","OffshoreWind", "Hydro", "Nuclear"] 
period = 1:8760
fuels = ["Power", "Heat"]

#2018
VariableCost = Dict(zip(technologies, [0.01, 0.01, 0.01, 0.83, 0.01]))
InvestmentCost = Dict(zip(technologies, [1020, 1250, 3500, 2200, 6000]))
#LCOE = Dict(zip(technologies, [14.94,7.78,12.12,5.07,8.60]))

OutputRatio = Dict()
for t in technologies, f in fuels, p in period
    OutputRatio[t,f,p] = 0
end

pv = capacityFactors["PV_AVG"]
wind_offshore = capacityFactors["WIND_OFFSHORE"]
wind_onshore = capacityFactors["WIND_ONSHORE_AVG"]

for f in fuels, p in period
    OutputRatio["SolarPV",f,p] = pv[p+1,8] #p+1 cos first row is text, and germany is column 8
    OutputRatio["OnshoreWind",f,p] = wind_onshore[p+1,8] 
    OutputRatio["OffshoreWind",f,p] = wind_offshore[p+1,8] 
    OutputRatio["Nuclear", f, p] = 0.9  #adjust this
    OutputRatio["Hydro", f, p] = 0.4652
end

#InputRatio = Dict()
#for t in technologies, f in fuels, p in period
#   InputRatio[t,f,p] = 0
#end

#2018
powerDemand = demands["LOAD"]
heatDemandLow = demands["HEAT_LOW"]
#heatDemandHigh = demands["HEAT_HIGH"]
annualPowerDemand = 1784.7
annualHeatDemand = 234.67 + 2477.64 #Low residential and industry heat demand, I ignored high heat for now

Demand = Dict()
for p in period
    Demand["Power", p] = powerDemand[p+1, 8]*(annualPowerDemand/8760)
    Demand["Heat", p] = heatDemandLow[p+1, 8]*(annualHeatDemand/8760)   
end

NPP = Model(Clp.Optimizer)
#Sums up the Cost for each technology per period 
@variable(NPP, TotalCostByTechnology[technologies, period] >=0)
#Sums up total Cost per period (technology Cost + Storage Cost)
@variable(NPP, TotalCostByPeriod[period] >= 0)
#Production of each technology of fuels in each period
@variable(NPP, Production[technologies, fuels ,period ] >= 0)
#The Capacity of how much a technology can produce in period t
@variable(NPP, Capacity[technologies] >= 0)
#Amount of fuel f wich is consumed in period t from the storage     
#@variable(NPP, StorageOutput[fuels, period] >= 0)
#Amount of fuel f wich is stored in period t in the storage
#@variable(NPP, StorageInput[fuels, period] >= 0)
#Amount of fuel f wich is in the storage at the end of period t (Input + Fuel stored in former periods)     
#@variable(NPP, Storage[fuels, period] >= 0)
#Maxmimum amount wich can be stored in period t 
#@variable(NPP, StorageCapacity[fuels, period]>= 0)

#Sums up the cost of each technology for period t (variable + fix costs)
@constraint(NPP, totalCostByTechnology[t in technologies, p in period], 
    sum(Production[t,f,p] for f in fuels)* VariableCost[t]  == TotalCostByTechnology[t,p]
)   #WHY would the model choose to not invest in the first period? Idk maybe it would, what would this mean/is that realistic tho?  

#Sums up the entire cost of a period (all techbology cost + storage cost)                            #IGNORING STORAGE FOR NOW
#@constraint(NPP, totalCostByPeriod[p in period], sum(TotalCostByTechnology[t,p] t in technologies)
#    + sum((StorageCapacity[f,p]- StorageCapacity[f,p-1])*StorageCapacityCost[t] for f in fuels)
#    + sum(Storage[f,p]*VariableStorageCost[f] for f in fuels) == TotalCostByPeriod[p]
#)                                                                  #SAME question here for storage? 

#Production function for each technology, fuel and time t (+ capacity constraint)
@constraint(NPP, ProductionFunction[t in technologies, f in fuels, p in period], Production[t,f,p] <= OutputRatio[t,f,p] * Capacity[t])
#Same Demand function as in the ESM Model from the lecture but with additional stored fuel capacities 
#on the left side of the equation: All the production in this period + the fuel wich can me consumed from the storage (Output)

#on the right side of the equation: Demand plus the fuel that we store in this period (Input)
@constraint(NPP, DemandAdequacy[t in technologies, f in fuels, p in period], sum(Production[t,f,p] for t in technologies)  >= Demand[f, p] ) #+ StorageOutput[f,p] + StorageInput[f,p]

#We can only use as much fuel from the Storage as we stored ealier
#@constraint(NPP, StorageBalance[f in fuels, p in period], StorageOutput[f,p] <= Storage[f,p - 1])  

#We can only store as much fuel as we have capacities
#@constraint(NPP, StorageCapacity[f in fuels, p in period], Storage[f,p] <= StorageCapacity[f,p]) 

#Update function of the amount of stored energy for each period
#The stored fuel level for the next period (Storage[f,t+1]) is 
#the current fuel level(Storage[f,t]) + the fuel we store this period (Input[f,t]) - the fuel we take out of the storage (Output[f,t]))
#@Constraint(NPP, StorageBalanceUpdate[f in fuels, p in period], Storage[f,p] == Storage[f,p-1] + StorageInput[f,p] - StorageOutput[f,p])

#linear objective function wich sums up the cost of all periods
@objective(NPP, Min, sum(TotalCostByTechnology[t,p] for p in period, t in technologies)+sum(Capacity[t]*InvestmentCost[t] for t in technologies))

optimize!(NPP)

objective_value(NPP)
value.(Production)
value.(Capacity)
