using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows.Forms;
using Grasshopper.Kernel;
using Grasshopper.Kernel.Types;
using Menegroth.GH.Types;

namespace Menegroth.GH.Components
{
    /// <summary>
    /// Packages design parameters for the structural sizing API.
    ///
    /// Numeric inputs (loads) are wired inputs with defaults.
    /// All enum-like selections are embedded in nested right-click menus —
    /// no external ValueList components needed.
    ///
    /// Menu structure:
    ///   Slab Params ▸ Floor System ▸ Flat Plate ▸ Analysis Method ▸ ...
    ///                                    ▸ Punching Strategy ▸ ...
    ///               ▸ Flat Slab ▸ ...
    ///               ▸ One-Way, Vault
    ///               ▸ Deflection Limit ▸ ...
    ///   Columns ▸ Type ▸ ...
    ///   Beams ▸ Type ▸ ...
    ///   Materials ▸ Concrete ▸ ...
    ///   Design ▸ Optimize For ▸ ...
    ///          ▸ Fire Rating ▸ ...
    ///   Foundation Params ▸ Size Foundations ▸ Soil Type ▸ ...
    ///   Units ▸ ...
    ///
    /// Override hierarchy when multiple params conflict: geometry-scoped overrides general;
    /// Slab Params / Foundation Params (specific inputs) override generic Params; earlier in a list overrides later.
    /// </summary>
    public class DesignParams : GH_Component
    {
        // ─── Persisted dropdown state ────────────────────────────────────
        private string _floorType = "flat_plate";
        private string _method = "DDM";
        private string _deflLimit = "L_360";
        private string _punchStrat = "grow_columns";
        private string _concrete = "NWC_4000";
        private string _rebar = "Rebar_60";
        private string _steel = "A992";
        private string _columnType = "rc_rect";
        private string _beamType = "steel_w";
        private string _beamCatalog = "large";
        private string _optimizeFor = "weight";
        private string _fireRating = "0";
        private bool _sizeFoundations = true;
        private string _foundationSoil = "medium_sand";
        private string _unitSystem = "imperial";

        // ─── Choice tables ───────────────────────────────────────────────

        private static readonly Choice[] FloorTypes =
        {
            new("Flat Plate",  "flat_plate"),
            new("Flat Slab",   "flat_slab"),
            new("One-Way",     "one_way"),
            new("Vault",       "vault"),
        };

        private static readonly Choice[] Methods =
        {
            new("DDM",               "DDM"),
            new("DDM (Simplified)",  "DDM_SIMPLIFIED"),
            new("EFM",              "EFM"),
            new("EFM (Hardy Cross)", "EFM_HARDY_CROSS"),
            new("FEA",              "FEA"),
        };

        private static readonly Choice[] DeflLimits =
        {
            new("L / 240  (total after attachment)",  "L_240"),
            new("L / 360  (immediate live load)",     "L_360"),
            new("L / 480  (sensitive elements)",      "L_480"),
        };

        private static readonly Choice[] PunchStrategies =
        {
            new("Grow Columns Only",             "grow_columns"),
            new("Grow First → Reinforce Last",   "reinforce_last"),
            new("Reinforce First → Grow Last",   "reinforce_first"),
        };

        private static readonly Choice[] Concretes =
        {
            new("NWC 3000 psi", "NWC_3000"),
            new("NWC 4000 psi", "NWC_4000"),
            new("NWC 5000 psi", "NWC_5000"),
            new("NWC 6000 psi", "NWC_6000"),
        };

        private static readonly Choice[] Rebars =
        {
            new("Grade 40", "Rebar_40"),
            new("Grade 60", "Rebar_60"),
            new("Grade 75", "Rebar_75"),
            new("Grade 80", "Rebar_80"),
        };

        private static readonly Choice[] Steels =
        {
            new("A992", "A992"),
        };

        private static readonly Choice[] ColumnTypes =
        {
            new("RC Rectangular", "rc_rect"),
            new("RC Circular",   "rc_circular"),
            new("Steel W-shape",  "steel_w"),
            new("Steel HSS",     "steel_hss"),
            new("Steel Pipe",    "steel_pipe"),
        };

