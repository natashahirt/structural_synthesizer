using System;
using Grasshopper.Kernel.Types;

namespace StructuralSizer.GH.Types
{
    /// <summary>
    /// Grasshopper Goo wrapper for <see cref="SizerParams"/>.
    /// Enables clean wiring between GH components.
    /// </summary>
    public class GH_SizerParams : GH_Goo<SizerParams>
    {
        public GH_SizerParams() { Value = new SizerParams(); }
        public GH_SizerParams(SizerParams p) { Value = p; }
        public GH_SizerParams(GH_SizerParams other) { Value = other.Value; }

        public override bool IsValid => Value != null;
        public override string TypeName => "SizerParams";
        public override string TypeDescription => "Design parameters for structural sizing";

        public override IGH_Goo Duplicate() => new GH_SizerParams(this);

        public override string ToString()
        {
            if (Value == null) return "Null SizerParams";
            return $"SizerParams (floor={Value.FloorType}, concrete={Value.Concrete})";
        }
    }
}
