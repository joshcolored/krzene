export type CatalogLocale = {
  code: string;
  label: string;
  country: string;
  countryCode: string;
  originalLanguage: string;
  tmdbLanguage: string;
};

export const CATALOG_LOCALES: CatalogLocale[] = [
  { code: "en-US", label: "English", country: "United States", countryCode: "US", originalLanguage: "en", tmdbLanguage: "en-US" },
  { code: "tl-PH", label: "Filipino", country: "the Philippines", countryCode: "PH", originalLanguage: "tl", tmdbLanguage: "tl-PH" },
  { code: "ja-JP", label: "Japanese", country: "Japan", countryCode: "JP", originalLanguage: "ja", tmdbLanguage: "ja-JP" },
  { code: "ko-KR", label: "Korean", country: "South Korea", countryCode: "KR", originalLanguage: "ko", tmdbLanguage: "ko-KR" },
  { code: "es-ES", label: "Spanish", country: "Spain", countryCode: "ES", originalLanguage: "es", tmdbLanguage: "es-ES" },
  { code: "fr-FR", label: "French", country: "France", countryCode: "FR", originalLanguage: "fr", tmdbLanguage: "fr-FR" },
  { code: "de-DE", label: "German", country: "Germany", countryCode: "DE", originalLanguage: "de", tmdbLanguage: "de-DE" },
  { code: "hi-IN", label: "Hindi", country: "India", countryCode: "IN", originalLanguage: "hi", tmdbLanguage: "hi-IN" },
  { code: "zh-CN", label: "Chinese", country: "China", countryCode: "CN", originalLanguage: "zh", tmdbLanguage: "zh-CN" },
];

export const DEFAULT_CATALOG_LOCALE = CATALOG_LOCALES[0];

export function catalogLocale(code?: string | null): CatalogLocale {
  return CATALOG_LOCALES.find((locale) => locale.code === code) ?? DEFAULT_CATALOG_LOCALE;
}
