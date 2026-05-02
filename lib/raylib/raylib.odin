/*
Bindings for [[ raylib v6 ; https://www.raylib.com ]].

	*********************************************************************************************
	*
	*   raylib v6 - A simple and easy-to-use library to enjoy videogames programming (www.raylib.com)
    *
	*   LICENSE: zlib/libpng
	*
	*   raylib is licensed under an unmodified zlib/libpng license, which is an OSI-certified,
	*   BSD-like license that allows static linking with closed source software:
	*
	*   Copyright (c) 2013-2024 Ramon Santamaria (@raysan5)
	*
	*   This software is provided "as-is", without any express or implied warranty. In no event
	*   will the authors be held liable for any damages arising from the use of this software.
	*
	*   Permission is granted to anyone to use this software for any purpose, including commercial
	*   applications, and to alter it and redistribute it freely, subject to the following restrictions:
	*
	*     1. The origin of this software must not be misrepresented; you must not claim that you
	*     wrote the original software. If you use this software in a product, an acknowledgment
	*     in the product documentation would be appreciated but is not required.
	*
	*     2. Altered source versions must be plainly marked as such, and must not be misrepresented
	*     as being the original software.
	*
	*     3. This notice may not be removed or altered from any source distribution.
	*
	*********************************************************************************************
*/
package m9raylib

import "core:c"
import "core:mem"

MAX_TEXTFORMAT_BUFFERS :: #config(RAYLIB_MAX_TEXTFORMAT_BUFFERS, 4)
MAX_TEXT_BUFFER_LENGTH :: #config(RAYLIB_MAX_TEXT_BUFFER_LENGTH, 1024)

#assert(size_of(rune) == size_of(c.int))

RAYLIB_LIB :: #config(RAYLIB_LIB, "")

when ODIN_OS == .Darwin {
	foreign import lib {RAYLIB_LIB, "system:Cocoa.framework", "system:OpenGL.framework", "system:IOKit.framework"}
} else when ODIN_OS == .Linux {
	foreign import lib {RAYLIB_LIB, "system:dl", "system:pthread", "system:X11"}
} else when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
	foreign import lib {RAYLIB_LIB}
} else {
	foreign import lib "system:raylib"
}

VERSION_MAJOR :: 6
VERSION_MINOR :: 0
VERSION_PATCH :: 0
VERSION :: "6.0"

PI :: 3.14159265358979323846
DEG2RAD :: PI / 180.0
RAD2DEG :: 180.0 / PI


// Some Basic Colors
// NOTE: Custom raylib color palette for amazing visuals on WHITE background
LIGHTGRAY :: Color{200, 200, 200, 255} // Light Gray
GRAY :: Color{130, 130, 130, 255} // Gray
DARKGRAY :: Color{80, 80, 80, 255} // Dark Gray
YELLOW :: Color{253, 249, 0, 255} // Yellow
GOLD :: Color{255, 203, 0, 255} // Gold
ORANGE :: Color{255, 161, 0, 255} // Orange
PINK :: Color{255, 109, 194, 255} // Pink
RED :: Color{230, 41, 55, 255} // Red
MAROON :: Color{190, 33, 55, 255} // Maroon
GREEN :: Color{0, 228, 48, 255} // Green
LIME :: Color{0, 158, 47, 255} // Lime
DARKGREEN :: Color{0, 117, 44, 255} // Dark Green
SKYBLUE :: Color{102, 191, 255, 255} // Sky Blue
BLUE :: Color{0, 121, 241, 255} // Blue
DARKBLUE :: Color{0, 82, 172, 255} // Dark Blue
PURPLE :: Color{200, 122, 255, 255} // Purple
VIOLET :: Color{135, 60, 190, 255} // Violet
DARKPURPLE :: Color{112, 31, 126, 255} // Dark Purple
BEIGE :: Color{211, 176, 131, 255} // Beige
BROWN :: Color{127, 106, 79, 255} // Brown
DARKBROWN :: Color{76, 63, 47, 255} // Dark Brown

WHITE :: Color{255, 255, 255, 255} // White
BLACK :: Color{0, 0, 0, 255} // Black
BLANK :: Color{0, 0, 0, 0} // Blank (Transparent)
MAGENTA :: Color{255, 0, 255, 255} // Magenta
RAYWHITE :: Color{245, 245, 245, 255} // My own White (raylib logo)

// Vector2 type
Vector2 :: [2]f32
// Vector3 type
Vector3 :: [3]f32
// Vector4 type
Vector4 :: [4]f32

// Quaternion type
Quaternion :: quaternion128

// Matrix type (right handed, stored row major)
Matrix :: #row_major matrix[4, 4]f32


// Color, 4 components, R8G8B8A8 (32bit)
//
// Note: In Raylib this is a struct. But here we use a fixed array, so that .rgba swizzling etc work.
Color :: distinct [4]u8

// Rectangle type
Rectangle :: struct {
	x:      f32, // Rectangle top-left corner position x
	y:      f32, // Rectangle top-left corner position y
	width:  f32, // Rectangle width
	height: f32, // Rectangle height
}

// Image type, bpp always RGBA (32bit)
// NOTE: Data stored in CPU memory (RAM)
Image :: struct {
	data:    rawptr, // Image raw data
	width:   c.int, // Image base width
	height:  c.int, // Image base height
	mipmaps: c.int, // Mipmap levels, 1 by default
	format:  PixelFormat, // Data format (PixelFormat type)
}

// Texture type
// NOTE: Data stored in GPU memory
Texture :: struct {
	id:      c.uint, // OpenGL texture id
	width:   c.int, // Texture base width
	height:  c.int, // Texture base height
	mipmaps: c.int, // Mipmap levels, 1 by default
	format:  PixelFormat, // Data format (PixelFormat type)
}

// Texture2D type, same as Texture
Texture2D :: Texture

// TextureCubemap type, actually, same as Texture
TextureCubemap :: Texture

// RenderTexture type, for texture rendering
RenderTexture :: struct {
	id:      c.uint, // OpenGL framebuffer object id
	texture: Texture, // Color buffer attachment texture
	depth:   Texture, // Depth buffer attachment texture
}

// RenderTexture2D type, same as RenderTexture
RenderTexture2D :: RenderTexture

// N-Patch layout info
NPatchInfo :: struct {
	source: Rectangle, // Texture source rectangle
	left:   c.int, // Left border offset
	top:    c.int, // Top border offset
	right:  c.int, // Right border offset
	bottom: c.int, // Bottom border offset
	layout: NPatchLayout, // Layout of the n-patch: 3x3, 1x3 or 3x1
}

// Font character info
GlyphInfo :: struct {
	value:    rune, // Character value (Unicode)
	offsetX:  c.int, // Character offset X when drawing
	offsetY:  c.int, // Character offset Y when drawing
	advanceX: c.int, // Character advance position X
	image:    Image, // Character image data
}

// Font type, includes texture and charSet array data
Font :: struct {
	baseSize:     c.int, // Base size (default chars height)
	glyphCount:   c.int, // Number of characters
	glyphPadding: c.int, // Padding around the chars
	texture:      Texture2D, // Characters texture atlas
	recs:         [^]Rectangle, // Characters rectangles in texture
	glyphs:       [^]GlyphInfo, // Characters info data
}

// Camera2D type, defines a 2d camera
Camera2D :: struct {
	offset:   Vector2, // Camera offset (displacement from target)
	target:   Vector2, // Camera target (rotation and zoom origin)
	rotation: f32, // Camera rotation in degrees
	zoom:     f32, // Camera zoom (scaling), should be 1.0f by default
}

// Shader type (generic)
Shader :: struct {
	id:   c.uint, // Shader program id
	locs: [^]c.int, // Shader locations array (MAX_SHADER_LOCATIONS)
}

// Wave type, defines audio wave data
Wave :: struct {
	frameCount: c.uint, // Total number of frames (considering channels)
	sampleRate: c.uint, // Frequency (samples per second)
	sampleSize: c.uint, // Bit depth (bits per sample): 8, 16, 32 (24 not supported)
	channels:   c.uint, // Number of channels (1-mono, 2-stereo)
	data:       rawptr, // Buffer data pointer
}

// Audio stream type
// NOTE: Actual structs are defined internally in raudio module
AudioStream :: struct {
	buffer:     rawptr, // Pointer to internal data used by the audio system
	processor:  rawptr, // Pointer to internal data processor, useful for audio effects
	sampleRate: c.uint, // Frequency (samples per second)
	sampleSize: c.uint, // Bit depth (bits per sample): 8, 16, 32 (24 not supported)
	channels:   c.uint, // Number of channels (1-mono, 2-stereo)
}

// Sound source type
Sound :: struct {
	using stream: AudioStream, // Audio stream
	frameCount:   c.uint, // Total number of frames (considering channels)
}

// Music stream type (audio file streaming from memory)
// NOTE: Anything longer than ~10 seconds should be streamed
Music :: struct {
	using stream: AudioStream, // Audio stream
	frameCount:   c.uint, // Total number of frames (considering channels)
	looping:      bool, // Music looping enable
	ctxType:      c.int, // Type of music context (audio filetype)
	ctxData:      rawptr, // Audio context data, depends on type
}

// Automation event
AutomationEvent :: struct {
	frame:  c.uint, // Event frame
	type:   c.uint, // Event type (AutomationEventType)
	params: [4]c.int, // Event parameters (if required) ---
}

// Automation event list
AutomationEventList :: struct {
	capacity: c.uint, // Events max entries (MAX_AUTOMATION_EVENTS)
	count:    c.uint, // Events entries count
	events:   [^]AutomationEvent, // Events entries
}

//----------------------------------------------------------------------------------
// Enumerators Definition
//----------------------------------------------------------------------------------
// System/Window config flags
// NOTE: Every bit registers one state (use it with bit masks)
// By default all flags are set to 0
ConfigFlag :: enum c.int {
	VSYNC_HINT               = 6, // Set to try enabling V-Sync on GPU
	FULLSCREEN_MODE          = 1, // Set to run program in fullscreen
	WINDOW_RESIZABLE         = 2, // Set to allow resizable window
	WINDOW_UNDECORATED       = 3, // Set to disable window decoration (frame and buttons)
	WINDOW_HIDDEN            = 7, // Set to hide window
	WINDOW_MINIMIZED         = 9, // Set to minimize window (iconify)
	WINDOW_MAXIMIZED         = 10, // Set to maximize window (expanded to monitor)
	WINDOW_UNFOCUSED         = 11, // Set to window non focused
	WINDOW_TOPMOST           = 12, // Set to window always on top
	WINDOW_ALWAYS_RUN        = 8, // Set to allow windows running while minimized
	WINDOW_TRANSPARENT       = 4, // Set to allow transparent framebuffer
	WINDOW_HIGHDPI           = 13, // Set to support HighDPI
	WINDOW_MOUSE_PASSTHROUGH = 14, // Set to support mouse passthrough, only supported when FLAG_WINDOW_UNDECORATED
	BORDERLESS_WINDOWED_MODE = 15, // Set to run program in borderless windowed mode
	MSAA_4X_HINT             = 5, // Set to try enabling MSAA 4X
	INTERLACED_HINT          = 16, // Set to try enabling interlaced video format (for V3D)
}
ConfigFlags :: distinct bit_set[ConfigFlag;c.int]


