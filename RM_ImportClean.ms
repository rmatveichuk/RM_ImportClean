/***********************************************************************
    RM_ImportClean  v1.6
    Набор инструментов подготовки геометрии, импортированной из CAD/Revit.

    Блок 1. Конвертация Mesh -> Poly без развала скруглений (Turn to Poly)
    Блок 2. Чистка вершин, не формирующих геометрию (бывш. RM_MeshCleaner)
    Блок 3. Поиск и выделение одинаковых элементов (бывш. RM_ElementFinder)

    Платформа: Autodesk 3ds Max (MaxScript). В других пакетах не работает.
    Кодировка: UTF-8 with BOM (обязательно, иначе кириллица развалится).
************************************************************************/


--------------------------------------------------------------- ОЧИСТКА СТАРЫХ ОКОН
try (destroyDialog ::RM_IC_MainRol) catch()
try (closeRolloutFloater ::RM_IC_floater) catch()
try (
    local desktopHWNDs = windows.getChildrenHWND (windows.getDesktopHWND())
    for h in desktopHWNDs do
    (
        local title = h[5]
        if title != undefined and (
            (matchPattern title pattern:"*RM ImportClean*") or 
            (matchPattern title pattern:"*RM_ImportClean*") or 
            (matchPattern title pattern:"*RM_MeshTools*") or 
            (matchPattern title pattern:"*RM MeshTools*")
        ) do (
            try (UIAccessor.CloseDialog h[1]) catch()
        )
    )
) catch()

global rm_ic_f2e = #()   -- полигон -> индекс элемента
global rm_ic_e2g = #()   -- элемент -> индекс группы
global rm_ic_g2row = #() -- группа  -> строка в multiListBox

global RM_IC_floater
global rm_ic_ef_obj    = undefined
global rm_ic_ef_poly   = true
global rm_ic_ef_elems  = #()
global rm_ic_ef_groups = #()

--------------------------------------------------------------- общие utils
fn rm_ic_isEPoly o = (isValidNode o and (classOf o.baseObject == Editable_Poly))
fn rm_ic_isEMesh o = (isValidNode o and (classOf o.baseObject == Editable_Mesh))
fn rm_ic_isGeo   o = (rm_ic_isEPoly o or rm_ic_isEMesh o)
fn rm_ic_fmt v = (try (units.formatValue v) catch (v as string))

/*======================================================================
    БЛОК 1 - КОНВЕРТАЦИЯ Mesh -> Poly
    Обычный Convert to Editable Poly склеивает треугольники в невыпуклые
    и неплоские n-gon'ы. На скруглениях это разваливает форму.
    Turn to Poly с жёсткими настройками собирает полигоны корректно.
======================================================================*/
fn rm_ic_convert obj maxSize:4 keepConvex:true requirePlanar:true planarTol:1.0 keepMidEdge:true =
(
    if not (isValidNode obj) do return false
    local m = Turn_to_Poly()
    m.limitPolySize         = true
    m.maxPolySize           = maxSize
    m.keepConvex            = keepConvex
    m.requirePlanar         = requirePlanar
    m.planarThresh          = planarTol
    m.removeMidEdgeVertices = not keepMidEdge
    addModifier obj m
    convertTo obj Editable_Poly
    true
)

/*======================================================================
    БЛОК 2 - ЧИСТКА ВЕРШИН
======================================================================*/
-- ленивое кэширование позиций вершин
fn rm_ic_vp obj cache i =
(
    local p = cache[i]
    if p == undefined do (p = polyop.getVert obj i; cache[i] = p)
    p
)

-- проверка UV-шва на ребре (дорого, только по запросу)
fn rm_ic_isMapSeam obj e fa fb chans =
(
    local ev = polyop.getEdgeVerts obj e
    local va = ev[1], vb = ev[2]
    local gfa = polyop.getFaceVerts obj fa
    local gfb = polyop.getFaceVerts obj fb
    local ia = findItem gfa va, ib = findItem gfa vb
    local ja = findItem gfb va, jb = findItem gfb vb
    if ia == 0 or ib == 0 or ja == 0 or jb == 0 then return true
    local seam = false
    for ch in chans while not seam do
    (
        local mfa = polyop.getMapFace obj ch fa
        local mfb = polyop.getMapFace obj ch fb
        if mfa != undefined and mfb != undefined do
            if mfa[ia] != mfb[ja] or mfa[ib] != mfb[jb] do seam = true
    )
    seam
)

