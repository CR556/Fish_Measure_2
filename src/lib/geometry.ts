import type { Unit } from './units';

export type Vec3 = { x: number; y: number; z: number };

export function dist3(a: Vec3, b: Vec3): number {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  const dz = a.z - b.z;
  return Math.sqrt(dx * dx + dy * dy + dz * dz);
}

/** Sum of consecutive segment lengths; adds the closing segment when closed. */
export function perimeter(points: Vec3[], closed: boolean): number {
  let total = 0;
  for (let i = 1; i < points.length; i++) {
    total += dist3(points[i - 1], points[i]);
  }
  if (closed && points.length >= 3) {
    total += dist3(points[points.length - 1], points[0]);
  }
  return total;
}

/**
 * Area of a 3D polygon via Newell's method: half the magnitude of the summed
 * cross products. Exact for planar polygons (e.g. points on a floor); for
 * slightly non-planar points it's the area on the best-fit plane.
 */
export function polygonArea(points: Vec3[]): number {
  if (points.length < 3) return 0;
  let nx = 0;
  let ny = 0;
  let nz = 0;
  for (let i = 0; i < points.length; i++) {
    const a = points[i];
    const b = points[(i + 1) % points.length];
    nx += (a.y - b.y) * (a.z + b.z);
    ny += (a.z - b.z) * (a.x + b.x);
    nz += (a.x - b.x) * (a.y + b.y);
  }
  return Math.sqrt(nx * nx + ny * ny + nz * nz) / 2;
}

export function formatArea(squareMeters: number, unit: Unit): string {
  switch (unit) {
    case 'm':
      return `${squareMeters.toFixed(2)} m²`;
    case 'cm':
      return `${(squareMeters * 10_000).toFixed(0)} cm²`;
    case 'ft':
      return `${(squareMeters * 10.7639).toFixed(2)} ft²`;
    case 'in':
      return `${(squareMeters * 1550.0031).toFixed(0)} in²`;
  }
}