// Trace log level
TraceLogLevel :: enum c.int {
	ALL = 0, // Display all logs
	TRACE, // Trace logging, intended for internal use only
	DEBUG, // Debug logging, used for internal debugging, it should be disabled on release builds
	INFO, // Info logging, used for program execution info
	WARNING, // Warning logging, used on recoverable failures
	ERROR, // Error logging, used on unrecoverable failures
	FATAL, // Fatal logging, used to abort program: exit(EXIT_FAILURE)
	NONE, // Disable logging
}

// Keyboard keys (US keyboard layout)
// NOTE: Use GetKeyPressed() to allow redefining
// required keys for alternative layouts
KeyboardKey :: enum c.int {
	KEY_NULL      = 0, // Key: NULL, used for no key pressed
	// Alphanumeric keys
	APOSTROPHE    = 39, // Key: '
	COMMA         = 44, // Key: ,
	MINUS         = 45, // Key: -
	PERIOD        = 46, // Key: .
	SLASH         = 47, // Key: /
	ZERO          = 48, // Key: 0
	ONE           = 49, // Key: 1
	TWO           = 50, // Key: 2
	THREE         = 51, // Key: 3
	FOUR          = 52, // Key: 4
	FIVE          = 53, // Key: 5
	SIX           = 54, // Key: 6
	SEVEN         = 55, // Key: 7
	EIGHT         = 56, // Key: 8
	NINE          = 57, // Key: 9
	SEMICOLON     = 59, // Key: ;
	EQUAL         = 61, // Key: =
	A             = 65, // Key: A | a
	B             = 66, // Key: B | b
	C             = 67, // Key: C | c
	D             = 68, // Key: D | d
	E             = 69, // Key: E | e
	F             = 70, // Key: F | f
	G             = 71, // Key: G | g
	H             = 72, // Key: H | h
	I             = 73, // Key: I | i
	J             = 74, // Key: J | j
	K             = 75, // Key: K | k
	L             = 76, // Key: L | l
	M             = 77, // Key: M | m
	N             = 78, // Key: N | n
	O             = 79, // Key: O | o
	P             = 80, // Key: P | p
	Q             = 81, // Key: Q | q
	R             = 82, // Key: R | r
	S             = 83, // Key: S | s
	T             = 84, // Key: T | t
	U             = 85, // Key: U | u
	V             = 86, // Key: V | v
	W             = 87, // Key: W | w
	X             = 88, // Key: X | x
	Y             = 89, // Key: Y | y
	Z             = 90, // Key: Z | z
	LEFT_BRACKET  = 91, // Key: [
	BACKSLASH     = 92, // Key: '\'
	RIGHT_BRACKET = 93, // Key: ]
	GRAVE         = 96, // Key: `
	// Function keys
	SPACE         = 32, // Key: Space
	ESCAPE        = 256, // Key: Esc
	ENTER         = 257, // Key: Enter
	TAB           = 258, // Key: Tab
	BACKSPACE     = 259, // Key: Backspace
	INSERT        = 260, // Key: Ins
	DELETE        = 261, // Key: Del
	RIGHT         = 262, // Key: Cursor right
	LEFT          = 263, // Key: Cursor left
	DOWN          = 264, // Key: Cursor down
	UP            = 265, // Key: Cursor up
	PAGE_UP       = 266, // Key: Page up
	PAGE_DOWN     = 267, // Key: Page down
	HOME          = 268, // Key: Home
	END           = 269, // Key: End
	CAPS_LOCK     = 280, // Key: Caps lock
	SCROLL_LOCK   = 281, // Key: Scroll down
	NUM_LOCK      = 282, // Key: Num lock
	PRINT_SCREEN  = 283, // Key: Print screen
	PAUSE         = 284, // Key: Pause
	F1            = 290, // Key: F1
	F2            = 291, // Key: F2
	F3            = 292, // Key: F3
	F4            = 293, // Key: F4
	F5            = 294, // Key: F5
	F6            = 295, // Key: F6
	F7            = 296, // Key: F7
	F8            = 297, // Key: F8
	F9            = 298, // Key: F9
	F10           = 299, // Key: F10
	F11           = 300, // Key: F11
	F12           = 301, // Key: F12
	LEFT_SHIFT    = 340, // Key: Shift left
	LEFT_CONTROL  = 341, // Key: Control left
	LEFT_ALT      = 342, // Key: Alt left
	LEFT_SUPER    = 343, // Key: Super left
	RIGHT_SHIFT   = 344, // Key: Shift right
	RIGHT_CONTROL = 345, // Key: Control right
	RIGHT_ALT     = 346, // Key: Alt right
	RIGHT_SUPER   = 347, // Key: Super right
	KB_MENU       = 348, // Key: KB menu
	// Keypad keys
	KP_0          = 320, // Key: Keypad 0
	KP_1          = 321, // Key: Keypad 1
	KP_2          = 322, // Key: Keypad 2
	KP_3          = 323, // Key: Keypad 3
	KP_4          = 324, // Key: Keypad 4
	KP_5          = 325, // Key: Keypad 5
	KP_6          = 326, // Key: Keypad 6
	KP_7          = 327, // Key: Keypad 7
	KP_8          = 328, // Key: Keypad 8
	KP_9          = 329, // Key: Keypad 9
	KP_DECIMAL    = 330, // Key: Keypad .
	KP_DIVIDE     = 331, // Key: Keypad /
	KP_MULTIPLY   = 332, // Key: Keypad *
	KP_SUBTRACT   = 333, // Key: Keypad -
	KP_ADD        = 334, // Key: Keypad +
	KP_ENTER      = 335, // Key: Keypad Enter
	KP_EQUAL      = 336, // Key: Keypad =
	// Android key buttons
	BACK          = 4, // Key: Android back button
	MENU          = 5, // Key: Android menu button
	VOLUME_UP     = 24, // Key: Android volume up button
	VOLUME_DOWN   = 25, // Key: Android volume down button
}

// Mouse buttons
MouseButton :: enum c.int {
	LEFT    = 0, // Mouse button left
	RIGHT   = 1, // Mouse button right
	MIDDLE  = 2, // Mouse button middle (pressed wheel)
	SIDE    = 3, // Mouse button side (advanced mouse device)
	EXTRA   = 4, // Mouse button extra (advanced mouse device)
	FORWARD = 5, // Mouse button fordward (advanced mouse device)
	BACK    = 6, // Mouse button back (advanced mouse device)
}

// Mouse cursor
MouseCursor :: enum c.int {
	DEFAULT       = 0, // Default pointer shape
	ARROW         = 1, // Arrow shape
	IBEAM         = 2, // Text writing cursor shape
	CROSSHAIR     = 3, // Cross shape
	POINTING_HAND = 4, // Pointing hand cursor
	RESIZE_EW     = 5, // Horizontal resize/move arrow shape
	RESIZE_NS     = 6, // Vertical resize/move arrow shape
	RESIZE_NWSE   = 7, // Top-left to bottom-right diagonal resize/move arrow shape
	RESIZE_NESW   = 8, // The top-right to bottom-left diagonal resize/move arrow shape
	RESIZE_ALL    = 9, // The omnidirectional resize/move cursor shape
	NOT_ALLOWED   = 10, // The operation-not-allowed shape
}

// Gamepad buttons
GamepadButton :: enum c.int {
	UNKNOWN = 0, // Unknown button, just for error checking
	LEFT_FACE_UP, // Gamepad left DPAD up button
	LEFT_FACE_RIGHT, // Gamepad left DPAD right button
	LEFT_FACE_DOWN, // Gamepad left DPAD down button
	LEFT_FACE_LEFT, // Gamepad left DPAD left button
	RIGHT_FACE_UP, // Gamepad right button up (i.e. PS3: Triangle, Xbox: Y)
	RIGHT_FACE_RIGHT, // Gamepad right button right (i.e. PS3: Circle, Xbox: B)
	RIGHT_FACE_DOWN, // Gamepad right button down (i.e. PS3: Cross, Xbox: A)
	RIGHT_FACE_LEFT, // Gamepad right button left (i.e. PS3: Square, Xbox: X)
	LEFT_TRIGGER_1, // Gamepad top/back trigger left (first), it could be a trailing button
	LEFT_TRIGGER_2, // Gamepad top/back trigger left (second), it could be a trailing button
	RIGHT_TRIGGER_1, // Gamepad top/back trigger right (first), it could be a trailing button
	RIGHT_TRIGGER_2, // Gamepad top/back trigger right (second), it could be a trailing button
	MIDDLE_LEFT, // Gamepad center buttons, left one (i.e. PS3: Select)
	MIDDLE, // Gamepad center buttons, middle one (i.e. PS3: PS, Xbox: XBOX)
	MIDDLE_RIGHT, // Gamepad center buttons, right one (i.e. PS3: Start)
	LEFT_THUMB, // Gamepad joystick pressed button left
	RIGHT_THUMB, // Gamepad joystick pressed button right
}

// Gamepad axis
GamepadAxis :: enum c.int {
	LEFT_X        = 0, // Gamepad left stick X axis
	LEFT_Y        = 1, // Gamepad left stick Y axis
	RIGHT_X       = 2, // Gamepad right stick X axis
	RIGHT_Y       = 3, // Gamepad right stick Y axis
	LEFT_TRIGGER  = 4, // Gamepad back trigger left, pressure level: [1..-1]
	RIGHT_TRIGGER = 5, // Gamepad back trigger right, pressure level: [1..-1]
}


// Shader location index
ShaderLocationIndex :: enum c.int {
	VERTEX_POSITION = 0, // Shader location: vertex attribute: position
	VERTEX_TEXCOORD01, // Shader location: vertex attribute: texcoord01
	VERTEX_TEXCOORD02, // Shader location: vertex attribute: texcoord02
	VERTEX_NORMAL, // Shader location: vertex attribute: normal
	VERTEX_TANGENT, // Shader location: vertex attribute: tangent
	VERTEX_COLOR, // Shader location: vertex attribute: color
	MATRIX_MVP, // Shader location: matrix uniform: model-view-projection
	MATRIX_VIEW, // Shader location: matrix uniform: view (camera transform)
	MATRIX_PROJECTION, // Shader location: matrix uniform: projection
	MATRIX_MODEL, // Shader location: matrix uniform: model (transform)
	MATRIX_NORMAL, // Shader location: matrix uniform: normal
	VECTOR_VIEW, // Shader location: vector uniform: view
	COLOR_DIFFUSE, // Shader location: vector uniform: diffuse color
	COLOR_SPECULAR, // Shader location: vector uniform: specular color
	COLOR_AMBIENT, // Shader location: vector uniform: ambient color
	MAP_ALBEDO, // Shader location: sampler2d texture: albedo (same as: SHADER_LOC_MAP_DIFFUSE)
	MAP_METALNESS, // Shader location: sampler2d texture: metalness (same as: SHADER_LOC_MAP_SPECULAR)
	MAP_NORMAL, // Shader location: sampler2d texture: normal
	MAP_ROUGHNESS, // Shader location: sampler2d texture: roughness
	MAP_OCCLUSION, // Shader location: sampler2d texture: occlusion
	MAP_EMISSION, // Shader location: sampler2d texture: emission
	MAP_HEIGHT, // Shader location: sampler2d texture: height
	MAP_CUBEMAP, // Shader location: samplerCube texture: cubemap
	MAP_IRRADIANCE, // Shader location: samplerCube texture: irradiance
	MAP_PREFILTER, // Shader location: samplerCube texture: prefilter
	MAP_BRDF, // Shader location: sampler2d texture: brdf
	VERTEX_BONEIDS, // Shader location: vertex attribute: boneIds
	VERTEX_BONEWEIGHTS, // Shader location: vertex attribute: boneWeights
	MATRIX_BONETRANSFORMS, // [v6: was BONE_MATRICES]
	VERTEX_INSTANCETRANSFORM, // [v6 new]
}


