# Type Hierarchy

> ```julia
> # Functions dispatch on (section_type, material_type):
> get_ϕMn(section::ISymmSection, steel::StructuralSteel, geom::SteelMemberGeometry)
> get_ϕMn(section::RCBeamSection, conc::Concrete, geom::ConcreteMemberGeometry)
> ```

## Overview

The codebase uses Julia's multiple dispatch to organize structural engineering calculations. Abstract types define interfaces, and concrete types provide implementations. Design code functions like `get_ϕMn`, `get_ϕVn`, and `check_interaction` dispatch on the combination of section type, material type, and member geometry to select the appropriate code provision.

## Materials

```
AbstractMaterial
├── Metal
│   ├── StructuralSteel      # ASTM A992, A500, A36, etc.
│   └── RebarSteel            # ASTM A615 Gr. 60, Gr. 80
├── Concrete                  # Normal-weight concrete (fc′ = 3000–8000 psi)
├── ReinforcedConcreteMaterial # Concrete + rebar composite
├── FiberReinforcedConcrete   # FRC with residual strength (fib MC2010)
└── Timber                    # GLT, LVL, CLT, NLT, DLT
```

### Material Type Subtypes

```
MetalType
├── StructuralSteelType       # Hot-rolled structural steel
└── RebarType                 # Reinforcing steel
```

```@docs
AbstractMaterial
StructuralSteel
RebarSteel
Concrete
FiberReinforcedConcrete
Timber
```

### Fire Protection

```
FireProtection
├── NoFireProtection
├── SFRM                     # Sprayed fire-resistive material (UL X772)
├── IntumescentCoating        # Intumescent paint (UL N643)
└── CustomCoating             # User-defined fire protection
```

```@docs
FireProtection
SFRM
IntumescentCoating
```

## Sections

```
AbstractSection
├── ISymmSection              # Doubly-symmetric I-shapes (W, S, HP)
├── HSSRectSection            # Rectangular HSS
├── HSSRoundSection           # Round HSS and Pipe
├── Rebar                     # Reinforcing bar (for rebar design)
├── RCBeamSection             # RC rectangular beam
├── RCTBeamSection            # RC T-beam
├── RCColumnSection           # RC rectangular column
├── RCCircularSection         # RC circular column
├── GlulamSection             # Glulam timber beam/column
└── PixelFrameSection         # PixelFrame composite section
```

### Hollow Section Subtypes

```
AbstractHollowSection
├── AbstractRectHollowSection
│   └── HSSRectSection
└── AbstractRoundHollowSection
    └── HSSRoundSection
```

```@docs
AbstractSection
ISymmSection
HSSRectSection
HSSRoundSection
RCBeamSection
RCTBeamSection
RCColumnSection
RCCircularSection
GlulamSection
PixelFrameSection
```

## Demands

```
AbstractDemand
├── MemberDemand              # Generic (Pu, Mu, Vu, Tu) demand
├── RCColumnDemand            # RC column (Pu, Mux, Muy) with slenderness
└── RCBeamDemand              # RC beam (Mu, Vu, Tu) with exposure
```

```@docs
AbstractDemand
MemberDemand
RCColumnDemand
RCBeamDemand
```

## Member Geometry

```
AbstractMemberGeometry
├── SteelMemberGeometry       # L, Lb, Kx, Ky, Cb for steel members
├── ConcreteMemberGeometry    # L, cover, ties/spirals for RC members
└── TimberMemberGeometry      # L, Le, moisture, temperature for timber
```

```@docs
AbstractMemberGeometry
SteelMemberGeometry
ConcreteMemberGeometry
TimberMemberGeometry
```

## Floor Systems

```
AbstractFloorSystem
├── AbstractConcreteSlab
│   ├── OneWay                # One-way slab spanning to beams
│   ├── TwoWay                # Two-way slab on beams
│   ├── FlatPlate             # Flat plate (beamless two-way)
│   ├── FlatSlab              # Flat slab with drop panels
│   ├── PTBanded              # Post-tensioned banded slab
│   ├── Waffle                # Waffle (ribbed) slab
│   ├── Grade                 # Slab on grade
│   ├── HollowCore            # Precast hollow-core plank
│   ├── Vault                 # Thin-shell vault
│   └── ShapedSlab            # Custom-geometry slab
├── AbstractSteelFloor
│   ├── CompositeDeck         # Composite steel deck + concrete
│   ├── NonCompositeDeck      # Non-composite steel deck
│   └── JoistRoofDeck         # Open-web steel joist roof
└── AbstractTimberFloor
    ├── CLT                   # Cross-laminated timber panel
    ├── DLT                   # Dowel-laminated timber panel
    ├── NLT                   # Nail-laminated timber panel
    └── MassTimberJoist        # Mass timber joist floor
```

```@docs
AbstractFloorSystem
FlatPlate
FlatSlab
CompositeDeck
Vault
CLT
```

### Spanning Behavior

