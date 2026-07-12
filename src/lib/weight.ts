import type { Species, StandardWeightFormula } from './species';

const GRAMS_PER_KILOGRAM = 1000;

export type WeightEstimate = {
  kg: number;
  source: 'standard-weight' | 'girth';
  formulaLabel: string;
  citation: string;
};

export function standardWeightKg(lengthM: number, formula: StandardWeightFormula) {
  const lengthMm = lengthM * 1000;
  if (!Number.isFinite(lengthMm) || lengthMm < formula.minimumLengthMm) return null;
  const grams = 10 ** (formula.a + formula.b * Math.log10(lengthMm));
  return Number.isFinite(grams) && grams > 0 ? grams / GRAMS_PER_KILOGRAM : null;
}

export function estimateSpeciesWeight(species: Species, lengthM: number): WeightEstimate | null {
  if (!species.ws) return null;
  const kg = standardWeightKg(lengthM, species.ws);
  return kg == null
    ? null
    : {
        kg,
        source: 'standard-weight',
        formulaLabel: 'Standard weight from total length',
        citation: species.ws.citation,
      };
}

export function estimateGirthWeight(
  lengthM: number,
  girthM: number,
  divisor: number,
  citation: string
): WeightEstimate | null {
  const lengthInches = lengthM * 39.3700787402;
  const girthInches = girthM * 39.3700787402;
  if (![lengthInches, girthInches, divisor].every(Number.isFinite) || divisor <= 0) return null;
  const pounds = (lengthInches * girthInches * girthInches) / divisor;
  return pounds > 0
    ? {
        kg: pounds * 0.45359237,
        source: 'girth',
        formulaLabel: `L×G²/${divisor}`,
        citation,
      }
    : null;
}
