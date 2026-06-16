#Requires AutoHotkey v2.0
#Include ..\lib\MultiSenderLib.ahk
#Include TestHelper.ahk

t := TestRunner("FormatBytes")

; Bytes range
t.AssertEqual(FormatBytes(0), "0 B/s", "zero bytes")
t.AssertEqual(FormatBytes(1), "1 B/s", "one byte")
t.AssertEqual(FormatBytes(512), "512 B/s", "512 bytes")
t.AssertEqual(FormatBytes(1024), "1024 B/s", "exactly 1024 bytes (boundary)")

; Kilobytes range
t.AssertEqual(FormatBytes(1025), "1.0 KB/s", "just above 1024")
t.AssertEqual(FormatBytes(2048), "2.0 KB/s", "2 KB")
t.AssertEqual(FormatBytes(524288), "512.0 KB/s", "512 KB")
t.AssertEqual(FormatBytes(1048576), "1024.0 KB/s", "exactly 1 MB boundary")

; Megabytes range
t.AssertEqual(FormatBytes(1048577), "1.0 MB/s", "just above 1 MB")
t.AssertEqual(FormatBytes(2097152), "2.0 MB/s", "2 MB")
t.AssertEqual(FormatBytes(10485760), "10.0 MB/s", "10 MB")
t.AssertEqual(FormatBytes(1073741824), "1024.0 MB/s", "1 GB")

failures := t.Report()
ExitApp(failures)
