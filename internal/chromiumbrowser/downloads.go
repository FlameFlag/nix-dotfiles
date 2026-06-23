package chromiumbrowser

import (
	"fmt"
	"net/http"
	"time"

	"github.com/FlameFlag/nix-dotfiles/internal/common/httpx"
)

func downloadFile(path, url string) error {
	return (&httpx.Client{HTTP: httpx.RetryableClient(30 * time.Second)}).DownloadFile(url, path)
}

func resolveDownloadURL(rawURL string) (string, error) {
	client := httpx.RetryableClient(30 * time.Second)
	req, err := http.NewRequest(http.MethodHead, rawURL, nil)
	if err != nil {
		return "", err
	}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return "", fmt.Errorf("HEAD %s: %s", rawURL, resp.Status)
	}
	return resp.Request.URL.String(), nil
}
