/*
In this file we handle the Git 'smart HTTP' protocol
*/

package git

import (
	"bytes"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"strings"

	"github.com/prometheus/client_golang/prometheus"

	"gitlab.com/gitlab-org/gitlab-workhorse/internal/api"
	"gitlab.com/gitlab-org/gitlab-workhorse/internal/helper"
)

var (
	gitHTTPRequests = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "gitlab_workhorse_git_http_requests",
			Help: "How many Git HTTP requests have been processed by gitlab-workhorse, partitioned by request type and agent.",
		},
		[]string{"request_type", "agent"},
	)

	gitHTTPBytes = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "gitlab_workhorse_git_http_bytes",
			Help: "How many Git HTTP bytes have been sent by gitlab-workhorse, partitioned by request type, agent and direction.",
		},
		[]string{"request_type", "agent", "direction"},
	)
)

func init() {
	prometheus.MustRegister(gitHTTPRequests)
	prometheus.MustRegister(gitHTTPBytes)
}

func GetInfoRefs(a *api.API) http.Handler {
	return repoPreAuthorizeHandler(a, handleGetInfoRefs)
}

func PostRPC(a *api.API) http.Handler {
	return repoPreAuthorizeHandler(a, handlePostRPC)
}

func looksLikeRepo(p string) bool {
	// If /path/to/foo.git/objects exists then let's assume it is a valid Git
	// repository.
	if _, err := os.Stat(path.Join(p, "objects")); err != nil {
		log.Print(err)
		return false
	}
	return true
}

func getRequestAgent(r *http.Request) string {
	u, _, ok := r.BasicAuth()
	if ok && u == "gitlab-ci-token" {
		return "gitlab-ci"
	} else if ok {
		return "logged"
	} else {
		return "anonymous"
	}
}

func repoPreAuthorizeHandler(myAPI *api.API, handleFunc api.HandleFunc) http.Handler {
	return myAPI.PreAuthorizeHandler(func(w http.ResponseWriter, r *http.Request, a *api.Response) {
		if a.RepoPath == "" {
			helper.Fail500(w, r, fmt.Errorf("repoPreAuthorizeHandler: RepoPath empty"))
			return
		}

		if !looksLikeRepo(a.RepoPath) {
			http.Error(w, "Not Found", 404)
			return
		}

		handleFunc(w, r, a)
	}, "")
}

func handleGetInfoRefs(w http.ResponseWriter, r *http.Request, a *api.Response) {
	rpc := r.URL.Query().Get("service")
	if !(rpc == "git-upload-pack" || rpc == "git-receive-pack") {
		// The 'dumb' Git HTTP protocol is not supported
		http.Error(w, "Not Found", 404)
		return
	}

	requestType := "get-info-refs"
	gitHTTPRequests.WithLabelValues(requestType, getRequestAgent(r)).Inc()
	var writtenOut int64
	defer func() {
		gitHTTPBytes.WithLabelValues(requestType, getRequestAgent(r), "out").Add(float64(writtenOut))
	}()

	// Prepare our Git subprocess
	cmd := gitCommand(a.GL_ID, "git", subCommand(rpc), "--stateless-rpc", "--advertise-refs", a.RepoPath)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		helper.Fail500(w, r, fmt.Errorf("handleGetInfoRefs: stdout: %v", err))
		return
	}
	defer stdout.Close()
	if err := cmd.Start(); err != nil {
		helper.Fail500(w, r, fmt.Errorf("handleGetInfoRefs: start %v: %v", cmd.Args, err))
		return
	}
	defer helper.CleanUpProcessGroup(cmd) // Ensure brute force subprocess clean-up

	// Start writing the response
	w.Header().Set("Content-Type", fmt.Sprintf("application/x-%s-advertisement", rpc))
	w.Header().Set("Cache-Control", "no-cache")
	w.WriteHeader(200) // Don't bother with HTTP 500 from this point on, just return
	if err := pktLine(w, fmt.Sprintf("# service=%s\n", rpc)); err != nil {
		helper.LogError(r, fmt.Errorf("handleGetInfoRefs: pktLine: %v", err))
		return
	}
	if err := pktFlush(w); err != nil {
		helper.LogError(r, fmt.Errorf("handleGetInfoRefs: pktFlush: %v", err))
		return
	}
	if writtenOut, err = io.Copy(w, stdout); err != nil {
		helper.LogError(
			r,
			&copyError{fmt.Errorf("handleGetInfoRefs: copy output of %v: %v", cmd.Args, err)},
		)
		return
	}
	if err := cmd.Wait(); err != nil {
		helper.LogError(r, fmt.Errorf("handleGetInfoRefs: wait for %v: %v", cmd.Args, err))
		return
	}
}