        private static readonly Choice[] BeamTypes =
        {
            new("Steel W-shape",  "steel_w"),
            new("Steel HSS",     "steel_hss"),
            new("RC Rectangular", "rc_rect"),
            new("RC T-beam",     "rc_tbeam"),
        };

        private static readonly Choice[] BeamCatalogs =
        {
            new("Standard (light–moderate loads)", "standard"),
            new("Small (light loads)",             "small"),
            new("Large (heavy loads, vaults)",     "large"),
            new("All (comprehensive)",             "all"),
        };

        private static readonly Choice[] Objectives =
        {
            new("Weight", "weight"),
            new("Carbon", "carbon"),
            new("Cost",   "cost"),
        };

        private static readonly Choice[] FireRatings =
        {
            new("None",     "0"),
            new("1 hour",   "1"),
            new("1.5 hour", "1.5"),
            new("2 hour",   "2"),
            new("3 hour",   "3"),
            new("4 hour",   "4"),
        };

        private static readonly Choice[] SoilTypes =
        {
            new("Loose Sand  (qa=75 kPa)",   "loose_sand"),
            new("Medium Sand (qa=150 kPa)",  "medium_sand"),
            new("Dense Sand  (qa=300 kPa)",  "dense_sand"),
            new("Soft Clay   (qa=50 kPa)",   "soft_clay"),
            new("Stiff Clay  (qa=150 kPa)",  "stiff_clay"),
            new("Hard Clay   (qa=300 kPa)",  "hard_clay"),
        };

        private static readonly Choice[] UnitSystems =
        {
            new("Imperial", "imperial"),
            new("Metric",   "metric"),
        };

        // ─── Constructor ─────────────────────────────────────────────────
        public DesignParams()
            : base("Design Params",
                   "DesignParams",
                   "Configure design parameters for structural sizing",
                   "Menegroth", "   Input")
        { }

        public override Guid ComponentGuid =>
            new Guid("75125D15-612B-495B-9544-AC4C08EBB8CE");

        public override void CreateAttributes()
        {
            m_attributes = new DesignParamsAttributes(this);
        }

        // ─── Wired inputs (numeric only) ─────────────────────────────────
        protected override void RegisterInputParams(GH_InputParamManager pManager)
        {
            pManager.AddNumberParameter("Floor LL (psf)", "Floor LL",
                "Floor live load in psf", GH_ParamAccess.item, 80.0);

            pManager.AddNumberParameter("Roof LL (psf)", "Roof LL",
                "Roof live load in psf", GH_ParamAccess.item, 20.0);

            pManager.AddNumberParameter("Floor SDL (psf)", "Floor SDL",
                "Floor superimposed dead load in psf", GH_ParamAccess.item, 15.0);

            pManager.AddNumberParameter("Roof SDL (psf)", "Roof SDL",
                "Roof superimposed dead load in psf", GH_ParamAccess.item, 15.0);

            pManager.AddNumberParameter("Grade LL (psf)", "Grade LL",
                "Grade-level live load in psf", GH_ParamAccess.item, 100.0);

            pManager.AddNumberParameter("Wall SDL (psf)", "Wall SDL",
                "Wall superimposed dead load in psf", GH_ParamAccess.item, 10.0);

            pManager.AddGenericParameter("Params", "Params",
                "Optional overrides (VaultParams, future FoundationParams). Expand (+) for Slab Params / Foundation Params.",
                GH_ParamAccess.list);
            pManager[6].Optional = true;

            pManager.AddGenericParameter("Slab Params", "Slab",
                "Optional slab/floor overrides (e.g. VaultParams). Shown when component is expanded.",
                GH_ParamAccess.list);
            pManager[7].Optional = true;

            pManager.AddGenericParameter("Foundation Params", "Foundation",
                "Optional foundation overrides. Reserved for future use. Shown when component is expanded.",
                GH_ParamAccess.list);
            pManager[8].Optional = true;
        }

