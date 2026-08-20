package drive

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"sort"
	"strings"
	"time"

	"golang.org/x/oauth2"
	"google.golang.org/api/drive/v3"
	"google.golang.org/api/googleapi"
	"google.golang.org/api/option"
)

// FolderMime is Drive's folder pseudo-mime type.
const FolderMime = "application/vnd.google-apps.folder"

// maxSnapshotBytes bounds a peer download. A snapshot is a JSON dump of one
// user's ledger; 64 MiB is orders of magnitude above any real one and keeps a
// corrupted or hostile file from exhausting memory.
const maxSnapshotBytes = 64 << 20

// Client is a thin, retrying wrapper over the Drive v3 file operations this
// project needs. The generated Drive client does NOT retry anything itself
// (0 of its 64 request sites use SendRequestWithRetry), so backoff is ours.
type Client struct {
	svc *drive.Service
}

// NewClient builds a Drive client from an oauth2 token source. Extra options
// are appended last (tests use option.WithEndpoint to point at a stub).
func NewClient(ctx context.Context, ts oauth2.TokenSource, opts ...option.ClientOption) (*Client, error) {
	all := append([]option.ClientOption{option.WithTokenSource(ts)}, opts...)
	svc, err := drive.NewService(ctx, all...)
	if err != nil {
		return nil, fmt.Errorf("drive service: %w", err)
	}
	return &Client{svc: svc}, nil
}

// FileInfo is the metadata subset the sync algorithm needs.
type FileInfo struct {
	ID           string
	Name         string
	ModifiedTime time.Time
	MD5          string
}

