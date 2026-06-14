#Requires AutoHotkey v2.0
#Include ..\lib\MultiSenderLib.ahk
#Include TestHelper.ahk

t := TestRunner("Webhook")

; ── BuildWebhookPayload structure ──────────────────────────

payload := BuildWebhookPayload(1, "hello world", true)
t.AssertTrue(InStr(payload, '"window":1') > 0, "window field")
t.AssertTrue(InStr(payload, '"message":"hello world"') > 0, "message field")
t.AssertTrue(InStr(payload, '"success":true') > 0, "success true")
t.AssertTrue(InStr(payload, '"timestamp":') > 0, "timestamp present")

; ── Payload with failure ───────────────────────────────────

payload := BuildWebhookPayload(3, "test msg", false)
t.AssertTrue(InStr(payload, '"success":false') > 0, "success false")
t.AssertTrue(InStr(payload, '"window":3') > 0, "window index 3")

; ── Payload with quotes in message ─────────────────────────

payload := BuildWebhookPayload(1, 'say "hi"', true)
t.AssertTrue(InStr(payload, '\"hi\"') > 0, "quotes escaped")
t.AssertFalse(InStr(payload, 'say "hi"') > 0, "raw quotes not present")

; ── Backslashes escaped before quotes ──────────────────────

payload := BuildWebhookPayload(1, 'C:\Users\test', true)
t.AssertTrue(InStr(payload, 'C:\\Users\\test') > 0, "backslashes escaped")
t.AssertFalse(InStr(payload, 'C:\Users\test') > 0, "raw backslashes not present")

; ── Control characters escaped ─────────────────────────────

payload := BuildWebhookPayload(1, "line1`nline2", true)
t.AssertTrue(InStr(payload, 'line1\nline2') > 0, "newline escaped")

payload := BuildWebhookPayload(1, "col1`tcol2", true)
t.AssertTrue(InStr(payload, 'col1\tcol2') > 0, "tab escaped")

; ── Backslash-quote combo ──────────────────────────────────

payload := BuildWebhookPayload(1, 'path\"file', true)
t.AssertTrue(InStr(payload, 'path\\\"file') > 0, "backslash then quote")

failures := t.Report()
ExitApp(failures)
