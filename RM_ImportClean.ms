/***********************************************************************
    RM_ImportClean  v1.7
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

global rm_ic_lang = #RU
global rm_ic_f2e = #()   -- полигон -> индекс элемента
global rm_ic_e2g = #()   -- элемент -> индекс группы
global rm_ic_g2row = #() -- группа  -> строка в multiListBox

global RM_IC_floater
global rm_ic_ef_obj    = undefined
global rm_ic_ef_poly   = true
global rm_ic_ef_elems  = #()
global rm_ic_ef_groups = #()
global rm_ic_par       = #()

global roRM_IC_convert
global roRM_IC_clean
global roRM_IC_elem
global RM_IC_MainRol

--------------------------------------------------------------- ЛОКАЛИЗАЦИЯ И НАСТРОЙКИ
fn rm_ic_t ru en = (if ::rm_ic_lang == #EN then en else ru)

fn rm_ic_getIniPath =
(
    (getDir #plugcfg) + "\\RM_ImportClean.ini"
)

fn rm_ic_loadSettings =
(
    local ini = rm_ic_getIniPath()
    if doesFileExist ini then
    (
        local l = getINISetting ini "Settings" "Language"
        if l == "EN" then rm_ic_lang = #EN else rm_ic_lang = #RU
    )
    else
    (
        rm_ic_lang = #RU
    )
)

fn rm_ic_saveSettings =
(
    local ini = rm_ic_getIniPath()
    setINISetting ini "Settings" "Language" (if rm_ic_lang == #EN then "EN" else "RU")
)

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

-- Разбор объекта на элементы через union-find по вершинам
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

    progressStart (rm_ic_t "RM_ImportClean: анализ элементов..." "RM_ImportClean: analyzing elements...")
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
        messageBox (rm_ic_t "Геометрия объекта изменилась с момента анализа.\nПожалуйста, выполните анализ заново." \
                            "Object geometry has changed since analysis.\nPlease run analysis again.") title:"RM_ImportClean"
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
    ИНТЕРФЕЙС & АВТОПОДГОНКА ВЫСОТЫ
======================================================================*/
global RM_IC_HEADER_H   = 23                 -- замерено: H0=115, H1=395
global RM_IC_PADDING    = 46                 -- замерено, сходится по обеим точкам
global RM_IC_HOLDER_GAP = RM_IC_PADDING - 10 -- 36 px: sub_holder.pos.y(28) + HOLDER_GAP(36) + RESIZE_OFS(8) = PADDING+28
global RM_IC_RESIZE_OFS = 8                  -- 8 px (смещение метки ресайза от низа)
global RM_IC_MARGIN_TOP = 40                 -- 40 px запас от верхнего края экрана
global RM_IC_MARGIN_BOT = 40                 -- 40 px запас от панели задач Windows

fn RM_IC_fitHeight ro sub =
(
    if ro == undefined or (classOf ro != RolloutClass) do return OK
    local need = RM_IC_PADDING
    for r in sub.rollouts do
    (
        need += if r.open then r.height else RM_IC_HEADER_H
    )

    local screenH = sysInfo.desktopSize.y as integer
    local cap = screenH - (RM_IC_MARGIN_TOP + RM_IC_MARGIN_BOT)
    if need > cap do need = cap

    local ds = getDialogSize ro
    if (abs (ds.y - need)) > 1 do (
        setDialogSize ro [ds.x, need]
        ro.sub_holder.height = need - RM_IC_HOLDER_GAP
        ro.lbl_resize.pos = [0, need - RM_IC_RESIZE_OFS]

        -- Защита от вылета за нижнюю кромку монитора:
        local curPos = GetDialogPos ro
        local maxBottom = screenH - RM_IC_MARGIN_BOT
        if (curPos.y + need) > maxBottom do (
            local newY = amax RM_IC_MARGIN_TOP (maxBottom - need)
            SetDialogPos ro [curPos.x, newY]
        )
    )
    OK
)