func handlePostRPC(w http.ResponseWriter, r *http.Request, a *api.Response) {
	var err error
	var body io.Reader
	var isShallowClone bool

	// Get Git action from URL
	action := filepath.Base(r.URL.Path)
	if !(action == "git-upload-pack" || action == "git-receive-pack") {
		// The 'dumb' Git HTTP protocol is not supported
		helper.Fail500(w, r, fmt.Errorf("handlePostRPC: unsupported action: %s", r.URL.Path))
		return
	}

	requestType := "post-" + action
	gitHTTPRequests.WithLabelValues(requestType, getRequestAgent(r)).Inc()
	var writtenIn, writtenOut int64
	defer func() {
		gitHTTPBytes.WithLabelValues(requestType, getRequestAgent(r), "in").Add(float64(writtenIn))
		gitHTTPBytes.WithLabelValues(requestType, getRequestAgent(r), "out").Add(float64(writtenOut))
	}()

	if action == "git-upload-pack" {
		buffer := &bytes.Buffer{}
		// Only sniff on the first 4096 bytes: we assume that if we find no
		// 'deepen' message in the first 4096 bytes there won't be one later
		// either.
		_, err = io.Copy(buffer, io.LimitReader(r.Body, 4096))
		if err != nil {
			helper.Fail500(w, r, &copyError{fmt.Errorf("handlePostRPC: buffer git-upload-pack body: %v", err)})
			return
		}

		isShallowClone = scanDeepen(bytes.NewReader(buffer.Bytes()))
		body = io.MultiReader(buffer, r.Body)
	} else {
		body = r.Body
	}

	// Prepare our Git subprocess
	cmd := gitCommand(a.GL_ID, "git", subCommand(action), "--stateless-rpc", a.RepoPath)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		helper.Fail500(w, r, fmt.Errorf("handlePostRPC: stdout: %v", err))
		return
	}
	defer stdout.Close()
	stdin, err := cmd.StdinPipe()
	if err != nil {
		helper.Fail500(w, r, fmt.Errorf("handlePostRPC: stdin: %v", err))
		return
	}
	defer stdin.Close()
	if err := cmd.Start(); err != nil {
		helper.Fail500(w, r, fmt.Errorf("handlePostRPC: start %v: %v", cmd.Args, err))
		return
	}
	defer helper.CleanUpProcessGroup(cmd) // Ensure brute force subprocess clean-up

	// Write the client request body to Git's standard input
	if writtenIn, err = io.Copy(stdin, body); err != nil {
		helper.Fail500(w, r, fmt.Errorf("handlePostRPC: write to %v: %v", cmd.Args, err))
		return
	}
	// Signal to the Git subprocess that no more data is coming
	stdin.Close()

	// It may take a while before we return and the deferred closes happen
	// so let's free up some resources already.
	r.Body.Close()

	// Start writing the response
	w.Header().Set("Content-Type", fmt.Sprintf("application/x-%s-result", action))
	w.Header().Set("Cache-Control", "no-cache")
	w.WriteHeader(200) // Don't bother with HTTP 500 from this point on, just return

	// This io.Copy may take a long time, both for Git push and pull.
	if writtenOut, err = io.Copy(w, stdout); err != nil {
		helper.LogError(
			r,
			&copyError{fmt.Errorf("handlePostRPC: copy output of %v: %v", cmd.Args, err)},
		)
		return
	}
	if err := cmd.Wait(); err != nil && !(isExitError(err) && isShallowClone) {
		helper.LogError(r, fmt.Errorf("handlePostRPC: wait for %v: %v", cmd.Args, err))
		return
	}
}

func isExitError(err error) bool {
	_, ok := err.(*exec.ExitError)
	return ok
}

func subCommand(rpc string) string {
	return strings.TrimPrefix(rpc, "git-")
}