        protected override void RegisterOutputParams(GH_OutputParamManager pManager)
        {
            pManager.AddGenericParameter("Params", "Params",
                "DesignParams for the Design Run component",
                GH_ParamAccess.item);

            pManager.AddTextParameter("Summary", "Summary",
                "Human-readable summary for debugging and agent context; includes API values",
                GH_ParamAccess.item);
        }

        // ─── Nested right-click menu ─────────────────────────────────────
        protected override void AppendAdditionalComponentMenuItems(ToolStripDropDown menu)
        {
            base.AppendAdditionalComponentMenuItems(menu);
            Menu_AppendSeparator(menu);

            // ── Slab Params ▸ Floor System ▸ ──
            var slabParamsMenu = Menu_AppendItem(menu, "Slab Params");
            var floorMenu = Menu_AppendItem(slabParamsMenu.DropDown, "Floor System");

            // Floor types as direct children
            foreach (var ft in FloorTypes)
            {
                var ftItem = new ToolStripMenuItem(ft.Label)
                {
                    Checked = _floorType == ft.Value,
                    Tag = new ChoiceTag { Field = "Floor Type", Value = ft.Value }
                };
                ftItem.Click += OnChoiceClicked;
                floorMenu.DropDownItems.Add(ftItem);

                // Add sub-options for Flat Plate and Flat Slab
                if (ft.Value == "flat_plate" || ft.Value == "flat_slab")
                {
                    // Analysis Method submenu
                    string methodLabel = LabelFor(Methods, _method);
                    var methodSub = new ToolStripMenuItem($"Analysis Method: {methodLabel}");
                    ftItem.DropDownItems.Add(methodSub);

                    foreach (var m in Methods)
                    {
                        var mItem = new ToolStripMenuItem(m.Label)
                        {
                            Checked = _method == m.Value,
                            Tag = new ChoiceTag { Field = "Analysis Method", Value = m.Value }
                        };
                        mItem.Click += OnChoiceClicked;
                        methodSub.DropDownItems.Add(mItem);
                    }

                    // Punching Strategy submenu
                    string punchLabel = LabelFor(PunchStrategies, _punchStrat);
                    var punchSub = new ToolStripMenuItem($"Punching Strategy: {punchLabel}");
                    ftItem.DropDownItems.Add(punchSub);

                    foreach (var p in PunchStrategies)
                    {
                        var pItem = new ToolStripMenuItem(p.Label)
                        {
                            Checked = _punchStrat == p.Value,
                            Tag = new ChoiceTag { Field = "Punching Strategy", Value = p.Value }
                        };
                        pItem.Click += OnChoiceClicked;
                        punchSub.DropDownItems.Add(pItem);
                    }
                }
            }

            Menu_AppendSeparator(floorMenu.DropDown);

            // Deflection Limit (shared across all floor types)
            AddSubChoices(floorMenu, "Deflection Limit", DeflLimits, _deflLimit);

            // ── Columns ▸ ──
            var colMenu = Menu_AppendItem(menu, "Columns");
            AddSubChoices(colMenu, "Column Type", ColumnTypes, _columnType);

            // ── Beams ▸ ──
            var beamMenu = Menu_AppendItem(menu, "Beams");
            AddSubChoices(beamMenu, "Beam Type", BeamTypes, _beamType);
            AddSubChoices(beamMenu, "RC Catalog", BeamCatalogs, _beamCatalog);

            // ── Materials ▸ ──
            var matMenu = Menu_AppendItem(menu, "Materials");
            AddSubChoices(matMenu, "Concrete", Concretes, _concrete);
            AddSubChoices(matMenu, "Rebar",    Rebars,    _rebar);
            AddSubChoices(matMenu, "Steel",    Steels,    _steel);

            // ── Design ▸ ──
            var designMenu = Menu_AppendItem(menu, "Design");
            AddSubChoices(designMenu, "Optimize For", Objectives,  _optimizeFor);
            AddSubChoices(designMenu, "Fire Rating",  FireRatings, _fireRating);

            // ── Foundation Params ▸ ──
            var fdnMenu = Menu_AppendItem(menu, "Foundation Params");

            var fdnToggle = new ToolStripMenuItem("Size Foundations")
            {
                Checked = _sizeFoundations,
                CheckOnClick = true
            };
            fdnToggle.CheckedChanged += (s, _) =>
            {
                _sizeFoundations = ((ToolStripMenuItem)s).Checked;
                UpdateMessage();
                ExpireSolution(true);
            };
            fdnMenu.DropDownItems.Add(fdnToggle);

            fdnMenu.DropDownItems.Add(new ToolStripSeparator());
            AddSubChoices(fdnMenu, "Soil Type", SoilTypes, _foundationSoil);

            Menu_AppendSeparator(menu);

            // ── Units (displayed under component, same pattern as Geometry Input) ──
            var unitsMenu = Menu_AppendItem(menu, "Units");
            foreach (var choice in UnitSystems)
            {
                var item = new ToolStripMenuItem(choice.Label)
                {
                    Checked = _unitSystem == choice.Value,
                    Tag = choice.Value
                };
                item.Click += (s, e) =>
                {
                    _unitSystem = (string)((ToolStripMenuItem)s).Tag;
                    UpdateMessage();
                    ExpireSolution(true);
                };
                unitsMenu.DropDownItems.Add(item);
            }
        }

