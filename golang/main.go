package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"time"
)

const clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

type credentials struct {
	AccessToken  string `json:"accessToken"`
	RefreshToken string `json:"refreshToken"`
	ExpiresAtMs  int64  `json:"expiresAt"`
}

func (c credentials) expired() bool {
	return c.ExpiresAtMs > 0 && time.Now().UnixMilli() >= c.ExpiresAtMs-300_000
}

type credentialStore struct {
	kind     string
	filePath string
	service  string
}

func stores() []credentialStore {
	var out []credentialStore
	if runtime.GOOS == "darwin" {
		out = append(out, credentialStore{kind: "keychain", service: "Claude Code-credentials"})
	}
	home, _ := os.UserHomeDir()
	if home != "" {
		out = append(out,
			credentialStore{kind: "file", filePath: filepath.Join(home, ".claude", ".credentials.json")},
			credentialStore{kind: "file", filePath: filepath.Join(home, ".claude.json")},
		)
	}
	return out
}

func (s credentialStore) read() (credentials, []byte, bool) {
	var raw []byte
	switch s.kind {
	case "keychain":
		b, err := exec.Command("security", "find-generic-password", "-s", s.service, "-w").Output()
		if err != nil {
			return credentials{}, nil, false
		}
		raw = bytes.TrimSpace(b)
	case "file":
		b, err := os.ReadFile(s.filePath)
		if err != nil {
			return credentials{}, nil, false
		}
		raw = b
	}
	var wrapper struct {
		ClaudeAiOauth credentials `json:"claudeAiOauth"`
		AccessToken   string      `json:"accessToken"`
		RefreshToken  string      `json:"refreshToken"`
		ExpiresAt     int64       `json:"expiresAt"`
	}
	if json.Unmarshal(raw, &wrapper) != nil {
		return credentials{}, nil, false
	}
	c := wrapper.ClaudeAiOauth
	if c.AccessToken == "" {
		c = credentials{wrapper.AccessToken, wrapper.RefreshToken, wrapper.ExpiresAt}
	}
	if c.AccessToken == "" {
		return credentials{}, nil, false
	}
	return c, raw, true
}

func (s credentialStore) write(c credentials, oldRaw []byte) error {
	var root any
	if json.Unmarshal(oldRaw, &root) == nil {
		if m, ok := root.(map[string]any); ok {
			if _, ok := m["claudeAiOauth"]; ok {
				m["claudeAiOauth"] = map[string]any{
					"accessToken": c.AccessToken, "refreshToken": c.RefreshToken, "expiresAt": c.ExpiresAtMs,
				}
				out, _ := json.MarshalIndent(m, "", "  ")
				return s.put(out)
			}
			m["accessToken"] = c.AccessToken
			m["refreshToken"] = c.RefreshToken
			m["expiresAt"] = c.ExpiresAtMs
			out, _ := json.MarshalIndent(m, "", "  ")
			return s.put(out)
		}
	}
	out, _ := json.MarshalIndent(map[string]any{
		"accessToken": c.AccessToken, "refreshToken": c.RefreshToken, "expiresAt": c.ExpiresAtMs,
	}, "", "  ")
	return s.put(out)
}

func (s credentialStore) put(data []byte) error {
	switch s.kind {
	case "keychain":
		return exec.Command("security", "add-generic-password", "-U", "-s", s.service, "-a", "", "-w", string(data)).Run()
	case "file":
		return os.WriteFile(s.filePath, data, 0600)
	}
	return errors.New("unknown store")
}

type tokenResponse struct {
	AccessToken  string  `json:"access_token"`
	RefreshToken string  `json:"refresh_token"`
	ExpiresIn    float64 `json:"expires_in"`
}

func refreshToken(c credentials, baseURL string) (credentials, error) {
	body, _ := json.Marshal(map[string]string{
		"grant_type": "refresh_token", "refresh_token": c.RefreshToken, "client_id": clientID,
	})
	req, _ := http.NewRequest("POST", strings.TrimSuffix(baseURL, "/")+"/v1/oauth/token", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return c, err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		return c, fmt.Errorf("refresh failed (HTTP %d): %s", resp.StatusCode, truncate(string(data), 200))
	}
	var tr tokenResponse
	if err := json.Unmarshal(data, &tr); err != nil {
		return c, err
	}
	rt := tr.RefreshToken
	if rt == "" {
		rt = c.RefreshToken
	}
	return credentials{tr.AccessToken, rt, time.Now().Add(time.Duration(tr.ExpiresIn) * time.Second).UnixMilli()}, nil
}

var knownWindows = [][2]string{
	{"five_hour", "Session (5h)"}, {"seven_day", "Weekly"}, {"seven_day_opus", "Weekly Opus"},
}

func fetchUsage(c credentials, baseURL string) (map[string]any, int, error) {
	req, _ := http.NewRequest("GET", strings.TrimSuffix(baseURL, "/")+"/api/oauth/usage", nil)
	req.Header.Set("Authorization", "Bearer "+c.AccessToken)
	req.Header.Set("anthropic-beta", "oauth-2025-04-20")
	req.Header.Set("User-Agent", "claude-code/1.0.119")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		return nil, resp.StatusCode, fmt.Errorf("HTTP %d: %s", resp.StatusCode, truncate(string(data), 200))
	}
	var m map[string]any
	if err := json.Unmarshal(data, &m); err != nil {
		return nil, resp.StatusCode, err
	}
	return m, 200, nil
}

