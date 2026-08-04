/**
 * Machine-readable error codes returned in the 400 body alongside the Arabic
 * `message`.
 *
 * The apps show `message` verbatim, so it must always be a complete Arabic
 * sentence on its own. A client that ALSO knows the code can do better — the
 * driver app re-renders the range in Arabic-Indic numerals, which the API
 * (Western digits on the wire, by convention) can't produce.
 */
export const TRIP_PRICE_OUT_OF_RANGE = 'TRIP_PRICE_OUT_OF_RANGE';
