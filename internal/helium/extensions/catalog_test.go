package extensions

import "testing"

func TestCatalogIsValid(t *testing.T) {
	catalog, err := LoadCatalog()
	if err != nil {
		t.Fatal(err)
	}
	if len(catalog.ChromeStore) == 0 {
		t.Fatal("Chrome Store extensions are empty")
	}
	if len(catalog.CRX) == 0 {
		t.Fatal("CRX extensions are empty")
	}
	if len(catalog.ZIP) == 0 {
		t.Fatal("ZIP extensions are empty")
	}
}
