package box2d

import "core:math"
import lin "core:math/linalg"

EPSILON :: math.F32_EPSILON

Vec2 :: [2]f32

// Cosine and sine pair
// This uses a custom implementation designed for cross-platform determinism
CosSin :: struct {
	// cosine and sine
	cosine: f32,
	sine:   f32,
}

Rot :: struct {
	c, s: f32, // cosine and sine
}

Transform :: struct {
	p: Vec2,
	q: Rot,
}

Mat22 :: matrix[2, 2]f32
AABB :: struct {
	lowerBound: Vec2,
	upperBound: Vec2,
}

// separation = dot(normal, point) - offset
Plane :: struct {
	normal: Vec2,
	offset: f32,
}

PI :: math.PI

Vec2_zero :: Vec2{0, 0}
Rot_identity :: Rot{1, 0}
Transform_identity :: Transform{{0, 0}, {1, 0}}
Mat22_zero :: Mat22{0, 0, 0, 0}

@(require_results)
ComputeCosSin :: proc "c" (radians: f32) -> (res: CosSin) {
	res.sine, res.cosine = math.sincos(radians)
	return
}

@(require_results)
IsNormalized :: proc "c" (v: Vec2) -> bool {
	aa := lin.dot(v, v)
	return abs(1. - aa) < 100. * EPSILON
}

@(require_results)
NormalizeChecked :: proc "odin" (v: Vec2) -> Vec2 {
	length := lin.length(v)
	if length < 1e-23 {
		panic("zero-length Vec2")
	}
	invLength := 1 / length
	return invLength * v
}

@(require_results)
GetLengthAndNormalize :: proc "c" (v: Vec2) -> (length: f32, vn: Vec2) {
	length = lin.length(v)
	if length < 1e-23 {
		return
	}
	invLength := 1 / length
	vn = invLength * v
	return
}

// Integration rotation from angular velocity
//	@param q1 initial rotation
//	@param deltaAngle the angular displacement in radians
@(require_results)
IntegrateRotation :: proc "c" (q1: Rot, deltaAngle: f32) -> Rot {
	// dc/dt = -omega * sin(t)
	// ds/dt = omega * cos(t)
	// c2 = c1 - omega * h * s1
	// s2 = s1 + omega * h * c1
	q2 := Rot{q1.c - deltaAngle * q1.s, q1.s + deltaAngle * q1.c}
	mag := math.sqrt(q2.s * q2.s + q2.c * q2.c)
	invMag := f32(mag > 0.0 ? 1 / mag : 0.0)
	return {q2.c * invMag, q2.s * invMag}
}

// Get the length squared of this vector
@(require_results)
LengthSquared :: proc "c" (v: Vec2) -> f32 {
	return v.x * v.x + v.y * v.y
}

// Get the distance squared between points
@(require_results)
DistanceSquared :: proc "c" (a, b: Vec2) -> f32 {
	c := Vec2{b.x - a.x, b.y - a.y}
	return c.x * c.x + c.y * c.y
}

// Make a rotation using an angle in radians
@(require_results)
MakeRot :: proc "c" (angle: f32) -> Rot {
	cs := ComputeCosSin(angle)
	return Rot{c = cs.cosine, s = cs.sine}
}

// Compute the rotation between two unit vectors
@(require_results)
ComputeRotationBetweenUnitVectors :: proc(v1, v2: Vec2) -> Rot {
	return NormalizeRot({c = lin.dot(v1, v2), s = v1.x * v2.y - v1.y * v2.x})
}

// Is this rotation normalized?
@(require_results)
IsNormalizedRot :: proc "c" (q: Rot) -> bool {
	// larger tolerance due to failure on mingw 32-bit
	qq := q.s * q.s + q.c * q.c
	return 1.0 - 0.0006 < qq && qq < 1 + 0.0006
}

