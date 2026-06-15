package httpx

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/google/renameio/v2"
	"github.com/hashicorp/go-retryablehttp"
)

var defaultRetryableClient = sync.OnceValue(func() *http.Client {
	return RetryableClient(0)
})

type Client struct {
	HTTP      *http.Client
	UserAgent string
}

type TextResponse struct {
	Status int
	Body   string
}

func (c *Client) GetBearerText(url, token string) (TextResponse, error) {
	req, err := c.request(http.MethodGet, url, nil)
	if err != nil {
		return TextResponse{}, err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	return c.text(req)
}

func (c *Client) PostJSONBearerText(url, token string, body any) (TextResponse, error) {
	payload, err := json.Marshal(body)
	if err != nil {
		return TextResponse{}, err
	}
	req, err := c.request(http.MethodPost, url, bytes.NewReader(payload))
	if err != nil {
		return TextResponse{}, err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	return c.text(req)
}

func (c *Client) Reader(url string) (io.ReadCloser, error) {
	resp, err := c.get(url)
	if err != nil {
		return nil, err
	}
	return resp.Body, nil
}

func (c *Client) Bytes(url string) ([]byte, error) {
	resp, err := c.get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	return io.ReadAll(resp.Body)
}

func (c *Client) Text(url string) (string, error) {
	body, err := c.Bytes(url)
	if err != nil {
		return "", err
	}
	return string(body), nil
}

func (c *Client) JSON(url string, out any) error {
	resp, err := c.get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	return json.NewDecoder(resp.Body).Decode(out)
}

func (c *Client) DownloadFile(url, path string) error {
	resp, err := c.get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	file, err := renameio.NewPendingFile(path, renameio.WithPermissions(0o644))
	if err != nil {
		return err
	}
	defer file.Cleanup()
	_, copyErr := io.Copy(file, resp.Body)
	if copyErr != nil {
		return copyErr
	}
	return file.CloseAtomicallyReplace()
}

func (c *Client) get(url string) (*http.Response, error) {
	req, err := c.request(http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	client := c.HTTP
	if client == nil {
		client = defaultRetryableClient()
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		defer resp.Body.Close()
		return nil, fmt.Errorf("GET %s: %s", url, resp.Status)
	}
	return resp, nil
}

func (c *Client) text(req *http.Request) (TextResponse, error) {
	client := c.HTTP
	if client == nil {
		client = defaultRetryableClient()
	}
	resp, err := client.Do(req)
	if err != nil {
		return TextResponse{}, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return TextResponse{}, err
	}
	return TextResponse{Status: resp.StatusCode, Body: string(body)}, nil
}

func RetryableClient(timeout time.Duration) *http.Client {
	retryClient := retryablehttp.NewClient()
	retryClient.Logger = nil
	retryClient.RetryMax = 3
	retryClient.HTTPClient = &http.Client{Timeout: timeout}
	return retryClient.StandardClient()
}

func (c *Client) request(method, url string, body io.Reader) (*http.Request, error) {
	req, err := http.NewRequest(method, url, body)
	if err != nil {
		return nil, err
	}
	if c.UserAgent != "" {
		req.Header.Set("User-Agent", c.UserAgent)
	}
	return req, nil
}
