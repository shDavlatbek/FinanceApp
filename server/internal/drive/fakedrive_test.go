package drive

import (
	"context"
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"io"
	"mime"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"golang.org/x/oauth2"
	"google.golang.org/api/option"
)

// fakeDrive is an in-memory stand-in for the Drive v3 JSON API covering the
// handful of operations the sync engine performs. It exists so the whole
// eight-step algorithm can be exercised end to end without credentials.
type fakeDrive struct {
	srv *httptest.Server

	mu     sync.Mutex
	files  map[string]*fakeFile
	nextID int

	listCalls, downloadCalls, createCalls, updateCalls, folderCreates int

	// failNext, when non-nil, is consulted before every request; a non-zero
	// status short-circuits with that error body.
	failNext func(*http.Request) (int, string)
}

type fakeFile struct {
	id, name, mimeType string
	parents            []string
	content            []byte
	modified           time.Time
	trashed            bool
}

func (f *fakeFile) md5() string {
	if f.mimeType == FolderMime {
		return ""
	}
	sum := md5.Sum(f.content)
	return hex.EncodeToString(sum[:])
}

func (f *fakeFile) meta() map[string]any {
	return map[string]any{
		"id":           f.id,
		"name":         f.name,
		"mimeType":     f.mimeType,
		"trashed":      f.trashed,
		"modifiedTime": f.modified.UTC().Format(time.RFC3339),
		"md5Checksum":  f.md5(),
	}
}

func newFakeDrive(t *testing.T) *fakeDrive {
	t.Helper()
	d := &fakeDrive{files: map[string]*fakeFile{}}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /drive/v3/files", d.handleList)
	mux.HandleFunc("POST /drive/v3/files", d.handleCreateMetadata)
	mux.HandleFunc("POST /upload/drive/v3/files", d.handleUploadCreate)
	mux.HandleFunc("PATCH /upload/drive/v3/files/{fileId}", d.handleUploadUpdate)
	mux.HandleFunc("GET /drive/v3/files/{fileId}", d.handleGet)
	d.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		d.mu.Lock()
		fail := d.failNext
		d.mu.Unlock()
		if fail != nil {
			if code, body := fail(r); code != 0 {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(code)
				io.WriteString(w, body)
				return
			}
		}
		mux.ServeHTTP(w, r)
	}))
	t.Cleanup(d.srv.Close)
	return d
}

func (d *fakeDrive) client(ctx context.Context, t *testing.T) *Client {
	t.Helper()
	c, err := NewClient(ctx, oauth2.StaticTokenSource(&oauth2.Token{AccessToken: "test", TokenType: "Bearer"}),
		option.WithEndpoint(d.srv.URL+"/drive/v3/"))
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}
	return c
}

func (d *fakeDrive) newID(prefix string) string {
	d.nextID++
	return prefix + strconv.Itoa(d.nextID)
}

// --- query parsing -------------------------------------------------------

var (
	qName     = regexp.MustCompile(`name = '([^']*)'`)
	qMime     = regexp.MustCompile(`mimeType = '([^']*)'`)
	qParent   = regexp.MustCompile(`'([^']*)' in parents`)
	qContains = regexp.MustCompile(`name contains '([^']*)'`)
)

func first(re *regexp.Regexp, s string) (string, bool) {
	m := re.FindStringSubmatch(s)
	if m == nil {
		return "", false
	}
	return m[1], true
}

func (d *fakeDrive) handleList(w http.ResponseWriter, r *http.Request) {
	d.mu.Lock()
	d.listCalls++
	q := r.URL.Query().Get("q")
	var out []map[string]any
	for _, f := range d.files {
		if f.trashed {
			continue
		}
		if name, ok := first(qName, q); ok && f.name != name {
			continue
		}
		if mt, ok := first(qMime, q); ok && f.mimeType != mt {
			continue
		}
		if p, ok := first(qParent, q); ok && !contains(f.parents, p) {
			continue
		}
		// Drive's `contains` is a substring match; mirror that so the client's
		// own re-filtering is what actually enforces the tally-*.json shape.
		if sub, ok := first(qContains, q); ok && !strings.Contains(f.name, sub) {
			continue
		}
		out = append(out, f.meta())
	}
	d.mu.Unlock()
	writeJSON(w, http.StatusOK, map[string]any{"files": out})
}

func contains(ss []string, v string) bool {
	for _, s := range ss {
		if s == v {
			return true
		}
	}
	return false
}

func (d *fakeDrive) handleCreateMetadata(w http.ResponseWriter, r *http.Request) {
	var meta struct {
		Name     string   `json:"name"`
		MimeType string   `json:"mimeType"`
		Parents  []string `json:"parents"`
	}
	if err := json.NewDecoder(r.Body).Decode(&meta); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": map[string]any{"code": 400, "message": err.Error()}})
		return
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	if meta.MimeType == FolderMime {
		d.folderCreates++
	}
	f := &fakeFile{
		id: d.newID("file-"), name: meta.Name, mimeType: meta.MimeType,
		parents: meta.Parents, modified: time.Now().UTC(),
	}
	d.files[f.id] = f
	writeJSON(w, http.StatusOK, f.meta())
}

