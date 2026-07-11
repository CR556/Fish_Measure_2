export type Unit = 'm' | 'cm' | 'ft' | 'in';

export const UNITS: Unit[] = ['m', 'cm', 'ft', 'in'];

export function nextUnit(unit: Unit): Unit {
  return UNITS[(UNITS.indexOf(unit) + 1) % UNITS.length];
}

export function formatDistance(meters: number, unit: Unit): string {
  switch (unit) {
    case 'm':
      return `${meters.toFixed(2)} m`;
    case 'cm':
      return `${(meters * 100).toFixed(1)} cm`;
    case 'in':
      return `${(meters * 39.3701).toFixed(1)} in`;
    case 'ft': {
      const totalInches = meters * 39.3701;
      const feet = Math.floor(totalInches / 12);
      const inches = totalInches - feet * 12;
      return `${feet}′ ${inches.toFixed(1)}″`;
    }
  }
}