/*======================================================================
    РОЛЛАУТЫ МОДУЛЕЙ
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

    fn updateLang =
    (
        roRM_IC_convert.title = rm_ic_t "1. Конвертация из Revit (Mesh -> Poly)" "1. Convert from Revit (Mesh -> Poly)"
        lb1.text = rm_ic_t "Заменяет обычный Convert to Poly, который" "Replaces standard Convert to Poly, which"
        lb2.text = rm_ic_t "разваливает скругления на невыпуклых n-gon'ах." "breaks fillets on non-convex n-gons."
        spMax.caption = rm_ic_t "Максимум сторон полигона:" "Max sides per polygon:"
        spMax.tooltip = rm_ic_t "Максимальное число сторон полигона (3 = треугольники, 4 = четырехугольники, >4 = n-гоны)." \
                                 "Max sides per polygon (3 = triangles, 4 = quads, >4 = n-gons)."
        chkConvex.text = "Keep Polygons Convex"
        chkConvex.tooltip = rm_ic_t "Запрещает создавать невыпуклые (вогнутые / L-образные) полигоны. Предотвращает заломы и ошибки затенения на скруглениях." \
                                    "Prevents creation of non-convex (concave / L-shaped) polygons. Eliminates shading glitches on curved CAD surfaces."
        chkPlanar.text = "Require Planar Polygons"
        chkPlanar.tooltip = rm_ic_t "Объединяет треугольники в полигоны только если они лежат строго в одной плоскости (с учетом порога Planar Threshold)." \
                                    "Only merges triangles into polygons if they are coplanar within the Planar Threshold angle."
        spPlanar.caption = rm_ic_t "   Planar Threshold, град:" "   Planar Threshold, deg:"
        spPlanar.tooltip = rm_ic_t "Максимальный угол между нормалями треугольников для их объединения в один плоский полигон." \
                                   "Maximum angle between triangle normals allowed to merge into a single planar polygon."
        chkMidEdge.text = rm_ic_t "Сохранять точки на рёбрах" "Keep mid-edge vertices"
        chkMidEdge.tooltip = rm_ic_t "Сохраняет вершины на рёбрах, предотвращая появление щелей и зазоров на стыках объектов." \
                                     "Preserves collinear vertices on boundary edges to prevent cracks between adjacent parts."
        btnConv.text = rm_ic_t "КОНВЕРТИРОВАТЬ ВЫДЕЛЕННЫЕ" "CONVERT SELECTED"
        btnConv.tooltip = rm_ic_t "Конвертировать выделенные объекты в Editable Poly с правильной топологией через Turn to Poly." \
                                  "Convert selected objects to Editable Poly with clean topology using Turn to Poly."
    )

    on btnConv pressed do
    (
        local objs = for o in selection where superClassOf o == GeometryClass collect o
        if objs.count == 0 do
        (
            messageBox (rm_ic_t "Выдели хотя бы один геометрический объект." "Select at least one geometry object.") title:"RM_ImportClean"
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
        lbConvRes.text = ((rm_ic_t "сконвертировано: " "converted: ") + ok as string + (rm_ic_t " из " " of ") + objs.count as string + \
                          "   (" + (formattedPrint ((timeStamp()-t0)/1000.0) format:".1f") + (rm_ic_t " c)" " s)"))
    )

    on roRM_IC_convert rolledUp state do (
        RM_IC_fitHeight ::RM_IC_MainRol ::RM_IC_MainRol.sub_holder
    )
)

rollout roRM_IC_clean "2. Чистка лишних вершин" width:330
(
    group "Что чистим / What to clean"
    (
        checkbox chkV "Pass 2: вершины на прямой (collinear)" checked:true
        checkbox chkE "Pass 1: рёбра между компланарными гранями" checked:false
    )
    group "Допуски / Tolerances"
    (
        spinner spV "Угол вершины, град:" range:[0.0,45.0,1.0] type:#float scale:0.1 fieldWidth:52
        spinner spF "Угол граней,  град:" range:[0.0,45.0,0.5] type:#float scale:0.1 fieldWidth:52
    )
    group "Не трогать границы / Preserve boundaries"
    (
        checkbox chkMat "Material ID" checked:true across:2
        checkbox chkSG  "Smooth Groups" checked:true
        checkbox chkUV  "UV швы (медленно)" checked:false
    )
    group "Дополнительно / Additional"
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

    fn updateLang =
    (
        roRM_IC_clean.title = rm_ic_t "2. Чистка лишних вершин" "2. Clean Redundant Vertices"
        chkV.text = rm_ic_t "Pass 2: вершины на прямой (collinear)" "Pass 2: Collinear vertices (straight line)"
        chkV.tooltip = rm_ic_t "Удаляет промежуточные вершины на прямых участках рёбер (коллинеарные), не меняя геометрию." \
                                "Removes intermediate collinear vertices along straight edges without changing mesh shape."
        chkE.text = rm_ic_t "Pass 1: рёбра между компланарными гранями" "Pass 1: Coplanar edges (flat surfaces)"
        chkE.tooltip = rm_ic_t "Удаляет невидимые ребра и диагонали триангуляции между гранями, лежащими в одной плоскости." \
                                "Removes internal diagonal edges and triangulation between coplanar faces."
        spV.caption = rm_ic_t "Угол вершины, град:" "Vertex angle, deg:"
        spV.tooltip = rm_ic_t "Максимальное угловое отклонение для признания вершины лежащей на прямой линии." \
                               "Maximum angular deviation for a vertex on an edge to be treated as collinear/straight."
        spF.caption = rm_ic_t "Угол граней,  град:" "Face angle, deg:"
        spF.tooltip = rm_ic_t "Максимальный угол между нормалями граней для признания их лежащими в одной плоскости." \
                               "Maximum angle between face normals to treat adjacent faces as coplanar."
        chkMat.tooltip = rm_ic_t "Не удалять рёбра на границах разных ID материалов (защита Multi/Sub-Object материалов)." \
                                 "Preserve edges between faces with different Material IDs (protects Multi/Sub-Object materials)."
        chkSG.tooltip = rm_ic_t "Не удалять рёбра на границах групп сглаживания (защита жестких ребер / hard edges)." \
                                "Preserve edges at smoothing group boundaries (preserves hard shading edges)."
        chkUV.text = rm_ic_t "UV швы (медленно)" "UV seams (slow)"
        chkUV.tooltip = rm_ic_t "Проверять текстурные каналы и защищать ребра на UV-швах от слияния (медленный режим)." \
                                "Check map channels and protect UV texture seams from being collapsed (slower)."
        chkWeld.text = rm_ic_t "Сначала Weld" "Pre-Weld Vertices"
        chkWeld.tooltip = rm_ic_t "Сварить близкие вершины перед очисткой (устраняет открытые трещины CAD-импорта)." \
                                  "Weld close vertices before cleaning (fixes open boundary cracks from CAD import)."
        spW.tooltip = rm_ic_t "Радиус сварки вершин (в единицах сцены / мм). По умолчанию 0.01." \
                              "Vertex welding threshold distance (in scene units). Default: 0.01."
        chkSel.text = rm_ic_t "Только внутри выделения sub-object" "Only within sub-object selection"
        chkSel.tooltip = rm_ic_t "Применять чистку только к текущему выделению вершин/рёбер в стеке Editable Poly." \
                                 "Apply cleaning only to currently selected sub-object vertices/edges in Editable Poly."
        spIt.caption = rm_ic_t "Повторов (Pass1+Pass2):" "Iterations (Pass1+Pass2):"
        spIt.tooltip = rm_ic_t "Число повторных циклов Pass1 + Pass2 (рекомендуется 2 прохода)." \
                               "Number of clean cycles Pass1 + Pass2 (2 passes recommended)."
        chkUndo.text = rm_ic_t "Включить Undo (жрёт RAM)" "Enable Undo (uses RAM)"
        chkUndo.tooltip = rm_ic_t "Включает запись операции в историю отмены (Ctrl+Z). На тяжелых сетках (>500k полигонов) требует много RAM." \
                                  "Records action into Undo buffer (Ctrl+Z). On huge meshes (>500k polys) may use high RAM."
        btnSel.text = rm_ic_t "1 - ВЫДЕЛИТЬ кандидатов (превью)" "1 - SELECT CANDIDATES (preview)"
        btnSel.tooltip = rm_ic_t "Найти и выделить в sub-object режиме рёбра или вершины под условия чистки без их удаления." \
                                 "Highlight candidate edges and vertices in sub-object mode without deleting them."
        btnRun.text = rm_ic_t "2 - ПОЧИСТИТЬ" "2 - CLEAN MESH"
        btnRun.tooltip = rm_ic_t "Удалить лишние рёбра и вершины согласно выбранным настройкам." \
                                 "Remove redundant edges and collinear vertices according to current settings."
        lbA.text = rm_ic_t "готов" "ready"
    )

    fn doJob selectOnly =
    (
        local objs = for o in selection where rm_ic_isEPoly o collect o
        if objs.count == 0 do
        (
            messageBox (rm_ic_t "Выдели хотя бы один Editable Poly.\nEditable Mesh сначала прогони через блок 1." \
                                "Select at least one Editable Poly.\nFor Editable Mesh, run Block 1 (Convert) first.") title:"RM_ImportClean"
            return false
        )

        local t0 = timeStamp()
        local totE = 0, totV = 0
        local pv0 = 0, pf0 = 0, pv1 = 0, pf1 = 0

        disableSceneRedraw()
        suspendEditing()
        progressStart (rm_ic_t "RM_ImportClean: чистка..." "RM_ImportClean: cleaning...")
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
            lbA.text = ((rm_ic_t "кандидатов: верт " "candidates: verts ") + totV as string + (rm_ic_t " / рёбер " " / edges ") + totE as string)
            lbB.text = ((rm_ic_t "время " "time ") + (formattedPrint dt format:".1f") + (rm_ic_t " c" " s"))
            try (
                max modify mode
                subObjectLevel = if (chkV.checked and totV > 0) then 1 else 2
            ) catch()
        )
        else
        (
            lbA.text = ((rm_ic_t "удалено: верт " "removed: verts ") + totV as string + (rm_ic_t " / рёбер " " / edges ") + totE as string)
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

    on roRM_IC_clean rolledUp state do (
        RM_IC_fitHeight ::RM_IC_MainRol ::RM_IC_MainRol.sub_holder
    )
)

rollout roRM_IC_elem "3. Одинаковые элементы" width:330
(
    group "Анализ / Analysis"
    (
        checkbox chkOrient "Учитывать поворот (строже)" checked:false
        spinner  spTol "Допуск совпадения:" range:[0.0001,1000.0,0.5] type:#float scale:0.01 fieldWidth:60
        button   btnGo "АНАЛИЗИРОВАТЬ ВЫДЕЛЕННЫЙ ОБЪЕКТ" width:299 height:28
    )
    label lbInfo "объект не проанализирован" height:16

    group "Группы одинаковых элементов / Duplicate groups"
    (
        radiobuttons rbSort labels:#("габарит / size", "повторы / count") default:1 columns:2
        multiListBox mlb "" height:12 width:299
    )
    button btnSelGrp "ВЫДЕЛИТЬ отмеченные группы" width:299 height:28

    group "Быстрый фильтр по размеру / Quick filter"
    (
        spinner spSize "Габарит меньше:" range:[0.0,1e9,5.0] type:#float scale:0.1 fieldWidth:60
        spinner spCnt  "и повторов не менее:" range:[1,10000,1] type:#integer fieldWidth:60
    )
    button btnSelSize "ВЫДЕЛИТЬ по фильтру" width:299 height:28
    
    button btnFromVP "НАЙТИ ТАКИЕ ЖЕ (по выделению)" width:299 height:28
    
    button btnDel "УДАЛИТЬ" width:150 height:28 across:2
    button btnDetach "ОТДЕЛИТЬ (Detach)" width:150 height:28
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
            ("x" + (gr[2].count as string) + (rm_ic_t "   габ " "   dim ") + (rm_ic_fmt gr[3]) + \
             "   v" + (gr[4] as string) + " f" + (gr[5] as string))
        )
        true
    )

    fn updateLang =
    (
        roRM_IC_elem.title = rm_ic_t "3. Одинаковые элементы" "3. Identical Elements"
        chkOrient.text = rm_ic_t "Учитывать поворот (строже)" "Consider orientation (strict)"
        chkOrient.tooltip = rm_ic_t "Сравнивать габариты элементов по осям X, Y, Z (не объединяет повернутые детали в одну группу)." \
                                    "Match oriented bounding box dimensions (does not group rotated copies together)."
        spTol.caption = rm_ic_t "Допуск совпадения:" "Match tolerance:"
        spTol.tooltip = rm_ic_t "Допустимая погрешность сравнения размеров и расстояний между вершинами элемента (в единицах сцены)." \
                                "Tolerance for matching vertex distance distributions and element dimensions (in scene units)."
        btnGo.text = rm_ic_t "АНАЛИЗИРОВАТЬ ВЫДЕЛЕННЫЙ ОБЪЕКТ" "ANALYZE SELECTED OBJECT"
        btnGo.tooltip = rm_ic_t "Быстро разобрать геометрию объекта на несвязанные элементы и сгруппировать одинаковые детали." \
                                "Fast scan object geometry into disconnected elements and group identical duplicates."
        rbSort.tooltip = rm_ic_t "Порядок сортировки групп элементов в списке ниже (по габариту или по числу повторов)." \
                                 "Sorting order for element groups in the list below (by size or by instance count)."
        mlb.tooltip = rm_ic_t "Список обнаруженных групп одинаковых деталей. Выберите одну или несколько строк для выделения во вьюпорте." \
                              "List of detected identical element groups. Select one or more rows to highlight in viewport."
        btnSelGrp.text = rm_ic_t "ВЫДЕЛИТЬ отмеченные группы" "SELECT MARKED GROUPS"
        btnSelGrp.tooltip = rm_ic_t "Выделить во вьюпорте все полигоны/элементы, принадлежащие отмеченным в списке группам." \
                                    "Select all faces/elements in viewport belonging to the groups marked in the list."
        spSize.caption = rm_ic_t "Габарит меньше:" "Bounding size <:"
        spSize.tooltip = rm_ic_t "Максимальный диагональный габарит элемента для фильтрации мелких деталей (болты, мусор, фурнитура)." \
                                 "Maximum diagonal bounding size to filter small repetitive parts (screws, dust, hardware)."
        spCnt.caption = rm_ic_t "и повторов не менее:" "and count >="
        spCnt.tooltip = rm_ic_t "Минимальное количество повторений детали в объекте для попадания в фильтр." \
                                "Minimum repetition count for an element group to match the filter."
        btnSelSize.text = rm_ic_t "ВЫДЕЛИТЬ по фильтру" "SELECT BY FILTER"
        btnSelSize.tooltip = rm_ic_t "Выделить во вьюпорте все группы элементов, удовлетворяющие заданному размеру и числу повторов." \
                                     "Highlight in viewport all element groups matching the size and count criteria."
        btnFromVP.text = rm_ic_t "НАЙТИ ТАКИЕ ЖЕ (по выделению)" "FIND SIMILAR (from selection)"
        btnFromVP.tooltip = rm_ic_t "Выделите деталь во вьюпорте и нажмите, чтобы найти и выделить все такие же копии в объекте." \
                                    "Select a part in the viewport and click to find and highlight all identical copies across the object."
        btnDel.text = rm_ic_t "УДАЛИТЬ" "DELETE"
        btnDel.tooltip = rm_ic_t "Безвозвратно удалить выделенные полигоны/элементы и очистить изолированные вершины." \
                                 "Permanently delete selected polygons/elements and remove isolated vertices."
        btnDetach.text = rm_ic_t "ОТДЕЛИТЬ (Detach)" "DETACH (Detach)"
        btnDetach.tooltip = rm_ic_t "Отделить выделенные полигоны/элементы в отдельный новый объект с сохранением трансформаций." \
                                    "Detach selected polygons/elements into a separate new object with preserved transforms."
        if rm_ic_ef_groups.count > 0 then (
            refreshList()
            local dup = 0
            for gr in rm_ic_ef_groups where gr[2].count > 1 do dup += gr[2].count
            lbInfo.text = ((rm_ic_t "элементов " "elements ") + rm_ic_ef_elems.count as string + \
                           (rm_ic_t " / групп " " / groups ") + rm_ic_ef_groups.count as string + \
                           (rm_ic_t " / в повторах " " / in duplicates ") + dup as string)
        ) else (
            lbInfo.text = rm_ic_t "объект не проанализирован" "object not analyzed"
        )
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
            messageBox (rm_ic_t "Выдели ровно ОДИН объект: Editable Poly или Editable Mesh." \
                                "Select exactly ONE object: Editable Poly or Editable Mesh.") title:"RM_ImportClean"
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
        lbInfo.text = ((rm_ic_t "элементов " "elements ") + rm_ic_ef_elems.count as string + \
                       (rm_ic_t " / групп " " / groups ") + rm_ic_ef_groups.count as string + \
                       (rm_ic_t " / в повторах " " / in duplicates ") + dup as string)
        refreshList()
        lbRes.text = ((rm_ic_t "анализ " "analysis ") + (formattedPrint ((timeStamp()-t0)/1000.0) format:".1f") + (rm_ic_t " c" " s"))
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
                messageBox (rm_ic_t "Выделите объект с проанализированной геометрией." \
                                    "Select an object with analyzed geometry.") title:"RM_ImportClean"
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
            lbRes.text = (rm_ic_t "во вьюпорте ничего не выделено" "nothing is selected in viewport")
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
            lbRes.text = (rm_ic_t "элемент не принадлежит ни одной группе" "element does not belong to any group")
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
        lbRes.text = ((rm_ic_t "найдено: " "found: ") + nElems as string + (rm_ic_t " эл., " " elems, ") + bits.numberSet as string + (rm_ic_t " пол." " polys"))
    )

    on rbSort changed st do refreshList()

    on btnSelGrp pressed do
    (
        if rm_ic_ef_groups.count == 0 or not isValidNode rm_ic_ef_obj do return false
        local picked = for i in mlb.selection where mlbMap[i] != undefined collect mlbMap[i]
        if picked.count == 0 do (lbRes.text = (rm_ic_t "не отмечено ни одной группы" "no groups selected in list"); return false)
        local bits = gatherBits picked
        rm_ic_selectFaces rm_ic_ef_obj rm_ic_ef_poly bits
        lbRes.text = ((rm_ic_t "выделено полигонов: " "selected polygons: ") + bits.numberSet as string)
    )

    on btnSelSize pressed do
    (
        if rm_ic_ef_groups.count == 0 or not isValidNode rm_ic_ef_obj do return false
        local picked = for i = 1 to rm_ic_ef_groups.count \
                       where rm_ic_ef_groups[i][3] < spSize.value and \
                             rm_ic_ef_groups[i][2].count >= spCnt.value collect i
        if picked.count == 0 do (lbRes.text = (rm_ic_t "под фильтр ничего не попало" "no elements matched filter"); return false)
        local bits = gatherBits picked
        rm_ic_selectFaces rm_ic_ef_obj rm_ic_ef_poly bits
        local ne = 0
        for gi in picked do ne += rm_ic_ef_groups[gi][2].count
        lbRes.text = ((rm_ic_t "элементов " "elements ") + ne as string + (rm_ic_t ", полигонов " ", polygons ") + bits.numberSet as string)
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
        if bits.numberSet == 0 do (lbRes.text = (rm_ic_t "нет выделенных полигонов" "no polygons selected"); return false)
        
        if (queryBox ((rm_ic_t "Удалить " "Delete ") + bits.numberSet as string + \
                      (rm_ic_t " выделенных полигонов?\nОтмена недоступна." " selected polygons?\nUndo is not available.")) \
                     title:"RM_ImportClean") do
        (
            undo off
            (
                if isPoly then (polyop.deleteFaces o bits delIsoVerts:true)
                else (meshop.deleteFaces o bits delIsoVerts:true)
                update o
            )
            redrawViews()
            lbRes.text = ((rm_ic_t "удалено полигонов: " "deleted polygons: ") + bits.numberSet as string + (rm_ic_t " (нужен повторный анализ)" " (re-analysis required)"))
            rm_ic_ef_groups = #(); rm_ic_ef_elems = #(); rm_ic_f2e = #(); rm_ic_e2g = #(); mlbMap = #(); mlb.items = #()
            lbInfo.text = (rm_ic_t "объект изменён - проанализируй заново" "object modified - analyze again")
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
        if bits.numberSet == 0 do (lbRes.text = (rm_ic_t "нет выделенных полигонов" "no polygons selected"); return false)
        
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
        
        lbRes.text = ((rm_ic_t "отделено: " "detached: ") + (if isValidNode newObj then newObj.name else newName) + " (" + cnt as string + (rm_ic_t " пол.)" " polys)"))
        rm_ic_ef_groups = #(); rm_ic_ef_elems = #(); rm_ic_f2e = #(); rm_ic_e2g = #(); mlbMap = #(); mlb.items = #()
        lbInfo.text = (rm_ic_t "объект изменён - проанализируй заново" "object modified - analyze again")
    )

    on roRM_IC_elem rolledUp state do (
        RM_IC_fitHeight ::RM_IC_MainRol ::RM_IC_MainRol.sub_holder
    )
)

/*======================================================================
    ГЛАВНОЕ ОКНО СО СТАНДАРТНЫМ СТЕКОМ МОДУЛЕЙ (SUBROLLOUT)
======================================================================*/
rollout RM_IC_MainRol "RM ImportClean" width:340 height:720
(
    local isDragging = false
    local isResizing = false
    local dragStartScreen = [0,0]
    local dragStartDialog = [0,0]
    local dragStartH = 720

    -- [КАСТОМНЫЙ TITLE BAR]
    dotNetControl lbl_title "System.Windows.Forms.Label" pos:[8,7] width:125 height:15
    dotNetControl lbl_line  "System.Windows.Forms.Label" pos:[135,7] width:140 height:15
    button btn_lang "EN" width:28 height:20 pos:[280,4]
    button btn_close "X" width:20 height:20 pos:[312,4] tooltip:"Close"
    
    -- [СТАНДАРТНЫЙ SUBROLLOUT ДЛЯ ВСЕХ 3 МОДУЛЕЙ]
    subRollout sub_holder "" pos:[4,28] width:332 height:684
    
    -- [НИЖНИЙ РЕСАЙЗЕР ДЛЯ СВОБОДНОЙ РЕГУЛИРОВКИ ВЫСОТЫ]
    dotNetControl lbl_resize "System.Windows.Forms.Label" pos:[0,712] width:340 height:8
    
    fn updateLayout h = (
        local newH = amax 115 h
        setDialogSize RM_IC_MainRol [340, newH]
        sub_holder.height = newH - RM_IC_HOLDER_GAP
        lbl_resize.pos = [0, newH - RM_IC_RESIZE_OFS]
    )

    fn applyLanguage =
    (
        local r1_open = roRM_IC_convert.open
        local r2_open = roRM_IC_clean.open
        local r3_open = roRM_IC_elem.open
        
        -- 1. Снимаем роллауты с контейнера
        removeSubRollout sub_holder roRM_IC_convert
        removeSubRollout sub_holder roRM_IC_clean
        removeSubRollout sub_holder roRM_IC_elem
        
        -- 2. Задаем заголовки баннеров ДО монтирования в SubRollout
        roRM_IC_convert.title = rm_ic_t "1. Конвертация из Revit (Mesh -> Poly)" "1. Convert from Revit (Mesh -> Poly)"
        roRM_IC_clean.title   = rm_ic_t "2. Чистка лишних вершин" "2. Clean Redundant Vertices"
        roRM_IC_elem.title    = rm_ic_t "3. Одинаковые элементы" "3. Identical Elements"
        
        -- 3. Монтируем роллауты обратно с сохранением их раскрытого/свернутого состояния
        addSubRollout sub_holder roRM_IC_convert rolledUp:(not r1_open)
        addSubRollout sub_holder roRM_IC_clean   rolledUp:(not r2_open)
        addSubRollout sub_holder roRM_IC_elem    rolledUp:(not r3_open)
        
        -- 4. Обновляем тексты всех внутренних контролов ПОСЛЕ монтирования
        roRM_IC_convert.updateLang()
        roRM_IC_clean.updateLang()
        roRM_IC_elem.updateLang()
        
        -- 5. Обновляем кнопки заголовка
        btn_lang.text = if rm_ic_lang == #RU then "EN" else "RU"
        btn_lang.tooltip = rm_ic_t "Переключить на английский язык (Switch to English)" "Переключить на русский язык (Switch to Russian)"
        btn_close.tooltip = rm_ic_t "Закрыть RM ImportClean" "Close RM ImportClean"
        
        -- 6. Подгоняем высоту
        RM_IC_fitHeight RM_IC_MainRol sub_holder
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
    
    on btn_lang pressed do
    (
        rm_ic_lang = if rm_ic_lang == #RU then #EN else #RU
        rm_ic_saveSettings()
        applyLanguage()
    )

    on btn_close pressed do destroyDialog RM_IC_MainRol
    
    on RM_IC_MainRol open do (
        local cColor = (dotNetClass "System.Drawing.Color").FromArgb 0 170 200
        local bgCol  = (dotNetClass "System.Drawing.Color").FromArgb 68 68 68
        local fStyle = (dotNetClass "System.Drawing.FontStyle").Regular
        local f      = dotNetObject "System.Drawing.Font" "Tahoma" 8 fStyle
        
        lbl_title.text = "RM ImportClean v1.7"
        lbl_title.ForeColor = cColor
        lbl_title.BackColor = bgCol
        lbl_title.Font = f
        
        lbl_line.text = "::::::::::::::::::::"
        lbl_line.ForeColor = cColor
        lbl_line.BackColor = bgCol
        lbl_line.Font = f
        
        lbl_resize.BackColor = bgCol
        lbl_resize.Cursor = (dotNetClass "System.Windows.Forms.Cursors").SizeNS
        
        -- Начальная установка заголовков под текущий язык:
        roRM_IC_convert.title = rm_ic_t "1. Конвертация из Revit (Mesh -> Poly)" "1. Convert from Revit (Mesh -> Poly)"
        roRM_IC_clean.title   = rm_ic_t "2. Чистка лишних вершин" "2. Clean Redundant Vertices"
        roRM_IC_elem.title    = rm_ic_t "3. Одинаковые элементы" "3. Identical Elements"

        -- Добавляем роллауты в контейнер:
        addSubRollout sub_holder roRM_IC_convert rolledUp:false
        addSubRollout sub_holder roRM_IC_clean   rolledUp:true
        addSubRollout sub_holder roRM_IC_elem    rolledUp:true

        -- Обновляем контролы:
        roRM_IC_convert.updateLang()
        roRM_IC_clean.updateLang()
        roRM_IC_elem.updateLang()
        
        btn_lang.text = if rm_ic_lang == #RU then "EN" else "RU"
        btn_lang.tooltip = rm_ic_t "Переключить на английский язык (Switch to English)" "Переключить на русский язык (Switch to Russian)"
        btn_close.tooltip = rm_ic_t "Закрыть RM ImportClean" "Close RM ImportClean"

        -- Автоподгонка начальной высоты:
        RM_IC_fitHeight RM_IC_MainRol sub_holder
    )
)

fn RM_IC_openUI =
(
    try (destroyDialog RM_IC_MainRol) catch()
    rm_ic_loadSettings()
    createDialog RM_IC_MainRol style:#()
)

RM_IC_openUI()
