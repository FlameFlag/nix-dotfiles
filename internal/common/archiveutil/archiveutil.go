package archiveutil

import (
	"archive/tar"
	"archive/zip"
	"compress/gzip"
	"context"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"strings"

	"github.com/ulikunitz/xz"
)

func ExtractZipFile(ctx context.Context, zipPath, dst string) error {
	reader, err := zip.OpenReader(zipPath)
	if err != nil {
		return err
	}
	defer reader.Close()

	if err := os.MkdirAll(dst, 0o755); err != nil {
		return err
	}
	root, err := os.OpenRoot(dst)
	if err != nil {
		return err
	}
	defer root.Close()
	for _, file := range reader.File {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
		source, err := file.Open()
		if err != nil {
			return err
		}
		err = extractEntry(root, file.Name, file.Mode(), source)
		if closeErr := source.Close(); err == nil {
			err = closeErr
		}
		if err != nil {
			return err
		}
	}
	return nil
}

func ExtractTarGz(ctx context.Context, source io.Reader, dst string) error {
	gzipReader, err := gzip.NewReader(source)
	if err != nil {
		return err
	}
	defer gzipReader.Close()

	return extractTar(ctx, gzipReader, dst)
}

func ExtractTarXz(ctx context.Context, source io.Reader, dst string) error {
	xzReader, err := xz.NewReader(source)
	if err != nil {
		return err
	}
	return extractTar(ctx, xzReader, dst)
}

func extractTar(ctx context.Context, source io.Reader, dst string) error {
	if err := os.MkdirAll(dst, 0o755); err != nil {
		return err
	}
	root, err := os.OpenRoot(dst)
	if err != nil {
		return err
	}
	defer root.Close()
	tarReader := tar.NewReader(source)
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
		header, err := tarReader.Next()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		if header.Typeflag != tar.TypeReg && header.Typeflag != tar.TypeDir {
			continue
		}
		if err := extractEntry(root, header.Name, header.FileInfo().Mode(), tarReader); err != nil {
			return err
		}
	}
}

func extractEntry(root *os.Root, name string, mode fs.FileMode, source io.Reader) error {
	target, err := safeLocalPath(name)
	if err != nil {
		return err
	}
	if target == "" {
		return nil
	}
	if mode.IsDir() {
		return root.MkdirAll(target, permOrDefault(mode, 0o755))
	}
	if !mode.IsRegular() {
		return nil
	}
	if err := root.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		return err
	}
	destination, err := root.OpenFile(
		target,
		os.O_WRONLY|os.O_CREATE|os.O_TRUNC,
		permOrDefault(mode, 0o644),
	)
	if err != nil {
		return err
	}
	_, copyErr := io.Copy(destination, source)
	closeErr := destination.Close()
	if copyErr != nil {
		return copyErr
	}
	return closeErr
}

func safeLocalPath(name string) (string, error) {
	clean := path.Clean(strings.ReplaceAll(name, "\\", "/"))
	if clean == "." {
		return "", nil
	}
	if path.IsAbs(clean) {
		return "", fmt.Errorf("archive entry escapes destination: %s", name)
	}
	candidate, err := filepath.Localize(clean)
	if err != nil || !filepath.IsLocal(candidate) {
		return "", fmt.Errorf("archive entry escapes destination: %s", name)
	}
	return candidate, nil
}

func safeTarget(dst, name string) (string, error) {
	candidate, err := safeLocalPath(name)
	if err != nil || candidate == "" {
		return candidate, err
	}
	return filepath.Join(dst, candidate), nil
}

func permOrDefault(mode fs.FileMode, fallback fs.FileMode) fs.FileMode {
	if perm := mode.Perm(); perm != 0 {
		return perm
	}
	return fallback
}
