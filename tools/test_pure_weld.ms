-- =========================================================================================
--  tools/test_pure_weld.ms
--  Регрессионный эталонный тест для проверки штатной сварки (Weld 0.01 мм) на Revit-стене.
--  Эталон: V176  E180  F6  chi2  border0  nonman0  degSum360  deltaArea 0.0000%
-- =========================================================================================

(
    fn getTopoStats obj =
    (
        local nv = polyop.getNumVerts obj
        local ne = polyop.getNumEdges obj
        local nf = polyop.getNumFaces obj
        local nBorder = 0, nNonMan = 0
        for e = 1 to ne do (
            local c = (polyop.getEdgeFaces obj e).count
            if c == 1 then nBorder += 1
            else if c > 2 do nNonMan += 1
        )
        local chi = nv - ne + nf
        local degSum = 0
        for f = 1 to nf do degSum += (polyop.getFaceDeg obj f)
        
        local m = snapshotAsMesh obj
        local numTri = meshop.getNumFaces m
        local totalArea = 0.0d0
        for fi = 1 to numTri do (
            local fv = meshop.getFace m fi
            local v1 = meshop.getVert m fv.x
            local v2 = meshop.getVert m fv.y
            local v3 = meshop.getVert m fv.z
            totalArea += ((length (cross (v2 - v1) (v3 - v1))) / 2.0)
        )
        delete m
        
        #(nv, ne, nf, chi, nBorder, nNonMan, degSum, totalArea)
    )

    local wallObj = getNodeByName "Basic Wall CON Z392"
    if not (isValidNode wallObj) do (
        format "Внимание: Объект 'Basic Wall CON Z392' не найден в сцене.\n"
        return false
    )
    
    local poly = copy wallObj
    convertToPoly poly
    
    local t0 = timeStamp()
    local before = getTopoStats poly
    
    -- Чистая штатная сварка
    poly.weldThreshold = units.decodeValue "0.01mm"
    polyop.weldVertsByThreshold poly #{1..(polyop.getNumVerts poly)}
    update poly
    
    local after = getTopoStats poly
    local weldTime = (timeStamp() - t0) / 1000.0
    delete poly
    
    local areaDelta = abs (after[8] - before[8]) / before[8] * 100.0
    
    format "\n=========================================================================================\n"
    format "      РЕГРЕССИОННЫЙ ТЕСТ WELD 0.01 мм (Basic Wall CON Z392)\n"
    format "=========================================================================================\n"
    format "Before: V=% E=% F=% chi=% border=% nonman=% degSum=% Area=%\n" \
        before[1] before[2] before[3] before[4] before[5] before[6] before[7] (formattedPrint before[8] format:".4f")
    format "After : V=% E=% F=% chi=% border=% nonman=% degSum=% Area=%\n" \
        after[1] after[2] after[3] after[4] after[5] after[6] after[7] (formattedPrint after[8] format:".4f")
    format "Время : % сек, Изменение площади: % %\n" (formattedPrint weldTime format:".4f") (formattedPrint areaDelta format:".6f")
    
    local pass = (after[1] == 176 and after[2] == 180 and after[3] == 6 and after[4] == 2 and after[5] == 0 and after[6] == 0 and after[7] == 360)
    format "Вердикт: %\n" (if pass then "PASS (ЭТАЛОН ПОДТВЕРЖДЁН)" else "FAIL")
    format "=========================================================================================\n\n"
    pass
)
