import Carbon
let srcs = TISCreateInputSourceList([kTISPropertyInputSourceID as String: "com.apple.keylayout.ABC"] as CFDictionary, true).takeRetainedValue() as! [TISInputSource]
let src = srcs[0]
let data = unsafeBitCast(TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData), to: CFData.self)
let layout = unsafeBitCast(CFDataGetBytePtr(data), to: UnsafePointer<UCKeyboardLayout>.self)
func ch(_ kc: UInt16, _ mod: UInt32, _ kt: UInt32) -> String {
  var dead: UInt32 = 0; var len = 0; var buf = [UniChar](repeating: 0, count: 4)
  UCKeyTranslate(layout, kc, UInt16(kUCKeyActionDown), (mod >> 8) & 0xFF, kt, OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &len, &buf)
  return String(utf16CodeUnits: buf, count: len)
}
for kc in UInt16(0)...UInt16(127) {
  let j = ch(kc,0,42), js = ch(kc,UInt32(shiftKey),42), a = ch(kc,0,40), as_ = ch(kc,UInt32(shiftKey),40)
  if j.isEmpty && a.isEmpty { continue }
  print(kc, j.debugDescription, js.debugDescription, a.debugDescription, as_.debugDescription)
}