```
SpanningBehavior
├── OneWaySpanning
├── TwoWaySpanning
└── BeamlessSpanning
```

### Analysis Methods

```
FlatPlateAnalysisMethod
├── DDM                       # Direct Design Method (ACI 318 §13.6)
├── EFM                       # Equivalent Frame Method (ACI 318 §13.7)
├── FEA                       # Finite Element Analysis
└── RuleOfThumb               # Quick span/thickness estimate
```

```
VaultAnalysisMethod
├── HaileAnalytical           # Analytical thin-shell theory
└── ShellFEA                  # Shell finite element analysis
```

### Floor Results

```
AbstractFloorResult
├── CIPSlabResult             # Cast-in-place slab result
├── ProfileResult             # Profile deck result
├── CompositeDeckResult       # Composite deck result
├── JoistDeckResult           # Joist deck result
├── TimberPanelResult         # Timber panel result
├── TimberJoistResult         # Timber joist result
├── VaultResult               # Vault analysis result
├── ShapedSlabResult          # Custom slab result
└── FlatPlatePanelResult      # Flat plate panel result
```

## Foundations

```
AbstractFoundation
├── AbstractShallowFoundation
│   ├── SpreadFooting         # Isolated spread footing
│   ├── CombinedFooting       # Combined footing for 2+ columns
│   ├── StripFooting          # Continuous strip footing
│   └── MatFoundation         # Mat (raft) foundation
└── AbstractDeepFoundation
    ├── DrivenPile            # Driven steel/concrete pile
    ├── DrilledShaft          # Cast-in-drilled-hole shaft
    └── Micropile             # Small-diameter grouted pile
```

### Foundation Results

```
AbstractFoundationResult
├── SpreadFootingResult
├── CombinedFootingResult
├── StripFootingResult
├── MatFootingResult
└── PileCapResult
```

```@docs
AbstractFoundation
SpreadFooting
StripFooting
MatFoundation
```

## Optimization

### Objectives

```
AbstractObjective
├── MinWeight                 # Minimize total structural weight
├── MinVolume                 # Minimize total material volume
├── MinCost                   # Minimize estimated cost
└── MinCarbon                 # Minimize embodied carbon (kgCO₂e)
```

```@docs
AbstractObjective
MinWeight
MinVolume
MinCost
MinCarbon
```

### Capacity Checkers

```
AbstractCapacityChecker
├── AISCChecker               # AISC 360-16 steel checks
├── ACIBeamChecker            # ACI 318 RC beam checks
├── ACIColumnChecker          # ACI 318 RC column checks
├── PixelFrameChecker         # PixelFrame composite checks
└── NDSChecker                # NDS timber checks (stub)
```

```@docs
AbstractCapacityChecker
AISCChecker
ACIBeamChecker
ACIColumnChecker
```

### Capacity Caches

```
AbstractCapacityCache
├── AISCCapacityCache
├── ACIBeamCapacityCache
├── ACIColumnCapacityCache
└── PixelFrameCapacityCache
```

### NLP Problems

```
AbstractNLPProblem
├── RCColumnNLPProblem
├── RCCircularNLPProblem
├── RCBeamNLPProblem
├── RCTBeamNLPProblem
├── HSSColumnNLPProblem
├── WColumnNLPProblem
├── SteelWBeamNLPProblem
├── SteelHSSBeamNLPProblem
├── VaultNLPProblem
└── FlatPlateNLPProblem
```

## Synthesizer Types

```
AbstractStructuralSynthesizer
├── AbstractBuildingSkeleton
│   └── BuildingSkeleton      # Geometry container
└── AbstractBuildingStructure
    └── BuildingStructure     # Skeleton + structural data
```

```@docs
BuildingSkeleton
BuildingStructure
```

## Dispatch Model

The key design pattern is multiple dispatch on `(section_type, material_type)` pairs. This allows the same function name to be used across different code provisions:

```julia
# AISC 360 — steel W-shape flexure
get_ϕMn(s::ISymmSection, m::StructuralSteel, g::SteelMemberGeometry)

# AISC 360 — steel HSS flexure
get_ϕMn(s::HSSRectSection, m::StructuralSteel, g::SteelMemberGeometry)

# ACI 318 — RC beam flexure
get_ϕMn(s::RCBeamSection, m::Concrete, g::ConcreteMemberGeometry)

# ACI 318 — RC T-beam flexure
get_ϕMn(s::RCTBeamSection, m::Concrete, g::ConcreteMemberGeometry)
```

The optimization framework uses this dispatch to provide a unified interface:

1. `AbstractCapacityChecker` wraps the dispatch logic
2. The optimizer calls `check_capacity(checker, section, demand)` for each candidate section
3. The checker dispatches to the appropriate code provision based on the section and material types
4. Results are compared via the `AbstractObjective` to select the optimal section

This pattern extends naturally to new materials and codes: adding Eurocode 2 support requires defining new concrete section types and implementing `get_ϕMn` / `get_ϕVn` dispatches for those types.
