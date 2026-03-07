module StructuralVisualization

using StructuralSynthesizer
import Asap
import GLMakie
import Graphs
import Meshes
import StructuralPlots
import LinearAlgebra: norm, normalize
using Unitful

include("visualization/_visualization.jl")

export visualize
export visualize_cell_groups, visualize_cell_tributary, visualize_cell_tributaries
export visualize_vertex_tributaries, visualize_tributaries_combined
export vis_embodied_carbon_summary
export draw_slab!, draw_slabs!, draw_vault!, draw_vault_deflected!
export slab_info, slab_summary_text
export visualize_vault

end # module StructuralVisualization