-- PASS 1 : рёбра между компланарными гранями
fn rm_ic_coplanarEdges obj faceTol:1.0 keepMat:true keepSG:true keepUV:false onlySel:false selectOnly:false =
(
    local nF = polyop.getNumFaces obj
    local nE = polyop.getNumEdges obj
    if nF == 0 or nE == 0 do return 0

    local f1 = #(), f2 = #()
    f1[nE] = 0; f2[nE] = 0
    for e = 1 to nE do (f1[e] = 0; f2[e] = 0)

    local nrm = #(), mid = #(), sg = #()
    nrm[nF] = [0,0,1]; mid[nF] = 0; sg[nF] = 0

    for f = 1 to nF do
    (
        nrm[f] = normalize (polyop.getFaceNormal obj f)
        if keepMat do mid[f] = polyop.getFaceMatID obj f
        if keepSG  do sg[f]  = polyop.getFaceSmoothGroup obj f
        for e in (polyop.getFaceEdges obj f) do
            (if f1[e] == 0 then f1[e] = f else f2[e] = f)
        if (bit.and f 8191) == 0 do progressUpdate (40.0 * f / nF)
    )

    local chans = #()
    if keepUV do
        for ch = 0 to (polyop.getNumMaps obj - 1) where (polyop.getMapSupport obj ch) do
            append chans ch

    local cosTol = cos faceTol
    local selE   = if onlySel then (polyop.getEdgeSelection obj) else undefined
    local esel   = #{}

    for e = 1 to nE where f2[e] != 0 and (selE == undefined or selE[e]) do
    (
        local a = f1[e], b = f2[e]
        if (dot nrm[a] nrm[b]) >= cosTol do
        (
            local ok = true
            if keepMat and mid[a] != mid[b] do ok = false
            if ok and keepSG and sg[a] != sg[b] and (bit.and sg[a] sg[b]) == 0 do ok = false
            if ok and chans.count > 0 do ok = not (rm_ic_isMapSeam obj e a b chans)
            if ok do esel[e] = true
        )
        if (bit.and e 16383) == 0 do progressUpdate (40.0 + 30.0 * e / nE)
    )

    local cnt = esel.numberSet
    if cnt > 0 do
    (
        polyop.setEdgeSelection obj esel
        if not selectOnly do
        (
            obj.EditablePoly.remove selLevel:#Edge
            polyop.deleteIsoVerts obj
            update obj
        )
    )
    cnt
)

-- PASS 2 : вершины, лежащие на прямой
fn rm_ic_collinearVerts obj vertTol:1.0 onlySel:false selectOnly:false killDegen:true =
(
    local nV = polyop.getNumVerts obj
    local nE = polyop.getNumEdges obj
    if nV == 0 or nE == 0 do return 0

    local deg = #(), nb1 = #(), nb2 = #()
    deg[nV] = 0; nb1[nV] = 0; nb2[nV] = 0
    for i = 1 to nV do deg[i] = 0

    for e = 1 to nE do
    (
        local ev = polyop.getEdgeVerts obj e
        local a = ev[1], b = ev[2], d = 0
        d = deg[a] + 1; deg[a] = d
        if d == 1 then nb1[a] = b else if d == 2 do nb2[a] = b
        d = deg[b] + 1; deg[b] = d
        if d == 1 then nb1[b] = a else if d == 2 do nb2[b] = a
        if (bit.and e 16383) == 0 do progressUpdate (70.0 + 20.0 * e / nE)
    )

    local selV   = if onlySel then (polyop.getVertSelection obj) else undefined
    local vsel   = #{}
    local cosTol = -(cos vertTol)
    local vc = #(); vc[nV] = undefined

    for v = 1 to nV where deg[v] == 2 and (selV == undefined or selV[v]) do
    (
        local a = nb1[v], b = nb2[v]
        if a != 0 and b != 0 and a != b do
        (
            local p  = rm_ic_vp obj vc v
            local d1 = (rm_ic_vp obj vc a) - p
            local d2 = (rm_ic_vp obj vc b) - p
            local l1 = length d1, l2 = length d2
            if killDegen and (l1 < 1e-5 or l2 < 1e-5) then vsel[v] = true
            else if l1 > 0 and l2 > 0 do
                if (dot (d1/l1) (d2/l2)) <= cosTol do vsel[v] = true
        )
    )

    local cnt = vsel.numberSet
    if cnt > 0 do
    (
        polyop.setVertSelection obj vsel
        if not selectOnly do
        (
            obj.EditablePoly.remove selLevel:#Vertex
            try (obj.EditablePoly.removeUnusedMapVerts()) catch()
            update obj
        )
    )
    cnt
)

/*======================================================================
    БЛОК 3 - ОДИНАКОВЫЕ ЭЛЕМЕНТЫ
======================================================================*/
fn rm_ic_q v t = ((floor (v / t + 0.5)) as integer)

-- ---------------------------------------------------------------------
-- Разбор объекта на элементы через union-find по вершинам.
-- Старая версия звала polyop.getElementsUsingFace на каждый элемент,
-- а это заливка по всей сетке: O(элементы x грани). На 900k полигонов
-- давало часы. Здесь два линейных прохода: O(грани + вершины).
-- ---------------------------------------------------------------------
global rm_ic_par = #()

fn rm_ic_find i =
(
    local r = i
    while rm_ic_par[r] != r do r = rm_ic_par[r]
    local c = i
    while rm_ic_par[c] != c do (local nx = rm_ic_par[c]; rm_ic_par[c] = r; c = nx)
    r
)

