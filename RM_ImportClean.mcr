-- ======================================================================
--  RM_ImportClean MacroScript
-- ======================================================================
macroScript RM_ImportClean
category:"RM scripts"
buttonText:"Import Clean"
toolTip:"RM ImportClean - Mesh cleaner & converter"
iconName:"Icon_RM_ImportClean"
(
    on execute do
    (
        local scriptPath = (getDir #userScripts) + "\\RM_ImportClean.ms"
        if doesFileExist scriptPath then
        (
            filein scriptPath
        )
        else
        (
            messageBox ("Файл скрипта не найден:\n" + scriptPath) title:"RM ImportClean"
        )
    )
)
