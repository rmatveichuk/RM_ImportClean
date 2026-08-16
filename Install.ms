(
    local scrname = "RM ImportClean"
    local mcrname = "RM_ImportClean.mcr"
    local scriptname = "RM_ImportClean.ms"
    
    -- Закрываем старый интерфейс и любые открытые окна этого плагина
    try (destroyDialog ::RM_IC_MainRol) catch()
    try (closeRolloutFloater ::RM_IC_floater) catch()
    try (destroyDialog ::roRM_IC_convert) catch()
    try (destroyDialog ::roRM_IC_clean) catch()
    try (destroyDialog ::roRM_IC_elem) catch()
    
    local desktopHWNDs = windows.getChildrenHWND (windows.getDesktopHWND())
    for h in desktopHWNDs do
    (
        local title = h[5]
        if title != undefined and (
            (matchPattern title pattern:"*RM ImportClean*") or 
            (matchPattern title pattern:"*RM_ImportClean*") or 
            (matchPattern title pattern:"*RM_MeshTools*") or 
            (matchPattern title pattern:"*RM MeshTools*")
        ) do
        (
            try (UIAccessor.CloseDialog h[1]) catch()
        )
    )
    
    -- Удаляем устаревшие макросы прошлых версий
    try (
        local oldMcr1 = (getDir #userMacros) + "\\RM_MeshCleaner.mcr"
        local oldMcr2 = (getDir #userMacros) + "\\RM_MeshTools.mcr"
        if doesFileExist oldMcr1 do deleteFile oldMcr1
        if doesFileExist oldMcr2 do deleteFile oldMcr2
    ) catch ()

    -- Выполняем макроскрипт и логику для авто-регистрации без перезапуска Max
    try (
        filein (getdir #userMacros + "\\" + mcrname)
        filein (getdir #userScripts + "\\" + scriptname)
    ) catch (
        format "RM_ImportClean Install Error: %\n" (getCurrentException())
    )

    -- Создаем понятное окно об успешной установке
    try(destroyDialog ::RM_IC_InstallMsg) catch()
    rollout RM_IC_InstallMsg "Установка завершена" width:360 height:180
    (
        label lbl_title "Скрипт RM ImportClean успешно установлен!" pos:[15,15] bold:true
        
        label lbl_info1 "Как добавить кнопку на панель:" pos:[15,45]
        label lbl_info2 "1. Customize -> Customize User Interface" pos:[15,65]
        label lbl_info3 "2. Вкладка Toolbars" pos:[15,80]
        label lbl_info4 "3. В списке Category выберите: RM scripts" pos:[15,95]
        label lbl_info5 "4. Перетащите 'Import Clean' на любую панель" pos:[15,110]
        
        button btn_close "Закрыть" width:90 height:26 pos:[135,140]
        
        on btn_close pressed do destroyDialog ::RM_IC_InstallMsg
    )
    
    createDialog ::RM_IC_InstallMsg modal:false
    ok
)
