# Test Opportunities from Reference Documents

This document catalogues test opportunities extracted from the StructurePoint and AISC reference documents that have been converted to text format.

---

## ✅ ALREADY IMPLEMENTED

### Flat Plate Design (StructurePoint)
- **File**: `test/slabs/test_flat_plate.jl`
- **Reference**: `DE-Two-Way-Flat-Plate-Concrete-Floor-System-Analysis-and-Design-ACI-318-14-spSlab-v1000.txt`
- **Status**: Updated to use 18×14 ft panel example

### Column P-M Interaction (StructurePoint)
- **File**: `test/concrete_column/test_column_pm.jl`
- **Reference**: `Interaction-Diagram-Tied-Reinforced-Concrete-Column-Design-Strength-ACI-318-19.txt`
- **Status**: Verified correct

### Steel AISC Design
- **File**: `test/steel_member/test_aisc_*.jl`
- **Reference**: `aisc_companion_manual_1.pdf` and `txt_extracts/`
- **Status**: Basic tests implemented

---

## 🔵 STRUCTUREPOINT - NEW TEST OPPORTUNITIES

### 1. Flat Slab with Drop Panels
**Reference**: `DE-Two-Way-Flat-Slab-Concrete-Floor-with-Drop-Panels...txt`

**Key Test Values**:
- Panel: variable spans
- f'c = 5,000 psi (slab), 6,000 psi (columns)
- fy = 60,000 psi
- SDL = 20 psf, LL = 60 psf
- Story height = 13 ft
- Drop panel design and punching shear around drop panels

**Tests to Add**:
- [ ] Drop panel thickness requirements
- [ ] Punching shear at column face vs drop panel edge
- [ ] Moment transfer with drop panels

---

### 2. One-Way Slab Design
**Reference**: `DE-One-Way-Slab-ACI-14-spBeam-v1000.txt`

**Key Test Values**:
- f'c = 4,000 psi, fy = 60,000 psi
- SDL = 20 psf, LL = 80 psf
- End bay: h_min = l/24
- Interior bay: h_min = l/28
- Slab thickness = 7 in
- #4 bars, clear cover = 0.75 in

**Tests to Add**:
- [ ] One-way slab minimum thickness (ACI Table 7.3.1.1)
- [ ] Moment coefficients (ACI 6.5)
- [ ] Transverse reinforcement at girders
- [ ] Shear at d from support

---

### 3. Simply Supported RC Beam
**Reference**: `DE-Simply-Supported-Reinforced-Concrete-Beam-Analysis-and-Design-ACI-318-14-spBeam-v1000.txt`

**Key Test Values**:
- f'c = 4.35 ksi, fy = 60 ksi
- DL = 0.82 kip/ft, LL = 1.00 kip/ft
- L = 25 ft
- h = 20 in, b = 12 in
- d = 17.56 in
- wu = 2.58 kip/ft
- Vu = 32.30 kip
- Mu = 201.88 kip-ft
- #9 longitudinal, #3 stirrups, cover = 1.5 in

**Tests to Add**:
- [ ] Beam flexural design (As calculation)
- [ ] Shear design (stirrup spacing)
- [ ] Deflection (immediate and long-term)
- [ ] Minimum reinforcement ratios

---

### 4. Continuous RC Beam
**Reference**: `Reinforced Concrete Continuous Beam Analysis and Design (ACI 318-14).txt`

**Tests to Add**:
- [ ] Moment redistribution
- [ ] Negative moment design
- [ ] Stirrup design at supports

---

### 5. Doubly Reinforced Beam
**Reference**: `DE-Doubly-Reinforced-Concrete-Beam-Design-ACI-318-14-spBeam-v1000.txt`

**Tests to Add**:
- [ ] Compression reinforcement calculations
- [ ] Strain compatibility
- [ ] Moment capacity with compression steel

---

### 6. Cantilever Beam
**Reference**: `DE-Reinforced-Concrete-Cantilever-Beam-Analysis-and-Design-ACI-318-14-spBeam-v1000.txt`

**Tests to Add**:
- [ ] Cantilever moment and shear
- [ ] Top reinforcement requirements
- [ ] Deflection at free end

---

### 7. Wide Module Skip Joist (One-Way Joist)
**Reference**: `DE-Wide-Module-Skip-Joist-ACI-14-spBeam-v1000.txt`

**Tests to Add**:
- [ ] Joist rib width and depth
- [ ] Distribution rib requirements
- [ ] Shear in joist ribs

---

### 8. Two-Way Slab with Beams
**Reference**: `DE-Two-Way-Concrete-Floor-Slab-with-Beams-System-Analysis-and-Design-ACI-318-14-spSlab-v1000.txt`

**Tests to Add**:
- [ ] Beam stiffness ratio αf
- [ ] Moment distribution with beams
- [ ] Beam torsion

---

### 9. Waffle Slab (Two-Way Joist)
**Reference**: `DE-Two-Way-Joist-Concrete-Slab-Floor-Waffle-Slab-System-Analysis-and-Design-ACI-318-14-spSlab-v1000.txt`

**Tests to Add**:
- [ ] Rib dimensions
- [ ] Solid head sizing
- [ ] Form module selection

---

### 10. Additional Column Examples
**Reference**: Various column files in `aci/reference/columns/`

- Biaxial bending (rectangular, square, circular)
- Slender columns (sway and non-sway)
- High-strength reinforcement
- Manual design procedures

---

## 🔶 AISC DESIGN MANUAL - NEW TEST OPPORTUNITIES

### Tension Members (Chapter D)

