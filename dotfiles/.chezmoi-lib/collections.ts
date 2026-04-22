type Entries<T extends Record<string, string>> = ReadonlyArray<
  {
    [K in keyof T]: readonly [K, T[K]];
  }[keyof T]
>;

export function entriesOf<const T extends Record<string, string>>(record: T) {
  return Object.entries(record) as unknown as Entries<T>;
}
