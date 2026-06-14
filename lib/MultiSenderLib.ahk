; ═══════════════════════════════════════════════════════════
; MultiSender Library - Extracted pure/testable functions
; ═══════════════════════════════════════════════════════════

; ── Utility ────────────────────────────────────────────────

FormatBytes(bytes) {
    if (bytes > 1048576)
        return Round(bytes / 1048576, 1) " MB/s"
    else if (bytes > 1024)
        return Round(bytes / 1024, 1) " KB/s"
    else
        return bytes " B/s"
}

; ── Config I/O ─────────────────────────────────────────────

LoadConfigFromFile(configFile, &followers, &schedulerInterval, &repeatCount,
                   &randomDelayMin, &randomDelayMax, &webhookURL,
                   &webhookEnabled, &passwordProtection, &masterPassword) {
    followers := []
    if !FileExist(configFile)
        return

    try {
        n := Integer(IniRead(configFile, "Win", "count", "0"))
        Loop n {
            val := IniRead(configFile, "Win", "f" A_Index, "")
            if (val != "")
                followers.Push(val)
        }

        schedulerInterval := Integer(IniRead(configFile, "Features", "schedulerInterval", "5000"))
        repeatCount := Integer(IniRead(configFile, "Features", "repeatCount", "1"))
        randomDelayMin := Integer(IniRead(configFile, "Features", "randomDelayMin", "0"))
        randomDelayMax := Integer(IniRead(configFile, "Features", "randomDelayMax", "1000"))
        webhookURL := IniRead(configFile, "Features", "webhookURL", "")
        webhookEnabled := Integer(IniRead(configFile, "Features", "webhookEnabled", "0"))
        passwordProtection := Integer(IniRead(configFile, "Features", "passwordProtection", "0"))
        masterPassword := IniRead(configFile, "Features", "masterPassword", "")
    } catch {
        followers := []
    }
}

SaveConfigToFile(configFile, followers, schedulerInterval, repeatCount,
                 randomDelayMin, randomDelayMax, webhookURL,
                 webhookEnabled, passwordProtection, masterPassword) {
    try {
        if FileExist(configFile)
            FileDelete(configFile)

        IniWrite(followers.Length, configFile, "Win", "count")
        Loop followers.Length
            IniWrite(followers[A_Index], configFile, "Win", "f" A_Index)

        IniWrite(schedulerInterval, configFile, "Features", "schedulerInterval")
        IniWrite(repeatCount, configFile, "Features", "repeatCount")
        IniWrite(randomDelayMin, configFile, "Features", "randomDelayMin")
        IniWrite(randomDelayMax, configFile, "Features", "randomDelayMax")
        IniWrite(webhookURL, configFile, "Features", "webhookURL")
        IniWrite(webhookEnabled, configFile, "Features", "webhookEnabled")
        IniWrite(passwordProtection, configFile, "Features", "passwordProtection")
        IniWrite(masterPassword, configFile, "Features", "masterPassword")
    }
}

; ── Theme I/O ──────────────────────────────────────────────

LoadThemeFromFile(themeFile) {
    if FileExist(themeFile) {
        return Integer(IniRead(themeFile, "Theme", "darkMode", "1"))
    }
    return 1
}

SaveThemeToFile(themeFile, isDarkMode) {
    IniWrite(isDarkMode ? "1" : "0", themeFile, "Theme", "darkMode")
}

; ── Messages I/O ───────────────────────────────────────────

LoadMessagesFromFile(msgFile) {
    try {
        if !FileExist(msgFile) {
            defaultMsgs := "Hello`r`nThank you"
            FileAppend(defaultMsgs, msgFile, "UTF-8")
        }
        return FileRead(msgFile, "UTF-8")
    } catch {
        return "Hello"
    }
}

SaveMessagesToFile(msgFile, txt) {
    try {
        if FileExist(msgFile)
            FileDelete(msgFile)
        FileAppend(Trim(txt, "`r`n "), msgFile, "UTF-8")
    }
}

; ── Stats ──────────────────────────────────────────────────

ResetSendStats(&sendStats) {
    sendStats := {count: 0, success: 0, failed: 0}
}

ComputeSuccessRate(sendStats) {
    if (sendStats.count = 0)
        return 0
    return Round((sendStats.success / sendStats.count) * 100)
}

; ── History ────────────────────────────────────────────────

AddToSendHistory(&sendHistory, &sendStats, historyFile, windowIdx, message, success) {
    timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    entry := timestamp " | Window:" windowIdx " | " (success ? "+" : "-") " | " message

    sendHistory.Push(entry)
    if (sendHistory.Length > 1000)
        sendHistory.RemoveAt(1)

    try {
        FileAppend(entry "`r`n", historyFile, "UTF-8")
    }

    sendStats.count++
    if (success)
        sendStats.success++
    else
        sendStats.failed++
}

ClearSendHistory(&sendHistory, historyFile) {
    sendHistory := []
    if FileExist(historyFile)
        FileDelete(historyFile)
}

ExportSendHistory(sendHistory, exportDir) {
    filepath := exportDir "\send_history_" FormatTime(, "yyyyMMdd_HHmmss") ".txt"
    content := ""
    for entry in sendHistory
        content .= entry "`r`n"
    FileAppend(content, filepath, "UTF-8")
    return filepath
}

; ── Hotkey Config I/O ──────────────────────────────────────

LoadHotkeysFromFile(hotkeyFile) {
    hotkeys := Map()
    if !FileExist(hotkeyFile)
        return hotkeys
    try {
        n := Integer(IniRead(hotkeyFile, "Hotkeys", "count", "0"))
        Loop n {
            key := IniRead(hotkeyFile, "Hotkeys", "key" A_Index, "")
            action := IniRead(hotkeyFile, "Hotkeys", "action" A_Index, "")
            if (key != "" && action != "")
                hotkeys[key] := action
        }
    }
    return hotkeys
}

SaveHotkeysToFile(hotkeyFile, hotkeys) {
    try {
        if FileExist(hotkeyFile)
            FileDelete(hotkeyFile)
        idx := 0
        for key, action in hotkeys {
            idx++
            IniWrite(key, hotkeyFile, "Hotkeys", "key" idx)
            IniWrite(action, hotkeyFile, "Hotkeys", "action" idx)
        }
        IniWrite(idx, hotkeyFile, "Hotkeys", "count")
    }
}

; ── Webhook Payload ────────────────────────────────────────

BuildWebhookPayload(windowIdx, message, success) {
    escapedMsg := StrReplace(message, '\', '\\')
    escapedMsg := StrReplace(escapedMsg, '"', '\"')
    escapedMsg := StrReplace(escapedMsg, '`n', '\n')
    escapedMsg := StrReplace(escapedMsg, '`r', '\r')
    escapedMsg := StrReplace(escapedMsg, '`t', '\t')
    timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    return '{"window":' windowIdx ',"message":"' escapedMsg '","success":' (success ? "true" : "false") ',"timestamp":"' timestamp '"}'
}

; ── Message Parsing ────────────────────────────────────────

ParseMessageLines(rawTxt) {
    lines := []
    Loop Parse rawTxt, "`n", "`r" {
        t := Trim(A_LoopField)
        if (t != "")
            lines.Push(t)
    }
    return lines
}