        /// <summary>
        /// Build a 2nd-level submenu: parent ▸ title ▸ [choices with checkmarks]
        /// </summary>
        private void AddSubChoices(
            ToolStripMenuItem parent,
            string title,
            Choice[] choices,
            string currentValue)
        {
            string currentLabel = choices.FirstOrDefault(c => c.Value == currentValue)?.Label ?? currentValue;
            var sub = new ToolStripMenuItem($"{title}: {currentLabel}");
            parent.DropDownItems.Add(sub);

            foreach (var choice in choices)
            {
                var item = new ToolStripMenuItem(choice.Label)
                {
                    Checked = choice.Value == currentValue,
                    Tag = new ChoiceTag { Field = title, Value = choice.Value }
                };
                item.Click += OnChoiceClicked;
                sub.DropDownItems.Add(item);
            }
        }

        private void OnChoiceClicked(object sender, EventArgs e)
        {
            var tag = (ChoiceTag)((ToolStripMenuItem)sender).Tag;

            switch (tag.Field)
            {
                case "Floor Type":        _floorType   = tag.Value; break;
                case "Analysis Method":   _method      = tag.Value; break;
                case "Deflection Limit":  _deflLimit   = tag.Value; break;
                case "Punching Strategy": _punchStrat  = tag.Value; break;
                case "Concrete":          _concrete    = tag.Value; break;
                case "Rebar":             _rebar       = tag.Value; break;
                case "Steel":             _steel        = tag.Value; break;
                case "Column Type":       _columnType  = tag.Value; break;
                case "Beam Type":         _beamType    = tag.Value; break;
                case "RC Catalog":         _beamCatalog = tag.Value; break;
                case "Optimize For":      _optimizeFor = tag.Value; break;
                case "Fire Rating":       _fireRating  = tag.Value; break;
                case "Soil Type":         _foundationSoil = tag.Value; break;
            }

            UpdateMessage();
            ExpireSolution(true);
        }

        // ─── Persistence ─────────────────────────────────────────────────
        public override bool Write(GH_IO.Serialization.GH_IWriter writer)
        {
            writer.SetString("FloorType",   _floorType);
            writer.SetString("Method",      _method);
            writer.SetString("DeflLimit",   _deflLimit);
            writer.SetString("PunchStrat",  _punchStrat);
            writer.SetString("Concrete",    _concrete);
            writer.SetString("Rebar",       _rebar);
            writer.SetString("Steel",       _steel);
            writer.SetString("ColumnType",  _columnType);
            writer.SetString("BeamType",    _beamType);
            writer.SetString("BeamCatalog", _beamCatalog);
            writer.SetString("OptimizeFor", _optimizeFor);
            writer.SetString("FireRating",  _fireRating);
            writer.SetBoolean("SizeFoundations", _sizeFoundations);
            writer.SetString("FoundationSoil", _foundationSoil);
            writer.SetString("UnitSystem",  _unitSystem);
            return base.Write(writer);
        }

