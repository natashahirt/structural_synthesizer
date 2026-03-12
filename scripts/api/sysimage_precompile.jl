# =============================================================================
# Sysimage precompile script — run during PackageCompiler.create_sysimage
# =============================================================================
#
# Executed inside the sysimage build so that StructuralSynthesizer and
# register_routes! (and the code paths they touch) are compiled into the
# custom sysimage. This matches the build-time warmup used in the Dockerfile.
#
# Usage: only via PackageCompiler (precompile_execution_file).
# =============================================================================

using StructuralSynthesizer
Base.invokelatest(register_routes!)
@info "Sysimage precompile: StructuralSynthesizer + register_routes! done"