-- Возвращает #( #(bitarray граней, ...), #( #(индексы вершин), ... ) )
fn rm_ic_collect obj isPoly =
(
    local nF = if isPoly then (polyop.getNumFaces obj) else (meshop.getNumFaces obj)
    local nV = if isPoly then (polyop.getNumVerts obj) else (meshop.getNumVerts obj)
    if nF == 0 or nV == 0 do return #(#(), #())

    rm_ic_par = #()
    rm_ic_par[nV] = 0
    for i = 1 to nV do rm_ic_par[i] = i

    -- 1) вершины каждой грани сливаем в один компонент
    local fv0 = #()
    fv0[nF] = 0
    for f = 1 to nF do
    (
        local fv, cnt
        if isPoly then (fv = polyop.getFaceVerts obj f; cnt = fv.count)
        else (fv = getFace obj f; cnt = 3)
        local a = fv[1] as integer
        fv0[f] = a
        local ra = rm_ic_find a
        for k = 2 to cnt do
        (
            local rb = rm_ic_find (fv[k] as integer)
            if rb != ra do rm_ic_par[rb] = ra
        )
        if (bit.and f 8191) == 0 do progressUpdate (30.0 * f / nF)
    )

    -- 2) нумеруем компоненты и раскладываем вершины
    local compId = #()
    compId[nV] = 0
    for i = 1 to nV do compId[i] = 0
    local nEl = 0
    local eVerts = #()
    for v = 1 to nV do
    (
        local r = rm_ic_find v
        local id = compId[r]
        if id == 0 do (nEl += 1; compId[r] = nEl; id = nEl; eVerts[nEl] = #())
        append eVerts[id] v
        if (bit.and v 16383) == 0 do progressUpdate (30.0 + 8.0 * v / nV)
    )
    if nEl == 0 do return #(#(), #())

    -- 3) раскладываем грани по компонентам
    local eFaceArr = #()
    eFaceArr[nEl] = undefined
    for i = 1 to nEl do eFaceArr[i] = #()
    for f = 1 to nF do
    (
        append eFaceArr[compId[rm_ic_find fv0[f]]] f
        if (bit.and f 16383) == 0 do progressUpdate (38.0 + 7.0 * f / nF)
    )

    -- 4) в bitarray, выбрасывая компоненты без граней (изолированные вершины)
    local elems = #(), verts = #()
    for i = 1 to nEl where eFaceArr[i].count > 0 do
    (
        local b = #{}
        for x in eFaceArr[i] do b[x] = true
        append elems b
        append verts eVerts[i]
    )
    #(elems, verts)
)

-- отпечаток элемента: не зависит от положения (и от поворота, если useOrient=false)
fn rm_ic_sig obj isPoly vlist nf useOrient tol =
(
    local nv = vlist.count
    if nv == 0 do return undefined

    local pts = #()
    pts[nv] = [0,0,0]
    local cen = [0,0,0]
    for i = 1 to nv do
    (
        local p = if isPoly then (polyop.getVert obj vlist[i]) else (meshop.getVert obj vlist[i])
        pts[i] = p
        cen += p
    )
    cen /= nv

    -- ВАЖНО: Point3 в MaxScript присваивается ПО ССЫЛКЕ.
    -- "local mn = pts[1], mx = pts[1]" делает mn и mx одним объектом,
    -- габарит тогда всегда 0. Поэтому считаем по отдельным float.
    local p0 = pts[1]
    local mnx = p0.x, mny = p0.y, mnz = p0.z
    local mxx = p0.x, mxy = p0.y, mxz = p0.z
    local ds = #()
    ds[nv] = 0.0
    for i = 1 to nv do
    (
        local p = pts[i]
        ds[i] = length (p - cen)
        if p.x < mnx do mnx = p.x
        if p.y < mny do mny = p.y
        if p.z < mnz do mnz = p.z
        if p.x > mxx do mxx = p.x
        if p.y > mxy do mxy = p.y
        if p.z > mxz do mxz = p.z
    )
    sort ds

    local dx = mxx - mnx, dy = mxy - mny, dz = mxz - mnz
    local size = sqrt (dx*dx + dy*dy + dz*dz)

    local i2 = amax 1 ((nv / 4) as integer)
    local i3 = amax 1 ((nv / 2) as integer)
    local i4 = amax 1 ((3 * nv / 4) as integer)
    local sig = (nv as string) + "|" + (nf as string) + "|" + \
                ((rm_ic_q ds[1]  tol) as string) + "," + \
                ((rm_ic_q ds[i2] tol) as string) + "," + \
                ((rm_ic_q ds[i3] tol) as string) + "," + \
                ((rm_ic_q ds[i4] tol) as string) + "," + \
                ((rm_ic_q ds[nv] tol) as string)

    if useOrient do
    (
        local d = #(dx, dy, dz)
        sort d
        sig += "|" + ((rm_ic_q d[1] tol) as string) + "," + \
                     ((rm_ic_q d[2] tol) as string) + "," + \
                     ((rm_ic_q d[3] tol) as string)
    )
    #(sig, size, nv, nf)
)

