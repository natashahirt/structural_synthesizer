using System;
using Grasshopper.Kernel.Types;

namespace StructuralSizer.GH.Types
{
    /// <summary>
    /// Grasshopper Goo wrapper for <see cref="SizerGeometry"/>.
    /// Enables clean wiring between GH components.
    /// </summary>
    public class GH_SizerGeometry : GH_Goo<SizerGeometry>
    {
        public GH_SizerGeometry() { Value = new SizerGeometry(); }
        public GH_SizerGeometry(SizerGeometry geo) { Value = geo; }
        public GH_SizerGeometry(GH_SizerGeometry other) { Value = other.Value; }

        public override bool IsValid => Value != null && Value.Vertices.Count >= 4;
        public override string TypeName => "SizerGeometry";
        public override string TypeDescription => "Building geometry for structural sizing";

        public override IGH_Goo Duplicate() => new GH_SizerGeometry(this);

        public override string ToString()
        {
            if (Value == null) return "Null SizerGeometry";
            return $"SizerGeometry ({Value.Vertices.Count} vertices, " +
                   $"{Value.BeamEdges.Count} beams, {Value.ColumnEdges.Count} columns)";
        }
    }
}