        public override bool Read(GH_IO.Serialization.GH_IReader reader)
        {
            if (reader.ItemExists("FloorType"))   _floorType   = reader.GetString("FloorType");
            if (reader.ItemExists("Method"))       _method      = reader.GetString("Method");
            if (reader.ItemExists("DeflLimit"))    _deflLimit   = reader.GetString("DeflLimit");
            if (reader.ItemExists("PunchStrat"))   _punchStrat  = reader.GetString("PunchStrat");
            if (reader.ItemExists("Concrete"))     _concrete    = reader.GetString("Concrete");
            if (reader.ItemExists("Rebar"))        _rebar       = reader.GetString("Rebar");
            if (reader.ItemExists("Steel"))        _steel       = reader.GetString("Steel");
            if (reader.ItemExists("ColumnType"))   _columnType  = reader.GetString("ColumnType");
            if (reader.ItemExists("BeamType"))     _beamType    = reader.GetString("BeamType");
            if (reader.ItemExists("BeamCatalog"))  _beamCatalog = reader.GetString("BeamCatalog");
            if (reader.ItemExists("OptimizeFor"))  _optimizeFor = reader.GetString("OptimizeFor");
            if (reader.ItemExists("FireRating"))   _fireRating  = reader.GetString("FireRating");
            if (reader.ItemExists("SizeFoundations")) _sizeFoundations = reader.GetBoolean("SizeFoundations");
            if (reader.ItemExists("FoundationSoil"))  _foundationSoil  = reader.GetString("FoundationSoil");
            if (reader.ItemExists("UnitSystem"))   _unitSystem  = reader.GetString("UnitSystem");
            UpdateMessage();
            return base.Read(reader);
        }

        // ─── Message bar ─────────────────────────────────────────────────
        public override void AddedToDocument(GH_Document document)
        {
            base.AddedToDocument(document);
            UpdateMessage();
        }

        private void UpdateMessage()
        {
            var parts = new List<string>
            {
                LabelFor(FloorTypes, _floorType),
                LabelFor(ColumnTypes, _columnType),
                LabelFor(BeamTypes, _beamType),
            };
            if (_sizeFoundations)
                parts.Add("Fdn: " + LabelFor(SoilTypes, _foundationSoil));
            parts.Add(LabelFor(UnitSystems, _unitSystem));
            Message = string.Join(" | ", parts);
        }

        private static string LabelFor(Choice[] choices, string value)
        {
            return choices.FirstOrDefault(c => c.Value == value)?.Label ?? value;
        }

        // ─── Solve ───────────────────────────────────────────────────────
        protected override void SolveInstance(IGH_DataAccess DA)
        {
            double floorLL = 80, roofLL = 20, floorSDL = 15, roofSDL = 15;
            double gradeLL = 100, wallSDL = 10;

            DA.GetData(0, ref floorLL);
            DA.GetData(1, ref roofLL);
            DA.GetData(2, ref floorSDL);
            DA.GetData(3, ref roofSDL);
            DA.GetData(4, ref gradeLL);
            DA.GetData(5, ref wallSDL);
            var paramsList = new List<IGH_Goo>();
            DA.GetDataList(6, paramsList);
            var slabParams = new List<IGH_Goo>();
            DA.GetDataList(7, slabParams);
            var foundationParams = new List<IGH_Goo>();
            DA.GetDataList(8, foundationParams);

            double fireRatingVal = 0;
            if (double.TryParse(_fireRating, System.Globalization.NumberStyles.Any,
                                System.Globalization.CultureInfo.InvariantCulture,
                                out double parsed))
                fireRatingVal = parsed;

            var p = new DesignParamsData
            {
                FloorLL         = floorLL,
                RoofLL          = roofLL,
                FloorSDL        = floorSDL,
                RoofSDL         = roofSDL,
                GradeLL         = gradeLL,
                WallSDL         = wallSDL,
                FireRating      = fireRatingVal,
                FloorType       = _floorType,
                AnalysisMethod  = _method,
                DeflectionLimit = _deflLimit,
                PunchingStrategy = _punchStrat,
                Concrete        = _concrete,
                Rebar           = _rebar,
                Steel           = _steel,
                ColumnType      = _columnType,
                BeamType        = _beamType,
                BeamCatalog     = _beamCatalog,
                OptimizeFor     = _optimizeFor,
                SizeFoundations = _sizeFoundations,
                FoundationSoil  = _foundationSoil,
                UnitSystem      = _unitSystem,
            };

            // Override hierarchy (highest wins): geometry-scoped > Slab/Foundation Params > generic Params; within a list, earlier > later.
            var allOverrides = BuildOverrideList(paramsList, slabParams, foundationParams);
            ApplyOverrides(p, allOverrides);

            DA.SetData(0, new GH_DesignParamsData(p));
            DA.SetData(1, BuildSummary(p));
        }

