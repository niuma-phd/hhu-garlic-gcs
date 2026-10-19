Unicode true

; Name shown to the user (wizard, Apps & Features, Start menu). APPNAME stays the key for the
; install dir and the uninstall registry entry, so upgrades find the previous install.
!ifndef DISPLAYNAME
    !define DISPLAYNAME "${APPNAME}"
!endif

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "Win\COM.nsh"
!include "Win\Propkey.nsh"
!include "FileFunc.nsh"

RequestExecutionLevel admin

!macro DemoteShortCut target
    !insertmacro ComHlpr_CreateInProcInstance ${CLSID_ShellLink} ${IID_IShellLink} r0 ""
    ${If} $0 <> 0
        ${IUnknown::QueryInterface} $0 '("${IID_IPersistFile}",.r1)'
        ${If} $1 P<> 0
            ${IPersistFile::Load} $1 '("${target}",1)'
            ${IUnknown::Release} $1 ""
        ${EndIf}
        ${IUnknown::QueryInterface} $0 '("${IID_IPropertyStore}",.r1)'
        ${If} $1 P<> 0
            System::Call '*${SYSSTRUCT_PROPERTYKEY}(${PKEY_AppUserModel_StartPinOption})p.r2'
            System::Call '*${SYSSTRUCT_PROPVARIANT}(${VT_UI4},,&i4 ${APPUSERMODEL_STARTPINOPTION_NOPINONINSTALL})p.r3'
            ${IPropertyStore::SetValue} $1 '($2,$3)'

            System::Call '*$2${SYSSTRUCT_PROPERTYKEY}(${PKEY_AppUserModel_ExcludeFromShowInNewInstall})'
            System::Call '*$3${SYSSTRUCT_PROPVARIANT}(${VT_BOOL},,&i2 ${VARIANT_TRUE})'
            ${IPropertyStore::SetValue} $1 '($2,$3)'

            System::Free $2
            System::Free $3
            ${IPropertyStore::Commit} $1 ""
            ${IUnknown::Release} $1 ""
        ${EndIf}
        ${IUnknown::QueryInterface} $0 '("${IID_IPersistFile}",.r1)'
        ${If} $1 P<> 0
            ${IPersistFile::Save} $1 '("${target}",1)'
            ${IUnknown::Release} $1 ""
        ${EndIf}
        ${IUnknown::Release} $0 ""
    ${EndIf}
!macroend

Name "${DISPLAYNAME}"
BrandingText "${DISPLAYNAME}"
Var StartMenuFolder

InstallDir "$PROGRAMFILES64\${APPNAME}"
SetCompressor /SOLID /FINAL lzma

!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_BITMAP "${HEADER_BITMAP}"
!define MUI_ICON "${INSTALLER_ICON}"
!define MUI_UNICON "${INSTALLER_ICON}"

; Open source notices before choosing where to install (custom builds pass LICENSE_FILE)
!ifdef LICENSE_FILE
    !define MUI_PAGE_HEADER_TEXT "开源许可声明"
    !define MUI_PAGE_HEADER_SUBTEXT "安装前请阅读本软件使用的开源软件及其许可证。"
    !define MUI_LICENSEPAGE_TEXT_TOP "按 Page Down 查看其余内容。许可证原文随软件安装在安装目录的 licenses 文件夹中。"
    !define MUI_LICENSEPAGE_TEXT_BOTTOM "点击“我接受”继续安装。"
    !insertmacro MUI_PAGE_LICENSE "${LICENSE_FILE}"
!endif
!insertmacro MUI_PAGE_STARTMENU Application $StartMenuFolder
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "SimpChinese"

Section "Install" SecMain
    SectionIn RO
    DetailPrint "检查已安装的版本"
    SetRegView 64
    ReadRegStr $R0 HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "UninstallString"
    StrCmp $R0 "" doInstall checkUninstaller

checkUninstaller:
    ; Remove quotes from uninstaller path to check if file exists
    StrCpy $R1 $R0 "" 1  ; Skip first quote
    StrLen $R2 $R1
    IntOp $R2 $R2 - 1    ; Remove last quote
    StrCpy $R1 $R1 $R2

    DetailPrint "检查卸载程序：$R1"
    IfFileExists "$R1" doUninstall cleanupOrphanedRegistry

