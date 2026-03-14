using System;
using System.Reflection;
using Grasshopper.Kernel;
using Grasshopper.Kernel.Attributes;

namespace Menegroth.GH.Components
{
    /// <summary>
    /// Custom attributes for the Visualization component so that Utilization Gradient
    /// and Deflection Gradient inputs are folded by default and only appear when the
    /// user expands the component (clicks the + button).
    /// </summary>
    public class VisualizationAttributes : GH_ComponentAttributes
    {
        private const int VisibleInputsWhenFolded = 4; // Result, Mode, Scale, Color By

        public VisualizationAttributes(IGH_Component owner) : base(owner)
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
                var type = GetType().BaseType; // GH_ComponentAttributes
                while (type != null && type.Name != "GH_ComponentAttributes")
                    type = type?.BaseType;
                if (type == null) return;

                // Common possible field names for "how many inputs to show when folded"
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
                        field.SetValue(this, true); // folded = true
                        return;
                    }
                }
            }
            catch
            {
                // Ignore: component still works, gradient inputs just stay visible by default.
            }
        }
    }
}