// Normalize rotation
@(require_results)
NormalizeRot :: proc "c" (q: Rot) -> Rot {
	mag := math.sqrt(q.s * q.s + q.c * q.c)
	invMag := f32(mag > 0.0 ? 1.0 / mag : 0.0)
	return {q.c * invMag, q.s * invMag}
}

// Normalized linear interpolation
// https://fgiesen.wordpress.com/2012/08/15/linear-interpolation-past-present-and-future/
// https://web.archive.org/web/20170825184056/http://number-none.com/product/Understanding%20Slerp,%20Then%20Not%20Using%20It/
@(require_results)
NLerp :: proc "c" (q1: Rot, q2: Rot, t: f32) -> Rot {
	omt := 1 - t
	return NormalizeRot({omt * q1.c + t * q2.c, omt * q1.s + t * q2.s})
}

// Compute the angular velocity necessary to rotate between two rotations over a give time
//	@param q1 initial rotation
//	@param q2 final rotation
//	@param inv_h inverse time step
@(require_results)
ComputeAngularVelocity :: proc "c" (q1: Rot, q2: Rot, inv_h: f32) -> f32 {
	// ds/dt = omega * cos(t)
	// dc/dt = -omega * sin(t)
	// s2 = s1 + omega * h * c1
	// c2 = c1 - omega * h * s1

	// omega * h * s1 = c1 - c2
	// omega * h * c1 = s2 - s1
	// omega * h = (c1 - c2) * s1 + (s2 - s1) * c1
	// omega * h = s1 * c1 - c2 * s1 + s2 * c1 - s1 * c1
	// omega * h = s2 * c1 - c2 * s1 = sin(a2 - a1) ~= a2 - a1 for small delta
	omega := inv_h * (q2.s * q1.c - q2.c * q1.s)
	return omega
}

// Get the angle in radians in the range [-pi, pi]
@(require_results)
Rot_GetAngle :: proc "c" (q: Rot) -> f32 {
	return math.atan2(q.s, q.c)
}

// Get the x-axis
@(require_results)
Rot_GetXAxis :: proc "c" (q: Rot) -> Vec2 {
	return {q.c, q.s}
}

// Get the y-axis
@(require_results)
Rot_GetYAxis :: proc "c" (q: Rot) -> Vec2 {
	return {-q.s, q.c}
}

// Multiply two rotations: q * r
@(require_results)
MulRot :: proc "c" (q, r: Rot) -> (qr: Rot) {
	// [qc -qs] * [rc -rs] = [qc*rc-qs*rs -qc*rs-qs*rc]
	// [qs  qc]   [rs  rc]   [qs*rc+qc*rs -qs*rs+qc*rc]
	// s(q + r) = qs * rc + qc * rs
	// c(q + r) = qc * rc - qs * rs
	qr.s = q.s * r.c + q.c * r.s
	qr.c = q.c * r.c - q.s * r.s
	return
}

// Transpose multiply two rotations: qT * r
@(require_results)
InvMulRot :: proc "c" (q, r: Rot) -> (qr: Rot) {
	// [ qc qs] * [rc -rs] = [qc*rc+qs*rs -qc*rs+qs*rc]
	// [-qs qc]   [rs  rc]   [-qs*rc+qc*rs qs*rs+qc*rc]
	// s(q - r) = qc * rs - qs * rc
	// c(q - r) = qc * rc + qs * rs
	qr.s = q.c * r.s - q.s * r.c
	qr.c = q.c * r.c + q.s * r.s
	return
}

// relative angle between b and a (rot_b * inv(rot_a))
@(require_results)
RelativeAngle :: proc "c" (b, a: Rot) -> f32 {
	// sin(b - a) = bs * ac - bc * as
	// cos(b - a) = bc * ac + bs * as
	s := b.s * a.c - b.c * a.s
	c := b.c * a.c + b.s * a.s
	return math.atan2(s, c)
}