cleanupOrphanedRegistry:
    DetailPrint "未找到旧版本的卸载程序，清理残留的注册表项…"
    SetRegView 64
    DeleteRegKey HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}"
    DeleteRegKey HKLM "SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\${EXENAME}.exe"
    Goto doInstall

doUninstall:
    DetailPrint "正在卸载旧版本…"
    ClearErrors
    ExecWait "$R0 /S -LEAVE_DATA=1 _?=$INSTDIR"
    ${If} ${Errors}
        MessageBox MB_OK|MB_ICONEXCLAMATION "无法启动旧版本的卸载程序。"
        Abort
    ${EndIf}
    IntCmp $0 0 doInstall
    MessageBox MB_OK|MB_ICONEXCLAMATION "无法卸载已安装的${DISPLAYNAME}旧版本。$\n$\n请先在“设置 → 应用”里卸载它，再继续安装。"
    Abort

doInstall:
    SetRegView 64
    SetOutPath $INSTDIR
    ; Install payload
    File /r /x ${EXENAME}.pdb /x ${EXENAME}.lib /x ${EXENAME}.exp ${DESTDIR}\*.*

    ; Create uninstaller and ARP data
    WriteUninstaller "$INSTDIR\${EXENAME}-Uninstall.exe"
    WriteRegStr   HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "DisplayName"    "${DISPLAYNAME}"
    WriteRegStr   HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "UninstallString" "$\"$INSTDIR\${EXENAME}-Uninstall.exe$\""
    WriteRegStr   HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "DisplayIcon"     "$INSTDIR\bin\${EXENAME}.exe"
    WriteRegStr   HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "InstallLocation" "$INSTDIR"
    WriteRegDWORD HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "NoModify" 1
    WriteRegDWORD HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "NoRepair" 1
    !ifdef ORGNAME
        WriteRegStr HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "Publisher" "${ORGNAME}"
    !endif
    !ifdef APPVERSION
        WriteRegStr HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "DisplayVersion" "${APPVERSION}"
    !endif

    ; WER dumps for crash triage
    WriteRegDWORD    HKLM "SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\${EXENAME}.exe" "DumpCount" 5
    WriteRegDWORD    HKLM "SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\${EXENAME}.exe" "DumpType" 1
    WriteRegExpandStr HKLM "SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\${EXENAME}.exe" "DumpFolder" "%LOCALAPPDATA%\${APPNAME}CrashDumps"

done:
    SetRegView lastused
SectionEnd

Section "Uninstall"
    SetRegView 64
    ${GetParameters} $R0
    ${GetOptions} $R0 "-LEAVE_DATA=" $R1
    !insertmacro MUI_STARTMENU_GETFOLDER Application $StartMenuFolder

    ; Remove files and shortcuts
    SetShellVarContext all
    RMDir /r /REBOOTOK "$INSTDIR"
    RMDir /r /REBOOTOK "$SMPROGRAMS\$StartMenuFolder\"
    SetShellVarContext current

    ${If} $R1 != 1
        RMDir /r /REBOOTOK "$APPDATA\${ORGNAME}\"
    ${EndIf}

    ; Remove ARP + WER
    DeleteRegKey HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}"
    DeleteRegKey HKLM "SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\${EXENAME}.exe"
SectionEnd

Section "Create Start Menu Shortcuts"
    SetRegView 64
    SetShellVarContext all
    CreateDirectory "$SMPROGRAMS\$StartMenuFolder"

    !insertmacro MUI_STARTMENU_WRITE_BEGIN Application
        CreateShortCut "$SMPROGRAMS\$StartMenuFolder\${DISPLAYNAME}.lnk" "$INSTDIR\bin\${EXENAME}.exe" "" "$INSTDIR\bin\${EXENAME}.exe" 0
        CreateShortCut "$SMPROGRAMS\$StartMenuFolder\${DISPLAYNAME}（兼容显示模式）.lnk" "$INSTDIR\bin\${EXENAME}.exe" "-swrast" "$INSTDIR\bin\${EXENAME}.exe" 0
        !insertmacro DemoteShortCut "$SMPROGRAMS\$StartMenuFolder\${DISPLAYNAME}（兼容显示模式）.lnk"
    !insertmacro MUI_STARTMENU_WRITE_END
SectionEnd
