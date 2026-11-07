import Carbon
func test(_ id: String) {
  let srcs = TISCreateInputSourceList([kTISPropertyInputSourceID as String: id] as CFDictionary, true).takeRetainedValue() as! [TISInputSource]
  guard let src = srcs.first, let p = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { print(id, "자판 데이터 없음"); return }
  let data = unsafeBitCast(p, to: CFData.self)
  let layout = unsafeBitCast(CFDataGetBytePtr(data), to: UnsafePointer<UCKeyboardLayout>.self)
  for (name, kc, mod) in [("Opt+Shift+9", UInt16(25), UInt32(optionKey|shiftKey)), ("Shift+`", UInt16(50), UInt32(shiftKey))] {
    var dead: UInt32 = 0; var len = 0; var buf = [UniChar](repeating: 0, count: 4)
    UCKeyTranslate(layout, kc, UInt16(kUCKeyActionDown), (mod >> 8) & 0xFF, 40, OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &len, &buf)
    let s = String(utf16CodeUnits: buf, count: len); print(id, name, s, s.unicodeScalars.map{String(format:"U+%04X",$0.value)})
  }
}
test("com.apple.keylayout.ABC")
