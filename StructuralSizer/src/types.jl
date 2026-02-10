# =============================================================================
# Abstract Types for Structural Engineering
# =============================================================================
# Base types for materials, design codes, sections, and building models.

# =============================================================================
# Materials
# =============================================================================

"""Base type for all structural materials (Steel, Concrete, Timber, etc.)"""
abstract type AbstractMaterial end

"""Base type for design code implementations (AISC, ACI, NDS, etc.)"""
abstract type AbstractDesignCode end

"""Base type for cross-sections (W shapes, HSS, RC columns, etc.)"""
abstract type AbstractSection end

"""Base type for structural synthesizer components."""
abstract type AbstractStructuralSynthesizer end

"""Base type for building skeletons (geometry only)."""
abstract type AbstractBuildingSkeleton <: AbstractStructuralSynthesizer end

"""Base type for building structures (geometry + sizing)."""
abstract type AbstractBuildingStructure <: AbstractStructuralSynthesizer end

"""Base type for load demand specifications."""
abstract type AbstractDemand end

"""Base type for member geometry specifications."""
abstract type AbstractMemberGeometry end