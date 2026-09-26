class_name SkyClock
extends RefCounted
## Where the sky stands at a clock hour: the stars, the sun's place among
## them and the moon's, for one night of the year at the latitude of
## Maine. The worlds' clock is local solar time and does not run through
## the days, so the date is fixed: late October, the town's season.
##
## The celestial frame: y the north celestial pole, x toward right
## ascension zero, -z toward six hours, so a star is
## (cos dec cos ra, sin dec, -cos dec sin ra). The world: y up, -z north,
## +x east. A star's hour angle is the local sidereal time less its right
## ascension; sidereal time is solar time plus the sun's right ascension
## less twelve hours.

const LATITUDE := 44.0
const DAY_OF_YEAR := 301.0         # 28 October
const OBLIQUITY := 23.44
## The moon's age at six in the evening, days after new: a crescent low
## in the west-south-west at dusk, set by nine, the rest of the night dark.
const MOON_AGE := 4.5
const SYNODIC := 29.53


## A direction in the celestial frame.
static func celestial(ra: float, dec: float) -> Vector3:
	return Vector3(cos(dec) * cos(ra), sin(dec), -cos(dec) * sin(ra))


## The sun's ecliptic longitude on the day, in radians.
static func sun_longitude() -> float:
	var n := DAY_OF_YEAR - 1.5
	var mean := deg_to_rad(280.46 + 0.9856474 * n)
	var g := deg_to_rad(357.528 + 0.9856003 * n)
	return fposmod(mean + deg_to_rad(1.915) * sin(g) + deg_to_rad(0.02) * sin(2.0 * g), TAU)


## A point of the ecliptic, in the celestial frame.
static func ecliptic(longitude: float) -> Vector3:
	var e := deg_to_rad(OBLIQUITY)
	var ra := atan2(cos(e) * sin(longitude), cos(longitude))
	var dec := asin(sin(e) * sin(longitude))
	return celestial(ra, dec)


static func sun_celestial() -> Vector3:
	return ecliptic(sun_longitude())


## The moon at an hour: its age grows through the night, carrying it
## east along the ecliptic about half a degree an hour.
static func moon_celestial(hours: float) -> Vector3:
	return ecliptic(sun_longitude() + TAU * moon_age(hours) / SYNODIC)


static func moon_age(hours: float) -> float:
	return MOON_AGE + (hours - 18.0) / 24.0


## The share of the moon's face in sunlight.
static func moon_lit(hours: float) -> float:
	return (1.0 - cos(TAU * moon_age(hours) / SYNODIC)) / 2.0


## Local sidereal time at a solar hour, in hours.
static func sidereal(hours: float) -> float:
	var s := sun_celestial()
	var ra_h := fposmod(atan2(-s.z, s.x), TAU) / TAU * 24.0
	return hours + ra_h - 12.0


## Celestial to world at a solar hour.
static func to_world(hours: float) -> Basis:
	var lat := deg_to_rad(LATITUDE)
	var meridian := Vector3(0.0, cos(lat), sin(lat))    # the equator due south
	var west := Vector3(-1.0, 0.0, 0.0)
	var pole := Vector3(0.0, sin(lat), -cos(lat))
	var t := deg_to_rad(sidereal(hours) * 15.0)
	return Basis(cos(t) * meridian + sin(t) * west, pole, -sin(t) * meridian + cos(t) * west)


## The moon's direction in the world at an hour.
static func moon_world(hours: float) -> Vector3:
	return (to_world(hours) * moon_celestial(hours)).normalized()


## The sun's direction in the world as the stars have it (for the moon's
## lit side; the day's light keeps its own path).
static func sun_world(hours: float) -> Vector3:
	return (to_world(hours) * sun_celestial()).normalized()


## North on the moon's face as seen: the celestial pole's direction
## across the line of sight.
static func moon_up(hours: float) -> Vector3:
	var m := moon_world(hours)
	var p := to_world(hours) * Vector3.UP
	return (p - m * p.dot(m)).normalized()
