# AISC 360 Chapter H - Combined Forces

"""P-M interaction check (H1-1). Returns utilization ratio."""
function check_PM_interaction(Pu, Mu, ϕPn, ϕMn; Pr=Pu, Mr=Mu)
    if Pr / ϕPn >= 0.2
        return Pr / ϕPn + 8/9 * (Mr / ϕMn)
    else
        return Pr / (2 * ϕPn) + Mr / ϕMn
    end
end

"""P-M interaction with computed capacities."""
function check_PM_interaction(s::ISymmSection, mat::Metal, Pu, Mu, Lb, Lc; 
                              axis=:weak, Cb=1.0, ϕ=0.90)
    ϕPn = get_ϕPn(s, mat, Lc; axis=axis, ϕ=ϕ)
    # Default to strong axis flexure for the simple P-M check unless context implies otherwise.
    # But usually P-M check is done with specific M and capacity.
    # Here we assume M is strong axis moment for simple cases.
    ϕMn = get_ϕMn(s, mat; Lb=Lb, Cb=Cb, axis=:strong, ϕ=ϕ)
    return check_PM_interaction(Pu, Mu, ϕPn, ϕMn)
end

"""Biaxial P-Mx-My interaction check (H1-2). Returns utilization ratio."""
function check_PMxMy_interaction(Pu, Mux, Muy, ϕPn, ϕMnx, ϕMny; Pr=Pu, Mrx=Mux, Mry=Muy)
    if Pr / ϕPn >= 0.2
        return Pr / ϕPn + 8/9 * (Mrx / ϕMnx + Mry / ϕMny)
    else
        return Pr / (2 * ϕPn) + Mrx / ϕMnx + Mry / ϕMny
    end
end

"""Biaxial interaction with computed capacities."""
function check_PMxMy_interaction(s::ISymmSection, mat::Metal, Pu, Mux, Muy, Lbx, Lby, Lc;
                                 axis=:weak, Cb=1.0, ϕ=0.90)
    ϕMnx = get_ϕMn(s, mat; Lb=Lbx, Cb=Cb, axis=:strong, ϕ=ϕ)
    ϕMny = get_ϕMn(s, mat; Lb=Lby, axis=:weak, ϕ=ϕ)
    ϕPn = get_ϕPn(s, mat, Lc; axis=axis, ϕ=ϕ)
    return check_PMxMy_interaction(Pu, Mux, Muy, ϕPn, ϕMnx, ϕMny)
end