// Convert any angle into the range [-pi, pi]
@(require_results)
UnwindAngle :: proc "c" (radians: f32) -> f32 {
	return math.remainder(radians, 2. * PI)
}

// Rotate a vector
@(require_results)
RotateVector :: proc "c" (q: Rot, v: Vec2) -> Vec2 {
	return {q.c * v.x - q.s * v.y, q.s * v.x + q.c * v.y}
}

// Inverse rotate a vector
@(require_results)
InvRotateVector :: proc "c" (q: Rot, v: Vec2) -> Vec2 {
	return {q.c * v.x + q.s * v.y, -q.s * v.x + q.c * v.y}
}

// Transform a point (e.g. local space to world space)
@(require_results)
TransformPoint :: proc "c" (t: Transform, p: Vec2) -> Vec2 {
	x := (t.q.c * p.x - t.q.s * p.y) + t.p.x
	y := (t.q.s * p.x + t.q.c * p.y) + t.p.y
	return {x, y}
}

// Inverse transform a point (e.g. world space to local space)
@(require_results)
InvTransformPoint :: proc "c" (t: Transform, p: Vec2) -> Vec2 {
	vx := p.x - t.p.x
	vy := p.y - t.p.y
	return {t.q.c * vx + t.q.s * vy, -t.q.s * vx + t.q.c * vy}
}

// Multiply two transforms. If the result is applied to a point p local to frame B,
// the transform would first convert p to a point local to frame A, then into a point
// in the world frame.
// v2 = A.q.Rot(B.q.Rot(v1) + B.p) + A.p
//    = (A.q * B.q).Rot(v1) + A.q.Rot(B.p) + A.p
@(require_results)
MulTransforms :: proc "c" (A, B: Transform) -> (C: Transform) {
	C.q = MulRot(A.q, B.q)
	C.p = RotateVector(A.q, B.p) + A.p
	return
}

// Creates a transform that converts a local point in frame B to a local point in frame A.
// v2 = A.q' * (B.q * v1 + B.p - A.p)
//    = A.q' * B.q * v1 + A.q' * (B.p - A.p)
@(require_results)
InvMulTransforms :: proc "c" (A, B: Transform) -> (C: Transform) {
	C.q = InvMulRot(A.q, B.q)
	C.p = InvRotateVector(A.q, B.p - A.p)
	return
}

// Get the inverse of a 2-by-2 matrix
@(require_results)
GetInverse22 :: proc "c" (A: Mat22) -> Mat22 {
	a := A[0, 0]
	b := A[0, 1]
	c := A[1, 0]
	d := A[1, 1]
	det := a * d - b * c
	if det != 0.0 {
		det = 1 / det
	}

	return Mat22{det * d, -det * b, -det * c, det * a}
}

// Solve A * x = b, where b is a column vector. This is more efficient
// than computing the inverse in one-shot cases.
@(require_results)
Solve22 :: proc "c" (A: Mat22, b: Vec2) -> Vec2 {
	a11 := A[0, 0]
	a12 := A[0, 1]
	a21 := A[1, 0]
	a22 := A[1, 1]
	det := a11 * a22 - a12 * a21
	if det != 0.0 {
		det = 1 / det
	}
	return {det * (a22 * b.x - a12 * b.y), det * (a11 * b.y - a21 * b.x)}
}

// Does a fully contain b
@(require_results)
AABB_Contains :: proc "c" (a, b: AABB) -> bool {
	(a.lowerBound.x <= b.lowerBound.x) or_return
	(a.lowerBound.y <= b.lowerBound.y) or_return
	(b.upperBound.x <= a.upperBound.x) or_return
	(b.upperBound.y <= a.upperBound.y) or_return
	return true
}

// Get the center of the AABB.
@(require_results)
AABB_Center :: proc "c" (a: AABB) -> Vec2 {
	return {0.5 * (a.lowerBound.x + a.upperBound.x), 0.5 * (a.lowerBound.y + a.upperBound.y)}
}