// Shader uniform data type
ShaderUniformDataType :: enum c.int {
	FLOAT = 0, // Shader uniform type: float
	VEC2, // Shader uniform type: vec2 (2 float)
	VEC3, // Shader uniform type: vec3 (3 float)
	VEC4, // Shader uniform type: vec4 (4 float)
	INT, // Shader uniform type: int
	IVEC2, // Shader uniform type: ivec2 (2 int)
	IVEC3, // Shader uniform type: ivec3 (3 int)
	IVEC4, // Shader uniform type: ivec4 (4 int)
	SAMPLER2D, // Shader uniform type: sampler2d
}

// Pixel formats
// NOTE: Support depends on OpenGL version and platform
PixelFormat :: enum c.int {
	UNKNOWN = 0,
	UNCOMPRESSED_GRAYSCALE = 1, // 8 bit per pixel (no alpha)
	UNCOMPRESSED_GRAY_ALPHA, // 8*2 bpp (2 channels)
	UNCOMPRESSED_R5G6B5, // 16 bpp
	UNCOMPRESSED_R8G8B8, // 24 bpp
	UNCOMPRESSED_R5G5B5A1, // 16 bpp (1 bit alpha)
	UNCOMPRESSED_R4G4B4A4, // 16 bpp (4 bit alpha)
	UNCOMPRESSED_R8G8B8A8, // 32 bpp
	UNCOMPRESSED_R32, // 32 bpp (1 channel - float)
	UNCOMPRESSED_R32G32B32, // 32*3 bpp (3 channels - float)
	UNCOMPRESSED_R32G32B32A32, // 32*4 bpp (4 channels - float)
	UNCOMPRESSED_R16, // 16 bpp (1 channel - float)
	UNCOMPRESSED_R16G16B16, // 16*3 bpp (3 channels - float)
	UNCOMPRESSED_R16G16B16A16, // 16*4 bpp (4 channels - float)
	COMPRESSED_DXT1_RGB, // 4 bpp (no alpha)
	COMPRESSED_DXT1_RGBA, // 4 bpp (1 bit alpha)
	COMPRESSED_DXT3_RGBA, // 8 bpp
	COMPRESSED_DXT5_RGBA, // 8 bpp
	COMPRESSED_ETC1_RGB, // 4 bpp
	COMPRESSED_ETC2_RGB, // 4 bpp
	COMPRESSED_ETC2_EAC_RGBA, // 8 bpp
	COMPRESSED_PVRT_RGB, // 4 bpp
	COMPRESSED_PVRT_RGBA, // 4 bpp
	COMPRESSED_ASTC_4x4_RGBA, // 8 bpp
	COMPRESSED_ASTC_8x8_RGBA, // 2 bpp
}

// Texture parameters: filter mode
// NOTE 1: Filtering considers mipmaps if available in the texture
// NOTE 2: Filter is accordingly set for minification and magnification
TextureFilter :: enum c.int {
	POINT = 0, // No filter, just pixel approximation
	BILINEAR, // Linear filtering
	TRILINEAR, // Trilinear filtering (linear with mipmaps)
	ANISOTROPIC_4X, // Anisotropic filtering 4x
	ANISOTROPIC_8X, // Anisotropic filtering 8x
	ANISOTROPIC_16X, // Anisotropic filtering 16x
}

// Texture parameters: wrap mode
TextureWrap :: enum c.int {
	REPEAT = 0, // Repeats texture in tiled mode
	CLAMP, // Clamps texture to edge pixel in tiled mode
	MIRROR_REPEAT, // Mirrors and repeats the texture in tiled mode
	MIRROR_CLAMP, // Mirrors and clamps to border the texture in tiled mode
}

// Cubemap layouts
CubemapLayout :: enum c.int {
	AUTO_DETECT = 0, // Automatically detect layout type
	LINE_VERTICAL, // Layout is defined by a vertical line with faces
	LINE_HORIZONTAL, // Layout is defined by an horizontal line with faces
	CROSS_THREE_BY_FOUR, // Layout is defined by a 3x4 cross with cubemap faces
	CROSS_FOUR_BY_THREE, // Layout is defined by a 4x3 cross with cubemap faces
}

// Font type, defines generation method
FontType :: enum c.int {
	DEFAULT = 0, // Default font generation, anti-aliased
	BITMAP, // Bitmap font generation, no anti-aliasing
	SDF, // SDF font generation, requires external shader
}

// Color blending modes (pre-defined)
BlendMode :: enum c.int {
	ALPHA = 0, // Blend textures considering alpha (default)
	ADDITIVE, // Blend textures adding colors
	MULTIPLIED, // Blend textures multiplying colors
	ADD_COLORS, // Blend textures adding colors (alternative)
	SUBTRACT_COLORS, // Blend textures subtracting colors (alternative)
	ALPHA_PREMULTIPLY, // Blend premultiplied textures considering alpha
	CUSTOM, // Blend textures using custom src/dst factors (use rlSetBlendFactors())
	CUSTOM_SEPARATE, // Blend textures using custom rgb/alpha separate src/dst factors (use rlSetBlendFactorsSeparate())
}

// Gestures
// NOTE: It could be used as flags to enable only some gestures
Gesture :: enum c.uint {
	TAP         = 0, // Tap gesture
	DOUBLETAP   = 1, // Double tap gesture
	HOLD        = 2, // Hold gesture
	DRAG        = 3, // Drag gesture
	SWIPE_RIGHT = 4, // Swipe right gesture
	SWIPE_LEFT  = 5, // Swipe left gesture
	SWIPE_UP    = 6, // Swipe up gesture
	SWIPE_DOWN  = 7, // Swipe down gesture
	PINCH_IN    = 8, // Pinch in gesture
	PINCH_OUT   = 9, // Pinch out gesture
}
Gestures :: distinct bit_set[Gesture;c.uint]

// N-patch layout
NPatchLayout :: enum c.int {
	NINE_PATCH = 0, // Npatch layout: 3x3 tiles
	THREE_PATCH_VERTICAL, // Npatch layout: 1x3 tiles
	THREE_PATCH_HORIZONTAL, // Npatch layout: 3x1 tiles
}

AudioCallback :: #type proc "c" (bufferData: rawptr, frames: c.uint)