// mediaBody extracts the metadata JSON and the media bytes from an upload.
// The generated client sends multipart/related for a metadata+media upload.
func mediaBody(r *http.Request) (meta []byte, media []byte, err error) {
	ct := r.Header.Get("Content-Type")
	mt, params, perr := mime.ParseMediaType(ct)
	if perr != nil {
		return nil, nil, perr
	}
	if !strings.HasPrefix(mt, "multipart/") {
		b, err := io.ReadAll(r.Body)
		return nil, b, err
	}
	mr := multipart.NewReader(r.Body, params["boundary"])
	for i := 0; ; i++ {
		p, err := mr.NextPart()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, nil, err
		}
		b, err := io.ReadAll(p)
		if err != nil {
			return nil, nil, err
		}
		if i == 0 {
			meta = b
		} else {
			media = b
		}
	}
	return meta, media, nil
}

func (d *fakeDrive) handleUploadCreate(w http.ResponseWriter, r *http.Request) {
	metaRaw, media, err := mediaBody(r)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": map[string]any{"code": 400, "message": err.Error()}})
		return
	}
	var meta struct {
		Name     string   `json:"name"`
		MimeType string   `json:"mimeType"`
		Parents  []string `json:"parents"`
	}
	_ = json.Unmarshal(metaRaw, &meta)

	d.mu.Lock()
	defer d.mu.Unlock()
	d.createCalls++
	f := &fakeFile{
		id: d.newID("file-"), name: meta.Name, mimeType: meta.MimeType,
		parents: meta.Parents, content: media, modified: time.Now().UTC(),
	}
	d.files[f.id] = f
	writeJSON(w, http.StatusOK, f.meta())
}

func (d *fakeDrive) handleUploadUpdate(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("fileId")
	metaRaw, media, err := mediaBody(r)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": map[string]any{"code": 400, "message": err.Error()}})
		return
	}
	// Drive rejects `parents` on an update; make sure we never send it.
	var meta map[string]any
	_ = json.Unmarshal(metaRaw, &meta)
	if _, bad := meta["parents"]; bad {
		writeJSON(w, http.StatusBadRequest, map[string]any{
			"error": map[string]any{"code": 400, "message": "The parents field is not directly writable in update requests."}})
		return
	}

	d.mu.Lock()
	defer d.mu.Unlock()
	d.updateCalls++
	f, ok := d.files[id]
	if !ok {
		writeJSON(w, http.StatusNotFound, map[string]any{"error": map[string]any{"code": 404, "message": "File not found: " + id}})
		return
	}
	f.content = media
	f.modified = time.Now().UTC()
	writeJSON(w, http.StatusOK, f.meta())
}

func (d *fakeDrive) handleGet(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("fileId")
	d.mu.Lock()
	f, ok := d.files[id]
	if ok && r.URL.Query().Get("alt") == "media" {
		d.downloadCalls++
	}
	d.mu.Unlock()
	if !ok {
		writeJSON(w, http.StatusNotFound, map[string]any{"error": map[string]any{"code": 404, "message": "File not found: " + id}})
		return
	}
	if r.URL.Query().Get("alt") == "media" {
		w.Header().Set("Content-Type", f.mimeType)
		w.Write(f.content)
		return
	}
	writeJSON(w, http.StatusOK, f.meta())
}

// --- helpers used by the engine test -------------------------------------

func (d *fakeDrive) put(name string, parents []string, content []byte) string {
	d.mu.Lock()
	defer d.mu.Unlock()
	for _, f := range d.files {
		if f.name == name {
			f.content = content
			f.modified = time.Now().UTC()
			return f.id
		}
	}
	f := &fakeFile{id: d.newID("peer-"), name: name, mimeType: FileMime,
		parents: parents, content: content, modified: time.Now().UTC()}
	d.files[f.id] = f
	return f.id
}

// putFolder drops a pre-existing folder into the Drive root, as if the other
// peer had created it.
func (d *fakeDrive) putFolder(name string) string {
	d.mu.Lock()
	defer d.mu.Unlock()
	f := &fakeFile{id: d.newID("folder-"), name: name, mimeType: FolderMime,
		parents: []string{"root"}, modified: time.Now().UTC()}
	d.files[f.id] = f
	return f.id
}

// putFolderWithID is putFolder with a caller-chosen id, so a test can pin the
// sort order two peers would both compute.
func (d *fakeDrive) putFolderWithID(id, name string) string {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.files[id] = &fakeFile{id: id, name: name, mimeType: FolderMime,
		parents: []string{"root"}, modified: time.Now().UTC()}
	return id
}

func (d *fakeDrive) byName(name string) *fakeFile {
	d.mu.Lock()
	defer d.mu.Unlock()
	for _, f := range d.files {
		if f.name == name {
			return f
		}
	}
	return nil
}

func (d *fakeDrive) counters() (list, download, create, update, folders int) {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.listCalls, d.downloadCalls, d.createCalls, d.updateCalls, d.folderCreates
}