// escapeQ escapes a literal for use inside single quotes in a Drive query.
func escapeQ(s string) string {
	return strings.NewReplacer(`\`, `\\`, `'`, `\'`).Replace(s)
}

// FindFolders returns the ids of EVERY live folder named name in the Drive
// root, sorted ascending.
//
// It returns all of them rather than the first because both peers run this
// same code against the same Drive: if the app's first sync and the server's
// first sync land in the same round trip, each sees an empty result and
// creates its own folder. Surfacing the duplicates lets the caller pick one
// deterministically instead of caching whichever it happened to make and
// splitting the two peers apart forever.
func (c *Client) FindFolders(ctx context.Context, name string) ([]string, error) {
	q := fmt.Sprintf("name = '%s' and mimeType = '%s' and trashed = false and 'root' in parents",
		escapeQ(name), FolderMime)

	var ids []string
	err := withBackoff(ctx, func() error {
		ids = ids[:0]
		return c.svc.Files.List().
			Q(q).
			Spaces("drive").
			Fields("nextPageToken, files(id,name)").
			PageSize(100).
			Context(ctx).
			Pages(ctx, func(page *drive.FileList) error {
				for _, f := range page.Files {
					if f.Name == name {
						ids = append(ids, f.Id)
					}
				}
				return nil
			})
	})
	if err != nil {
		return nil, fmt.Errorf("find folder %q: %w", name, err)
	}
	sort.Strings(ids) // every peer orders the candidates identically
	return ids, nil
}

// CreateFolder creates a folder with the given name in the Drive root.
func (c *Client) CreateFolder(ctx context.Context, name string) (string, error) {
	var id string
	err := withBackoff(ctx, func() error {
		f, err := c.svc.Files.Create(&drive.File{
			Name:     name,
			MimeType: FolderMime,
			Parents:  []string{"root"},
		}).Fields("id").Context(ctx).Do()
		if err != nil {
			return err
		}
		id = f.Id
		return nil
	})
	if err != nil {
		return "", fmt.Errorf("create folder %q: %w", name, err)
	}
	return id, nil
}

// FolderExists reports whether folderID still resolves to a live folder. A
// cached id can go stale if the user deletes or trashes the folder.
func (c *Client) FolderExists(ctx context.Context, folderID string) (bool, error) {
	var ok bool
	err := withBackoff(ctx, func() error {
		f, err := c.svc.Files.Get(folderID).Fields("id,mimeType,trashed").Context(ctx).Do()
		if err != nil {
			if IsNotFound(err) {
				ok = false
				return nil
			}
			return err
		}
		ok = f.MimeType == FolderMime && !f.Trashed
		return nil
	})
	return ok, err
}

// ListSnapshots lists every tally-*.json in the folder, asking for exactly
// the fields the sync algorithm needs.
func (c *Client) ListSnapshots(ctx context.Context, folderID string) ([]FileInfo, error) {
	q := fmt.Sprintf("'%s' in parents and name contains '%s' and trashed = false",
		escapeQ(folderID), escapeQ(FilePrefix))

	var out []FileInfo
	err := withBackoff(ctx, func() error {
		out = out[:0]
		return c.svc.Files.List().
			Q(q).
			Spaces("drive").
			Fields("nextPageToken, files(id,name,modifiedTime,md5Checksum)").
			PageSize(100).
			Context(ctx).
			Pages(ctx, func(page *drive.FileList) error {
				for _, f := range page.Files {
					// Drive's `contains` is a substring match, not a prefix
					// one, and it ignores the suffix entirely — re-check both.
					if _, ok := DeviceIDFromFileName(f.Name); !ok {
						continue
					}
					mt, _ := time.Parse(time.RFC3339, f.ModifiedTime)
					out = append(out, FileInfo{ID: f.Id, Name: f.Name, ModifiedTime: mt, MD5: f.Md5Checksum})
				}
				return nil
			})
	})
	if err != nil {
		return nil, fmt.Errorf("list snapshots: %w", err)
	}
	return out, nil
}

// Download fetches a file's content by id.
func (c *Client) Download(ctx context.Context, fileID string) ([]byte, error) {
	var body []byte
	err := withBackoff(ctx, func() error {
		// Download() sets alt=media and runs googleapi.CheckResponse for us.
		// Never set Accept-Encoding here: gensupport rejects it, and net/http
		// already negotiates and transparently gunzips.
		resp, err := c.svc.Files.Get(fileID).Context(ctx).Download()
		if err != nil {
			return err
		}
		defer resp.Body.Close()
		b, err := io.ReadAll(io.LimitReader(resp.Body, maxSnapshotBytes))
		if err != nil {
			return err
		}
		body = b
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("download %s: %w", fileID, err)
	}
	return body, nil
}

// Create uploads a new JSON file into the folder and returns its metadata.
func (c *Client) Create(ctx context.Context, folderID, name string, content []byte) (FileInfo, error) {
	var info FileInfo
	err := withBackoff(ctx, func() error {
		f, err := c.svc.Files.Create(&drive.File{
			Name:     name,
			Parents:  []string{folderID},
			MimeType: FileMime,
		}).
			Media(bytes.NewReader(content), googleapi.ContentType(FileMime)).
			Fields("id,name,modifiedTime,md5Checksum").
			Context(ctx).Do()
		if err != nil {
			return err
		}
		info = fileInfo(f)
		return nil
	})
	if err != nil {
		return info, fmt.Errorf("create %s: %w", name, err)
	}
	return info, nil
}

// Update replaces a file's content by id.
//
// Parents must NOT be set on an update — Drive rejects it; moving a file uses
// AddParents/RemoveParents instead.
func (c *Client) Update(ctx context.Context, fileID string, content []byte) (FileInfo, error) {
	var info FileInfo
	err := withBackoff(ctx, func() error {
		f, err := c.svc.Files.Update(fileID, &drive.File{}).
			Media(bytes.NewReader(content), googleapi.ContentType(FileMime)).
			Fields("id,name,modifiedTime,md5Checksum").
			Context(ctx).Do()
		if err != nil {
			return err
		}
		info = fileInfo(f)
		return nil
	})
	if err != nil {
		return info, fmt.Errorf("update %s: %w", fileID, err)
	}
	return info, nil
}

func fileInfo(f *drive.File) FileInfo {
	mt, _ := time.Parse(time.RFC3339, f.ModifiedTime)
	return FileInfo{ID: f.Id, Name: f.Name, ModifiedTime: mt, MD5: f.Md5Checksum}
}