@(default_calling_convention = "c")
foreign lib {
	//------------------------------------------------------------------------------------
	// Global Variables Definition
	//------------------------------------------------------------------------------------
	// It's lonely here...

	//------------------------------------------------------------------------------------
	// Window and Graphics Device Functions (Module: core)
	//------------------------------------------------------------------------------------

	// Window-related functions

	InitWindow :: proc(width, height: c.int, title: cstring) --- // Initialize window and OpenGL context
	WindowShouldClose :: proc() -> bool --- // Check if application should close (KEY_ESCAPE pressed or windows close icon clicked)
	CloseWindow :: proc() --- // Close window and unload OpenGL context
	IsWindowReady :: proc() -> bool --- // Check if window has been initialized successfully
	IsWindowFullscreen :: proc() -> bool --- // Check if window is currently fullscreen
	IsWindowHidden :: proc() -> bool --- // Check if window is currently hidden
	IsWindowMinimized :: proc() -> bool --- // Check if window is currently minimized
	IsWindowMaximized :: proc() -> bool --- // Check if window is currently maximized
	IsWindowFocused :: proc() -> bool --- // Check if window is currently focused
	IsWindowResized :: proc() -> bool --- // Check if window has been resized last frame
	IsWindowState :: proc(flags: ConfigFlags) -> bool --- // Check if one specific window flag is enabled
	SetWindowState :: proc(flags: ConfigFlags) --- // Set window configuration state using flags
	ClearWindowState :: proc(flags: ConfigFlags) --- // Clear window configuration state flags
	ToggleFullscreen :: proc() --- // Toggle window state: fullscreen/windowed
	ToggleBorderlessWindowed :: proc() --- // Toggle window state: borderless windowed
	MaximizeWindow :: proc() --- // Set window state: maximized, if resizable
	MinimizeWindow :: proc() --- // Set window state: minimized, if resizable
	RestoreWindow :: proc() --- // Set window state: not minimized/maximized
	SetWindowIcon :: proc(image: Image) --- // Set icon for window (single image, RGBA 32bit,)
	SetWindowIcons :: proc(images: [^]Image, count: c.int) --- // Set icon for window (multiple images, RGBA 32bit,)
	SetWindowTitle :: proc(title: cstring) --- // Set title for window
	SetWindowPosition :: proc(x, y: c.int) --- // Set window position on screen
	SetWindowMonitor :: proc(monitor: c.int) --- // Set monitor for the current window
	SetWindowMinSize :: proc(width, height: c.int) --- // Set window minimum dimensions (for WINDOW_RESIZABLE)
	SetWindowMaxSize :: proc(width, height: c.int) --- // Set window maximum dimensions (for WINDOW_RESIZABLE)
	SetWindowSize :: proc(width, height: c.int) --- // Set window dimensions
	SetWindowOpacity :: proc(opacity: f32) --- // Set window opacity [0.0f..1.0f]
	SetWindowFocused :: proc() --- // Set window focused
	GetWindowHandle :: proc() -> rawptr --- // Get native window handle
	GetScreenWidth :: proc() -> c.int --- // Get current screen width
	GetScreenHeight :: proc() -> c.int --- // Get current screen height
	GetRenderWidth :: proc() -> c.int --- // Get current render width (it considers HiDPI)
	GetRenderHeight :: proc() -> c.int --- // Get current render height (it considers HiDPI)
	GetMonitorCount :: proc() -> c.int --- // Get number of connected monitors
	GetCurrentMonitor :: proc() -> c.int --- // Get current monitor where window is placed
	GetMonitorPosition :: proc(monitor: c.int) -> Vector2 --- // Get specified monitor position
	GetMonitorWidth :: proc(monitor: c.int) -> c.int --- // Get specified monitor width (current video mode used by monitor)
	GetMonitorHeight :: proc(monitor: c.int) -> c.int --- // Get specified monitor height (current video mode used by monitor)
	GetMonitorPhysicalWidth :: proc(monitor: c.int) -> c.int --- // Get specified monitor physical width in millimetres
	GetMonitorPhysicalHeight :: proc(monitor: c.int) -> c.int --- // Get specified monitor physical height in millimetres
	GetMonitorRefreshRate :: proc(monitor: c.int) -> c.int --- // Get specified monitor refresh rate
	GetWindowPosition :: proc() -> Vector2 --- // Get window position XY on monitor
	GetWindowScaleDPI :: proc() -> Vector2 --- // Get window scale DPI factor
	GetMonitorName :: proc(monitor: c.int) -> cstring --- // Get the human-readable, UTF-8 encoded name of the specified monitor
	SetClipboardText :: proc(text: cstring) --- // Set clipboard text content
	GetClipboardText :: proc() -> cstring --- // Get clipboard text content
	GetClipboardImage :: proc() -> Image --- // Get clipboard image content
	EnableEventWaiting :: proc() --- // Enable waiting for events on EndDrawing(), no automatic event polling
	DisableEventWaiting :: proc() --- // Disable waiting for events on EndDrawing(), automatic events polling


	// Custom frame control functions
	// NOTE: Those functions are intended for advance users that want full control over the frame processing
	// By default EndDrawing() does this job: draws everything + SwapScreenBuffer() + manage frame timing + PollInputEvents()
	// To avoid that behaviour and control frame processes manually, enable in config.h: SUPPORT_CUSTOM_FRAME_CONTROL

	SwapScreenBuffer :: proc() --- // Swap back buffer with front buffer (screen drawing)
	PollInputEvents :: proc() --- // Register all input events
	WaitTime :: proc(seconds: f64) --- // Wait for some time (halt program execution)


	// Cursor-related functions

	ShowCursor :: proc() --- // Shows cursor
	HideCursor :: proc() --- // Hides cursor
	IsCursorHidden :: proc() -> bool --- // Check if cursor is not visible
	EnableCursor :: proc() --- // Enables cursor (unlock cursor)
	DisableCursor :: proc() --- // Disables cursor (lock cursor)
	IsCursorOnScreen :: proc() -> bool --- // Check if cursor is on the current screen.

	// Drawing-related functions

	ClearBackground :: proc(color: Color) --- // Set background color (framebuffer clear color)
	BeginDrawing :: proc() --- // Setup canvas (framebuffer) to start drawing
	EndDrawing :: proc() --- // End canvas drawing and swap buffers (double buffering)
	BeginMode2D :: proc(camera: Camera2D) --- // Initialize 2D mode with custom camera (2D)
	EndMode2D :: proc() --- // Ends 2D mode with custom camera
	BeginTextureMode :: proc(target: RenderTexture2D) --- // Initializes render texture for drawing
	EndTextureMode :: proc() --- // Ends drawing to render texture
	BeginShaderMode :: proc(shader: Shader) --- // Begin custom shader drawing
	EndShaderMode :: proc() --- // End custom shader drawing (use default shader)
	BeginBlendMode :: proc(mode: BlendMode) --- // Begin blending mode (alpha, additive, multiplied)
	EndBlendMode :: proc() --- // End blending mode (reset to default: alpha blending)
	BeginScissorMode :: proc(x, y, width, height: c.int) --- // Begin scissor mode (define screen area for following drawing)
	EndScissorMode :: proc() --- // End scissor mode

	// Shader management functions
	// NOTE: Shader functionality is not available on OpenGL 1.1

	LoadShader :: proc(vsFileName, fsFileName: cstring) -> Shader --- // Load shader from files and bind default locations
	LoadShaderFromMemory :: proc(vsCode, fsCode: cstring) -> Shader --- // Load shader from code strings and bind default locations
	IsShaderValid :: proc(shader: Shader) -> bool --- // Check if a shader is valid (loaded on GPU)
	GetShaderLocation :: proc(shader: Shader, uniformName: cstring) -> c.int --- // Get shader uniform location
	GetShaderLocationAttrib :: proc(shader: Shader, attribName: cstring) -> c.int --- // Get shader attribute location

	// We use #any_int here so we can pass ShaderLocationIndex
	SetShaderValue :: proc(shader: Shader, #any_int locIndex: c.int, value: rawptr, uniformType: ShaderUniformDataType) --- // Set shader uniform value
	SetShaderValueV :: proc(shader: Shader, #any_int locIndex: c.int, value: rawptr, uniformType: ShaderUniformDataType, count: c.int) --- // Set shader uniform value vector
	SetShaderValueMatrix :: proc(shader: Shader, #any_int locIndex: c.int, mat: Matrix) --- // Set shader uniform value (matrix 4x4)
	SetShaderValueTexture :: proc(shader: Shader, #any_int locIndex: c.int, texture: Texture2D) --- // Set shader uniform value for texture (sampler2d)
	UnloadShader :: proc(shader: Shader) --- // Unload shader from GPU memory (VRAM)

	// Screen-space-related functions

	GetWorldToScreen2D :: proc(position: Vector2, camera: Camera2D) -> Vector2 --- // Get the screen space position for a 2d camera world space position
	GetScreenToWorld2D :: proc(position: Vector2, camera: Camera2D) -> Vector2 --- // Get the world space position for a 2d camera screen space position
	GetCameraMatrix2D :: proc(camera: Camera2D) -> Matrix --- // Get camera 2d transform matrix

	// Timing-related functions

	SetTargetFPS :: proc(fps: c.int) --- // Set target FPS (maximum)
	GetFPS :: proc() -> c.int --- // Returns current FPS
	GetFrameTime :: proc() -> f32 --- // Returns time in seconds for last frame drawn (delta time)
	GetTime :: proc() -> f64 --- // Returns elapsed time in seconds since InitWindow()

	// Misc. functions
	TakeScreenshot :: proc(fileName: cstring) --- // Takes a screenshot of current screen (filename extension defines format)
	SetConfigFlags :: proc(flags: ConfigFlags) --- // Setup init configuration flags (view FLAGS). NOTE: This function is expected to be called before window creation

	// NOTE: Following functions implemented in module [utils]
	//------------------------------------------------------------------
	TraceLog :: proc(logLevel: TraceLogLevel, text: cstring, #c_vararg args: ..any) --- // Show trace log messages (LOG_DEBUG, LOG_INFO, LOG_WARNING, LOG_ERROR)
	SetTraceLogLevel :: proc(logLevel: TraceLogLevel) --- // Set the current threshold (minimum) log level
	MemAlloc :: proc(size: c.uint) -> rawptr --- // Internal memory allocator
	MemRealloc :: proc(ptr: rawptr, size: c.uint) -> rawptr --- // Internal memory reallocator

	// Compression/Encoding functionality

	CompressData :: proc(data: rawptr, dataSize: c.int, compDataSize: ^c.int) -> [^]byte --- // Compress data (DEFLATE algorithm), memory must be MemFree()
	DecompressData :: proc(compData: rawptr, compDataSize: c.int, dataSize: ^c.int) -> [^]byte --- // Decompress data (DEFLATE algorithm), memory must be MemFree()
	EncodeDataBase64 :: proc(data: rawptr, dataSize: c.int, outputSize: ^c.int) -> [^]byte --- // Encode data to Base64 string, memory must be MemFree()
	DecodeDataBase64 :: proc(data: rawptr, outputSize: ^c.int) -> [^]byte --- // Decode Base64 string data, memory must be MemFree()
	ComputeCRC32 :: proc(data: rawptr, dataSize: c.int) -> c.uint --- // Compute CRC32 hash code
	ComputeMD5 :: proc(data: rawptr, dataSize: c.int) -> [^]c.uint --- // Compute MD5 hash code, returns static int[4] (16 bytes)
	ComputeSHA1 :: proc(data: rawptr, dataSize: c.int) -> [^]c.uint --- // Compute SHA1 hash code, returns static int[5] (20 bytes)


	// Automation events functionality

	LoadAutomationEventList :: proc(fileName: cstring) -> AutomationEventList --- // Load automation events list from file, NULL for empty list, capacity = MAX_AUTOMATION_EVENTS
	UnloadAutomationEventList :: proc(list: AutomationEventList) --- // Unload automation events list from file
	ExportAutomationEventList :: proc(list: AutomationEventList, fileName: cstring) -> bool --- // Export automation events list as text file
	SetAutomationEventList :: proc(list: ^AutomationEventList) --- // Set automation event list to record to
	SetAutomationEventBaseFrame :: proc(frame: c.int) --- // Set automation event internal base frame to start recording
	StartAutomationEventRecording :: proc() --- // Start recording automation events (AutomationEventList must be set)
	StopAutomationEventRecording :: proc() --- // Stop recording automation events
	PlayAutomationEvent :: proc(event: AutomationEvent) --- // Play a recorded automation event

	//------------------------------------------------------------------------------------
	// Input Handling Functions (Module: core)
	//------------------------------------------------------------------------------------

	// Input-related functions: keyboard

	IsKeyPressed :: proc(key: KeyboardKey) -> bool --- // Detect if a key has been pressed once
	IsKeyPressedRepeat :: proc(key: KeyboardKey) -> bool --- // Check if a key has been pressed again
	IsKeyDown :: proc(key: KeyboardKey) -> bool --- // Detect if a key is being pressed
	IsKeyReleased :: proc(key: KeyboardKey) -> bool --- // Detect if a key has been released once
	IsKeyUp :: proc(key: KeyboardKey) -> bool --- // Detect if a key is NOT being pressed
	GetKeyPressed :: proc() -> KeyboardKey --- // Get key pressed (keycode), call it multiple times for keys queued
	GetCharPressed :: proc() -> rune --- // Get char pressed (unicode), call it multiple times for chars queued
	SetExitKey :: proc(key: KeyboardKey) --- // Set a custom key to exit program (default is ESC)

	// Input-related functions: gamepads

	IsGamepadAvailable :: proc(gamepad: c.int) -> bool --- // Check if a gamepad is available
	GetGamepadName :: proc(gamepad: c.int) -> cstring --- // Get gamepad internal name id
	IsGamepadButtonPressed :: proc(gamepad: c.int, button: GamepadButton) -> bool --- // Check if a gamepad button has been pressed once
	IsGamepadButtonDown :: proc(gamepad: c.int, button: GamepadButton) -> bool --- // Check if a gamepad button is being pressed
	IsGamepadButtonReleased :: proc(gamepad: c.int, button: GamepadButton) -> bool --- // Check if a gamepad button has been released once
	IsGamepadButtonUp :: proc(gamepad: c.int, button: GamepadButton) -> bool --- // Check if a gamepad button is NOT being pressed
	GetGamepadButtonPressed :: proc() -> GamepadButton --- // Get the last gamepad button pressed
	GetGamepadAxisCount :: proc(gamepad: c.int) -> c.int --- // Get gamepad axis count for a gamepad
	GetGamepadAxisMovement :: proc(gamepad: c.int, axis: GamepadAxis) -> f32 --- // Get axis movement value for a gamepad axis
	SetGamepadMappings :: proc(mappings: cstring) -> c.int --- // Set internal gamepad mappings (SDL_GameControllerDB)
	SetGamepadVibration :: proc(gamepad: c.int, leftMotor: f32, rightMotor: f32, duration: f32) --- // Set gamepad vibration for both motors (duration in seconds)


	// Input-related functions: mouse

	IsMouseButtonPressed :: proc(button: MouseButton) -> bool --- // Detect if a mouse button has been pressed once
	IsMouseButtonDown :: proc(button: MouseButton) -> bool --- // Detect if a mouse button is being pressed
	IsMouseButtonReleased :: proc(button: MouseButton) -> bool --- // Detect if a mouse button has been released once
	IsMouseButtonUp :: proc(button: MouseButton) -> bool ---

	GetMouseX :: proc() -> c.int --- // Returns mouse position X
	GetMouseY :: proc() -> c.int --- // Returns mouse position Y
	GetMousePosition :: proc() -> Vector2 --- // Returns mouse position XY
	GetMouseDelta :: proc() -> Vector2 --- // Returns mouse delta XY
	SetMousePosition :: proc(x, y: c.int) --- // Set mouse position XY
	SetMouseOffset :: proc(offsetX, offsetY: c.int) --- // Set mouse offset
	SetMouseScale :: proc(scaleX, scaleY: f32) --- // Set mouse scaling
	GetMouseWheelMove :: proc() -> f32 --- // Returns mouse wheel movement Y
	GetMouseWheelMoveV :: proc() -> Vector2 --- // Get mouse wheel movement for both X and Y
	SetMouseCursor :: proc(cursor: MouseCursor) --- // Set mouse cursor

	// Input-related functions: touch

	GetTouchX :: proc() -> c.int --- // Returns touch position X for touch point 0 (relative to screen size)
	GetTouchY :: proc() -> c.int --- // Returns touch position Y for touch point 0 (relative to screen size)
	GetTouchPosition :: proc(index: c.int) -> Vector2 --- // Returns touch position XY for a touch point index (relative to screen size)
	GetTouchPointId :: proc(index: c.int) -> c.int --- // Get touch point identifier for given index
	GetTouchPointCount :: proc() -> c.int --- // Get number of touch points

	//------------------------------------------------------------------------------------
	// Gestures and Touch Handling Functions (Module: rgestures)
	//------------------------------------------------------------------------------------

	SetGesturesEnabled :: proc(flags: Gestures) --- // Enable a set of gestures using flags

	GetGestureDetected :: proc() -> Gestures --- // Get latest detected gesture
	GetGestureHoldDuration :: proc() -> f32 --- // Get gesture hold time in seconds
	GetGestureDragVector :: proc() -> Vector2 --- // Get gesture drag vector
	GetGestureDragAngle :: proc() -> f32 --- // Get gesture drag angle
	GetGesturePinchVector :: proc() -> Vector2 --- // Get gesture pinch delta
	GetGesturePinchAngle :: proc() -> f32 --- // Get gesture pinch angle

	//------------------------------------------------------------------------------------
	// Basic Shapes Drawing Functions (Module: shapes)
	//------------------------------------------------------------------------------------
	// Set texture and rectangle to be used on shapes drawing
	// NOTE: It can be useful when using basic shapes and one single font,
	// defining a font char white rectangle would allow drawing everything in a single draw call

	SetShapesTexture :: proc(texture: Texture2D, source: Rectangle) --- // Set texture and rectangle to be used on shapes drawing
	GetShapesTexture :: proc() -> Texture2D --- // Get texture that is used for shapes drawing
	GetShapesTextureRectangle :: proc() -> Rectangle --- // Get texture source rectangle that is used for shapes drawing


	// Basic shapes drawing functions

	DrawPixel :: proc(posX, posY: c.int, color: Color) --- // Draw a pixel using geometry [Can be slow, use with care]
	DrawPixelV :: proc(position: Vector2, color: Color) --- // Draw a pixel using geometry (Vector version) [Can be slow, use with care]
	DrawLine :: proc(startPosX, startPosY, endPosX, endPosY: c.int, color: Color) --- // Draw a line
	DrawLineV :: proc(startPos, endPos: Vector2, color: Color) --- // Draw a line (using gl lines)
	DrawLineEx :: proc(startPos, endPos: Vector2, thick: f32, color: Color) --- // Draw a line (using triangles/quads)
	DrawLineStrip :: proc(points: [^]Vector2, pointCount: c.int, color: Color) --- // Draw lines sequence (using gl lines)
	DrawLineBezier :: proc(startPos, endPos: Vector2, thick: f32, color: Color) --- // Draw line segment cubic-bezier in-out interpolation
	DrawCircle :: proc(centerX, centerY: c.int, radius: f32, color: Color) --- // Draw a color-filled circle
	DrawCircleSector :: proc(center: Vector2, radius: f32, startAngle, endAngle: f32, segments: c.int, color: Color) --- // Draw a piece of a circle
	DrawCircleSectorLines :: proc(center: Vector2, radius: f32, startAngle, endAngle: f32, segments: c.int, color: Color) --- // Draw circle sector outline
	DrawCircleGradient :: proc(center: Vector2, radius: f32, inner, outer: Color) --- // Draw a gradient-filled circle [v6: was (centerX, centerY: c.int, ...)]
	DrawCircleV :: proc(center: Vector2, radius: f32, color: Color) --- // Draw a color-filled circle (Vector version)
	DrawCircleLines :: proc(centerX, centerY: c.int, radius: f32, color: Color) --- // Draw circle outline
	DrawCircleLinesV :: proc(center: Vector2, radius: f32, color: Color) --- // Draw circle outline (Vector version)
	DrawEllipse :: proc(centerX, centerY: c.int, radiusH, radiusV: f32, color: Color) --- // Draw ellipse
	DrawEllipseLines :: proc(centerX, centerY: c.int, radiusH, radiusV: f32, color: Color) --- // Draw ellipse outline
	DrawRing :: proc(center: Vector2, innerRadius, outerRadius: f32, startAngle, endAngle: f32, segments: c.int, color: Color) --- // Draw ring
	DrawRingLines :: proc(center: Vector2, innerRadius, outerRadius: f32, startAngle, endAngle: f32, segments: c.int, color: Color) --- // Draw ring outline
	DrawRectangle :: proc(posX, posY: c.int, width, height: c.int, color: Color) --- // Draw a color-filled rectangle
	DrawRectangleV :: proc(position: Vector2, size: Vector2, color: Color) --- // Draw a color-filled rectangle (Vector version)
	DrawRectangleRec :: proc(rec: Rectangle, color: Color) --- // Draw a color-filled rectangle
	DrawRectanglePro :: proc(rec: Rectangle, origin: Vector2, rotation: f32, color: Color) --- // Draw a color-filled rectangle with pro parameters
	DrawRectangleGradientV :: proc(posX, posY: c.int, width, height: c.int, top, bottom: Color) --- // Draw a vertical-gradient-filled rectangle
	DrawRectangleGradientH :: proc(posX, posY: c.int, width, height: c.int, left, right: Color) --- // Draw a horizontal-gradient-filled rectangle
	DrawRectangleGradientEx :: proc(rec: Rectangle, topLeft, bottomLeft, topRight, bottomRight: Color) --- // Draw a gradient-filled rectangle with custom vertex colors
	DrawRectangleLines :: proc(posX, posY: c.int, width, height: c.int, color: Color) --- // Draw rectangle outline
	DrawRectangleLinesEx :: proc(rec: Rectangle, lineThick: f32, color: Color) --- // Draw rectangle outline with extended parameters
	DrawRectangleRounded :: proc(rec: Rectangle, roundness: f32, segments: c.int, color: Color) --- // Draw rectangle with rounded edges
	DrawRectangleRoundedLines :: proc(rec: Rectangle, roundness: f32, segments: c.int, color: Color) --- // Draw rectangle lines with rounded edges
	DrawRectangleRoundedLinesEx :: proc(rec: Rectangle, roundness: f32, segments: c.int, lineThick: f32, color: Color) --- // Draw rectangle with rounded edges outline
	DrawTriangle :: proc(v1, v2, v3: Vector2, color: Color) --- // Draw a color-filled triangle (vertex in counter-clockwise order!)
	DrawTriangleLines :: proc(v1, v2, v3: Vector2, color: Color) --- // Draw triangle outline (vertex in counter-clockwise order!)
	DrawTriangleFan :: proc(points: [^]Vector2, pointCount: c.int, color: Color) --- // Draw a triangle fan defined by points (first vertex is the center)
	DrawTriangleStrip :: proc(points: [^]Vector2, pointCount: c.int, color: Color) --- // Draw a triangle strip defined by points
	DrawPoly :: proc(center: Vector2, sides: c.int, radius: f32, rotation: f32, color: Color) --- // Draw a regular polygon (Vector version)
	DrawPolyLines :: proc(center: Vector2, sides: c.int, radius: f32, rotation: f32, color: Color) --- // Draw a polygon outline of n sides
	DrawPolyLinesEx :: proc(center: Vector2, sides: c.int, radius: f32, rotation: f32, lineThick: f32, color: Color) --- // Draw a polygon outline of n sides with extended parameters

	// Splines drawing functions
	DrawSplineLinear :: proc(points: [^]Vector2, pointCount: c.int, thick: f32, color: Color) --- // Draw spline: Linear, minimum 2 points
	DrawSplineBasis :: proc(points: [^]Vector2, pointCount: c.int, thick: f32, color: Color) --- // Draw spline: B-Spline, minimum 4 points
	DrawSplineCatmullRom :: proc(points: [^]Vector2, pointCount: c.int, thick: f32, color: Color) --- // Draw spline: Catmull-Rom, minimum 4 points
	DrawSplineBezierQuadratic :: proc(points: [^]Vector2, pointCount: c.int, thick: f32, color: Color) --- // Draw spline: Quadratic Bezier, minimum 3 points (1 control point): [p1, c2, p3, c4...]
	DrawSplineBezierCubic :: proc(points: [^]Vector2, pointCount: c.int, thick: f32, color: Color) --- // Draw spline: Cubic Bezier, minimum 4 points (2 control points): [p1, c2, c3, p4, c5, c6...]
	DrawSplineSegmentLinear :: proc(p1, p2: Vector2, thick: f32, color: Color) --- // Draw spline segment: Linear, 2 points
	DrawSplineSegmentBasis :: proc(p1, p2, p3, p4: Vector2, thick: f32, color: Color) --- // Draw spline segment: B-Spline, 4 points
	DrawSplineSegmentCatmullRom :: proc(p1, p2, p3, p4: Vector2, thick: f32, color: Color) --- // Draw spline segment: Catmull-Rom, 4 points
	DrawSplineSegmentBezierQuadratic :: proc(p1, c2, p3: Vector2, thick: f32, color: Color) --- // Draw spline segment: Quadratic Bezier, 2 points, 1 control point
	DrawSplineSegmentBezierCubic :: proc(p1, c2, c3, p4: Vector2, thick: f32, color: Color) --- // Draw spline segment: Cubic Bezier, 2 points, 2 control points

	// Spline segment point evaluation functions, for a given t [0.0f .. 1.0f]
	GetSplinePointLinear :: proc(startPos, endPos: Vector2, t: f32) -> Vector2 --- // Get (evaluate) spline point: Linear
	GetSplinePointBasis :: proc(p1, p2, p3, p4: Vector2, t: f32) -> Vector2 --- // Get (evaluate) spline point: B-Spline
	GetSplinePointCatmullRom :: proc(p1, p2, p3, p4: Vector2, t: f32) -> Vector2 --- // Get (evaluate) spline point: Catmull-Rom
	GetSplinePointBezierQuad :: proc(p1, c2, p3: Vector2, t: f32) -> Vector2 --- // Get (evaluate) spline point: Quadratic Bezier
	GetSplinePointBezierCubic :: proc(p1, c2, c3, p4: Vector2, t: f32) -> Vector2 --- // Get (evaluate) spline point: Cubic Bezier
	// Basic shapes collision detection functions
	CheckCollisionRecs :: proc(rec1, rec2: Rectangle) -> bool --- // Check collision between two rectangles
	CheckCollisionCircles :: proc(center1: Vector2, radius1: f32, center2: Vector2, radius2: f32) -> bool --- // Check collision between two circles
	CheckCollisionCircleRec :: proc(center: Vector2, radius: f32, rec: Rectangle) -> bool --- // Check collision between circle and rectangle
	CheckCollisionCircleLine :: proc(center: Vector2, radius: f32, p1, p2: Vector2) -> bool --- // Check if circle collides with a line created betweeen two points [p1] and [p2]
	CheckCollisionPointRec :: proc(point: Vector2, rec: Rectangle) -> bool --- // Check if point is inside rectangle
	CheckCollisionPointCircle :: proc(point, center: Vector2, radius: f32) -> bool --- // Check if point is inside circle
	CheckCollisionPointTriangle :: proc(point: Vector2, p1, p2, p3: Vector2) -> bool --- // Check if point is inside a triangle
	CheckCollisionPointLine :: proc(point: Vector2, p1, p2: Vector2, threshold: c.int) -> bool --- // Check if point belongs to line created between two points [p1] and [p2] with defined margin in pixels [threshold]
	CheckCollisionPointPoly :: proc(point: Vector2, points: [^]Vector2, pointCount: c.int) -> bool --- // Check if point is within a polygon described by array of vertices
	CheckCollisionLines :: proc(startPos1, endPos1, startPos2, endPos2: Vector2, collisionPoint: [^]Vector2) -> bool --- // Check the collision between two lines defined by two points each, returns collision point by reference
	GetCollisionRec :: proc(rec1, rec2: Rectangle) -> Rectangle --- // Get collision rectangle for two rectangles collision


	// Image loading functions
	// NOTE: These functions do not require GPU access

	LoadImage :: proc(fileName: cstring) -> Image --- // Load image from file into CPU memory (RAM)
	LoadImageRaw :: proc(fileName: cstring, width, height: c.int, format: PixelFormat, headerSize: c.int) -> Image --- // Load image from RAW file data
	LoadImageAnim :: proc(fileName: cstring, frames: ^c.int) -> Image --- // Load image sequence from file (frames appended to image.data)
	LoadImageAnimFromMemory :: proc(fileType: cstring, fileData: rawptr, dataSize: c.int, frames: ^c.int) -> Image --- // Load image sequence from memory buffer
	LoadImageFromMemory :: proc(fileType: cstring, fileData: rawptr, dataSize: c.int) -> Image --- // Load image from memory buffer, fileType refers to extension: i.e. '.png'
	LoadImageFromTexture :: proc(texture: Texture2D) -> Image --- // Load image from GPU texture data
	LoadImageFromScreen :: proc() -> Image --- // Load image from screen buffer and (screenshot)
	IsImageValid :: proc(image: Image) -> bool --- // Check if an image is ready
	UnloadImage :: proc(image: Image) --- // Unload image from CPU memory (RAM)
	ExportImage :: proc(image: Image, fileName: cstring) -> bool --- // Export image data to file, returns true on success
	ExportImageToMemory :: proc(image: Image, fileType: cstring, fileSize: ^c.int) -> rawptr --- // Export image to memory buffer
	ExportImageAsCode :: proc(image: Image, fileName: cstring) -> bool --- // Export image as code file defining an array of bytes, returns true on success

	// Image generation functions

	GenImageColor :: proc(width, height: c.int, color: Color) -> Image --- // Generate image: plain color
	GenImageGradientLinear :: proc(width, height, direction: c.int, start, end: Color) -> Image --- // Generate image: linear gradient, direction in degrees [0..360], 0=Vertical gradient
	GenImageGradientRadial :: proc(width, height: c.int, density: f32, inner, outer: Color) -> Image --- // Generate image: radial gradient
	GenImageGradientSquare :: proc(width, height: c.int, density: f32, inner, outer: Color) -> Image --- // Generate image: square gradient
	GenImageChecked :: proc(width, height: c.int, checksX, checksY: c.int, col1, col2: Color) -> Image --- // Generate image: checked
	GenImageWhiteNoise :: proc(width, height: c.int, factor: f32) -> Image --- // Generate image: white noise
	GenImagePerlinNoise :: proc(width, height: c.int, offsetX, offsetY: c.int, scale: f32) -> Image --- // Generate image: perlin noise
	GenImageCellular :: proc(width, height: c.int, tileSize: c.int) -> Image --- // Generate image: cellular algorithm, bigger tileSize means bigger cells
	GenImageText :: proc(width, height: c.int, text: cstring) -> Image --- // Generate image: grayscale image from text data

	// Image manipulation functions

	ImageCopy :: proc(image: Image) -> Image --- // Create an image duplicate (useful for transformations)
	ImageFromImage :: proc(image: Image, rec: Rectangle) -> Image --- // Create an image from another image piece
	ImageFromChannel :: proc(image: Image, selectedChannel: c.int) -> Image --- // Create an image from a selected channel of another image (GRAYSCALE)
	ImageText :: proc(text: cstring, fontSize: c.int, color: Color) -> Image --- // Create an image from text (default font)
	ImageTextEx :: proc(font: Font, text: cstring, fontSize: f32, spacing: f32, tint: Color) -> Image --- // Create an image from text (custom sprite font)
	ImageFormat :: proc(image: ^Image, newFormat: PixelFormat) --- // Convert image data to desired format
	ImageToPOT :: proc(image: ^Image, fill: Color) --- // Convert image to POT (power-of-two)
	ImageCrop :: proc(image: ^Image, crop: Rectangle) --- // Crop an image to a defined rectangle
	ImageAlphaCrop :: proc(image: ^Image, threshold: f32) --- // Crop image depending on alpha value
	ImageAlphaClear :: proc(image: ^Image, color: Color, threshold: f32) --- // Clear alpha channel to desired color
	ImageAlphaMask :: proc(image: ^Image, alphaMask: Image) --- // Apply alpha mask to image
	ImageAlphaPremultiply :: proc(image: ^Image) --- // Premultiply alpha channel
	ImageBlurGaussian :: proc(image: ^Image, blurSize: c.int) --- // Apply Gaussian blur using a box blur approximation
	ImageKernelConvolution :: proc(image: ^Image, kernel: [^]f32, kernelSize: c.int) --- // Apply custom square convolution kernel to image
	ImageResize :: proc(image: ^Image, newWidth, newHeight: c.int) --- // Resize image (Bicubic scaling algorithm)
	ImageResizeNN :: proc(image: ^Image, newWidth, newHeight: c.int) --- // Resize image (Nearest-Neighbor scaling algorithm)
	ImageResizeCanvas :: proc(image: ^Image, newWidth, newHeight: c.int, offsetX, offsetY: c.int, fill: Color) --- // Resize canvas and fill with color
	ImageMipmaps :: proc(image: ^Image) --- // Compute all mipmap levels for a provided image
	ImageDither :: proc(image: ^Image, rBpp, gBpp, bBpp, aBpp: c.int) --- // Dither image data to 16bpp or lower (Floyd-Steinberg dithering)
	ImageFlipVertical :: proc(image: ^Image) --- // Flip image vertically
	ImageFlipHorizontal :: proc(image: ^Image) --- // Flip image horizontally
	ImageRotate :: proc(image: ^Image, degrees: c.int) --- // Rotate image by input angle in degrees( -359 to 359)
	ImageRotateCW :: proc(image: ^Image) --- // Rotate image clockwise 90deg
	ImageRotateCCW :: proc(image: ^Image) --- // Rotate image counter-clockwise 90deg
	ImageColorTint :: proc(image: ^Image, color: Color) --- // Modify image color: tint
	ImageColorInvert :: proc(image: ^Image) --- // Modify image color: invert
	ImageColorGrayscale :: proc(image: ^Image) --- // Modify image color: grayscale
	ImageColorContrast :: proc(image: ^Image, contrast: f32) --- // Modify image color: contrast (-100 to 100)
	ImageColorBrightness :: proc(image: ^Image, brightness: c.int) --- // Modify image color: brightness (-255 to 255)
	ImageColorReplace :: proc(image: ^Image, color, replace: Color) --- // Modify image color: replace color
	LoadImageColors :: proc(image: Image) -> [^]Color --- // Load color data from image as a Color array (RGBA - 32bit)
	LoadImagePalette :: proc(image: Image, maxPaletteSize: c.int, colorCount: ^c.int) -> [^]Color --- // Load colors palette from image as a Color array (RGBA - 32bit)
	UnloadImageColors :: proc(colors: [^]Color) --- // Unload color data loaded with LoadImageColors()
	UnloadImagePalette :: proc(colors: [^]Color) --- // Unload colors palette loaded with LoadImagePalette()
	GetImageAlphaBorder :: proc(image: Image, threshold: f32) -> Rectangle --- // Get image alpha border rectangle
	GetImageColor :: proc(image: Image, x, y: c.int) -> Color --- // Get image pixel color at (x, y) position

	// Image drawing functions
	// NOTE: Image software-rendering functions (CPU)

	ImageClearBackground :: proc(dst: ^Image, color: Color) --- // Clear image background with given color
	ImageDrawPixel :: proc(dst: ^Image, posX, posY: c.int, color: Color) --- // Draw pixel within an image
	ImageDrawPixelV :: proc(dst: ^Image, position: Vector2, color: Color) --- // Draw pixel within an image (Vector version)
	ImageDrawLine :: proc(dst: ^Image, startPosX, startPosY, endPosX, endPosY: c.int, color: Color) --- // Draw line within an image
	ImageDrawLineV :: proc(dst: ^Image, start, end: Vector2, color: Color) --- // Draw line within an image (Vector version)
	ImageDrawLineEx :: proc(dst: ^Image, start, end: Vector2, thick: c.int, color: Color) --- // Draw a line defining thickness within an image
	ImageDrawCircle :: proc(dst: ^Image, centerX, centerY: c.int, radius: c.int, color: Color) --- // Draw a filled circle within an image
	ImageDrawCircleV :: proc(dst: ^Image, center: Vector2, radius: c.int, color: Color) --- // Draw a filled circle within an image (Vector version)
	ImageDrawCircleLines :: proc(dst: ^Image, centerX, centerY: c.int, radius: c.int, color: Color) --- // Draw circle outline within an image
	ImageDrawCircleLinesV :: proc(dst: ^Image, center: Vector2, radius: c.int, color: Color) --- // Draw circle outline within an image (Vector version)
	ImageDrawRectangle :: proc(dst: ^Image, posX, posY: c.int, width, height: c.int, color: Color) --- // Draw rectangle within an image
	ImageDrawRectangleV :: proc(dst: ^Image, position, size: Vector2, color: Color) --- // Draw rectangle within an image (Vector version)
	ImageDrawRectangleRec :: proc(dst: ^Image, rec: Rectangle, color: Color) --- // Draw rectangle within an image
	ImageDrawRectangleLines :: proc(dst: ^Image, rec: Rectangle, thick: c.int, color: Color) --- // Draw rectangle lines within an image
	ImageDrawTriangle :: proc(dst: ^Image, v1, v2, v3: Vector2, color: Color) --- // Draw triangle within an image
	ImageDrawTriangleEx :: proc(dst: ^Image, v1, v2, v3: Vector2, c1, c2, c3: Color) --- // Draw triangle with interpolated colors within an image
	ImageDrawTriangleLines :: proc(dst: ^Image, v1, v2, v3: Vector2, color: Color) --- // Draw triangle outline within an image
	ImageDrawTriangleFan :: proc(dst: ^Image, points: [^]Vector2, pointCount: c.int, color: Color) --- // Draw a triangle fan defined by points within an image (first vertex is the center)
	ImageDrawTriangleStrip :: proc(dst: ^Image, points: [^]Vector2, pointCount: c.int, color: Color) --- // Draw a triangle strip defined by points within an image
	ImageDraw :: proc(dst: ^Image, src: Image, srcRec, dstRec: Rectangle, tint: Color) --- // Draw a source image within a destination image (tint applied to source)
	ImageDrawText :: proc(dst: ^Image, text: cstring, posX, posY: c.int, fontSize: c.int, color: Color) --- // Draw text (using default font) within an image (destination)
	ImageDrawTextEx :: proc(dst: ^Image, font: Font, text: cstring, position: Vector2, fontSize: f32, spacing: f32, tint: Color) --- // Draw text (custom sprite font) within an image (destination)

	// Texture loading functions
	// NOTE: These functions require GPU access

	LoadTexture :: proc(fileName: cstring) -> Texture2D --- // Load texture from file into GPU memory (VRAM)
	LoadTextureFromImage :: proc(image: Image) -> Texture2D --- // Load texture from image data
	LoadTextureCubemap :: proc(image: Image, layout: CubemapLayout) -> TextureCubemap --- // Load cubemap from image, multiple image cubemap layouts supported
	LoadRenderTexture :: proc(width, height: c.int) -> RenderTexture2D --- // Load texture for rendering (framebuffer)
	IsTextureValid :: proc(texture: Texture2D) -> bool --- // Check if a texture is valid
	UnloadTexture :: proc(texture: Texture2D) --- // Unload texture from GPU memory (VRAM)
	IsRenderTextureValid :: proc(target: RenderTexture2D) -> bool --- // Check if a render texture is valid
	UnloadRenderTexture :: proc(target: RenderTexture2D) --- // Unload render texture from GPU memory (VRAM)
	UpdateTexture :: proc(texture: Texture2D, pixels: rawptr) --- // Update GPU texture with new data
	UpdateTextureRec :: proc(texture: Texture2D, rec: Rectangle, pixels: rawptr) --- // Update GPU texture rectangle with new data

	// Texture configuration functions

	GenTextureMipmaps :: proc(texture: ^Texture2D) --- // Generate GPU mipmaps for a texture
	SetTextureFilter :: proc(texture: Texture2D, filter: TextureFilter) --- // Set texture scaling filter mode
	SetTextureWrap :: proc(texture: Texture2D, wrap: TextureWrap) --- // Set texture wrapping mode

	// Texture drawing functions
	DrawTexture :: proc(texture: Texture2D, posX, posY: c.int, tint: Color) --- // Draw a Texture2D
	DrawTextureV :: proc(texture: Texture2D, position: Vector2, tint: Color) --- // Draw a Texture2D with position defined as Vector2
	DrawTextureEx :: proc(texture: Texture2D, position: Vector2, rotation: f32, scale: f32, tint: Color) --- // Draw a Texture2D with extended parameters
	DrawTextureRec :: proc(texture: Texture2D, source: Rectangle, position: Vector2, tint: Color) --- // Draw a part of a texture defined by a rectangle
	DrawTexturePro :: proc(texture: Texture2D, source, dest: Rectangle, origin: Vector2, rotation: f32, tint: Color) --- // Draw a part of a texture defined by a rectangle with 'pro' parameters
	DrawTextureNPatch :: proc(texture: Texture2D, nPatchInfo: NPatchInfo, dest: Rectangle, origin: Vector2, rotation: f32, tint: Color) --- // Draws a texture (or part of it) that stretches or shrinks nicely

	// Color/pixel related functions

	@(deprecated = "Prefer col1 == col2")
	ColorIsEqual :: proc(col1, col2: Color) --- // Check if two colors are equal
	Fade :: proc(color: Color, alpha: f32) -> Color --- // Get color with alpha applied, alpha goes from 0.0f to 1.0f
	ColorToInt :: proc(color: Color) -> c.uint --- // Get hexadecimal value for a Color (0xRRGGBBAA)
	ColorNormalize :: proc(color: Color) -> Vector4 --- // Get Color normalized as float [0..1]
	ColorFromNormalized :: proc(normalized: Vector4) -> Color --- // Get Color from normalized values [0..1]
	ColorToHSV :: proc(color: Color) -> Vector3 --- // Get HSV values for a Color, hue [0..360], saturation/value [0..1]
	ColorFromHSV :: proc(hue, saturation, value: f32) -> Color --- // Get a Color from HSV values, hue [0..360], saturation/value [0..1]
	ColorTint :: proc(color, tint: Color) -> Color --- // Get color multiplied with another color
	ColorBrightness :: proc(color: Color, factor: f32) -> Color --- // Get color with brightness correction, brightness factor goes from -1.0f to 1.0f
	ColorContrast :: proc(color: Color, contrast: f32) -> Color --- // Get color with contrast correction, contrast values between -1.0f and 1.0f
	ColorAlpha :: proc(color: Color, alpha: f32) -> Color --- // Get color with alpha applied, alpha goes from 0.0f to 1.0f
	ColorAlphaBlend :: proc(dst, src, tint: Color) -> Color --- // Get src alpha-blended into dst color with tint
	ColorLerp :: proc(color1, color2: Color, factor: f32) -> Color --- // Get color lerp interpolation between two colors, factor [0.0f..1.0f]
	GetColor :: proc(hexValue: c.uint) -> Color --- // Get Color structure from hexadecimal value
	GetPixelColor :: proc(srcPtr: rawptr, format: PixelFormat) -> Color --- // Get Color from a source pixel pointer of certain format
	SetPixelColor :: proc(dstPtr: rawptr, color: Color, format: PixelFormat) --- // Set color formatted into destination pixel pointer
	GetPixelDataSize :: proc(width, height: c.int, format: PixelFormat) -> c.int --- // Get pixel data size in bytes for certain format


	//------------------------------------------------------------------------------------
	// Font Loading and Text Drawing Functions (Module: text)
	//------------------------------------------------------------------------------------

	// Font loading/unloading functions

	GetFontDefault :: proc() -> Font --- // Get the default Font
	LoadFont :: proc(fileName: cstring) -> Font --- // Load font from file into GPU memory (VRAM)
	LoadFontEx :: proc(fileName: cstring, fontSize: c.int, codepoints: [^]rune, codepointCount: c.int) -> Font --- // Load font from file with extended parameters, use NULL for codepoints and 0 for codepointCount to load the default character set, font size is provided in pixels height
	LoadFontFromImage :: proc(image: Image, key: Color, firstChar: rune) -> Font --- // Load font from Image (XNA style)
	LoadFontFromMemory :: proc(fileType: cstring, fileData: rawptr, dataSize: c.int, fontSize: c.int, codepoints: [^]rune, codepointCount: c.int) -> Font --- // Load font from memory buffer, fileType refers to extension: i.e. '.ttf'
	IsFontValid :: proc(font: Font) -> bool --- // Check if a font is valid (font data loaded, WARNING: GPU texture not checked)
	LoadFontData :: proc(fileData: rawptr, dataSize: c.int, fontSize: c.int, codepoints: [^]rune, codepointCount: c.int, type: FontType, glyphCount: ^c.int) -> [^]GlyphInfo --- // Load font data for further use
	GenImageFontAtlas :: proc(glyphs: [^]GlyphInfo, glyphRecs: ^[^]Rectangle, codepointCount: c.int, fontSize: c.int, padding: c.int, packMethod: c.int) -> Image --- // Generate image font atlas using chars info
	UnloadFontData :: proc(glyphs: [^]GlyphInfo, glyphCount: c.int) --- // Unload font chars info data (RAM)
	UnloadFont :: proc(font: Font) --- // Unload font from GPU memory (VRAM)
	ExportFontAsCode :: proc(font: Font, fileName: cstring) -> bool --- // Export font as code file, returns true on success

	// Text drawing functions

	DrawFPS :: proc(posX, posY: c.int) --- // Draw current FPS
	DrawText :: proc(text: cstring, posX, posY: c.int, fontSize: c.int, color: Color) --- // Draw text (using default font)
	DrawTextEx :: proc(font: Font, text: cstring, position: Vector2, fontSize: f32, spacing: f32, tint: Color) --- // Draw text using font and additional parameters
	DrawTextPro :: proc(font: Font, text: cstring, position, origin: Vector2, rotation: f32, fontSize: f32, spacing: f32, tint: Color) --- // Draw text using Font and pro parameters (rotation)
	DrawTextCodepoint :: proc(font: Font, codepoint: rune, position: Vector2, fontSize: f32, tint: Color) --- // Draw one character (codepoint)
	DrawTextCodepoints :: proc(font: Font, codepoints: [^]rune, codepointCount: c.int, position: Vector2, fontSize: f32, spacing: f32, tint: Color) --- // Draw multiple character (codepoint)

	// Text font info functions

	SetTextLineSpacing :: proc(spacing: c.int) --- // Set vertical line spacing when drawing with line-breaks
	MeasureText :: proc(text: cstring, fontSize: c.int) -> c.int --- // Measure string width for default font
	MeasureTextEx :: proc(font: Font, text: cstring, fontSize: f32, spacing: f32) -> Vector2 --- // Measure string size for Font
	GetGlyphIndex :: proc(font: Font, codepoint: rune) -> c.int --- // Get glyph index position in font for a codepoint (unicode character), fallback to '?' if not found
	GetGlyphInfo :: proc(font: Font, codepoint: rune) -> GlyphInfo --- // Get glyph font info data for a codepoint (unicode character), fallback to '?' if not found
	GetGlyphAtlasRec :: proc(font: Font, codepoint: rune) -> Rectangle --- // Get glyph rectangle in font atlas for a codepoint (unicode character), fallback to '?' if not found

	// Text codepoints management functions (unicode characters)

	LoadUTF8 :: proc(codepoints: [^]rune, length: c.int) -> [^]byte --- // Load UTF-8 text encoded from codepoints array
	UnloadUTF8 :: proc(text: [^]byte) --- // Unload UTF-8 text encoded from codepoints array
	LoadCodepoints :: proc(text: cstring, count: ^c.int) -> [^]rune --- // Load all codepoints from a UTF-8 text string, codepoints count returned by parameter
	UnloadCodepoints :: proc(codepoints: [^]rune) --- // Unload codepoints data from memory
	GetCodepointCount :: proc(text: cstring) -> c.int --- // Get total number of codepoints in a UTF-8 encoded string
	GetCodepoint :: proc(text: cstring, codepointSize: ^c.int) -> rune --- // Get next codepoint in a UTF-8 encoded string, 0x3f('?') is returned on failure
	GetCodepointNext :: proc(text: cstring, codepointSize: ^c.int) -> rune --- // Get next codepoint in a UTF-8 encoded string, 0x3f('?') is returned on failure
	GetCodepointPrevious :: proc(text: cstring, codepointSize: ^c.int) -> rune --- // Get previous codepoint in a UTF-8 encoded string, 0x3f('?') is returned on failure
	CodepointToUTF8 :: proc(codepoint: rune, utf8Size: ^c.int) -> cstring --- // Encode one codepoint into UTF-8 byte array (array length returned as parameter)

	//------------------------------------------------------------------------------------
	// Audio Loading and Playing Functions (Module: audio)
	//------------------------------------------------------------------------------------

	// Audio device management functions

	InitAudioDevice :: proc() --- // Initialize audio device and context
	CloseAudioDevice :: proc() --- // Close the audio device and context
	IsAudioDeviceReady :: proc() -> bool --- // Check if audio device has been initialized successfully
	SetMasterVolume :: proc(volume: f32) --- // Set master volume (listener)
	GetMasterVolume :: proc() -> f32 --- // Get master volume (listener)

	// Wave/Sound loading/unloading functions

	LoadWave :: proc(fileName: cstring) -> Wave --- // Load wave data from file
	LoadWaveFromMemory :: proc(fileType: cstring, fileData: rawptr, dataSize: c.int) -> Wave --- // Load wave from memory buffer, fileType refers to extension: i.e. '.wav'
	IsWaveValid :: proc(wave: Wave) -> bool --- // Checks if wave data is // Checks if wave data is valid (data loaded and parameters)
	LoadSound :: proc(fileName: cstring) -> Sound --- // Load sound from file
	LoadSoundFromWave :: proc(wave: Wave) -> Sound --- // Load sound from wave data
	LoadSoundAlias :: proc(source: Sound) -> Sound --- // Create a new sound that shares the same sample data as the source sound, does not own the sound data
	IsSoundValid :: proc(sound: Sound) -> bool --- // Checks if a sound is valid (data loaded and buffers initialized)
	UpdateSound :: proc(sound: Sound, data: rawptr, frameCount: c.int) --- // Update sound buffer with new data
	UnloadWave :: proc(wave: Wave) --- // Unload wave data
	UnloadSound :: proc(sound: Sound) --- // Unload sound
	UnloadSoundAlias :: proc(alias: Sound) --- // Unload a sound alias (does not deallocate sample data)
	ExportWave :: proc(wave: Wave, fileName: cstring) -> bool --- // Export wave data to file, returns true on success
	ExportWaveAsCode :: proc(wave: Wave, fileName: cstring) -> bool --- // Export wave sample data to code (.h), returns true on success

	// Wave/Sound management functions

	PlaySound :: proc(sound: Sound) --- // Play a sound
	StopSound :: proc(sound: Sound) --- // Stop playing a sound
	PauseSound :: proc(sound: Sound) --- // Pause a sound
	ResumeSound :: proc(sound: Sound) --- // Resume a paused sound
	IsSoundPlaying :: proc(sound: Sound) -> bool --- // Check if a sound is currently playing
	SetSoundVolume :: proc(sound: Sound, volume: f32) --- // Set volume for a sound (1.0 is max level)
	SetSoundPitch :: proc(sound: Sound, pitch: f32) --- // Set pitch for a sound (1.0 is base level)
	SetSoundPan :: proc(sound: Sound, pan: f32) --- // Set pan for a sound (0.5 is center)
	WaveCopy :: proc(wave: Wave) -> Wave --- // Copy a wave to a new wave
	WaveCrop :: proc(wave: ^Wave, initFrame, finalFrame: c.int) --- // Crop a wave to defined samples range
	WaveFormat :: proc(wave: ^Wave, sampleRate, sampleSize: c.int, channels: c.int) --- // Convert wave data to desired format
	LoadWaveSamples :: proc(wave: Wave) -> [^]f32 --- // Load samples data from wave as a 32bit float data array
	UnloadWaveSamples :: proc(samples: [^]f32) --- // Unload samples data loaded with LoadWaveSamples()


	// Music management functions

	LoadMusicStream :: proc(fileName: cstring) -> Music --- // Load music stream from file
	LoadMusicStreamFromMemory :: proc(fileType: cstring, data: rawptr, dataSize: c.int) -> Music --- // Load music stream from data
	IsMusicValid :: proc(music: Music) -> bool --- // Checks if a music stream is valid (context and buffers initialized)
	UnloadMusicStream :: proc(music: Music) --- // Unload music stream
	PlayMusicStream :: proc(music: Music) --- // Start music playing
	IsMusicStreamPlaying :: proc(music: Music) -> bool --- // Check if music is playing
	UpdateMusicStream :: proc(music: Music) --- // Updates buffers for music streaming
	StopMusicStream :: proc(music: Music) --- // Stop music playing
	PauseMusicStream :: proc(music: Music) --- // Pause music playing
	ResumeMusicStream :: proc(music: Music) --- // Resume playing paused music
	SeekMusicStream :: proc(music: Music, position: f32) --- // Seek music to a position (in seconds)
	SetMusicVolume :: proc(music: Music, volume: f32) --- // Set volume for music (1.0 is max level)
	SetMusicPitch :: proc(music: Music, pitch: f32) --- // Set pitch for a music (1.0 is base level)
	SetMusicPan :: proc(music: Music, pan: f32) --- // Set pan for a music (0.5 is center)
	GetMusicTimeLength :: proc(music: Music) -> f32 --- // Get music time length (in seconds)
	GetMusicTimePlayed :: proc(music: Music) -> f32 --- // Get current music time played (in seconds)

	// AudioStream management functions

	LoadAudioStream :: proc(sampleRate, sampleSize: c.uint, channels: c.uint) -> AudioStream --- // Load audio stream (to stream raw audio pcm data)
	IsAudioStreamValid :: proc(stream: AudioStream) -> bool --- // Checks if an audio stream is valid (buffers initialized)
	UnloadAudioStream :: proc(stream: AudioStream) --- // Unload audio stream and free memory
	UpdateAudioStream :: proc(stream: AudioStream, data: rawptr, frameCount: c.int) --- // Update audio stream buffers with data
	IsAudioStreamProcessed :: proc(stream: AudioStream) -> bool --- // Check if any audio stream buffers requires refill
	PlayAudioStream :: proc(stream: AudioStream) --- // Play audio stream
	PauseAudioStream :: proc(stream: AudioStream) --- // Pause audio stream
	ResumeAudioStream :: proc(stream: AudioStream) --- // Resume audio stream
	IsAudioStreamPlaying :: proc(stream: AudioStream) -> bool --- // Check if audio stream is playing
	StopAudioStream :: proc(stream: AudioStream) --- // Stop audio stream
	SetAudioStreamVolume :: proc(stream: AudioStream, volume: f32) --- // Set volume for audio stream (1.0 is max level)
	SetAudioStreamPitch :: proc(stream: AudioStream, pitch: f32) --- // Set pitch for audio stream (1.0 is base level)
	SetAudioStreamPan :: proc(stream: AudioStream, pan: f32) --- // Set pan for audio stream (0.5 is centered)
	SetAudioStreamBufferSizeDefault :: proc(size: c.int) --- // Default size for new audio streams
	SetAudioStreamCallback :: proc(stream: AudioStream, callback: AudioCallback) --- // Audio thread callback to request new data

	AttachAudioStreamProcessor :: proc(stream: AudioStream, processor: AudioCallback) --- // Attach audio stream processor to stream, receives the samples as 'float'
	DetachAudioStreamProcessor :: proc(stream: AudioStream, processor: AudioCallback) --- // Detach audio stream processor from stream

	AttachAudioMixedProcessor :: proc(processor: AudioCallback) --- // Attach audio stream processor to the entire audio pipeline, receives the samples as 'float'
	DetachAudioMixedProcessor :: proc(processor: AudioCallback) --- // Detach audio stream processor from the entire audio pipeline
}

//  Check if a gesture have been detected
IsGestureDetected :: proc "c" (gesture: Gesture) -> bool {
	@(default_calling_convention = "c")
	foreign lib {
		IsGestureDetected :: proc "c" (gesture: Gestures) -> bool ---
	}
	return IsGestureDetected({gesture})
}

// Internal memory free
MemFree :: proc {
	MemFreePtr,
	MemFreeCstring,
}


@(default_calling_convention = "c")
foreign lib {
	@(link_name = "MemFree")
	MemFreePtr :: proc(ptr: rawptr) ---
}

MemFreeCstring :: proc "c" (s: cstring) {
	MemFreePtr(rawptr(s))
}


MemAllocator :: proc "contextless" () -> mem.Allocator {
	return mem.Allocator{MemAllocatorProc, nil}
}

MemAllocatorProc :: proc(
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (
	data: []byte,
	err: mem.Allocator_Error,
) {
	switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		ptr := MemAlloc(c.uint(size))
		if ptr == nil {
			err = .Out_Of_Memory
			return
		}
		data = mem.byte_slice(ptr, size)
		return
	case .Free:
		MemFree(old_memory)
		return nil, nil

	case .Resize, .Resize_Non_Zeroed:
		ptr := MemRealloc(old_memory, c.uint(size))
		if ptr == nil {
			err = .Out_Of_Memory
			return
		}
		data = mem.byte_slice(ptr, size)
		return

	case .Free_All, .Query_Features, .Query_Info:
		return nil, .Mode_Not_Implemented
	}
	return nil, .Mode_Not_Implemented
}