func truncate(s string, n int) string {
	if len(s) > n {
		return s[:n]
	}
	return s
}

type win struct {
	label string
	util  float64
	reset time.Time
	hasR  bool
}

func printUsage(m map[string]any, useJSON bool) {
	if useJSON {
		out, _ := json.MarshalIndent(m, "", "  ")
		fmt.Println(string(out))
		return
	}
	var wins []win
	seen := map[string]bool{}
	add := func(key, label string, o map[string]any) {
		u, ok := o["utilization"].(float64)
		if !ok {
			return
		}
		w := win{label: label, util: u}
		if rs, ok := o["resets_at"].(string); ok {
			if t, err := time.Parse(time.RFC3339Nano, rs); err == nil {
				w.reset, w.hasR = t, true
			}
		}
		wins = append(wins, w)
	}
	for _, k := range knownWindows {
		if o, ok := m[k[0]].(map[string]any); ok {
			add(k[0], k[1], o)
			seen[k[0]] = true
		}
	}
	var extra []string
	for k := range m {
		if !seen[k] {
			extra = append(extra, k)
		}
	}
	sort.Strings(extra)
	for _, k := range extra {
		if o, ok := m[k].(map[string]any); ok {
			add(k, strings.ReplaceAll(k, "_", " "), o)
		}
	}
	for _, w := range wins {
		line := fmt.Sprintf("%-18s %3.0f%% used", w.label+":", w.util)
		if w.hasR {
			line += fmt.Sprintf("  (resets in %s, %s)", remaining(time.Until(w.reset)), w.reset.Format("Mon 15:04"))
		}
		fmt.Println(line)
	}
}

func remaining(d time.Duration) string {
	if d <= 0 {
		return "now"
	}
	mins := int(d.Minutes())
	if mins >= 1440 {
		return fmt.Sprintf("%dd%dh", mins/1440, (mins%1440)/60)
	}
	if mins >= 60 {
		return fmt.Sprintf("%dh%dm", mins/60, mins%60)
	}
	return fmt.Sprintf("%dm", mins)
}

func main() {
	autoRenew := flag.Bool("auto-renew", false, "refresh expired tokens and write them back to the shared credential store")
	baseURL := flag.String("base-url", "https://api.anthropic.com", "API base URL")
	useJSON := flag.Bool("json", false, "print raw usage JSON")
	watch := flag.Bool("watch", false, "keep printing usage on an interval")
	interval := flag.Duration("interval", 5*time.Minute, "watch refresh interval")
	flag.Parse()

	var found credentialStore
	var creds credentials
	var raw []byte
	foundS := false
	for _, s := range stores() {
		if c, r, ok := s.read(); ok {
			found, creds, raw, foundS = s, c, r, true
			break
		}
	}
	if !foundS {
		fmt.Fprintln(os.Stderr, "no Claude credentials found (Keychain 'Claude Code-credentials', ~/.claude/.credentials.json, or ~/.claude.json)")
		os.Exit(1)
	}

	if creds.expired() {
		if *autoRenew {
			nc, err := refreshToken(creds, *baseURL)
			if err != nil {
				fmt.Fprintln(os.Stderr, "refresh failed:", err)
				os.Exit(1)
			}
			creds = nc
			if err := found.write(creds, raw); err != nil {
				fmt.Fprintln(os.Stderr, "could not persist renewed token:", err)
			}
		} else {
			// Re-read once — another process (e.g. the claude CLI) may have refreshed it.
			if c2, raw2, ok := found.read(); ok && !c2.expired() {
				creds, raw = c2, raw2
			} else {
				fmt.Fprintln(os.Stderr, "credentials expired — re-login with claude CLI or pass --auto-renew")
				os.Exit(1)
			}
		}
	}

	for {
		m, status, err := fetchUsage(creds, *baseURL)
		if status == 401 || status == 403 {
			if *autoRenew {
				nc, rerr := refreshToken(creds, *baseURL)
				if rerr != nil {
					fmt.Fprintln(os.Stderr, "refresh failed:", rerr)
					os.Exit(1)
				}
				creds = nc
				_ = found.write(creds, raw)
				m, status, err = fetchUsage(creds, *baseURL)
			} else if c2, raw2, ok := found.read(); ok {
				creds, raw = c2, raw2
				m, status, err = fetchUsage(creds, *baseURL)
			}
		}
		if err != nil {
			fmt.Fprintln(os.Stderr, "error:", err)
			if *watch {
				time.Sleep(*interval)
				// re-read creds in case they changed
				if s2 := storeFor(found); s2 != nil {
					if c2, raw2, ok := s2.read(); ok {
						creds, raw = c2, raw2
					}
				}
				continue
			}
			os.Exit(1)
		}
		printUsage(m, *useJSON)
		if !*watch {
			return
		}
		fmt.Println()
		time.Sleep(*interval)
		if s2 := storeFor(found); s2 != nil {
			if c2, raw2, ok := s2.read(); ok {
				if creds.expired() {
					if *autoRenew {
						if nc, err := refreshToken(c2, *baseURL); err == nil {
							c2 = nc
							_ = s2.write(c2, raw2)
						}
					}
					creds, raw = c2, raw2
					continue
				}
				creds, raw = c2, raw2
			}
		}
	}
}

func storeFor(s credentialStore) *credentialStore { return &s }