#### Example D.1 - W-Shape Tension (W8×21)
**Already implemented** in `test_aisc_companion_manual_1.jl`
- φPn_yield = 277 kips (LRFD)
- φPn_rupture = 211 kips (Ae = 4.32 in²)
- L/r = 238 < 300

#### Example D.2 - Single Angle Tension (L4×4×½)
**Values**:
- Ag = 3.75 in², rz = 0.776 in
- Fy = 50 ksi, Fu = 65 ksi
- Pu = 120 kips (LRFD)
- φPn_yield = 169 kips
- φPn_rupture = 140 kips (U = 0.869)

**Tests to Add**:
- [ ] Single angle net area with bolt holes
- [ ] Shear lag factor U (Table D3.1)
- [ ] Slenderness limit calculation

#### Example D.3 - WT-Shape Tension (WT6×20)
**Values**:
- Ag = 5.84 in², rx = 1.57 in
- Pu = 240 kips (LRFD)
- φPn_yield = 263 kips
- φPn_rupture = 245 kips (U = 0.860)

**Tests to Add**:
- [ ] WT shear lag with welded connection
- [ ] Connection length effects on U

#### Example D.6 - Double Angle Tension (2L4×4×½)
**Values**:
- PD = 40 kips, PL = 120 kips
- L = 25 ft

---

### Compression Members (Chapter E)

#### Example E.1A - W-Shape Column Pinned (W14×82)
**Values**:
- Ag = 24.0 in², Fy = 50 ksi
- KL = 30 ft (pinned-pinned)
- φPn = 692 kips (LRFD)

#### Example E.1C - W14×132 Column
**Values**:
- Ag = 38.8 in²
- Lcy/ry = 95.7
- φcFn = 23.0 ksi (LRFD)
- φPn = 892 kips

#### Example E.1D - W14×90 Column
**Values**:
- Ag = 26.5 in², rx = 6.14 in, ry = 3.70 in
- Lcx = 30 ft, Lcy = 15 ft
- Lcx/rx = 58.6 (governs)
- Fe = 83.3 ksi
- Fn = 38.9 ksi
- φPn = 927 kips (LRFD)

**Tests to Add**:
- [ ] Elastic buckling stress Fe calculation
- [ ] Inelastic buckling Fcr
- [ ] Slenderness check (λr limits)
- [ ] Weak vs strong axis buckling

#### Example E.4A - Moment Frame Column (W14×82)
**Values**:
- K = 1.5 (from alignment chart)
- Lcx = 21.0 ft (equivalent)
- φPn = 940 kips @ Lc = 9 ft

**Tests to Add**:
- [ ] Effective length factor K from alignment chart
- [ ] Stiffness reduction factor τb
- [ ] Sidesway uninhibited frames

---

### Flexure Members (Chapter F)

#### Example F.1-1A - W-Shape Continuously Braced
**Tests to Add**:
- [ ] Compact section Mp
- [ ] Plastic section modulus Zx

#### Example F.1-2 - Braced at Third Points
**Tests to Add**:
- [ ] LTB with Lb = L/3
- [ ] Cb modification factor

#### Example F.1-3 - Braced at Midspan
**Tests to Add**:
- [ ] LTB with Lb = L/2
- [ ] Moment gradient effects

#### Example F.3 - Noncompact Flanges
**Tests to Add**:
- [ ] FLB (Flange Local Buckling)
- [ ] Noncompact limit states

---

### Shear (Chapter G)

#### Example G.1 - W-Shape Major Axis Shear (W24×62)
**Already implemented** in `test_aisc_companion_manual_1.jl`
- Vn = 306 kips
- Cv1 = 1.0, φv = 1.0

**Tests to Add**:
- [ ] Channel shear (Example G.2)
- [ ] Minor axis shear (Example G.6)

---

### Combined Forces (Chapter H)

#### Example H.1 - Combined Compression and Bending (Braced Frame)
**Tests to Add**:
- [ ] H1-1a interaction equation (Pr/Pc ≥ 0.2)
- [ ] H1-1b interaction equation (Pr/Pc < 0.2)

#### Example H.2 - Combined P-M (Specification H2)
**Tests to Add**:
- [ ] Alternative interaction per H2

#### Example H.3 - Combined Tension and Flexure
**Tests to Add**:
- [ ] Tension-bending interaction

---

### Connections (Chapter J)

#### Example J.1 - Fillet Weld in Longitudinal Shear
**Tests to Add**:
- [ ] Weld strength per inch
- [ ] Effective throat calculation

#### Example J.3 - Combined Tension and Shear (Bearing)
**Tests to Add**:
- [ ] Bolt shear-tension interaction

#### Example J.4 - Slip-Critical Connections
**Tests to Add**:
- [ ] Slip resistance
- [ ] Hole factor

---

## Priority Recommendations

### High Priority (Core Functionality)
1. **One-Way Slab** - Foundation for joist systems
2. **Simply Supported RC Beam** - Core beam design
3. **Compression E.1D** - Full column calculation verification
4. **Flexure F.1** - Full beam flexure verification

### Medium Priority (Extended Capability)
5. **Drop Panel Slab** - Important for punching shear
6. **Continuous RC Beam** - Multi-span structures
7. **Combined Forces H.1** - Beam-column interaction

### Lower Priority (Future Features)
8. **Waffle Slab** - Specialized floor system
9. **Connections** - Detailed connection design
10. **Slender Columns** - Advanced column design

---

## File Locations

### StructurePoint References
- Slabs: `src/slabs/codes/concrete/reference/`
- Beams: `src/members/codes/aci/reference/beams/`
- Columns: `src/members/codes/aci/reference/columns/`

### AISC References
- Main: `src/members/codes/aisc/reference/`
- Extracts: `src/members/codes/aisc/reference/txt_extracts/`
