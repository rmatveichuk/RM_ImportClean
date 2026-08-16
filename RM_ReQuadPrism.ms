-- =========================================================================================
--  RM_ReQuadPrism.ms
--  Module: Watertight Prism Recognition & Regular Quad Mesh Rebuilder
--  STATUS: STANDALONE ARCHIVE (NOT CONNECTED TO PIPELINE)
--
--  METRICS & LIMITATIONS:
--  - Покрытие: 13.6% от выборки сцены (призматические стойки, простые вертикальные профили).
--  - Отказы: #reject_not_prism, #reject_hole, #reject_multi_loop, #reject_flat.
--  - Не покрывает стены с проёмами (окна/двери), полые профили и плоские панели (#reject_flat).
--  - Увеличивает вес сетки (+n граней, где n — число сегментов профиля; для дуговой стены n=88).
--  - Для закрытия открытых рёбер (border=12) достаточно штатного Weld (0.01 мм, F=6, border=0).
-- =========================================================================================

global rm_ic_requad_engine

struct RM_IC_Result
(
    verdict,    -- #accept or #reject
    reason,     -- string explanation / code
    data        -- array with beforeStats, afterStats, beforeArea, afterArea, shifts, areaDelta, h
)

struct RM_IC_PrismEngine
(
    weldTol = 2.0,      -- tolerance (mm) for welding co-located duplicate vertices
    angleTol = 4.0,     -- degrees tolerance for normal orthogonality
    
    -- Computes Newell normal of polygon
    fn faceNormal obj f =
    (
        local vs = polyop.getFaceVerts obj f
        local cnt = vs.count, n = [0,0,0]
        for i = 1 to cnt do
        (
            local a = polyop.getVert obj vs[i]
            local b = polyop.getVert obj vs[(mod i cnt) + 1]
            n.x += (a.y - b.y) * (a.z + b.z)
            n.y += (a.z - b.z) * (a.x + b.x)
            n.z += (a.x - b.x) * (a.y + b.y)
        )
        if (length n) < 1e-9 then [0,0,0] else (normalize n)
    ),
    
    -- Computes true triangulated surface area
    fn getTriangulatedArea obj =
    (
        local m = snapshotAsMesh obj
        local numF = meshop.getNumFaces m
        local totalA = 0.0d0
        for f = 1 to numF do (
            local fv = meshop.getFace m f
            local v1 = meshop.getVert m fv.x
            local v2 = meshop.getVert m fv.y
            local v3 = meshop.getVert m fv.z
            local cr = cross (v2 - v1) (v3 - v1)
            totalA += ((length cr) / 2.0)
        )
        delete m
        totalA
    ),
    
    -- Computes topological properties: V, E, F, chi, borders, nonman, iso, degSum
    fn getTopoStats obj =
    (
        local nv = polyop.getNumVerts obj
        local ne = polyop.getNumEdges obj
        local nf = polyop.getNumFaces obj
        local nBorder = 0, nNonMan = 0, nIso = 0
        for e = 1 to ne do
        (
            local c = (polyop.getEdgeFaces obj e).count
            case of
            (
                (c == 0): nIso += 1
                (c == 1): nBorder += 1
                (c >  2): nNonMan += 1
                default: ()
            )
        )
        local degSum = 0
        for f = 1 to nf do degSum += (polyop.getFaceDeg obj f)
        local chi = nv - ne + nf
        #(nv, ne, nf, chi, nBorder, nNonMan, nIso, degSum)
    ),
    
    -- Two-way Hausdorff distance (old <-> new)
    fn getTwoWayShift objA objB =
    (
        local va = for i = 1 to (polyop.getNumVerts objA) collect (polyop.getVert objA i)
        local vb = for i = 1 to (polyop.getNumVerts objB) collect (polyop.getVert objB i)
        
        local shiftAtoB = 0.0
        for p in va do (
            local best = 1e18
            for q in vb do (local d = length (p - q); if d < best do best = d)
            if best > shiftAtoB do shiftAtoB = best
        )
        
        local shiftBtoA = 0.0
        for p in vb do (
            local best = 1e18
            for q in va do (local d = length (p - q); if d < best do best = d)
            if best > shiftBtoA do shiftBtoA = best
        )
        
        #(shiftAtoB, shiftBtoA, (amax shiftAtoB shiftBtoA))
    ),
    
    -- Classifies open edges into duplicate cracks (#crack) vs true boundary openings (#hole)
    fn checkCracksAndHoles obj tol:2.0 =
    (
        local openEdges = polyop.getOpenEdges obj
        if openEdges.numberSet == 0 do return #closed
        
        local openVerts = (polyop.getVertsUsingEdge obj openEdges) as array
        local vPos = for v in openVerts collect (polyop.getVert obj v)
        
        local hasRealHole = false
        for i = 1 to openVerts.count do (
            local p = vPos[i]
            local hasMatch = false
            for j = 1 to openVerts.count where i != j do (
                if (length (p - vPos[j])) <= tol do (hasMatch = true; exit)
            )
            if not hasMatch do (hasRealHole = true; exit)
        )
        
        if hasRealHole then #hole else #crack
    ),
    
    -- Optional removal of collinear 2-valence vertices (default OFF)
    fn removeCollinearMidVerts obj =
    (
        local nv = polyop.getNumVerts obj
        local toRemove = #{}
        for v = 1 to nv do (
            local edges = (polyop.getEdgesUsingVert obj v) as array
            if edges.count == 2 do (
                local vAdj = (polyop.getVertsUsingEdge obj edges) - #{v}
                local vArr = vAdj as array
                if vArr.count == 2 do (
                    local p0 = polyop.getVert obj v
                    local p1 = polyop.getVert obj vArr[1]
                    local p2 = polyop.getVert obj vArr[2]
                    local d1 = normalize (p1 - p0)
                    local d2 = normalize (p2 - p0)
                    if (dot d1 d2) < -0.999 do toRemove[v] = true
                )
            )
        )
        if toRemove.numberSet > 0 do (
            polyop.setVertSelection obj toRemove
            obj.EditablePoly.Remove selLevel:#Vertex
        )
    ),
    
    -- Core Prism Recognition & Re-Quad Rebuild
    fn processObject obj weldDuplicates:true removeCollinear:false =
    (
        if not (isValidNode obj) do return (RM_IC_Result #reject "Invalid node" undefined)
        
        local isPoly = (classOf obj.baseObject == Editable_Poly)
        if not isPoly do convertToPoly obj
        
        -- Optional: collinear vertex removal (default OFF)
        if removeCollinear do removeCollinearMidVerts obj
        
        -- Weld co-located duplicate vertices
        if weldDuplicates do (
            try (
                obj.weldThreshold = weldTol
                polyop.weldVertsByThreshold obj #{1..(polyop.getNumVerts obj)}
            ) catch()
        )
        
        -- 1. Check for real boundary holes
        local holeStatus = checkCracksAndHoles obj tol:weldTol
        if holeStatus == #hole do (
            return (RM_IC_Result #reject "#reject_hole" undefined)
        )
        
        local beforeStats = getTopoStats obj
        local beforeArea = getTriangulatedArea obj
        
        local nf = polyop.getNumFaces obj
        local nv = polyop.getNumVerts obj
        local ne = polyop.getNumEdges obj
        if nf < 4 or nv < 6 do (
            return (RM_IC_Result #reject "#reject_too_simple" undefined)
        )
        
        local fNormals = for f = 1 to nf collect (faceNormal obj f)
        
        -- 2. Collect candidate extrusion axes
        local candAxes = #()
        for f = 1 to nf do (
            local n = fNormals[f]
            if (length n) > 0.5 do append candAxes (normalize n)
        )
        for e = 1 to (amin 60 ne) do (
            local ev = polyop.getEdgeVerts obj e
            local p1 = polyop.getVert obj ev[1]
            local p2 = polyop.getVert obj ev[2]
            local d = p2 - p1
            if (length d) > weldTol do append candAxes (normalize d)
        )
        
        local bestAxis = undefined
        local bestTopVerts = #()
        local bestBotVerts = #()
        local bestMatch = #()
        
        for cand in candAxes do (
            local vHeights = for v = 1 to nv collect (dot (polyop.getVert obj v) cand)
            local minH = vHeights[1], maxH = vHeights[1]
            for h in vHeights do (
                if h < minH do minH = h
                if h > maxH do maxH = h
            )
            
            local totalHeight = maxH - minH
            if totalHeight > weldTol do (
                local topV = for v = 1 to nv where (abs (vHeights[v] - maxH)) <= weldTol collect v
                local botV = for v = 1 to nv where (abs (vHeights[v] - minH)) <= weldTol collect v
                
                if (topV.count + botV.count) == nv and topV.count == botV.count and topV.count >= 3 do (
                    local topProj = for v in topV collect (
                        local p = polyop.getVert obj v
                        p - ((dot p cand) * cand)
                    )
                    local botProj = for v in botV collect (
                        local p = polyop.getVert obj v
                        p - ((dot p cand) * cand)
                    )
                    
                    local match = #()
                    match[topV.count] = 0
                    local allMatched = true
                    for ti = 1 to topV.count do (
                        local tp = topProj[ti]
                        local bestD = 1e18, bestBi = 0
                        for bi = 1 to botV.count do (
                            local d = length (tp - botProj[bi])
                            if d < bestD do (bestD = d; bestBi = bi)
                        )
                        if bestD > weldTol then (allMatched = false; exit)
                        match[ti] = bestBi
                    )
                    
                    if allMatched do (
                        bestAxis = cand
                        bestTopVerts = topV
                        bestBotVerts = botV
                        bestMatch = match
                        exit
                    )
                )
            )
        )
        
        if bestAxis == undefined do (
            return (RM_IC_Result #reject "#reject_not_prism" undefined)
        )
        
        local topVerts = bestTopVerts
        local botVerts = bestBotVerts
        local topToBotMatch = bestMatch
        
        -- 3. Extract top boundary loop
        local topEdges = #{}
        for e = 1 to (polyop.getNumEdges obj) do (
            local ev = polyop.getEdgeVerts obj e
            if (findItem topVerts ev[1]) > 0 and (findItem topVerts ev[2]) > 0 do topEdges[e] = true
        )
        
        local loopVerts = #()
        local startV = topVerts[1]
        append loopVerts startV
        local currV = startV
        local visitedV = #{startV}
        
        for step = 1 to topVerts.count do (
            local adjEdges = (polyop.getEdgesUsingVert obj currV) * topEdges
            local nextV = undefined
            for e in adjEdges do (
                local ev = polyop.getEdgeVerts obj e
                local other = if ev[1] == currV then ev[2] else ev[1]
                if not visitedV[other] do (nextV = other; exit)
            )
            if nextV != undefined then (
                append loopVerts nextV
                visitedV[nextV] = true
                currV = nextV
            ) else exit
        )
        
        -- If single closed boundary loop does not contain all top vertices (e.g. Tube with cavity):
        if loopVerts.count != topVerts.count do (
            return (RM_IC_Result #reject "#reject_multi_loop" undefined)
        )
        
        local N = loopVerts.count
        if N < 3 do (
            return (RM_IC_Result #reject "#reject_invalid_profile" undefined)
        )
        
        -- 4. Build pristine Re-Quad mesh
        local reMesh = convertToPoly (mesh numverts:0 numfaces:0)
        
        for i = 1 to N do (
            polyop.createVert reMesh (polyop.getVert obj loopVerts[i])
        )
        for i = 1 to N do (
            local topIdxInArr = findItem topVerts loopVerts[i]
            local botIdxInArr = topToBotMatch[topIdxInArr]
            local actualBotV = botVerts[botIdxInArr]
            polyop.createVert reMesh (polyop.getVert obj actualBotV)
        )
        
        local topCapArray = for i = 1 to N collect i
        polyop.createPolygon reMesh topCapArray
        
        local botCapArray = for i = N to 1 by -1 collect (N + i)
        polyop.createPolygon reMesh botCapArray
        
        for i = 1 to N do (
            local next_i = if i < N then (i + 1) else 1
            polyop.createPolygon reMesh #(i, next_i, N + next_i, N + i)
        )
        
        update reMesh
        
        -- 5. Strict Post-condition Validation (h = 0 -> chi = 2)
        local afterStats = getTopoStats reMesh
        local afterArea = getTriangulatedArea reMesh
        local shifts = getTwoWayShift obj reMesh
        local areaDelta = abs (afterArea - beforeArea) / beforeArea
        local expectedChi = 2
        
        local failReasons = #()
        if afterStats[5] != 0 do append failReasons ("after.border == " + afterStats[5] as string)
        if afterStats[6] != 0 do append failReasons ("after.nonman == " + afterStats[6] as string)
        if afterStats[4] != expectedChi do append failReasons ("after.chi == " + afterStats[4] as string + " (expected " + expectedChi as string + ")")
        if afterStats[8] != (2 * afterStats[2]) do append failReasons ("degree_sum " + afterStats[8] as string + " != 2*E " + (2*afterStats[2]) as string)
        if afterStats[1] > beforeStats[1] do append failReasons ("after.v " + afterStats[1] as string + " > before.v " + beforeStats[1] as string)
        if shifts[3] > (weldTol * 2.0) do append failReasons ("maxShift " + (formattedPrint shifts[3] format:".4f") + " > tol")
        
        if failReasons.count > 0 do (
            delete reMesh
            local reasonStr = "#reject_postcondition ("
            for r in failReasons do reasonStr += (r + "; ")
            reasonStr += ")"
            return (RM_IC_Result #reject reasonStr undefined)
        )
        
        -- Replace geometry with pristine reMesh
        polyop.attach obj reMesh
        local oldFaces = #{1..nf}
        polyop.deleteFaces obj oldFaces delIsoVerts:true
        update obj
        
        -- Assign Smoothing Groups
        local newNF = polyop.getNumFaces obj
        for f = 1 to newNF do (
            local n = faceNormal obj f
            if (abs (dot n bestAxis)) < 0.1 then polyop.setFaceSmoothGroup obj f 1
            else polyop.setFaceSmoothGroup obj f 2
        )
        
        (RM_IC_Result #accept "#accepted_watertight_prism" #(beforeStats, afterStats, beforeArea, afterArea, shifts, areaDelta, 0))
    )
)

rm_ic_requad_engine = RM_IC_PrismEngine()