        /// <summary>
        /// Build a human-readable summary of design parameters for debugging and agent context.
        /// Includes API payload values in parentheses for matching against serialized JSON.
        /// </summary>
        private string BuildSummary(DesignParamsData p)
        {
            var sb = new System.Text.StringBuilder();
            sb.AppendLine("Design Parameters Summary");
            sb.AppendLine("────────────────────────");

            sb.Append("Floor: ").Append(LabelFor(FloorTypes, p.FloorType))
              .Append(" (").Append(p.FloorType).AppendLine(")");
            if (p.FloorType == "flat_plate" || p.FloorType == "flat_slab")
            {
                sb.Append("  Method: ").Append(LabelFor(Methods, p.AnalysisMethod)).Append(" (").Append(p.AnalysisMethod).Append(")");
                sb.Append(" | Deflection: ").Append(LabelFor(DeflLimits, p.DeflectionLimit)).Append(" (").Append(p.DeflectionLimit).Append(")");
                sb.Append(" | Punching: ").Append(LabelFor(PunchStrategies, p.PunchingStrategy)).Append(" (").Append(p.PunchingStrategy).AppendLine(")");
            }
            if (p.FloorType == "vault" && p.VaultLambda.HasValue)
                sb.Append("  Vault λ: ").AppendLine(p.VaultLambda.Value.ToString("F2"));

            sb.Append("Columns: ").Append(LabelFor(ColumnTypes, p.ColumnType))
              .Append(" (").Append(p.ColumnType).AppendLine(")");
            sb.Append("Beams: ").Append(LabelFor(BeamTypes, p.BeamType)).Append(" (").Append(p.BeamType).Append(")");
            if (p.BeamType == "rc_rect" || p.BeamType == "rc_tbeam")
                sb.Append(" | catalog: ").Append(LabelFor(BeamCatalogs, p.BeamCatalog)).Append(" (").Append(p.BeamCatalog).Append(")");
            sb.AppendLine();
            sb.Append("Materials: ").Append(LabelFor(Concretes, p.Concrete)).Append(" (").Append(p.Concrete).Append(")");
            sb.Append(", ").Append(LabelFor(Rebars, p.Rebar)).Append(" (").Append(p.Rebar).Append(")");
            sb.Append(", ").Append(LabelFor(Steels, p.Steel)).Append(" (").Append(p.Steel).AppendLine(")");

            sb.Append("Loads (psf): Floor LL ").Append(p.FloorLL.ToString("F0"));
            sb.Append(", Roof LL ").Append(p.RoofLL.ToString("F0"));
            sb.Append(", SDL ").Append(p.FloorSDL.ToString("F0")).Append("/").Append(p.RoofSDL.ToString("F0"));
            sb.Append(", Grade ").Append(p.GradeLL.ToString("F0"));
            sb.Append(", Wall SDL ").Append(p.WallSDL.ToString("F0")).AppendLine();

            var fireLabel = LabelFor(FireRatings,
                p.FireRating.ToString(System.Globalization.CultureInfo.InvariantCulture));
            sb.Append("Design: Optimize for ").Append(LabelFor(Objectives, p.OptimizeFor)).Append(" (").Append(p.OptimizeFor).Append(")");
            sb.Append(" | Fire rating: ").Append(fireLabel).Append(" (").Append(p.FireRating.ToString("F1")).Append(" hr)").AppendLine();

            if (p.SizeFoundations)
                sb.Append("Foundations: Size (").Append(LabelFor(SoilTypes, p.FoundationSoil))
                  .Append(" / ").Append(p.FoundationSoil).AppendLine(")");
            else
                sb.AppendLine("Foundations: Not sizing");

            sb.Append("Units: ").Append(LabelFor(UnitSystems, p.UnitSystem))
              .Append(" (").Append(p.UnitSystem).AppendLine(")");

            if (p.ScopedVaultOverrides != null && p.ScopedVaultOverrides.Count > 0)
            {
                sb.Append("Scoped vault overrides: ").Append(p.ScopedVaultOverrides.Count).AppendLine(" group(s)");
                for (int i = 0; i < p.ScopedVaultOverrides.Count; i++)
                {
                    var ov = p.ScopedVaultOverrides[i];
                    if (ov == null) continue;
                    int nFaces = ov.Faces?.Count ?? 0;
                    var part = $"  [{i + 1}] {nFaces} face(s)";
                    if (ov.Lambda.HasValue)
                        part += $", λ={ov.Lambda.Value:F2}";
                    sb.AppendLine(part);
                }
            }

            return sb.ToString().TrimEnd();
        }

