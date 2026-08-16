-- =========================================================================================
--  tools/probe_ui_height.ms
--  Диагностический скрипт приёмки автоподгонки высоты окна RM_ImportClean под DPI.
--  Измеряет все 8 комбинаций роллаутов, положение окна на экране и видимость кнопок.
-- =========================================================================================

(
    local ro = ::RM_IC_MainRol
    if ro == undefined or (classOf ro != RolloutClass) or not ro.open do (
        return "RM_ImportClean не открыт. Запустите RM_ImportClean.ms перед тестом."
    )
    
    local sub = ro.sub_holder
    local screenH = sysInfo.desktopSize.y as integer
    local cap = screenH - 80
    
    -- 8 комбинаций состояний роллаутов
    local combos = #(
        #(false, false, false, "000 (все свернуты)"),
        #(true,  false, false, "100 (только мод 1)"),
        #(false, true,  false, "010 (только мод 2)"),
        #(false, false, true,  "001 (только мод 3)"),
        #(true,  true,  false, "110 (мод 1 + 2)   "),
        #(true,  false, true,  "101 (мод 1 + 3)   "),
        #(false, true,  true,  "011 (мод 2 + 3)   "),
        #(true,  true,  true,  "111 (все три)     ")
    )
    
    local out = "\n====================================================================================================\n"
    out += ("          ПРИЁМКА АВТОПОДГОНКИ ВЫСОТЫ ОКНА (SCREEN: " + (sysInfo.desktopSize.x as integer) as string + "x" + screenH as string + " px, CAP: " + cap as string + " px)\n")
    out += "====================================================================================================\n"
    out += "Состояние роллаутов | getDialogSize.y | sub_holder.h | Сумма откр. | Кламп | Низ виден на экране?\n"
    out += "--------------------+-----------------+--------------+-------------+-------+----------------------\n"
    
    for c in combos do
    (
        sub.rollouts[1].open = c[1]
        sub.rollouts[2].open = c[2]
        sub.rollouts[3].open = c[3]
        windows.processPostedMessages()
        
        RM_IC_fitHeight ro sub
        windows.processPostedMessages()
        
        local dlgSize = getDialogSize ro
        local dlgPos = GetDialogPos ro
        local subH = sub.height
        
        local openSum = 0
        for r in sub.rollouts where r.open do openSum += r.height
        
        local isClamped = (dlgSize.y == cap)
        local bottomScreenY = dlgPos.y + dlgSize.y
        local isBottomVisible = (bottomScreenY <= screenH)
        
        local padLabel = substring (c[4] + "                   ") 1 19
        out += (" " + padLabel + " | " + (dlgSize.y as integer) as string + " px        | " + (subH as integer) as string + " px      | " + openSum as string + " px      | " + (if isClamped then "ДА   " else "НЕТ  ") + " | " + (if isBottomVisible then "ДА " else "НЕТ") + " (Y=" + (bottomScreenY as integer) as string + ", max " + screenH as string + ")\n")
    )
    out += "====================================================================================================\n"
    
    -- Восстановление стандартного стартового состояния (открыт только Модуль 1)
    sub.rollouts[1].open = true
    sub.rollouts[2].open = false
    sub.rollouts[3].open = false
    RM_IC_fitHeight ro sub
    windows.processPostedMessages()
    
    format "%\n" out
    out
)
