/** Thousands-grouped IQD price, e.g. 12000 → "12,000 د.ع" (matches the rider/
 * driver apps' `formatPrice` convention: Western digit grouping, Arabic dinar
 * suffix). */
export function formatPrice(amount: number): string {
  return `${amount.toLocaleString("en-US")} د.ع`;
}