fn rm_ic_analyze obj useOrient tol =
(
    local isPoly = rm_ic_isEPoly obj
    rm_ic_ef_obj  = obj
    rm_ic_ef_poly = isPoly

    progressStart "RM_ImportClean: анализ элементов..."
    local pack   = rm_ic_collect obj isPoly
    local elems  = pack[1]
    local everts = pack[2]
    rm_ic_ef_elems = elems

    local n = elems.count
    if n == 0 do (progressEnd(); rm_ic_ef_groups = #(); return #())

    local rows = #()
    rows[n] = undefined
    for i = 1 to n do
    (
        local s = rm_ic_sig obj isPoly everts[i] (elems[i].numberSet) useOrient tol
        rows[i] = if s == undefined then #("?", 0.0, 0, 0, i) \
                  else #(s[1], s[2], s[3], s[4], i)
        if (bit.and i 255) == 0 do progressUpdate (45.0 + 50.0 * i / n)
    )

    qsort rows (fn rm_cmpSig a b = stricmp a[1] b[1])

    local groups = #()
    local i = 1
    while i <= n do
    (
        local j = i
        local ids = #()
        while j <= n and rows[j][1] == rows[i][1] do
        (
            append ids rows[j][5]
            j += 1
        )
        append groups #(rows[i][1], ids, rows[i][2], rows[i][3], rows[i][4])
        i = j
    )
    progressEnd()
    rm_ic_ef_groups = groups

    -- Строим обратные таблицы поиска Face->Element и Element->Group
    local nf = if isPoly then (polyop.getNumFaces obj) else (meshop.getNumFaces obj)
    rm_ic_f2e = #()
    rm_ic_f2e[nf] = 0
    for ei = 1 to rm_ic_ef_elems.count do
        for f in rm_ic_ef_elems[ei] do rm_ic_f2e[f] = ei

    rm_ic_e2g = #()
    rm_ic_e2g[rm_ic_ef_elems.count] = 0
    for gi = 1 to rm_ic_ef_groups.count do
        for ei in rm_ic_ef_groups[gi][2] do rm_ic_e2g[ei] = gi

    groups
)

fn rm_ic_selectFaces obj isPoly bits =
(
    if not (isValidNode obj) do return false
    
    local actualIsPoly = (classOf obj.baseObject == Editable_Poly)
    local actualIsMesh = (classOf obj.baseObject == Editable_Mesh)
    if not (actualIsPoly or actualIsMesh) do return false
    
    local numFaces = if actualIsPoly then (polyop.getNumFaces obj) else (meshop.getNumFaces obj)
    local safeBits = bits * #{1..numFaces}
    if safeBits.numberSet != bits.numberSet do
    (
        messageBox "Геометрия объекта изменилась с момента анализа.\nПожалуйста, выполните анализ заново." title:"RM_ImportClean"
        return false
    )

    if (selection.count != 1 or selection[1] != obj) do select obj
    max modify mode
    try (modPanel.setCurrentObject obj.baseObject) catch()
    
    if actualIsPoly then
    (
        subObjectLevel = 4
        obj.EditablePoly.SetSelection #Face #{}
        obj.EditablePoly.SetSelection #Face safeBits
    )
    else
    (
        subObjectLevel = 3
        setFaceSelection obj safeBits
    )
    
    if (viewport.getRenderLevel() == #wireframe) do
    (
        viewport.SetRenderLevel #smoothhighlights
        viewport.SetShowEdgeFaces true
    )
    
    redrawViews()
    true
)

/*======================================================================
    ИНТЕРФЕЙС
======================================================================*/
rollout roRM_IC_convert "1. Конвертация из Revit (Mesh -> Poly)" width:330
(
    label lb1 "Заменяет обычный Convert to Poly, который" align:#left
    label lb2 "разваливает скругления на невыпуклых n-gon'ах." align:#left
    spinner  spMax "Максимум сторон полигона:" range:[3,30,4] type:#integer fieldWidth:52
    checkbox chkConvex "Keep Polygons Convex" checked:true
    checkbox chkPlanar "Require Planar Polygons" checked:true
    spinner  spPlanar "   Planar Threshold, град:" range:[0.0,45.0,1.0] type:#float scale:0.1 fieldWidth:52
    checkbox chkMidEdge "Сохранять точки на рёбрах" checked:true
    button   btnConv "КОНВЕРТИРОВАТЬ ВЫДЕЛЕННЫЕ" width:312 height:30
    label    lbConvRes "" height:16

    on btnConv pressed do
    (
        local objs = for o in selection where superClassOf o == GeometryClass collect o
        if objs.count == 0 do
        (
            messageBox "Выдели хотя бы один геометрический объект." title:"RM_ImportClean"
            return false
        )
        local t0 = timeStamp()
        local ok = 0
        disableSceneRedraw()
        try
        (
            for o in objs do
            (
                if (rm_ic_convert o maxSize:spMax.value keepConvex:chkConvex.checked \
                    requirePlanar:chkPlanar.checked planarTol:spPlanar.value \
                    keepMidEdge:chkMidEdge.checked) do ok += 1
            )
        )
        catch (format "RM_ImportClean convert ERROR: %\n" (getCurrentException()))
        enableSceneRedraw()
        redrawViews()
        lbConvRes.text = ("сконвертировано: " + ok as string + " из " + objs.count as string + \
                          "   (" + (formattedPrint ((timeStamp()-t0)/1000.0) format:".1f") + " c)")
    )
)

rollout roRM_IC_clean "2. Чистка лишних вершин" width:330
(
    group "Что чистим"
    (
        checkbox chkV "Pass 2: вершины на прямой (collinear)" checked:true
        checkbox chkE "Pass 1: рёбра между компланарными гранями" checked:false
    )
    group "Допуски"
    (
        spinner spV "Угол вершины, град:" range:[0.0,45.0,1.0] type:#float scale:0.1 fieldWidth:52
        spinner spF "Угол граней,  град:" range:[0.0,45.0,0.5] type:#float scale:0.1 fieldWidth:52
    )
    group "Не трогать границы"
    (
        checkbox chkMat "Material ID" checked:true across:2
        checkbox chkSG  "Smooth Groups" checked:true
        checkbox chkUV  "UV швы (медленно)" checked:false
    )
    group "Дополнительно"
    (
        checkbox chkWeld "Сначала Weld" checked:false across:2
        spinner  spW "" range:[0.0,10000.0,0.01] type:#float scale:0.001 fieldWidth:56
        checkbox chkSel "Только внутри выделения sub-object" checked:false
        spinner  spIt "Повторов (Pass1+Pass2):" range:[1,5,2] type:#integer fieldWidth:52
        checkbox chkUndo "Включить Undo (жрёт RAM)" checked:false
    )
    button btnSel "1 - ВЫДЕЛИТЬ кандидатов (превью)" width:312 height:26
    button btnRun "2 - ПОЧИСТИТЬ" width:312 height:32
    label lbA "готов" height:16
    label lbB "" height:16

    fn doJob selectOnly =
    (
        local objs = for o in selection where rm_ic_isEPoly o collect o
        if objs.count == 0 do
        (
            messageBox "Выдели хотя бы один Editable Poly.\nEditable Mesh сначала прогони через блок 1." title:"RM_ImportClean"
            return false
        )

        local t0 = timeStamp()
        local totE = 0, totV = 0
        local pv0 = 0, pf0 = 0, pv1 = 0, pf1 = 0

        disableSceneRedraw()
        suspendEditing()
        progressStart "RM_ImportClean: чистка..."
        try
        (
            for obj in objs do
            (
                pv0 += polyop.getNumVerts obj
                pf0 += polyop.getNumFaces obj

                if chkWeld.checked and not selectOnly do
                (
                    obj.weldThreshold = spW.value
                    polyop.weldVertsByThreshold obj #{1..(polyop.getNumVerts obj)}
                    update obj
                )

                local iter = if selectOnly then 1 else spIt.value
                for i = 1 to iter do
                (
                    if chkE.checked do
                        totE += rm_ic_coplanarEdges obj faceTol:spF.value keepMat:chkMat.checked \
                                keepSG:chkSG.checked keepUV:chkUV.checked \
                                onlySel:chkSel.checked selectOnly:selectOnly
                    if chkV.checked do
                        totV += rm_ic_collinearVerts obj vertTol:spV.value \
                                onlySel:chkSel.checked selectOnly:selectOnly
                    if selectOnly do exit
                    if keyboard.escPressed do exit
                )
                pv1 += polyop.getNumVerts obj
                pf1 += polyop.getNumFaces obj
            )
        )
        catch (format "RM_ImportClean clean ERROR: %\n" (getCurrentException()))
        progressEnd()
        resumeEditing()
        enableSceneRedraw()
        redrawViews()

        local dt = (timeStamp() - t0) / 1000.0
        if selectOnly then
        (
            lbA.text = ("кандидатов: верт " + totV as string + " / рёбер " + totE as string)
            lbB.text = ("время " + (formattedPrint dt format:".1f") + " c")
            try (
                max modify mode
                subObjectLevel = if (chkV.checked and totV > 0) then 1 else 2
            ) catch()
        )
        else
        (
            lbA.text = ("удалено: верт " + totV as string + " / рёбер " + totE as string)
            lbB.text = ("verts " + pv0 as string + " -> " + pv1 as string + \
                        "   polys " + pf0 as string + " -> " + pf1 as string)
        )
        format "RM_ImportClean: verts % -> % | polys % -> % | % sec\n" pv0 pv1 pf0 pf1 dt
        true
    )

    on btnSel pressed do doJob true
    on btnRun pressed do
    (
        if chkUndo.checked then (undo "RM_ImportClean clean" on (doJob false))
        else (undo off (doJob false))
    )
)

rollout roRM_IC_elem "3. Одинаковые элементы" width:330
(
    group "Анализ"
    (
        checkbox chkOrient "Учитывать поворот (строже)" checked:false
        spinner  spTol "Допуск совпадения:" range:[0.0001,1000.0,0.5] type:#float scale:0.01 fieldWidth:60
        button   btnGo "АНАЛИЗИРОВАТЬ ВЫДЕЛЕННЫЙ ОБЪЕКТ" width:299 height:28
    )
    label lbInfo "объект не проанализирован" height:16

    group "Группы одинаковых элементов"
    (
        radiobuttons rbSort labels:#("мелкие сверху","частые сверху") default:1 columns:2
        multiListBox mlb "" height:12 width:299
    )
    button btnSelGrp "ВЫДЕЛИТЬ отмеченные группы" width:299 height:28

    group "Быстрый фильтр по размеру"
    (
        spinner spSize "Габарит меньше:" range:[0.0,1e9,5.0] type:#float scale:0.1 fieldWidth:60
        spinner spCnt  "и повторов не менее:" range:[1,10000,1] type:#integer fieldWidth:60
    )
    button btnSelSize "ВЫДЕЛИТЬ по фильтру" width:299 height:28
    
    button btnFromVP "НАЙТИ ТАКИЕ ЖЕ (по выделению)" width:299 height:28 tooltip:"Выделите деталь во вьюпорте и нажмите, чтобы найти и выделить все такие же копии"
    
    button btnDel "УДАЛИТЬ" width:150 height:28 across:2 tooltip:"Удалить выделенные полигоны/элементы"
    button btnDetach "ОТДЕЛИТЬ (Detach)" width:150 height:28 tooltip:"Отделить выделенное в отдельный новый объект"
    label lbRes "" height:16

    -- карта "строка списка -> индекс группы" (multiListBox не имеет .tag)
    local mlbMap = #()

    fn refreshList =
    (
        local g = rm_ic_ef_groups
        if g.count == 0 do (mlbMap = #(); rm_ic_g2row = #(); mlb.items = #(); return false)
        local idx = for i = 1 to g.count collect i
        if rbSort.state == 1 then
            qsort idx (fn rm_cs a b = (if rm_ic_ef_groups[a][3] < rm_ic_ef_groups[b][3] then -1 \
                                       else if rm_ic_ef_groups[a][3] > rm_ic_ef_groups[b][3] then 1 else 0))
        else
            qsort idx (fn rm_cc a b = (if rm_ic_ef_groups[a][2].count > rm_ic_ef_groups[b][2].count then -1 \
                                       else if rm_ic_ef_groups[a][2].count < rm_ic_ef_groups[b][2].count then 1 else 0))
        mlbMap = idx
        rm_ic_g2row = #()
        rm_ic_g2row[g.count] = 0
        for row = 1 to idx.count do rm_ic_g2row[idx[row]] = row
        
        mlb.items = for i in idx collect
        (
            local gr = rm_ic_ef_groups[i]
            ("x" + (gr[2].count as string) + "   габ " + (rm_ic_fmt gr[3]) + \
             "   v" + (gr[4] as string) + " f" + (gr[5] as string))
        )
        true
    )

    fn gatherBits groupIdxList =
    (
        local bits = #{}
        for gi in groupIdxList do
            for ei in rm_ic_ef_groups[gi][2] do bits += rm_ic_ef_elems[ei]
        bits
    )

    on btnGo pressed do
    (
        local o = selection[1]
        if selection.count != 1 or not rm_ic_isGeo o do
        (
            messageBox "Выдели ровно ОДИН объект: Editable Poly или Editable Mesh." title:"RM_ImportClean"
            return false
        )
        local t0 = timeStamp()
        disableSceneRedraw()
        try (
            rm_ic_analyze o chkOrient.checked spTol.value
        )
        catch (format "RM_ImportClean elem ERROR: %\n" (getCurrentException()))
        enableSceneRedraw()

        local dup = 0
        for gr in rm_ic_ef_groups where gr[2].count > 1 do dup += gr[2].count
        lbInfo.text = ("элементов " + rm_ic_ef_elems.count as string + \
                       " / групп " + rm_ic_ef_groups.count as string + \
                       " / в повторах " + dup as string)
        refreshList()
        lbRes.text = ("анализ " + (formattedPrint ((timeStamp()-t0)/1000.0) format:".1f") + " c")
    )

    on btnFromVP pressed do
    (
        local o = rm_ic_ef_obj
        if not (isValidNode o) do (
            if selection.count == 1 and (rm_ic_isGeo selection[1]) then (
                o = selection[1]
                rm_ic_ef_obj = o
                rm_ic_ef_poly = (classOf o.baseObject == Editable_Poly)
            ) else (
                messageBox "Выделите объект с проанализированной геометрией." title:"RM_ImportClean"
                return false
            )
        )
        
        -- Если объект еще не был проанализирован, автоматически выполняем анализ
        if rm_ic_ef_groups.count == 0 or rm_ic_f2e.count == 0 do (
            rm_ic_analyze o chkOrient.checked spTol.value
            refreshList()
        )

        local isPoly = (classOf o.baseObject == Editable_Poly)
        local sel = if isPoly then (polyop.getFaceSelection o) else (getFaceSelection o)
        if sel.numberSet == 0 do (
            lbRes.text = "во вьюпорте ничего не выделено"
            return false
        )

        local gset = #{}
        for f in sel do
        (
            local ei = rm_ic_f2e[f]
            if ei != undefined and ei > 0 do
            (
                local gi = rm_ic_e2g[ei]
                if gi != undefined and gi > 0 do gset[gi] = true
            )
        )
        if gset.numberSet == 0 do (
            lbRes.text = "элемент не принадлежит ни одной группе"
            return false
        )

        local rows = #{}
        for gi in gset do (
            if rm_ic_g2row[gi] != undefined do rows[rm_ic_g2row[gi]] = true
        )
        mlb.selection = rows

        local bits = #{}
        local nElems = 0
        for gi in gset do (
            for ei in rm_ic_ef_groups[gi][2] do (
                bits += rm_ic_ef_elems[ei]
                nElems += 1
            )
        )

        rm_ic_selectFaces o rm_ic_ef_poly bits
        lbRes.text = ("найдено: " + nElems as string + " эл., " + bits.numberSet as string + " пол.")
    )

    on rbSort changed st do refreshList()

    on btnSelGrp pressed do
    (
        if rm_ic_ef_groups.count == 0 or not isValidNode rm_ic_ef_obj do return false
        local picked = for i in mlb.selection where mlbMap[i] != undefined collect mlbMap[i]
        if picked.count == 0 do (lbRes.text = "не отмечено ни одной группы"; return false)
        local bits = gatherBits picked
        rm_ic_selectFaces rm_ic_ef_obj rm_ic_ef_poly bits
        lbRes.text = ("выделено полигонов: " + bits.numberSet as string)
    )

    on btnSelSize pressed do
    (
        if rm_ic_ef_groups.count == 0 or not isValidNode rm_ic_ef_obj do return false
        local picked = for i = 1 to rm_ic_ef_groups.count \
                       where rm_ic_ef_groups[i][3] < spSize.value and \
                             rm_ic_ef_groups[i][2].count >= spCnt.value collect i
        if picked.count == 0 do (lbRes.text = "под фильтр ничего не попало"; return false)
        local bits = gatherBits picked
        rm_ic_selectFaces rm_ic_ef_obj rm_ic_ef_poly bits
        local ne = 0
        for gi in picked do ne += rm_ic_ef_groups[gi][2].count
        lbRes.text = ("элементов " + ne as string + ", полигонов " + bits.numberSet as string)
    )

    on btnDel pressed do
    (
        local o = rm_ic_ef_obj
        if not isValidNode o do return false
        
        local isPoly = (classOf o.baseObject == Editable_Poly)
        local isMesh = (classOf o.baseObject == Editable_Mesh)
        if not (isPoly or isMesh) do return false
        
        local bits = if isPoly then (polyop.getFaceSelection o) \
                     else (getFaceSelection o)
        if bits.numberSet == 0 do (lbRes.text = "нет выделенных полигонов"; return false)
        
        if (queryBox ("Удалить " + bits.numberSet as string + " выделенных полигонов?\nОтмена недоступна.") \
                     title:"RM_ImportClean") do
        (
            undo off
            (
                if isPoly then (polyop.deleteFaces o bits delIsoVerts:true)
                else (meshop.deleteFaces o bits delIsoVerts:true)
                update o
            )
            redrawViews()
            lbRes.text = ("удалено полигонов: " + bits.numberSet as string + " (нужен повторный анализ)")
            rm_ic_ef_groups = #(); rm_ic_ef_elems = #(); rm_ic_f2e = #(); rm_ic_e2g = #(); mlbMap = #(); mlb.items = #()
            lbInfo.text = "объект изменён - проанализируй заново"
        )
    )

    on btnDetach pressed do
    (
        local o = rm_ic_ef_obj
        if not isValidNode o do return false
        
        local isPoly = (classOf o.baseObject == Editable_Poly)
        local isMesh = (classOf o.baseObject == Editable_Mesh)
        if not (isPoly or isMesh) do return false
        
        local bits = if isPoly then (polyop.getFaceSelection o) \
                     else (getFaceSelection o)
        if bits.numberSet == 0 do (lbRes.text = "нет выделенных полигонов"; return false)
        
        local cnt = bits.numberSet
        local origNumFaces = if isPoly then (polyop.getNumFaces o) else (meshop.getNumFaces o)
        local newName = uniqueName (o.name + "_detached")
        local newObj = undefined
        
        undo "RM_ImportClean Detach" on
        (
            if isPoly then
            (
                local beforeNodes = objects as array
                polyop.detachFaces o bits delete:true asNode:true name:newName
                local afterNodes = objects as array
                for n in afterNodes where (findItem beforeNodes n) == 0 do newObj = n
                update o
            )
            else
            (
                newObj = copy o
                newObj.name = newName
                local deleteBits = #{1..origNumFaces} - bits
                meshop.deleteFaces newObj deleteBits delIsoVerts:true
                update newObj
                
                meshop.deleteFaces o bits delIsoVerts:true
                update o
            )
        )
        redrawViews()
        
        if isValidNode newObj do select newObj
        
        lbRes.text = ("отделено: " + (if isValidNode newObj then newObj.name else newName) + " (" + cnt as string + " пол.)")
        rm_ic_ef_groups = #(); rm_ic_ef_elems = #(); rm_ic_f2e = #(); rm_ic_e2g = #(); mlbMap = #(); mlb.items = #()
        lbInfo.text = "объект изменён - проанализируй заново"
    )
)

/*======================================================================
    ГЛАВНОЕ ОКНО С КАСТОМНОЙ ШАПКОЙ (СТАЙЛИНГ RM TOOLS)
======================================================================*/
global RM_IC_MainRol

rollout RM_IC_MainRol "RM ImportClean" width:340 height:710
(
    local isDragging = false
    local isResizing = false
    local dragStartScreen = [0,0]
    local dragStartDialog = [0,0]
    local dragStartH = 710

    -- [КАСТОМНЫЙ TITLE BAR & BORDER]
    dotNetControl lbl_title "System.Windows.Forms.Label" pos:[8,7] width:125 height:15
    dotNetControl lbl_line  "System.Windows.Forms.Label" pos:[135,7] width:170 height:15
    button btn_close "X" width:20 height:20 pos:[312,4] tooltip:"Close"
    
    -- [КОНТЕЙНЕР ДЛЯ МОДУЛЕЙ]
    subRollout sub_holder "" pos:[4,28] width:332 height:670
    
    -- [НИЖНИЙ РЕСАЙЗЕР ДЛЯ ПЕРЕТАСКИВАНИЯ ПО ВЫСОТЕ]
    dotNetControl lbl_resize "System.Windows.Forms.Label" pos:[0,700] width:340 height:10
    
    fn updateLayout h = (
        local newH = amax 200 h
        RM_IC_MainRol.height = newH
        sub_holder.height = newH - 38
        lbl_resize.pos = [0, newH - 10]
    )
    
    on RM_IC_MainRol lbuttondown pt do (
        if pt.y > (RM_IC_MainRol.height - 12) then (
            isResizing = true
            dragStartScreen = mouse.screenpos
            dragStartH = RM_IC_MainRol.height
        ) else (
            isDragging = true
            dragStartScreen = mouse.screenpos
            dragStartDialog = GetDialogPos RM_IC_MainRol
        )
    )
    on RM_IC_MainRol lbuttonup pt do ( 
        isDragging = false 
        isResizing = false
    )
    on RM_IC_MainRol mousemove pt do (
        if isResizing then (
            updateLayout (dragStartH + (mouse.screenpos.y - dragStartScreen.y))
        ) else if isDragging do (
            SetDialogPos RM_IC_MainRol (dragStartDialog + (mouse.screenpos - dragStartScreen))
        )
    )
    
    on lbl_resize MouseDown arg do (
        isResizing = true
        dragStartScreen = mouse.screenpos
        dragStartH = RM_IC_MainRol.height
    )
    on lbl_resize MouseUp arg do ( isResizing = false )
    on lbl_resize MouseMove arg do (
        if isResizing do (
            updateLayout (dragStartH + (mouse.screenpos.y - dragStartScreen.y))
        )
    )
    
    on lbl_title MouseDown arg do (
        isDragging = true
        dragStartScreen = mouse.screenpos
        dragStartDialog = GetDialogPos RM_IC_MainRol
    )
    on lbl_title MouseUp arg do ( isDragging = false )
    on lbl_title MouseMove arg do (
        if isDragging do SetDialogPos RM_IC_MainRol (dragStartDialog + (mouse.screenpos - dragStartScreen))
    )
    
    on lbl_line MouseDown arg do (
        isDragging = true
        dragStartScreen = mouse.screenpos
        dragStartDialog = GetDialogPos RM_IC_MainRol
    )
    on lbl_line MouseUp arg do ( isDragging = false )
    on lbl_line MouseMove arg do (
        if isDragging do SetDialogPos RM_IC_MainRol (dragStartDialog + (mouse.screenpos - dragStartScreen))
    )
    
    on btn_close pressed do destroyDialog RM_IC_MainRol
    
    on RM_IC_MainRol open do (
        local cColor = (dotNetClass "System.Drawing.Color").FromArgb 0 170 200
        local bgCol  = (dotNetClass "System.Drawing.Color").FromArgb 68 68 68
        local fStyle = (dotNetClass "System.Drawing.FontStyle").Regular
        local f      = dotNetObject "System.Drawing.Font" "Tahoma" 8 fStyle
        
        lbl_title.text = "RM ImportClean v1.6"
        lbl_title.ForeColor = cColor
        lbl_title.BackColor = bgCol
        lbl_title.Font = f
        
        lbl_line.text = ":::::::::::::::::::::::::"
        lbl_line.ForeColor = cColor
        lbl_line.BackColor = bgCol
        lbl_line.Font = f
        
        lbl_resize.BackColor = bgCol
        lbl_resize.Cursor = (dotNetClass "System.Windows.Forms.Cursors").SizeNS
        
        addSubRollout sub_holder roRM_IC_convert rolledUp:false
        addSubRollout sub_holder roRM_IC_clean   rolledUp:true
        addSubRollout sub_holder roRM_IC_elem    rolledUp:false
        
        updateLayout RM_IC_MainRol.height
    )
)

fn RM_IC_openUI =
(
    try (destroyDialog RM_IC_MainRol) catch()
    createDialog RM_IC_MainRol style:#()
)

RM_IC_openUI()
