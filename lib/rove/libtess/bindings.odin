package libtess

import "core:c"

foreign import lib {#config(LIBTESS2_LIB, "libtess2.a")}

Tesselator :: struct {} // opaque

Real :: f32
Index :: c.int

UNDEF :: ~Index(0)

WindingRule :: enum c.int {
	ODD,
	NONZERO,
	POSITIVE,
	NEGATIVE,
	ABS_GEQ_TWO,
}

ElementType :: enum c.int {
	POLYGONS,
	CONNECTED_POLYGONS,
	BOUNDARY_CONTOURS,
}

Option :: enum c.int {
	CONSTRAINED_DELAUNAY_TRIANGULATION,
	REVERSE_CONTOURS,
}

Status :: enum c.int {
	OK,
	OUT_OF_MEMORY,
	INVALID_INPUT,
}

@(link_prefix = "tess", default_calling_convention = "c")
foreign lib {
	NewTess :: proc(alloc: rawptr) -> ^Tesselator ---
	DeleteTess :: proc(tess: ^Tesselator) ---
	AddContour :: proc(tess: ^Tesselator, size: c.int, pointer: rawptr, stride: c.int, count: c.int) ---
	SetOption :: proc(tess: ^Tesselator, option: Option, value: c.int) ---
	Tesselate :: proc(tess: ^Tesselator, windingRule: WindingRule, elementType: ElementType, polySize: c.int, vertexSize: c.int, normal: [^]Real) -> c.int ---

	GetVertexCount :: proc(tess: ^Tesselator) -> c.int ---
	GetVertices :: proc(tess: ^Tesselator) -> [^]Real ---
	GetVertexIndices :: proc(tess: ^Tesselator) -> [^]Index ---
	GetElementCount :: proc(tess: ^Tesselator) -> c.int ---
	GetElements :: proc(tess: ^Tesselator) -> [^]Index ---

	GetStatus :: proc(tess: ^Tesselator) -> Status ---
}
