import type { Entries } from "type-fest";

export function entriesOf<const T extends Record<string, string>>(record: T) {
  return Object.entries(record) as Entries<T>;
}