        /// <summary>
        /// Build override list in application order so that hierarchy is respected:
        /// geometry-scoped overrides general; Slab/Foundation Params override generic Params; earlier overrides later.
        /// List is ordered: generic Params (reversed so earlier wins), then Slab Params (reversed), then Foundation Params (reversed).
        /// </summary>
        private static List<IGH_Goo> BuildOverrideList(
            List<IGH_Goo> paramsList,
            List<IGH_Goo> slabParams,
            List<IGH_Goo> foundationParams)
        {
            var allOverrides = new List<IGH_Goo>(paramsList.Count + slabParams.Count + foundationParams.Count);
            for (int i = paramsList.Count - 1; i >= 0; i--)
                allOverrides.Add(paramsList[i]);
            for (int i = slabParams.Count - 1; i >= 0; i--)
                allOverrides.Add(slabParams[i]);
            for (int i = foundationParams.Count - 1; i >= 0; i--)
                allOverrides.Add(foundationParams[i]);
            return allOverrides;
        }

        /// <summary>Apply all overrides (VaultParams, future FoundationParams). Order reflects hierarchy: later in list wins.</summary>
        private void ApplyOverrides(DesignParamsData target, List<IGH_Goo> allOverrides)
        {
            if (target == null || allOverrides == null || allOverrides.Count == 0)
                return;

            foreach (var goo in allOverrides)
            {
                if (TryGetVaultParams(goo, out var vault))
                {
                    if (vault.Lambda.HasValue && vault.Lambda.Value <= 0.0)
                    {
                        AddRuntimeMessage(GH_RuntimeMessageLevel.Warning,
                            "Ignoring VaultParams override with invalid lambda <= 0.");
                        continue;
                    }
                    if (vault.HasScopedFaces)
                        target.ScopedVaultOverrides.Add(vault.Clone());
                    else
                        vault.ApplyTo(target);
                    continue;
                }
                // Future: if (TryGetFoundationParams(goo, out var fdn)) { ... }
            }
        }

        private static bool TryGetVaultParams(IGH_Goo goo, out VaultParamsData vault)
        {
            vault = null;
            if (goo == null) return false;

            if (goo is GH_VaultParamsData ghVault && ghVault.Value != null)
            {
                vault = ghVault.Value;
                return true;
            }

            if (goo is GH_ObjectWrapper wrapper && wrapper.Value is VaultParamsData wrappedVault)
            {
                vault = wrappedVault;
                return true;
            }

            return false;
        }

        // ─── Helper types ────────────────────────────────────────────────
        private class Choice
        {
            public string Label { get; }
            public string Value { get; }
            public Choice(string label, string value) { Label = label; Value = value; }
        }

        private class ChoiceTag
        {
            public string Field { get; set; } = "";
            public string Value { get; set; } = "";
        }
    }
}
