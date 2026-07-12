import catalog from '../assets/species/species.json';

export type GirthFamily =
  | 'bass'
  | 'panfish'
  | 'percid'
  | 'esocid'
  | 'salmonid'
  | 'catfish'
  | 'carp'
  | 'primitive'
  | 'other';

export type StandardWeightFormula = {
  a: number;
  b: number;
  inputLengthUnit: 'mm';
  outputWeightUnit: 'g';
  lengthType: 'total';
  minimumLengthMm: number;
  citation: string;
};

export type Species = {
  id: string;
  common: string;
  scientific: string;
  aliases: string[];
  ws: StandardWeightFormula | null;
  wsSource: string | null;
  girthFamily: GirthFamily;
  lengthRangeCm: [number, number];
};

export const speciesCatalog = catalog.species as Species[];
export const speciesById = new Map(speciesCatalog.map((species) => [species.id, species]));

export function searchSpecies(query: string) {
  const normalized = query.trim().toLowerCase();
  if (!normalized) return speciesCatalog;
  return speciesCatalog.filter((species) =>
    [species.common, species.scientific, ...species.aliases]
      .some((value) => value.toLowerCase().includes(normalized))
  );
}

export function compactSpeciesCatalogForPrompt() {
  return speciesCatalog
    .filter((species) => species.id !== 'other')
    .map(({ id, common, scientific, aliases }) => ({ id, common, scientific, aliases }));
}
