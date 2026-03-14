using System.Reflection;
using Grasshopper.Kernel;
using Grasshopper.Kernel.Attributes;

namespace Menegroth.GH.Components
{
    /// <summary>
    /// Custom attributes for the Design Params component so that only the generic
    /// "Params" input is visible when folded; "Slab Params" and "Foundation Params"
    /// appear when the user expands the component (clicks the + button).
    /// </summary>
    public class DesignParamsAttributes : GH_ComponentAttributes
    {
        /// <summary>Inputs 0-6 visible when folded (loads + Params). Inputs 7-8 (Slab / Foundation Params) show when expanded.</summary>
        private const int VisibleInputsWhenFolded = 7;

        public DesignParamsAttributes(IGH_Component owner) : base(owner)
        {
            SetFoldedInputCount(VisibleInputsWhenFolded);
        }

        /// <summary>
        /// Try to set the number of input parameters visible when the component is folded.
        /// Uses reflection because the SDK does not expose this publicly.
        /// </summary>
        private void SetFoldedInputCount(int count)
        {
            try
            {
                var type = GetType().BaseType;
                while (type != null && type.Name != "GH_ComponentAttributes")
                    type = type?.BaseType;
                if (type == null) return;

                string[] candidates = { "m_foldedInputCount", "m_initialFoldedInputCount", "m_collapsedInputCount", "m_folded" };
                foreach (var name in candidates)
                {
                    var field = type.GetField(name, BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public);
                    if (field == null) continue;
                    if (field.FieldType == typeof(int))
                    {
                        field.SetValue(this, count);
                        return;
                    }
                    if (field.FieldType == typeof(bool) && count > 0)
                    {
                        field.SetValue(this, true);
                        return;
                    }
                }
            }
            catch
            {
                // Component still works; optional params stay visible by default.
            }
        }
    }
}
