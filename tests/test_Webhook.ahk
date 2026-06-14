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

failures := t.Report()
ExitApp(failures)