// Get the extents of the AABB (half-widths).
@(require_results)
AABB_Extents :: proc "c" (a: AABB) -> Vec2 {
	return {0.5 * (a.upperBound.x - a.lowerBound.x), 0.5 * (a.upperBound.y - a.lowerBound.y)}
}

// Union of two AABBs
@(require_results)
AABB_Union :: proc "c" (a, b: AABB) -> (c: AABB) {
	c.lowerBound.x = min(a.lowerBound.x, b.lowerBound.x)
	c.lowerBound.y = min(a.lowerBound.y, b.lowerBound.y)
	c.upperBound.x = max(a.upperBound.x, b.upperBound.x)
	c.upperBound.y = max(a.upperBound.y, b.upperBound.y)
	return
}

// Do a and b overlap
@(require_results)
AABB_Overlaps :: proc "c" (a, b: AABB) -> bool {
	return(
		!(b.lowerBound.x > a.upperBound.x ||
			b.lowerBound.y > a.upperBound.y ||
			a.lowerBound.x > b.upperBound.x ||
			a.lowerBound.y > b.upperBound.y) \
	)
}

// Compute the bounding box of an array of circles
@(require_results)
MakeAABB :: proc "c" (points: []Vec2, radius: f32) -> AABB {
	a := AABB{points[0], points[0]}
	for point in points {
		a.lowerBound = lin.min(a.lowerBound, point)
		a.upperBound = lin.max(a.upperBound, point)
	}

	r := Vec2{radius, radius}
	a.lowerBound = a.lowerBound - r
	a.upperBound = a.upperBound + r

	return a
}

// Signed separation of a point from a plane
@(require_results)
PlaneSeparation :: proc "c" (plane: Plane, point: Vec2) -> f32 {
	return lin.dot(plane.normal, point) - plane.offset
}

@(require_results)
IsValidFloat :: proc "c" (a: f32) -> bool {
	#partial switch math.classify(a) {
	case .NaN, .Inf, .Neg_Inf:
		return false
	case:
		return true
	}
}

@(require_results)
IsValidVec2 :: proc "c" (v: Vec2) -> bool {
	IsValidFloat(v.x) or_return
	IsValidFloat(v.y) or_return
	return true
}

@(require_results)
IsValidRotation :: proc "c" (q: Rot) -> bool {
	IsValidFloat(q.s) or_return
	IsValidFloat(q.c) or_return
	return IsNormalizedRot(q)
}

// Is this a valid bounding box? Not Nan or infinity. Upper bound greater than or equal to lower bound.
@(require_results)
IsValidAABB :: proc "c" (aabb: AABB) -> bool {
	IsValidVec2(aabb.lowerBound) or_return
	IsValidVec2(aabb.upperBound) or_return
	(aabb.upperBound.x >= aabb.lowerBound.x) or_return
	(aabb.upperBound.y >= aabb.lowerBound.y) or_return
	return true
}

// Is this a valid plane? Normal is a unit vector. Not Nan or infinity.
@(require_results)
IsValidPlane :: proc "c" (plane: Plane) -> bool {
	IsValidFloat(plane.offset) or_return
	IsValidVec2(plane.normal) or_return
	IsNormalized(plane.normal) or_return
	return true
}

// One-dimensional mass-spring-damper simulation. Returns the new velocity given the position and time step.
// You can then compute the new position using:
// position += timeStep * newVelocity
// This drives towards a zero position. By using implicit integration we get a stable solution
// that doesn't require transcendental functions.
@(require_results)
b2SpringDamper :: proc "c" (hertz, dampingRatio, position, velocity, timeStep: f32) -> f32 {
	omega := 2. * PI * hertz
	omegaH := omega * timeStep
	return (velocity - omega * omegaH * position) / (1. + 2. * dampingRatio * omegaH + omegaH * omegaH)
}
