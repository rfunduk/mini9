# unified input API - works for keyboard, mouse, and gamepad
def down?(input, gamepad: nil)
  keycode = KEY_MAP[input.to_s] or return false
  _key_down_impl(keycode, gamepad)
end

def pressed?(input, gamepad: nil)
  keycode = KEY_MAP[input.to_s] or return false
  _key_pressed_impl(keycode, gamepad)
end

def released?(input, gamepad: nil)
  keycode = KEY_MAP[input.to_s] or return false
  _key_released_impl(keycode, gamepad)
end

def keys
  # _keys_impl returns raw raylib keycodes -> filter to curated subset
  _keys_impl.filter_map { |c| KEYCODE_MAP[c]&.to_sym }
end

def get_axis(h = nil, v = nil, horizontal: nil, vertical: nil, gamepad: nil)
  x = 0.0
  y = 0.0

  h ||= horizontal
  v ||= vertical

  # handle gamepad axes that return Vector2 directly
  if KEY_MAP[h[0].to_s] >= 30000 && KEY_MAP[h[0].to_s] <= 30003 &&
     KEY_MAP[v[0].to_s] >= 30000 && KEY_MAP[v[0].to_s] <= 30003
    if not gamepad
      raise ArgumentError.new("Which gamepad do you want to get_axis for?")
    end
    puts "PASSING #{[KEY_MAP[h[0].to_s], KEY_MAP[v[0].to_s], gamepad]}"
    return _get_gamepad_axis_value(KEY_MAP[h[0].to_s], KEY_MAP[v[0].to_s], gamepad)

  else
    if h
      x -= 1.0 if down?(h[0], gamepad: gamepad)
      x += 1.0 if down?(h[1], gamepad: gamepad)
    end

    if v
      y -= 1.0 if down?(v[0], gamepad: gamepad)
      y += 1.0 if down?(v[1], gamepad: gamepad)
    end

    v2(x, y).normalized
  end
end


KEY_MAP = {
  # letters
  "a" => 65, "b" => 66, "c" => 67, "d" => 68, "e" => 69, "f" => 70, "g" => 71, "h" => 72,
  "i" => 73, "j" => 74, "k" => 75, "l" => 76, "m" => 77, "n" => 78, "o" => 79, "p" => 80,
  "q" => 81, "r" => 82, "s" => 83, "t" => 84, "u" => 85, "v" => 86, "w" => 87, "x" => 88,
  "y" => 89, "z" => 90,

  # numbers
  "0" => 48, "1" => 49, "2" => 50, "3" => 51, "4" => 52, "5" => 53, "6" => 54, "7" => 55,
  "8" => 56, "9" => 57,

  # special keys
  "space" => 32, "enter" => 257, "escape" => 256, "backspace" => 259, "tab" => 258,
  "shift" => 340, "ctrl" => 341, "alt" => 342, "super" => 343,

  # arrow keys
  "right" => 262, "left" => 263, "down" => 264, "up" => 265,

  # function keys
  "f1" => 290, "f2" => 291, "f3" => 292, "f4" => 293, "f5" => 294, "f6" => 295,
  "f7" => 296, "f8" => 297, "f9" => 298, "f10" => 299, "f11" => 300, "f12" => 301,

  # symbols
  "minus" => 45, "equal" => 61, "comma" => 44, "period" => 46, "slash" => 47,
  "semicolon" => 59, "apostrophe" => 39, "grave" => 96, "left_bracket" => 91,
  "right_bracket" => 93, "backslash" => 92,

  # mouse buttons (using 10000+ offset from MouseButton enum values)
  "left_mouse" => 10000, "right_mouse" => 10001, "middle_mouse" => 10002,
  "side_mouse" => 10003, "extra_mouse" => 10004, "forward_mouse" => 10005, "back_mouse" => 10006,

  # gamepad buttons (using 20000+ offset from GamepadButton enum values)
  "left_face_up" => 20001, "left_face_right" => 20002, "left_face_down" => 20003, "left_face_left" => 20004,
  "right_face_up" => 20005, "right_face_right" => 20006, "right_face_down" => 20007, "right_face_left" => 20008,
  "left_trigger_1" => 20009, "left_trigger_2" => 20010, "right_trigger_1" => 20011, "right_trigger_2" => 20012,
  "middle_left" => 20013, "middle" => 20014, "middle_right" => 20015,
  "left_thumb" => 20016, "right_thumb" => 20017,

  # gamepad axes (using 30000+ offset from GamepadAxis enum values)
  "left_x" => 30000, "left_y" => 30001, "right_x" => 30002, "right_y" => 30003,
  "left_trigger" => 30004, "right_trigger" => 30005
}

KEYCODE_MAP = KEY_MAP.each_with_object({}) { |(k, v), h| h[v] = k }
